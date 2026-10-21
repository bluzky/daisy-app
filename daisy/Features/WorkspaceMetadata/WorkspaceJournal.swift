//
//  WorkspaceJournal.swift
//  daisy
//
//  A workspace's journal: one Markdown file per day in its `journals/`
//  folder, named `YYYY-MM-DD.md` after the local calendar day. A missing
//  entry is created, holding the Journal template or else only
//  `# YYYY-MM-DD` (see `JournalTemplate`), when the user opens that day
//  (Today's Journal, or a day picked in the toolbar calendar); listing and
//  stepping between entries never write.
//
//  No AppKit, so it links into `tests/swift-tests`.
//

import Foundation

/// A calendar day, independent of time zone once made: journal entries
/// name a day, not an instant.
nonisolated struct JournalDay: Hashable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    /// Nil when the three numbers are not a real day in the Gregorian calendar.
    init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year), (1...12).contains(month), day >= 1,
              day <= Self.daysInMonth(year: year, month: month) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day `date` falls on in `calendar`'s time zone.
    init(date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        year = parts.year ?? 1
        month = parts.month ?? 1
        day = parts.day ?? 1
    }

    /// Parses exactly `YYYY-MM-DD`.
    init?(string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    var string: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Midnight at the start of the day in `calendar`.
    func date(in calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    static func < (lhs: JournalDay, rhs: JournalDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2:
            let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
            return leap ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }
}

enum WorkspaceJournal {
    static let folderName = "journals"
    static let fileExtension = "md"

    enum JournalError: LocalizedError {
        case outsideWorkspace
        case notAFile(String)

        var errorDescription: String? {
            switch self {
            case .outsideWorkspace:
                NSLocalizedString("The journals folder is outside the workspace.", comment: "Workspace journal error")
            case .notAFile(let name):
                String(format: NSLocalizedString("“%@” in the journals folder is not a file.",
                                                 comment: "Workspace journal error"), name)
            }
        }
    }

    enum Direction {
        case previous
        case next
    }

    static func fileName(for day: JournalDay) -> String {
        "\(day.string).\(fileExtension)"
    }

    static func day(fromFileName name: String) -> JournalDay? {
        let suffix = ".\(fileExtension)"
        guard name.hasSuffix(suffix) else { return nil }
        return JournalDay(string: String(name.dropLast(suffix.count)))
    }

    /// The day `url` is the entry for, or nil when it is not a file directly
    /// in this workspace's `journals/` folder.
    static func day(of url: URL, root: URL) -> JournalDay? {
        guard let day = day(fromFileName: url.lastPathComponent),
              let folder = try? journalsFolder(root: root),
              canonicalPath(url.deletingLastPathComponent()) == canonicalPath(folder)
        else { return nil }
        return day
    }

    /// Every day that has an entry. Reads the folder only; an unreadable or
    /// missing folder has none. Only what `resolve` would open counts, so a
    /// FIFO, a folder or a symlink leading out of `journals/` gets no dot in
    /// the calendar and is never stepped to.
    static func entryDays(root: URL) -> Set<JournalDay> {
        guard let folder = try? journalsFolder(root: root),
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path)
        else { return [] }
        var days = Set<JournalDay>()
        for name in names {
            guard let day = day(fromFileName: name),
                  entryKind(folder.appendingPathComponent(name), folder: folder) == .file else { continue }
            days.insert(day)
        }
        return days
    }

    /// The nearest day before or after `day` that has an entry.
    static func adjacentDay(to day: JournalDay, _ direction: Direction, root: URL) -> JournalDay? {
        let days = entryDays(root: root)
        switch direction {
        case .previous: return days.filter { $0 < day }.max()
        case .next: return days.filter { $0 > day }.min()
        }
    }

    /// The existing entry for `day`, or nil when there is none. Throws when
    /// something that is not a regular file in `journals/` has its name.
    static func resolve(day: JournalDay, root: URL) throws -> URL? {
        let folder = try journalsFolder(root: root)
        let entry = folder.appendingPathComponent(fileName(for: day))
        switch entryKind(entry, folder: folder) {
        case .missing: return nil
        case .file: return entry
        case .outside: throw JournalError.outsideWorkspace
        case .notAFile: throw JournalError.notAFile(entry.lastPathComponent)
        }
    }

    /// The entry for `day`, created holding `contents` (by default its H1)
    /// when there is none. Never replaces a file; a failed write leaves
    /// nothing behind.
    ///
    /// The folder is opened once and the file is created relative to that
    /// descriptor, after checking where the descriptor really points. A
    /// `journals/` swapped for a symlink after `journalsFolder` checked it
    /// therefore can't redirect the write out of the workspace. A folder this
    /// call made is removed on failure only while empty, so another writer's
    /// entries are never deleted.
    static func openOrCreate(day: JournalDay, root: URL, contents: String? = nil) throws -> URL {
        if let entry = try resolve(day: day, root: root) { return entry }
        let folder = try journalsFolder(root: root)
        let name = fileName(for: day)
        let data = Data((contents ?? "# \(day.string)\n").utf8)

        let createdFolder = mkdir(folder.path, 0o755) == 0
        if !createdFolder, errno != EEXIST { throw posixError(errno) }
        func removeCreatedFolder() {
            if createdFolder { _ = rmdir(folder.path) }
        }

        let directory = open(folder.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard directory >= 0 else {
            let code = errno
            removeCreatedFolder()
            throw posixError(code)
        }
        defer { close(directory) }
        guard let opened = path(of: directory), isInside(opened, root: root) else {
            removeCreatedFolder()
            throw JournalError.outsideWorkspace
        }

        let file = openat(directory, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o644)
        guard file >= 0 else {
            let code = errno
            // Another writer got there first: open its entry.
            if code == EEXIST, let existing = try? resolve(day: day, root: root) { return existing }
            removeCreatedFolder()
            throw posixError(code)
        }
        let written = data.withUnsafeBytes { buffer -> Bool in
            var offset = 0
            while offset < buffer.count {
                let count = write(file, buffer.baseAddress! + offset, buffer.count - offset)
                if count < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                offset += count
            }
            return true
        }
        let code = errno
        let closed = close(file) == 0
        guard written, closed else {
            _ = unlinkat(directory, name, 0)
            removeCreatedFolder()
            throw posixError(written ? errno : code)
        }
        return folder.appendingPathComponent(name)
    }

    /// `<root>/journals`, refused when it resolves outside the root.
    private static func journalsFolder(root: URL) throws -> URL {
        let folder = root.appendingPathComponent(folderName, isDirectory: true)
        let resolvedRoot = canonicalPath(root)
        guard canonicalPath(folder).hasPrefix(resolvedRoot.hasSuffix("/") ? resolvedRoot : resolvedRoot + "/") else {
            throw JournalError.outsideWorkspace
        }
        return folder
    }

    private enum EntryKind {
        case missing
        /// A regular file, or a symlink to one in the same folder.
        case file
        /// A symlink leading out of the folder.
        case outside
        /// A folder, FIFO, socket, device or dangling symlink.
        case notAFile
    }

    /// Looks without following the name, so a FIFO is never opened.
    private static func entryKind(_ entry: URL, folder: URL) -> EntryKind {
        var info = stat()
        guard lstat(entry.path, &info) == 0 else { return .missing }
        switch info.st_mode & S_IFMT {
        case S_IFREG:
            return .file
        case S_IFLNK:
            let target = entry.resolvingSymlinksInPath()
            guard canonicalPath(target.deletingLastPathComponent()) == canonicalPath(folder) else {
                return .outside
            }
            var targetInfo = stat()
            guard lstat(target.path, &targetInfo) == 0, targetInfo.st_mode & S_IFMT == S_IFREG else {
                return .notAFile
            }
            return .file
        default:
            return .notAFile
        }
    }

    /// Where an open descriptor really is, symlinks resolved.
    private static func path(of descriptor: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(descriptor, F_GETPATH, &buffer) == 0 else { return nil }
        return String(cString: buffer)
    }

    /// Whether `path`, already resolved, is inside `root` once it is too.
    private static func isInside(_ path: String, root: URL) -> Bool {
        guard let resolved = realpath(root.path, nil) else { return false }
        defer { free(resolved) }
        let rootPath = String(cString: resolved)
        return path.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/")
    }

    private static func posixError(_ code: Int32) -> Error {
        POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }

    private static func canonicalPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }
}
