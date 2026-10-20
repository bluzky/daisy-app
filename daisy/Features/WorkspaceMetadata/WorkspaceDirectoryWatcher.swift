//
//  WorkspaceDirectoryWatcher.swift
//  daisy
//
//  Reports changes anywhere under a workspace root, coalesced by FSEvents.
//  A changed file is reported by path; anything that changes many files at
//  once (a folder created, moved or deleted) or events the system dropped
//  ask for a full rescan instead.
//

import CoreServices
import Foundation

nonisolated final class WorkspaceDirectoryWatcher: @unchecked Sendable {
    enum Change: Sendable, Equatable {
        case files([URL])
        case rescan
    }

    private let handler: @Sendable (Change) -> Void
    private let queue = DispatchQueue(label: "doc.daisy.workspace-watcher")
    private var stream: FSEventStreamRef?

    /// Nil when FSEvents cannot watch `root`. The stream retains the
    /// watcher until `stop`.
    init?(root: URL, latency: TimeInterval = 0.3, handler: @escaping @Sendable (Change) -> Void) {
        self.handler = handler
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: { info in
                guard let info else { return nil }
                _ = Unmanaged<WorkspaceDirectoryWatcher>.fromOpaque(info).retain()
                return UnsafeRawPointer(info)
            },
            release: { info in
                guard let info else { return }
                Unmanaged<WorkspaceDirectoryWatcher>.fromOpaque(info).release()
            },
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagWatchRoot
        )
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, count, paths, flags, _ in
                guard let info else { return }
                let watcher = Unmanaged<WorkspaceDirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
                let paths = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
                let flags = Array(UnsafeBufferPointer(start: flags, count: count))
                watcher.deliver(paths: paths, flags: flags)
            },
            &context,
            [root.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else { return nil }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        guard FSEventStreamStart(stream) else {
            stop()
            return nil
        }
    }

    func stop() {
        guard let stream else { return }
        self.stream = nil
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    private func deliver(paths: [String], flags: [FSEventStreamEventFlags]) {
        if let change = Self.change(paths: paths, flags: flags) {
            handler(change)
        }
    }

    static func change(paths: [String], flags: [FSEventStreamEventFlags]) -> Change? {
        let rescanFlags = FSEventStreamEventFlags(
            kFSEventStreamEventFlagMustScanSubDirs
                | kFSEventStreamEventFlagUserDropped
                | kFSEventStreamEventFlagKernelDropped
                | kFSEventStreamEventFlagRootChanged
        )
        let folderChangeFlags = FSEventStreamEventFlags(
            kFSEventStreamEventFlagItemCreated
                | kFSEventStreamEventFlagItemRemoved
                | kFSEventStreamEventFlagItemRenamed
        )
        var files: [URL] = []
        for (path, flag) in zip(paths, flags) {
            if flag & rescanFlags != 0 { return .rescan }
            if flag & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir) != 0 {
                if flag & folderChangeFlags != 0 { return .rescan }
                continue
            }
            if flag & FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsFile
                                              | kFSEventStreamEventFlagItemIsSymlink) != 0 {
                files.append(URL(fileURLWithPath: path))
            }
        }
        return files.isEmpty ? nil : .files(files)
    }
}
