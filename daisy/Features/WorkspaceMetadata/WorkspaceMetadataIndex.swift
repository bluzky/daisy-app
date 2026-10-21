//
//  WorkspaceMetadataIndex.swift
//  daisy
//
//  The tags, contexts and projects of one workspace's saved Markdown files,
//  with unsaved buffers standing in for their files. One index serves every
//  workspace window on a root. It only reads the workspace; what it read is
//  kept in memory and copied to a `WorkspaceIndexStore` outside the
//  workspace, so the next open starts from the copy instead of an empty
//  scan. Completion asks it for nothing, because editors are handed
//  snapshots. Kept free of AppKit so the helper tests can drive it.
//

import CryptoKit
import Foundation
import Synchronization

nonisolated enum WorkspaceMetadataKind: CaseIterable, Sendable {
    case tag, context, project
}

/// What one workspace's names look like at one moment, in the shape the
/// editor's `setWorkspaceCandidates` takes.
nonisolated struct WorkspaceMetadataSnapshot: Sendable, Equatable {
    nonisolated struct Candidate: Sendable, Equatable {
        /// Without its marker.
        let name: String
        let count: Int
    }

    /// Unique across all indexes, so an editor moved to another workspace,
    /// or to none, never keeps names because the new snapshot looks older.
    let version: Int
    let tags: [Candidate]
    let contexts: [Candidate]
    let projects: [Candidate]
    /// False while the first scan is still running.
    let isComplete: Bool
    /// The scan stopped at a cap, so some files are not counted.
    let isTruncated: Bool

    func candidates(_ kind: WorkspaceMetadataKind) -> [Candidate] {
        switch kind {
        case .tag: tags
        case .context: contexts
        case .project: projects
        }
    }

    /// No names, for an editor whose window stopped being a workspace.
    static func empty() -> WorkspaceMetadataSnapshot {
        WorkspaceMetadataSnapshot(version: nextVersion(), tags: [], contexts: [], projects: [],
                                  isComplete: true, isTruncated: false)
    }

    private static let versionCounter = Mutex(0)

    static func nextVersion() -> Int {
        versionCounter.withLock { value in
            value += 1
            return value
        }
    }
}

/// One file's names: normalized key → source spelling (marker stripped) →
/// occurrences.
nonisolated struct WorkspaceMetadataContribution: Sendable, Equatable {
    typealias Spellings = [String: Int]
    private(set) var names: [WorkspaceMetadataKind: [String: Spellings]] = [:]

    init() {}

    init(_ metadata: WorkspaceMetadata) {
        add(metadata.tags, as: .tag)
        add(metadata.contexts, as: .context)
        add(metadata.projects, as: .project)
    }

    /// `count` more occurrences of `spelling`, as a stored row records them.
    mutating func add(kind: WorkspaceMetadataKind, key: String, spelling: String, count: Int) {
        names[kind, default: [:]][key, default: [:]][spelling, default: 0] += count
    }

    private mutating func add(_ tokens: [WorkspaceMetadataToken], as kind: WorkspaceMetadataKind) {
        for token in tokens {
            // Every marker is one character: `#`, `@` or `+`.
            names[kind, default: [:]][token.key, default: [:]][String(token.source.dropFirst()), default: 0] += 1
        }
    }

    /// Adds `other` once, or takes it away with `sign` -1.
    mutating func merge(_ other: WorkspaceMetadataContribution, sign: Int) {
        for (kind, keys) in other.names {
            for (key, spellings) in keys {
                for (spelling, count) in spellings {
                    let total = (names[kind]?[key]?[spelling] ?? 0) + sign * count
                    if total > 0 {
                        names[kind, default: [:]][key, default: [:]][spelling] = total
                        continue
                    }
                    names[kind]?[key]?[spelling] = nil
                    if names[kind]?[key]?.isEmpty == true { names[kind]?[key] = nil }
                }
            }
        }
    }

    /// The most used spelling of each name, ties going to the one that sorts
    /// first, with the count of every spelling together.
    func candidates(_ kind: WorkspaceMetadataKind) -> [WorkspaceMetadataSnapshot.Candidate] {
        (names[kind] ?? [:])
            .sorted { $0.key < $1.key }
            .compactMap { _, spellings in
                guard let display = spellings.min(by: { lhs, rhs in
                    lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
                }) else { return nil }
                return .init(name: display.key, count: spellings.values.reduce(0, +))
            }
    }
}

actor WorkspaceMetadataIndex {
    nonisolated struct Limits: Sendable {
        var maximumFileSize = 1 << 20
        var maximumFileCount = ProjectFileIndex.maximumFileCount
        var maximumDepth = ProjectFileIndex.maximumDepth
        /// Files read between partial snapshots during a scan.
        var batchSize = 64
        /// Files read at once. The extractor's context pool has four.
        var concurrency = 4
    }

    /// Symlinks resolved, then standardized, as `SidebarWorkspace` does.
    nonisolated static func canonicalRoot(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }

    nonisolated let root: URL
    private let limits: Limits
    /// Where the store's file goes; nil keeps everything in memory.
    private let cacheDirectory: URL?

    private nonisolated struct Fingerprint: Sendable, Equatable {
        let modificationDate: Date?
        let size: Int?
    }

    private nonisolated struct FileEntry: Sendable, Equatable {
        let fingerprint: Fingerprint
        /// SHA-256 of the bytes the contribution was extracted from.
        let hash: Data
        let contribution: WorkspaceMetadataContribution
    }

    private nonisolated struct DiscoveredFile: Sendable {
        let relativePath: String
        let url: URL
        let fingerprint: Fingerprint
    }

    private nonisolated enum FileRead: Sendable {
        case parsed(FileEntry)
        /// Gone, or too large, unreadable or not UTF-8: it contributes nothing.
        case excluded
    }

    private var files: [String: FileEntry] = [:]
    /// Unsaved buffers by file, latest last; the latest stands in for the file.
    private var overlays: [String: [(owner: UUID, contribution: WorkspaceMetadataContribution)]] = [:]
    private var aggregate = WorkspaceMetadataContribution()
    /// Reads per path, so a slow read cannot overwrite a newer one.
    private var readGenerations: [String: Int] = [:]
    private var isComplete = false
    private var isTruncated = false
    private var isStarted = false
    private var isStopped = false

    private var reconcileTask: Task<Void, Never>?
    private var reconcileRequested = false

    private var store: WorkspaceIndexStore?
    /// The cache has been read, or given up on, before the first scan.
    private var isCacheLoaded = false
    /// Remove Workspace deleted the cache; nothing is written again.
    private var isCacheDiscarded = false
    /// Files whose saved entry changed since the store last got them.
    private var unsavedPaths: Set<String> = []
    private var flushTask: Task<Void, Never>?

    private var watcher: WorkspaceDirectoryWatcher?
    private var subscribers: [UUID: AsyncStream<WorkspaceMetadataSnapshot>.Continuation] = [:]
    private var latest: WorkspaceMetadataSnapshot?

    init(root: URL, limits: Limits = Limits(), cacheDirectory: URL? = nil) {
        self.root = Self.canonicalRoot(root)
        self.limits = limits
        self.cacheDirectory = cacheDirectory
    }

    // MARK: - Snapshots

    /// The latest snapshot now and each later one. Snapshots that arrive
    /// faster than they are read collapse to the newest.
    func snapshots() -> AsyncStream<WorkspaceMetadataSnapshot> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: WorkspaceMetadataSnapshot.self,
                                                             bufferingPolicy: .bufferingNewest(1))
        continuation.onTermination = { [weak self] _ in
            Task { await self?.unsubscribe(id) }
        }
        subscribers[id] = continuation
        continuation.yield(latest ?? makeSnapshot())
        return stream
    }

    func snapshot() -> WorkspaceMetadataSnapshot {
        latest ?? makeSnapshot()
    }

    private func unsubscribe(_ id: UUID) {
        subscribers[id] = nil
    }

    private func makeSnapshot() -> WorkspaceMetadataSnapshot {
        WorkspaceMetadataSnapshot(version: WorkspaceMetadataSnapshot.nextVersion(),
                                  tags: aggregate.candidates(.tag),
                                  contexts: aggregate.candidates(.context),
                                  projects: aggregate.candidates(.project),
                                  isComplete: isComplete,
                                  isTruncated: isTruncated)
    }

    private func publish() {
        let snapshot = makeSnapshot()
        guard snapshot.tags != latest?.tags || snapshot.contexts != latest?.contexts
                || snapshot.projects != latest?.projects || snapshot.isComplete != latest?.isComplete
                || snapshot.isTruncated != latest?.isTruncated else { return }
        latest = snapshot
        for continuation in subscribers.values { continuation.yield(snapshot) }
    }

    // MARK: - Lifecycle

    /// Starts watching the root and runs the first scan. Calling it again
    /// does nothing.
    func start() {
        guard !isStarted, !isStopped else { return }
        isStarted = true
        watcher = WorkspaceDirectoryWatcher(root: root) { [weak self] change in
            Task { await self?.handle(change) }
        }
        Task { await reconcile() }
    }

    /// Stops watching, then returns once what was pending is saved and the
    /// store is closed.
    func stop() async {
        isStopped = true
        watcher?.stop()
        watcher = nil
        reconcileTask?.cancel()
        for continuation in subscribers.values { continuation.finish() }
        subscribers.removeAll()
        await flushCache()
        await closeStore()
    }

    private func closeStore() async {
        await store?.close()
        store = nil
    }

    private func handle(_ change: WorkspaceDirectoryWatcher.Change) async {
        switch change {
        case let .files(urls): await filesChanged(urls)
        case .rescan: await reconcile()
        }
    }

    // MARK: - Reconciling with the disk

    /// Walks the root, reading files that are new or whose size or date
    /// changed and dropping ones that are gone. The first run is the initial
    /// scan, publishing partial snapshots as it goes. A request while one
    /// runs makes it run once more when it ends.
    func reconcile() async {
        if let running = reconcileTask {
            reconcileRequested = true
            await running.value
            return
        }
        let task = Task { await runReconcileLoop() }
        reconcileTask = task
        await task.value
    }

    private func runReconcileLoop() async {
        if !isCacheLoaded {
            isCacheLoaded = true
            await loadCache()
        }
        repeat {
            reconcileRequested = false
            await reconcileOnce()
        } while reconcileRequested && !isStopped
        reconcileTask = nil
    }

    private func reconcileOnce() async {
        let (discovered, truncated) = await Self.discover(root: root, limits: limits)
        guard !isStopped else { return }
        isTruncated = truncated

        let present = Set(discovered.map(\.relativePath))
        for path in files.keys where !present.contains(path) {
            setFile(nil, at: path)
        }

        let pending = discovered.filter { files[$0.relativePath]?.fingerprint != $0.fingerprint }
        var start = 0
        while start < pending.count, !isStopped {
            let batch = Array(pending[start..<min(start + limits.batchSize, pending.count)])
            await read(batch)
            start += batch.count
            if !isComplete { publish() }
            scheduleFlush()
        }
        isComplete = true
        publish()
        scheduleFlush()
    }

    /// Re-reads or drops each of these files: saved, created, renamed or
    /// deleted, as the watcher reports them. Paths outside the root or ones
    /// the scan would not index are ignored.
    func filesChanged(_ urls: [URL]) async {
        let batch = urls.compactMap { url -> DiscoveredFile? in
            guard let path = relativePath(of: url) else { return nil }
            // Past the cap the scan stopped at, a file stays uncounted, as
            // the next reconcile would leave it.
            if isTruncated && files[path] == nil { return nil }
            return DiscoveredFile(relativePath: path, url: root.appending(path: path),
                                  fingerprint: Fingerprint(modificationDate: nil, size: nil))
        }
        guard !batch.isEmpty else { return }
        await read(batch)
        publish()
        scheduleFlush()
    }

    private func read(_ batch: [DiscoveredFile]) async {
        var generations: [String: Int] = [:]
        for file in batch {
            let generation = (readGenerations[file.relativePath] ?? 0) + 1
            readGenerations[file.relativePath] = generation
            generations[file.relativePath] = generation
        }
        let limits = limits
        // Bytes that hash the same as last time keep their names unread.
        let known = files
        let results = await withTaskGroup(of: (String, FileRead).self) { group in
            var results: [(String, FileRead)] = []
            var iterator = batch.makeIterator()
            func addRead(_ file: DiscoveredFile) {
                let previous = known[file.relativePath]
                group.addTask { (file.relativePath, await Self.readFile(file.url, limits: limits, previous: previous)) }
            }
            for _ in 0..<limits.concurrency {
                guard let file = iterator.next() else { break }
                addRead(file)
            }
            while let result = await group.next() {
                results.append(result)
                if let file = iterator.next() { addRead(file) }
            }
            return results
        }
        for (path, result) in results where readGenerations[path] == generations[path] {
            apply(result, at: path)
        }
    }

    private func apply(_ result: FileRead, at path: String) {
        switch result {
        case let .parsed(entry):
            setFile(entry, at: path)
        case .excluded:
            setFile(nil, at: path)
        }
    }

    // MARK: - Cache

    /// Whether what the index reads is being saved to the store.
    var isCachePersistent: Bool { store != nil }

    /// Opens the store and counts every file it holds, as of when the store
    /// last saw it; the first scan then re-reads only what changed since.
    /// Nothing is cached when the cache folder is inside the workspace,
    /// because Daisy writes nothing there but the marker and pages.
    private func loadCache() async {
        guard let directory = cacheDirectory, !isCacheDiscarded,
              !Self.isInside(directory, root: root),
              let parserVersion = WorkspaceMetadataExtractor.parserVersion else { return }
        do {
            let store = try await WorkspaceIndexStore.open(root: root, in: directory, parserVersion: parserVersion)
            let records = try await store.load()
            guard !isStopped, !isCacheDiscarded else {
                await store.close()
                if isCacheDiscarded { WorkspaceIndexStore.deleteCache(root: root, in: directory) }
                return
            }
            self.store = store
            // A file read while the store opened is newer than its row.
            for (path, record) in records where files[path] == nil && readGenerations[path] == nil {
                setFile(FileEntry(fingerprint: Fingerprint(modificationDate: record.modificationDate, size: record.size),
                                  hash: record.hash, contribution: record.contribution), at: path)
                // The store already has it.
                unsavedPaths.remove(path)
            }
            if !records.isEmpty { publish() }
        } catch {
            await closeStore()
        }
    }

    nonisolated private static func isInside(_ url: URL, root: URL) -> Bool {
        let components = canonicalRoot(url).pathComponents
        let rootComponents = root.pathComponents
        return components.count >= rootComponents.count
            && Array(components.prefix(rootComponents.count)) == rootComponents
    }

    /// Saves every changed file, in order, one write at a time. A store
    /// that fails is dropped and the index carries on in memory.
    private func scheduleFlush() {
        guard store != nil, flushTask == nil, !unsavedPaths.isEmpty else { return }
        flushTask = Task { await runFlushLoop() }
    }

    private func runFlushLoop() async {
        while let store, !unsavedPaths.isEmpty {
            let changes = unsavedPaths.sorted().map { path in
                (path: path, record: files[path].map {
                    WorkspaceIndexStore.Record(modificationDate: $0.fingerprint.modificationDate,
                                               size: $0.fingerprint.size, hash: $0.hash,
                                               contribution: $0.contribution)
                })
            }
            unsavedPaths.removeAll()
            do {
                try await store.write(changes)
            } catch {
                if self.store === store { await closeStore() }
            }
        }
        flushTask = nil
    }

    /// Waits until every change so far is in the store.
    func flushCache() async {
        while let running = flushTask { await running.value }
    }

    /// Deletes this workspace's cache file only and indexes the workspace
    /// again from nothing, saving a new file. Unsaved buffers still count.
    /// A store that had failed is tried again.
    func rebuildCache() async {
        guard !isStopped else { return }
        if let running = reconcileTask { await running.value }
        await flushTask?.value
        isCacheDiscarded = false
        if let store {
            do {
                try await store.reset()
            } catch {
                // Open it again, from nothing, before the scan below.
                await closeStore()
                isCacheLoaded = false
            }
        } else if let directory = cacheDirectory {
            WorkspaceIndexStore.deleteCache(root: root, in: directory)
            isCacheLoaded = false
        }
        for path in files.keys { setFile(nil, at: path) }
        unsavedPaths.removeAll()
        isComplete = false
        publish()
        await reconcile()
    }

    /// Closes and deletes this workspace's cache, for Remove Workspace, and
    /// writes no other.
    func discardCache() async {
        isCacheDiscarded = true
        isCacheLoaded = true
        await flushTask?.value
        await closeStore()
        if let directory = cacheDirectory {
            WorkspaceIndexStore.deleteCache(root: root, in: directory)
        }
    }

    // MARK: - Unsaved buffers

    /// Counts `markdown` in place of the saved file at `url` until
    /// `restoreDiskContribution` is called for `owner`. Each owner, one per
    /// window, has one buffer per file, and only the latest one counts, so
    /// tabs on one file never count it twice.
    func setOverlay(_ markdown: String, for url: URL, owner: UUID) async {
        guard let path = relativePath(of: url) else { return }
        guard let metadata = await Self.extract(markdown) else { return }
        let effective = effectiveContribution(at: path)
        var stack = overlays[path] ?? []
        stack.removeAll { $0.owner == owner }
        stack.append((owner, WorkspaceMetadataContribution(metadata)))
        overlays[path] = stack
        replaceEffective(effective, at: path)
        publish()
    }

    /// Drops `owner`'s buffer for `url` and re-reads the file, which holds
    /// the saved text after a save and the old text after a discard.
    func restoreDiskContribution(for url: URL, owner: UUID) async {
        guard let path = relativePath(of: url) else { return }
        let file = DiscoveredFile(relativePath: path, url: root.appending(path: path),
                                  fingerprint: Fingerprint(modificationDate: nil, size: nil))
        if !isTruncated || files[path] != nil {
            await read([file])
            scheduleFlush()
        }
        let effective = effectiveContribution(at: path)
        overlays[path]?.removeAll { $0.owner == owner }
        if overlays[path]?.isEmpty == true { overlays[path] = nil }
        replaceEffective(effective, at: path)
        publish()
    }

    // MARK: - Aggregate

    private func effectiveContribution(at path: String) -> WorkspaceMetadataContribution? {
        overlays[path]?.last?.contribution ?? files[path]?.contribution
    }

    private func setFile(_ entry: FileEntry?, at path: String) {
        let effective = effectiveContribution(at: path)
        if files[path] != entry { unsavedPaths.insert(path) }
        files[path] = entry
        replaceEffective(effective, at: path)
    }

    private func replaceEffective(_ old: WorkspaceMetadataContribution?, at path: String) {
        let new = effectiveContribution(at: path)
        guard old != new else { return }
        if let old { aggregate.merge(old, sign: -1) }
        if let new { aggregate.merge(new, sign: 1) }
    }

    // MARK: - Files

    /// The key for a file the scan would index, or nil: outside the root,
    /// in a hidden, pruned or package folder, too deep, not Markdown, or a
    /// symlink to anything outside the root. A symlink inside the root keys
    /// as its target, so the file counts once.
    private func relativePath(of url: URL) -> String? {
        Self.relativePath(of: url, root: root, limits: limits)
    }

    nonisolated private static func relativePath(of url: URL, root: URL, limits: Limits) -> String? {
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
        let rootComponents = root.pathComponents
        let components = resolved.pathComponents
        guard components.count > rootComponents.count,
              Array(components.prefix(rootComponents.count)) == rootComponents else { return nil }
        let relative = Array(components.dropFirst(rootComponents.count))
        guard relative.count <= limits.maximumDepth,
              !relative.contains(where: { $0.hasPrefix(".") }),
              !relative.dropLast().contains(where: ProjectFileIndex.prunedDirectoryNames.contains),
              FileKind.classify(resolved) == .markdown else { return nil }
        var folder = root
        for name in relative.dropLast() {
            folder.append(path: name, directoryHint: .isDirectory)
            if (try? folder.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true { return nil }
        }
        return relative.joined(separator: "/")
    }

    @concurrent
    nonisolated private static func discover(root: URL, limits: Limits) async -> ([DiscoveredFile], Bool) {
        let walk = ProjectFileIndex.build(root: root,
                                          maximumFileCount: limits.maximumFileCount,
                                          maximumDepth: limits.maximumDepth)
        var seen: Set<String> = []
        var discovered: [DiscoveredFile] = []
        for position in walk.candidates.indices {
            guard let url = walk.url(at: position),
                  let path = relativePath(of: url, root: root, limits: limits),
                  seen.insert(path).inserted else { continue }
            let target = root.appending(path: path)
            let values = try? target.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            discovered.append(DiscoveredFile(relativePath: path, url: target,
                                             fingerprint: Fingerprint(modificationDate: values?.contentModificationDate,
                                                                      size: values?.fileSize)))
        }
        return (discovered, walk.isTruncated)
    }

    @concurrent
    nonisolated private static func readFile(_ url: URL, limits: Limits, previous: FileEntry?) async -> FileRead {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let values = try? url.resourceValues(forKeys: keys),
              values.isRegularFile == true else { return .excluded }
        guard let size = values.fileSize, size <= limits.maximumFileSize,
              let data = try? Data(contentsOf: url) else { return .excluded }
        let fingerprint = Fingerprint(modificationDate: values.contentModificationDate, size: size)
        let hash = Data(SHA256.hash(data: data))
        if let previous, previous.hash == hash {
            return .parsed(FileEntry(fingerprint: fingerprint, hash: hash, contribution: previous.contribution))
        }
        guard let markdown = String(data: data, encoding: .utf8),
              let metadata = WorkspaceMetadataExtractor.extract(markdown) else { return .excluded }
        return .parsed(FileEntry(fingerprint: fingerprint, hash: hash,
                                 contribution: WorkspaceMetadataContribution(metadata)))
    }

    @concurrent
    nonisolated private static func extract(_ markdown: String) async -> WorkspaceMetadata? {
        WorkspaceMetadataExtractor.extract(markdown)
    }
}

// MARK: - Sharing one index per root

extension WorkspaceMetadataIndex {
    /// How long an index outlives the last window using it, so closing and
    /// reopening a window does not rescan.
    @MainActor static var idleReleaseInterval: Duration = .seconds(60)

    /// Where acquired indexes keep their caches; nil keeps them in memory.
    @MainActor static var cacheDirectory: URL? = WorkspaceIndexStore.defaultDirectory

    @MainActor private static var entries: [URL: (index: WorkspaceMetadataIndex, users: Int, generation: Int)] = [:]

    /// The index for `root`, started, shared with every other user of the
    /// same canonical root. Pair each call with `release`.
    @MainActor static func acquire(root: URL) -> WorkspaceMetadataIndex {
        let key = canonicalRoot(root)
        if let entry = entries[key] {
            entries[key] = (entry.index, entry.users + 1, entry.generation + 1)
            return entry.index
        }
        let index = WorkspaceMetadataIndex(root: key, cacheDirectory: cacheDirectory)
        entries[key] = (index, 1, 0)
        Task { await index.start() }
        return index
    }

    /// Stops the index once nobody has acquired it again for
    /// `idleReleaseInterval`.
    @MainActor static func release(_ index: WorkspaceMetadataIndex) {
        guard let entry = entries[index.root], entry.index === index else { return }
        let users = entry.users - 1
        entries[index.root] = (index, users, entry.generation + 1)
        guard users == 0 else { return }
        let generation = entry.generation + 1
        Task { @MainActor in
            try? await Task.sleep(for: idleReleaseInterval)
            guard let current = entries[index.root], current.index === index,
                  current.users == 0, current.generation == generation else { return }
            entries[index.root] = nil
            await index.stop()
        }
    }

    /// Indexes still held, by canonical root. For tests.
    @MainActor static func existingIndex(root: URL) -> WorkspaceMetadataIndex? {
        entries[canonicalRoot(root)]?.index
    }

    /// Deletes the workspace's cache, through its index when one is held,
    /// for Remove Workspace.
    @MainActor static func discardCache(root: URL) {
        let key = canonicalRoot(root)
        if let index = entries[key]?.index {
            Task { await index.discardCache() }
        } else if let directory = cacheDirectory {
            Task.detached(priority: .utility) { WorkspaceIndexStore.deleteCache(root: key, in: directory) }
        }
    }

    /// Rebuilds the cache of the workspace on `root`, if it is indexed.
    @MainActor static func rebuildCache(root: URL) {
        guard let index = entries[canonicalRoot(root)]?.index else { return }
        Task { await index.rebuildCache() }
    }

    /// Deletes caches of workspaces not opened for 30 days, at launch.
    @MainActor static func purgeStaleCaches() {
        guard let directory = cacheDirectory else { return }
        Task.detached(priority: .background) { WorkspaceIndexStore.purgeStaleCaches(in: directory) }
    }

    /// Reconciles every index, as when Daisy becomes active again.
    @MainActor static func reconcileAll() {
        for entry in entries.values {
            Task { await entry.index.reconcile() }
        }
    }
}
