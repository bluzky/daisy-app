//
//  WorkspaceFileWriter.swift
//  daisy
//
//  Rewrites one Markdown file inside a workspace, for checking a task off
//  from the Tasks sidebar while the file is not open. Every directory on the
//  way is opened relative to its parent with O_NOFOLLOW, and the read, the
//  temporary file and the rename all go through the final directory's
//  descriptor, never a path: a symlink anywhere on the way is refused, and a
//  directory swapped for one partway through cannot redirect the write.
//
//  One gap stays open without a file lock: an outside edit landing between
//  the last re-read and the rename is overwritten, as with
//  `WorkspaceJournal.replaceEntry`.
//
//  No AppKit, so it links into `tests/swift-tests`.
//

import Foundation
import Synchronization

nonisolated enum WorkspaceFileWriter {
    enum WriterError: LocalizedError, Equatable {
        /// Empty, `.`, `..` or NUL components, or an absolute path.
        case invalidPath
        /// The root is not the directory the index was opened on.
        case rootChanged
        /// A symlink, hard link, folder, FIFO or other non-regular file.
        case notAFile(String)

        var errorDescription: String? {
            switch self {
            case .invalidPath:
                NSLocalizedString("The task’s file is not inside the workspace.", comment: "Task write error")
            case .rootChanged:
                NSLocalizedString("The workspace folder changed.", comment: "Task write error")
            case .notAFile(let name):
                String(format: NSLocalizedString("“%@” is not a regular file.", comment: "Task write error"), name)
            }
        }
    }

    /// Device and inode of a workspace root, captured when the index is
    /// bound, so a root swapped for another directory later is refused.
    nonisolated struct RootIdentity: Equatable, Sendable {
        let device: UInt64
        let inode: UInt64

        init(root: URL) throws {
            let directory = try WorkspaceFileWriter.openRoot(root)
            defer { close(directory) }
            self = try RootIdentity(descriptor: directory)
        }

        fileprivate init(descriptor: Int32) throws {
            var info = stat()
            guard fstat(descriptor, &info) == 0 else { throw WorkspaceFileWriter.posixError(errno) }
            device = UInt64(bitPattern: Int64(info.st_dev))
            inode = UInt64(info.st_ino)
        }
    }

    /// Points between the steps of `replace`, for tests that swap files
    /// underneath it.
    enum Step: Sendable {
        case afterWalk
        case beforeRecheck
    }

    static let testHook = Mutex<(@Sendable (Step) -> Void)?>(nil)

    /// The file's bytes, read the same way `replace` reads them.
    static func read(relativePath: String, root: URL,
                     expectedRootIdentity: RootIdentity) throws -> Data {
        let (directory, name) = try openParent(of: relativePath, root: root, expectedRootIdentity: expectedRootIdentity)
        defer { close(directory) }
        return try readRegularFile(name, in: directory).data
    }

    /// Replaces the file with `contents` only while it still holds
    /// `expected`; false when it changed. Permissions, extended attributes
    /// (Finder tags among them), ACLs and the creation date are kept, and a
    /// reader never sees half of the new text.
    static func replace(relativePath: String, root: URL, expected: Data, with contents: String,
                        expectedRootIdentity: RootIdentity) throws -> Bool {
        let (directory, name) = try openParent(of: relativePath, root: root, expectedRootIdentity: expectedRootIdentity)
        defer { close(directory) }
        runHook(.afterWalk)
        let current = try readRegularFile(name, in: directory)
        guard current.data == expected else { return false }

        let temporary = ".\(name).\(UUID().uuidString).tmp"
        let mode = current.mode & 0o777
        let file = openat(directory, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode)
        guard file >= 0 else { throw posixError(errno) }
        func discardTemporary() { _ = unlinkat(directory, temporary, 0) }
        copyMetadata(of: name, in: directory, matching: current, to: file)
        // The umask may have narrowed the mode `openat` was given.
        let written = fchmod(file, mode) == 0 && writeAll(file, Data(contents.utf8)) && fsync(file) == 0
        let code = errno
        let closed = close(file) == 0
        guard written, closed else {
            discardTemporary()
            throw posixError(written ? errno : code)
        }

        runHook(.beforeRecheck)
        // The target must still be the same file with the same bytes.
        guard let again = try? readRegularFile(name, in: directory),
              again.device == current.device, again.inode == current.inode, again.data == expected else {
            discardTemporary()
            return false
        }
        guard renameat(directory, temporary, directory, name) == 0 else {
            let code = errno
            discardTemporary()
            throw posixError(code)
        }
        return true
    }

    // MARK: - Walking

    private static func runHook(_ step: Step) {
        let hook = testHook.withLock { $0 }
        hook?(step)
    }

    fileprivate static func openRoot(_ root: URL) throws -> Int32 {
        let directory = open(root.path(percentEncoded: false), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw posixError(errno) }
        return directory
    }

    /// Validated components of a workspace-relative path.
    static func components(of relativePath: String) throws -> [String] {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/"), !relativePath.contains("\u{0}") else {
            throw WriterError.invalidPath
        }
        let parts = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            throw WriterError.invalidPath
        }
        return parts
    }

    /// A descriptor on the file's own directory, reached one component at a
    /// time without following a symlink, with the file's name.
    private static func openParent(of relativePath: String, root: URL,
                                   expectedRootIdentity: RootIdentity) throws -> (Int32, String) {
        let parts = try components(of: relativePath)
        var directory = try openRoot(root)
        do {
            guard try RootIdentity(descriptor: directory) == expectedRootIdentity else {
                throw WriterError.rootChanged
            }
            for name in parts.dropLast() {
                let next = openat(directory, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard next >= 0 else {
                    let code = errno
                    throw code == ELOOP || code == ENOTDIR ? WriterError.notAFile(name) : posixError(code)
                }
                close(directory)
                directory = next
            }
        } catch {
            close(directory)
            throw error
        }
        return (directory, parts[parts.count - 1])
    }

    private struct RegularFile {
        let data: Data
        let mode: mode_t
        let device: dev_t
        let inode: ino_t
        let created: timespec
    }

    /// A regular file with one link, not following a symlink and never
    /// blocking on a FIFO.
    private static func readRegularFile(_ name: String, in directory: Int32) throws -> RegularFile {
        let file = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard file >= 0 else {
            let code = errno
            throw code == ELOOP ? WriterError.notAFile(name) : posixError(code)
        }
        defer { close(file) }
        var info = stat()
        guard fstat(file, &info) == 0 else { throw posixError(errno) }
        guard info.st_mode & S_IFMT == S_IFREG, info.st_nlink == 1 else { throw WriterError.notAFile(name) }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = Darwin.read(file, &buffer, buffer.count)
            if count < 0 {
                if errno == EINTR { continue }
                throw posixError(errno)
            }
            if count == 0 { break }
            data.append(buffer, count: count)
        }
        return RegularFile(data: data, mode: info.st_mode, device: info.st_dev, inode: info.st_ino,
                           created: info.st_birthtimespec)
    }

    /// Copies the original's extended attributes, ACL and creation date onto
    /// the temporary file. Best effort: a note that loses them is still
    /// better than a check-off that fails, and the permission bits are set
    /// separately. Skipped when the name no longer leads to `original`.
    private static func copyMetadata(of name: String, in directory: Int32, matching original: RegularFile,
                                     to file: Int32) {
        let source = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard source >= 0 else { return }
        defer { close(source) }
        var info = stat()
        guard fstat(source, &info) == 0, info.st_dev == original.device, info.st_ino == original.inode else { return }
        _ = fcopyfile(source, file, nil, copyfile_flags_t(COPYFILE_XATTR | COPYFILE_ACL))
        var attributes = attrlist()
        attributes.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        attributes.commonattr = attrgroup_t(ATTR_CMN_CRTIME)
        var created = original.created
        _ = fsetattrlist(file, &attributes, &created, MemoryLayout<timespec>.size, 0)
    }

    private static func writeAll(_ file: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { buffer -> Bool in
            guard let base = buffer.baseAddress else { return true }
            var offset = 0
            while offset < buffer.count {
                let count = write(file, base + offset, buffer.count - offset)
                if count < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                offset += count
            }
            return true
        }
    }

    fileprivate static func posixError(_ code: Int32) -> Error {
        POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }
}
