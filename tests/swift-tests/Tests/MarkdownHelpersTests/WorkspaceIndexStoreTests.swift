import Foundation
import SQLite3
import XCTest
@testable import MarkdownHelpers

final class WorkspaceIndexStoreTests: XCTestCase {
    private var base: URL!
    private var root: URL!
    private var cache: URL!
    /// Files get this date, so one rewritten in place keeps its fingerprint
    /// and only the cache can explain what the index reports.
    private let fixedDate = Date(timeIntervalSinceReferenceDate: 800_000_000)

    override class func setUp() {
        super.setUp()
        TestVendor.installWorkspaceMetadataExtractor()
    }

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspaceIndexStoreTests-\(UUID().uuidString)", isDirectory: true)
        root = base.appending(path: "workspace", directoryHint: .isDirectory)
        cache = base.appending(path: "Caches/WorkspaceIndex", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        root = WorkspaceMetadataIndex.canonicalRoot(root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: base)
    }

    // MARK: - Helpers

    @discardableResult
    private func write(_ text: String, to path: String, in folder: URL? = nil) throws -> URL {
        let url = (folder ?? root).appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: fixedDate], ofItemAtPath: url.path)
        return url
    }

    private func tags(_ index: WorkspaceMetadataIndex) async -> [String: Int] {
        Dictionary(uniqueKeysWithValues: await index.snapshot().candidates(.tag).map { ($0.name, $0.count) })
    }

    /// Scans `folder`, saving to `cache`, and waits until the store has it.
    private func cached(_ folder: URL? = nil, cacheDirectory: URL? = nil) async -> WorkspaceMetadataIndex {
        let index = WorkspaceMetadataIndex(root: folder ?? root, cacheDirectory: cacheDirectory ?? cache)
        await index.reconcile()
        await index.flushCache()
        return index
    }

    private func cacheURL(_ folder: URL? = nil) -> URL {
        WorkspaceIndexStore.cacheURL(for: WorkspaceIndexStore.identity(of: folder ?? root), in: cache)
    }

    private func sql(_ statements: String, at url: URL) throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        // A stopped index closes its store a moment later.
        sqlite3_busy_timeout(database, 2000)
        let status = sqlite3_exec(database, statements, nil, nil, nil)
        XCTAssertEqual(status, SQLITE_OK, String(cString: sqlite3_errmsg(database)))
    }

    /// Writes `#alpha`, caches it, then swaps the text for `#bravo` with the
    /// same size and date: a reopen that reports `alpha` used the cache.
    private func cacheThenSwapInPlace() async throws {
        WorkspaceIndexStore.deleteCache(root: root, in: cache)
        try write("#alpha", to: "a.md")
        let first = await cached()
        await first.stop()
        try write("#bravo", to: "a.md")
    }

    // MARK: - Reopening

    func testReopenStartsFromCache() async throws {
        try await cacheThenSwapInPlace()
        let reopened = await cached()
        let tags = await tags(reopened)
        let isPersistent = await reopened.isCachePersistent
        XCTAssertEqual(tags, ["alpha": 1])
        XCTAssertTrue(isPersistent)
    }

    func testReopenRereadsChangedCreatedAndDeletedFiles() async throws {
        try write("#keep", to: "keep.md")
        try write("#gone", to: "gone.md")
        try write("#old", to: "edit.md")
        let first = await cached()
        await first.stop()

        try FileManager.default.removeItem(at: root.appending(path: "gone.md"))
        try "#new and longer".write(to: root.appending(path: "edit.md"), atomically: true, encoding: .utf8)
        try write("#added", to: "added.md")

        let reopened = await cached()
        await assertTags(reopened, ["keep": 1, "new": 1, "added": 1])
        let third = await cached()
        await assertTags(third, ["keep": 1, "new": 1, "added": 1])
    }

    func testUnsavedBufferIsNeverCached() async throws {
        let url = try write("#saved", to: "a.md")
        let first = await cached()
        await first.setOverlay("#draft", for: url, owner: UUID())
        await first.flushCache()
        await first.stop()

        let reopened = await cached()
        await assertTags(reopened, ["saved": 1])
    }

    // MARK: - Rejecting a cache

    func testIncompatibleCacheIsRebuilt() async throws {
        for key in ["schema", "parser", "root", "volume"] {
            try await cacheThenSwapInPlace()
            try sql("UPDATE meta SET value = 'other' WHERE key = '\(key)'", at: cacheURL())
            let reopened = await cached()
            await assertTags(reopened, ["bravo": 1], "\(key) mismatch")
            await reopened.stop()
        }
    }

    func testCorruptCacheIsRebuilt() async throws {
        try await cacheThenSwapInPlace()
        try Data(repeating: 0x5A, count: 8192).write(to: cacheURL())
        for suffix in ["-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(filePath: cacheURL().path + suffix))
        }

        let reopened = await cached()
        await assertTags(reopened, ["bravo": 1])
        let isPersistent = await reopened.isCachePersistent
        XCTAssertTrue(isPersistent, "a corrupt file is replaced, not given up on")
    }

    func testPurgedCacheIsRebuilt() async throws {
        try await cacheThenSwapInPlace()
        try FileManager.default.removeItem(at: cache)

        let reopened = await cached()
        await assertTags(reopened, ["bravo": 1])
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL().path))
    }

    func testRowLeavingTheRootRejectsTheWholeCache() async throws {
        try await cacheThenSwapInPlace()
        try sql("""
            INSERT INTO files (path, modified, size, hash) VALUES ('../outside.md', NULL, 1, zeroblob(32));
            INSERT INTO tokens (path, kind, key, spelling, count) VALUES ('../outside.md', 0, 'secret', 'secret', 1);
            """, at: cacheURL())

        let reopened = await cached()
        await assertTags(reopened, ["bravo": 1])
    }

    func testMalformedRowsRejectTheCache() async throws {
        let rows = [
            "UPDATE tokens SET kind = 9",
            "UPDATE tokens SET count = 0",
            "UPDATE files SET hash = x'00'",
            "INSERT INTO files (path, modified, size, hash) VALUES ('/etc/x.md', NULL, 1, zeroblob(32))",
        ]
        for row in rows {
            try await cacheThenSwapInPlace()
            try sql(row, at: cacheURL())
            let reopened = await cached()
            await assertTags(reopened, ["bravo": 1], row)
            await reopened.stop()
        }
    }

    func testImpossibleTokenRowsRejectTheCache() async throws {
        let rows = [
            // A token twice, which would add its count twice.
            "INSERT INTO tokens SELECT * FROM tokens",
            // Counts that would overflow once added up.
            "UPDATE tokens SET count = 9223372036854775807",
            "UPDATE tokens SET count = \(WorkspaceIndexStore.maximumOccurrencesPerFile + 1)",
            "UPDATE tokens SET spelling = 'two words'",
            "UPDATE tokens SET spelling = '#alpha'",
            "UPDATE tokens SET spelling = 'a//b'",
            "UPDATE tokens SET spelling = '123'",
            "UPDATE tokens SET key = 'two words'",
            "UPDATE tokens SET key = 'al' || char(10) || 'pha'",
        ]
        for row in rows {
            try await cacheThenSwapInPlace()
            try sql(row, at: cacheURL())
            let reopened = await cached()
            await assertTags(reopened, ["bravo": 1], row)
            await reopened.stop()
        }
    }

    func testNamesTheExtractorWritesAreAccepted() {
        for name in ["alpha", "Release_2", "-dash", "area/sub", "café", "cafe\u{301}", "日本語", "x1"] {
            XCTAssertTrue(WorkspaceIndexStore.isName(name), name)
        }
        for name in ["", "123", "/a", "a/", "a b", "#a", "a.b"] {
            XCTAssertFalse(WorkspaceIndexStore.isName(name), name)
        }
    }

    func testMovedRootDoesNotTrustTheOldCache() async throws {
        try await cacheThenSwapInPlace()
        // Before the move: the volume of a path that is gone is unknown.
        let oldCache = cacheURL()
        var moved = base.appending(path: "moved", directoryHint: .isDirectory)
        try FileManager.default.moveItem(at: root, to: moved)
        moved = WorkspaceMetadataIndex.canonicalRoot(moved)
        XCTAssertNotEqual(cacheURL(moved), oldCache)

        // The old file is keyed by the old path and is not looked at...
        let reopened = await cached(moved)
        await assertTags(reopened, ["bravo": 1])
        await reopened.stop()

        // ...and one copied to the new key names the old root, so it is rejected.
        try FileManager.default.removeItem(at: cacheURL(moved))
        try FileManager.default.copyItem(at: oldCache, to: cacheURL(moved))
        let copied = await cached(moved)
        await assertTags(copied, ["bravo": 1])
    }

    // MARK: - Falling back to memory

    func testUnwritableCacheFallsBackToMemory() async throws {
        try write("#alpha", to: "a.md")
        try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not a folder".utf8).write(to: cache)

        let index = await cached()
        await assertTags(index, ["alpha": 1])
        let isPersistent = await index.isCachePersistent
        XCTAssertFalse(isPersistent)
    }

    func testContendedCacheFallsBackToMemory() async throws {
        try write("#alpha", to: "a.md")
        let first = await cached()
        await first.stop()
        try write("#bravo", to: "b.md")

        var holder: OpaquePointer?
        XCTAssertEqual(sqlite3_open(cacheURL().path, &holder), SQLITE_OK)
        defer { sqlite3_close(holder) }
        sqlite3_busy_timeout(holder, 2000)
        XCTAssertEqual(sqlite3_exec(holder, "BEGIN EXCLUSIVE", nil, nil, nil), SQLITE_OK)

        let index = await cached()
        await assertTags(index, ["alpha": 1, "bravo": 1])
        let isPersistent = await index.isCachePersistent
        XCTAssertFalse(isPersistent)
        XCTAssertEqual(sqlite3_exec(holder, "ROLLBACK", nil, nil, nil), SQLITE_OK)

        // Leaving WAL needs every other connection closed: the failed open
        // must not have kept one.
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(holder, "PRAGMA journal_mode = DELETE", -1, &statement, nil), SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        XCTAssertEqual(sqlite3_column_text(statement, 0).map { String(cString: $0) }, "delete")
    }

    func testWithoutCacheDirectoryNothingIsWritten() async throws {
        try write("#alpha", to: "a.md")
        let index = WorkspaceMetadataIndex(root: root)
        await index.reconcile()
        await assertTags(index, ["alpha": 1])
        let isPersistent = await index.isCachePersistent
        XCTAssertFalse(isPersistent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
    }

    // MARK: - The workspace stays untouched

    func testNothingIsWrittenIntoTheWorkspace() async throws {
        try write("#alpha", to: "a.md")
        try write("#bravo", to: "notes/b.md")
        let index = await cached()
        await index.rebuildCache()
        await index.flushCache()
        await index.stop()

        let written = FileManager.default.enumerator(atPath: root.path)?.allObjects as? [String]
        XCTAssertEqual(Set(written ?? []), ["a.md", "notes", "notes/b.md"])
    }

    func testCacheFolderInsideTheWorkspaceIsNotUsed() async throws {
        try write("#alpha", to: "a.md")
        let inside = root.appending(path: "Library/Caches/WorkspaceIndex", directoryHint: .isDirectory)

        let index = await cached(cacheDirectory: inside)
        await assertTags(index, ["alpha": 1])
        let isPersistent = await index.isCachePersistent
        XCTAssertFalse(isPersistent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "Library").path))
    }

    // MARK: - Rebuild, remove, purge

    func testRebuildRecreatesOnlyThisWorkspacesCache() async throws {
        var other = base.appending(path: "other", directoryHint: .isDirectory)
        try write("#other", to: "o.md", in: other)
        other = WorkspaceMetadataIndex.canonicalRoot(other)
        let otherIndex = await cached(other)
        await otherIndex.stop()
        try write("#otter", to: "o.md", in: other)

        try await cacheThenSwapInPlace()
        let index = await cached()
        await assertTags(index, ["alpha": 1])
        await index.rebuildCache()
        await index.flushCache()
        await assertTags(index, ["bravo": 1])

        // The other workspace still opens from its untouched cache.
        let otherReopened = await cached(other)
        await assertTags(otherReopened, ["other": 1])
        await index.stop()
        let reopened = await cached()
        await assertTags(reopened, ["bravo": 1])
    }

    func testRebuildAfterTheCacheFolderWasPurgedKeepsCaching() async throws {
        try write("#alpha", to: "a.md")
        let index = await cached()
        // Resetting the open store fails: its folder is gone.
        try FileManager.default.removeItem(at: cache)

        await index.rebuildCache()
        await index.flushCache()
        let isPersistent = await index.isCachePersistent
        XCTAssertTrue(isPersistent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL().path))
        await assertTags(index, ["alpha": 1])
    }

    func testRebuildRetriesAFailedStore() async throws {
        try write("#alpha", to: "a.md")
        try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not a folder".utf8).write(to: cache)
        let index = await cached()
        try FileManager.default.removeItem(at: cache)

        await index.rebuildCache()
        await index.flushCache()
        let isPersistent = await index.isCachePersistent
        XCTAssertTrue(isPersistent)
        await assertTags(index, ["alpha": 1])
    }

    func testDiscardDeletesTheCacheAndWritesNoMore() async throws {
        try write("#alpha", to: "a.md")
        let index = await cached()
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL().path))

        await index.discardCache()
        try write("#bravo", to: "b.md")
        await index.reconcile()
        await index.flushCache()

        await assertTags(index, ["alpha": 1, "bravo": 1])
        let leftover = try FileManager.default.contentsOfDirectory(atPath: cache.path)
        XCTAssertEqual(leftover, [])
    }

    func testPurgeDeletesOnlyCachesNotOpenedFor30Days() throws {
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let now = Date()
        func make(_ name: String, openedDaysAgo days: Double) throws {
            for suffix in ["", "-wal", "-shm"] {
                let url = cache.appending(path: name + suffix)
                try Data().write(to: url)
                try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-days * 86_400)],
                                                      ofItemAtPath: url.path)
            }
        }
        try make("stale.sqlite", openedDaysAgo: 31)
        try make("fresh.sqlite", openedDaysAgo: 29)

        WorkspaceIndexStore.purgeStaleCaches(in: cache, now: now)

        let left = try FileManager.default.contentsOfDirectory(atPath: cache.path)
        XCTAssertEqual(Set(left), ["fresh.sqlite", "fresh.sqlite-wal", "fresh.sqlite-shm"])
    }

    func testOpeningMarksTheCacheOpened() async throws {
        try write("#alpha", to: "a.md")
        let first = await cached()
        await first.stop()
        let old = Date().addingTimeInterval(-40 * 86_400)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: cacheURL().path)

        _ = await cached()
        WorkspaceIndexStore.purgeStaleCaches(in: cache)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL().path))
    }

    // MARK: - Tasks

    /// Caches one task, then rewrites the file in place with the same size
    /// and date: a reopen that reports `alpha` read the task from the cache.
    private func cacheTaskThenSwapInPlace() async throws {
        WorkspaceIndexStore.deleteCache(root: root, in: cache)
        try write("- [ ] alpha due:2026-10-23 p:high", to: "a.md")
        let first = await cached()
        await first.stop()
        try write("- [x] bravo due:2026-10-23 p:high", to: "a.md")
    }

    func testReopenRestoresTasksWithoutRereading() async throws {
        try await cacheTaskThenSwapInPlace()
        let reopened = await cached()
        let tasks = await reopened.tasks()
        XCTAssertEqual(tasks, [WorkspaceIndexedTask(path: "a.md", task: WorkspaceTaskMetadata(
            line: 1, due: "2026-10-23", scheduled: nil, priority: "high", text: "alpha", checked: false))])
        let revision = await reopened.taskRevision
        XCTAssertGreaterThan(revision, 0, "a cache load signals tasks")
    }

    func testSchemaOneCacheIsRebuilt() async throws {
        try await cacheTaskThenSwapInPlace()
        try sql("DROP TABLE tasks; UPDATE meta SET value = '1' WHERE key = 'schema'", at: cacheURL())
        let reopened = await cached()
        let texts = await reopened.tasks().map(\.task.text)
        XCTAssertEqual(texts, ["bravo"])
    }

    func testMalformedTaskRowsRejectTheCache() async throws {
        let rows = [
            "UPDATE tasks SET line = 0",
            "UPDATE tasks SET checked = 2",
            "UPDATE tasks SET due = '2026-02-30'",
            "UPDATE tasks SET scheduled = 7",
            "UPDATE tasks SET priority = 'urgent'",
            "UPDATE tasks SET text = 'a' || char(10) || 'b'",
            "UPDATE tasks SET text = x'41'",
        ]
        for row in rows {
            try await cacheTaskThenSwapInPlace()
            try sql("PRAGMA foreign_keys = OFF; \(row)", at: cacheURL())
            let reopened = await cached()
            let texts = await reopened.tasks().map(\.task.text)
            XCTAssertEqual(texts, ["bravo"], row)
            await reopened.stop()
        }
    }

    func testOrphanTaskRowRejectsTheCache() async throws {
        try await cacheTaskThenSwapInPlace()
        try sql("""
            PRAGMA foreign_keys = OFF;
            INSERT INTO tasks (path, line, text, checked) VALUES ('ghost.md', 1, 'ghost', 0)
            """, at: cacheURL())
        let reopened = await cached()
        let texts = await reopened.tasks().map(\.task.text)
        XCTAssertEqual(texts, ["bravo"])
    }

    func testSafeRelativePaths() {
        for path in ["a.md", "notes/b.md", "a b/c.md"] {
            XCTAssertTrue(WorkspaceIndexStore.isSafeRelativePath(path), path)
        }
        for path in ["", "/a.md", "../a.md", "a/../../b.md", "./a.md", "a//b.md", "a/", "a\u{0}.md"] {
            XCTAssertFalse(WorkspaceIndexStore.isSafeRelativePath(path), path)
        }
    }

    private func assertTags(_ index: WorkspaceMetadataIndex, _ expected: [String: Int], _ message: String = "",
                            file: StaticString = #filePath, line: UInt = #line) async {
        let actual = await tags(index)
        XCTAssertEqual(actual, expected, message, file: file, line: line)
    }
}
