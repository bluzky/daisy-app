import CoreServices
import Foundation
import XCTest
@testable import MarkdownHelpers

final class WorkspaceMetadataIndexTests: XCTestCase {
    private var root: URL!

    override class func setUp() {
        super.setUp()
        TestVendor.installWorkspaceMetadataExtractor()
    }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspaceMetadataIndexTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o644],
                                               ofItemAtPath: root.appending(path: "locked.md").path)
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func write(_ text: String, to path: String) throws -> URL {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func names(_ snapshot: WorkspaceMetadataSnapshot,
                       _ kind: WorkspaceMetadataKind) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: snapshot.candidates(kind).map { ($0.name, $0.count) })
    }

    private func assertTags(_ index: WorkspaceMetadataIndex, _ expected: [String: Int],
                            file: StaticString = #filePath, line: UInt = #line) async {
        let tags = names(await index.snapshot(), .tag)
        XCTAssertEqual(tags, expected, file: file, line: line)
    }

    private func scanned(limits: WorkspaceMetadataIndex.Limits = .init()) async -> WorkspaceMetadataIndex {
        let index = WorkspaceMetadataIndex(root: root, limits: limits)
        await index.reconcile()
        return index
    }

    // MARK: - Scanning

    func testScanCountsNamesAcrossFiles() async throws {
        try write("Plan #Release @Desk +Daisy\n- [ ] Ship #release due:2026-01-02 p:high", to: "a.md")
        try write("#Release notes +daisy +Daisy", to: "notes/b.markdown")
        try write("#ignored", to: "c.txt")

        let snapshot = await scanned().snapshot()

        XCTAssertTrue(snapshot.isComplete)
        XCTAssertFalse(snapshot.isTruncated)
        // The most used spelling wins; a tie goes to the one that sorts first.
        XCTAssertEqual(names(snapshot, .tag), ["Release": 3])
        XCTAssertEqual(names(snapshot, .context), ["Desk": 1])
        XCTAssertEqual(names(snapshot, .project), ["Daisy": 3])
    }

    func testTieBetweenSpellingsIsDeterministic() async throws {
        try write("#beta #Beta", to: "a.md")
        await assertTags(await scanned(), ["Beta": 2])
    }

    func testScanPublishesPartialSnapshots() async throws {
        for number in 1...3 {
            try write("#tag\(number)", to: "\(number).md")
        }
        var limits = WorkspaceMetadataIndex.Limits()
        limits.batchSize = 1
        limits.concurrency = 1
        let index = WorkspaceMetadataIndex(root: root, limits: limits)
        let stream = await index.snapshots()
        let collector = Task {
            var snapshots: [WorkspaceMetadataSnapshot] = []
            for await snapshot in stream {
                snapshots.append(snapshot)
                if snapshot.isComplete { break }
            }
            return snapshots
        }
        await index.reconcile()
        let snapshots = await collector.value

        XCTAssertTrue(snapshots.contains { !$0.isComplete && !$0.tags.isEmpty })
        XCTAssertEqual(snapshots.last?.tags.count, 3)
        let versions = snapshots.map(\.version)
        XCTAssertEqual(versions, versions.sorted())
        XCTAssertEqual(Set(versions).count, versions.count)
    }

    func testScanExcludesHiddenPrunedAndOversizedFiles() async throws {
        try write("#kept", to: "kept.md")
        try write("#hidden", to: ".hidden/a.md")
        try write("#dotfile", to: ".notes.md")
        try write("#vendored", to: "node_modules/pkg/README.md")
        try write("#packaged", to: "Thing.app/Contents/a.md")
        try write("#large " + String(repeating: "x", count: 200), to: "large.md")
        var limits = WorkspaceMetadataIndex.Limits()
        limits.maximumFileSize = 100

        let snapshot = await scanned(limits: limits).snapshot()

        XCTAssertEqual(names(snapshot, .tag), ["kept": 1])
    }

    func testUnreadableFilesAreLeftOut() async throws {
        try write("#kept", to: "kept.md")
        let locked = try write("#locked", to: "locked.md")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)

        let index = await scanned()
        await assertTags(index, ["kept": 1])

        // A file that becomes unreadable after the scan drops out too.
        let kept = root.appending(path: "kept.md")
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: kept.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: kept.path) }
        await index.filesChanged([kept])
        await assertTags(index, [:])
    }

    func testScanCapIsReported() async throws {
        for number in 1...5 {
            try write("#tag\(number)", to: "\(number).md")
        }
        var limits = WorkspaceMetadataIndex.Limits()
        limits.maximumFileCount = 2

        let snapshot = await scanned(limits: limits).snapshot()

        XCTAssertTrue(snapshot.isTruncated)
        XCTAssertEqual(snapshot.tags.count, 2)
    }

    func testSymlinksOutsideTheRootAreNotFollowed() async throws {
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspaceMetadataIndexOutside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try "#outside".write(to: outside.appending(path: "o.md"), atomically: true, encoding: .utf8)
        try write("#inside", to: "real.md")
        let fileManager = FileManager.default
        try fileManager.createSymbolicLink(at: root.appending(path: "o.md"),
                                           withDestinationURL: outside.appending(path: "o.md"))
        try fileManager.createSymbolicLink(at: root.appending(path: "folder"), withDestinationURL: outside)
        try fileManager.createSymbolicLink(at: root.appending(path: "alias.md"),
                                           withDestinationURL: root.appending(path: "real.md"))

        let snapshot = await scanned().snapshot()

        // The alias inside the root counts its target once.
        XCTAssertEqual(names(snapshot, .tag), ["inside": 1])
    }

    // MARK: - Changes

    func testFileChangesUpdateTheIndex() async throws {
        let a = try write("#alpha", to: "a.md")
        let index = await scanned()

        try write("#alpha #beta", to: "a.md")
        await index.filesChanged([a])
        await assertTags(index, ["alpha": 1, "beta": 1])

        let b = try write("#gamma", to: "b.md")
        await index.filesChanged([b])
        await assertTags(index, ["alpha": 1, "beta": 1, "gamma": 1])

        let renamed = root.appending(path: "c.md")
        try FileManager.default.moveItem(at: b, to: renamed)
        await index.filesChanged([b, renamed])
        await assertTags(index, ["alpha": 1, "beta": 1, "gamma": 1])

        try FileManager.default.removeItem(at: renamed)
        await index.filesChanged([renamed])
        await assertTags(index, ["alpha": 1, "beta": 1])

        // Files the scan would not index are ignored.
        let hidden = try write("#hidden", to: ".daisy/x.md")
        await index.filesChanged([hidden])
        await assertTags(index, ["alpha": 1, "beta": 1])
    }

    func testReconcileFindsChangesWithoutEvents() async throws {
        try write("#alpha", to: "a.md")
        try write("#beta", to: "b.md")
        let index = await scanned()

        // A different size, so the fingerprint changes.
        try write("#alpha #delta", to: "a.md")
        try FileManager.default.removeItem(at: root.appending(path: "b.md"))
        try write("#gamma", to: "sub/c.md")
        await index.reconcile()

        await assertTags(index, ["alpha": 1, "delta": 1, "gamma": 1])
    }

    // MARK: - Unsaved buffers

    func testOverlayReplacesSavedContributionAndRestores() async throws {
        let a = try write("#saved", to: "a.md")
        let index = await scanned()
        let owner = UUID()

        await index.setOverlay("#draft #draft", for: a, owner: owner)
        await assertTags(index, ["draft": 2])

        // Discard: the file still holds the saved text.
        await index.restoreDiskContribution(for: a, owner: owner)
        await assertTags(index, ["saved": 1])

        // Save: the file now holds the buffer's text.
        await index.setOverlay("#draft", for: a, owner: owner)
        try write("#draft", to: "a.md")
        await index.restoreDiskContribution(for: a, owner: owner)
        await assertTags(index, ["draft": 1])
    }

    func testSnapshotExcludingAFileLeavesOutItsNames() async throws {
        let a = try write("@Minh #shared", to: "a.md")
        let b = try write("@Minh @mike #shared", to: "b.md")
        let index = await scanned()

        // A half-typed `@M` in a's unsaved buffer.
        await index.setOverlay("@Minh #shared @M", for: a, owner: UUID())
        let all = await index.snapshot()
        let withoutA = await index.snapshot(excludingNamesOf: a)
        let withoutB = await index.snapshot(excludingNamesOf: b)
        let withoutNone = await index.snapshot(excludingNamesOf: nil)
        XCTAssertEqual(names(all, .context), ["Minh": 2, "mike": 1, "M": 1])
        XCTAssertEqual(names(withoutA, .context), ["Minh": 1, "mike": 1], "the editor on a supplies a's names itself")
        XCTAssertEqual(names(withoutA, .tag), ["shared": 1])
        XCTAssertEqual(names(withoutB, .context), ["Minh": 1, "M": 1])
        XCTAssertEqual(names(withoutNone, .context), names(all, .context))
    }

    func testTwoTabsOnOneFileCountItOnce() async throws {
        let a = try write("#saved", to: "a.md")
        let index = await scanned()
        let first = UUID(), second = UUID()

        await index.setOverlay("#one", for: a, owner: first)
        await index.setOverlay("#two", for: a, owner: second)
        await assertTags(index, ["two": 1])

        await index.restoreDiskContribution(for: a, owner: second)
        await assertTags(index, ["one": 1])
        await index.restoreDiskContribution(for: a, owner: first)
        await assertTags(index, ["saved": 1])
    }

    func testOverlayOutsideTheRootIsIgnored() async throws {
        try write("#saved", to: "a.md")
        let index = await scanned()
        let outside = FileManager.default.temporaryDirectory.appending(path: "elsewhere.md")

        await index.setOverlay("#draft", for: outside, owner: UUID())

        await assertTags(index, ["saved": 1])
    }

    // MARK: - Tasks

    private func taskTexts(_ index: WorkspaceMetadataIndex) async -> [String] {
        await index.tasks().map { "\($0.path):\($0.task.line) \($0.task.checked ? "x" : "o") \($0.task.text)" }
    }

    func testTasksAreKeptPerFile() async throws {
        try write("- [ ] Ship #release due:2026-10-23 p:high\n- [x] Done scheduled:2026-10-20", to: "b.md")
        try write("Intro\n\n- [ ] Plan +daisy", to: "a.md")
        let index = await scanned()

        let texts = await taskTexts(index)
        XCTAssertEqual(texts, ["a.md:3 o Plan +daisy", "b.md:1 o Ship #release", "b.md:2 x Done"])
        let tasks = await index.tasks()
        let first = try XCTUnwrap(tasks.first { $0.path == "b.md" })
        XCTAssertEqual(first.task.due, "2026-10-23")
        XCTAssertEqual(first.task.priority, "high")
        // Tasks never reach the completion snapshot.
        await assertTags(index, ["release": 1])
    }

    func testTaskRevisionFollowsOnlyTaskChanges() async throws {
        let a = try write("#one\n- [ ] Task due:2026-10-23", to: "a.md")
        let index = await scanned()
        var revision = await index.taskRevision

        func expect(_ changed: Bool, after text: String, _ message: String,
                    file: StaticString = #filePath, line: UInt = #line) async throws {
            try write(text, to: "a.md")
            await index.filesChanged([a])
            let next = await index.taskRevision
            XCTAssertEqual(next != revision, changed, message, file: file, line: line)
            revision = next
        }
        try await expect(false, after: "#one\n- [ ] Task due:2026-10-23", "unchanged re-read")
        try await expect(false, after: "#two\n- [ ] Task due:2026-10-23", "tag-only edit")
        try await expect(true, after: "#two\n- [ ] Task due:2026-10-24", "due only")
        try await expect(true, after: "#two\n- [ ] Task due:2026-10-24 scheduled:2026-10-22", "scheduled only")
        try await expect(true, after: "#two\n- [x] Task due:2026-10-24 scheduled:2026-10-22", "checked only")
        try await expect(true, after: "#two\n- [x] Renamed due:2026-10-24 scheduled:2026-10-22", "text only")

        let owner = UUID()
        await index.setOverlay("- [ ] Draft due:2026-10-25", for: a, owner: owner)
        let afterOverlay = await index.taskRevision
        XCTAssertNotEqual(afterOverlay, revision, "overlay set")
        await index.restoreDiskContribution(for: a, owner: owner)
        let afterRestore = await index.taskRevision
        XCTAssertNotEqual(afterRestore, afterOverlay, "overlay cleared")

        try FileManager.default.removeItem(at: a)
        await index.filesChanged([a])
        let afterDelete = await index.taskRevision
        XCTAssertNotEqual(afterDelete, afterRestore, "delete")
        let tasks = await index.tasks()
        XCTAssertEqual(tasks, [])
    }

    func testTaskChangesStreamYieldsRevisions() async throws {
        let a = try write("- [ ] Task", to: "a.md")
        let index = await scanned()
        let stream = await index.taskChanges()
        var iterator = stream.makeAsyncIterator()
        let initial = await iterator.next()
        let initialRevision = await index.taskRevision
        XCTAssertEqual(initial, initialRevision)

        try write("- [x] Task", to: "a.md")
        await index.filesChanged([a])
        let next = await iterator.next()
        let nextRevision = await index.taskRevision
        XCTAssertEqual(next, nextRevision)
        XCTAssertGreaterThan(next ?? 0, initial ?? 0)
    }

    func testRecordTaskWriteUpdatesTasksImmediately() async throws {
        let a = try write("- [ ] Task", to: "a.md")
        let index = await scanned()
        let before = await index.taskRevision

        await index.recordTaskWrite(markdown: "- [x] Task", for: a)

        let texts = await taskTexts(index)
        XCTAssertEqual(texts, ["a.md:1 x Task"])
        let after = await index.taskRevision
        XCTAssertNotEqual(after, before)
        // The disk still says otherwise; the next read is believed.
        await index.filesChanged([a])
        let reread = await taskTexts(index)
        XCTAssertEqual(reread, ["a.md:1 o Task"])
    }

    // MARK: - Workspaces

    func testOverlappingWorkspacesIndexIndependently() async throws {
        try write("#outer", to: "a.md")
        try write("#inner", to: "sub/b.md")

        let outer = await scanned().snapshot()
        let inner = WorkspaceMetadataIndex(root: root.appending(path: "sub"))
        await inner.reconcile()

        XCTAssertEqual(names(outer, .tag), ["inner": 1, "outer": 1])
        await assertTags(inner, ["inner": 1])
    }

    @MainActor
    func testWindowsOnOneRootShareAnIndexUntilIdle() async throws {
        let alias = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspaceMetadataIndexAlias-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
        defer { try? FileManager.default.removeItem(at: alias) }
        try FileManager.default.createDirectory(at: root.appending(path: "sub"), withIntermediateDirectories: true)
        WorkspaceMetadataIndex.idleReleaseInterval = .milliseconds(50)
        defer { WorkspaceMetadataIndex.idleReleaseInterval = .seconds(60) }

        let first = WorkspaceMetadataIndex.acquire(root: root)
        let second = WorkspaceMetadataIndex.acquire(root: alias.appending(path: "sub/.."))
        let nested = WorkspaceMetadataIndex.acquire(root: root.appending(path: "sub"))
        XCTAssertTrue(first === second)
        XCTAssertFalse(first === nested)

        WorkspaceMetadataIndex.release(first)
        WorkspaceMetadataIndex.release(nested)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(WorkspaceMetadataIndex.existingIndex(root: root) === first)
        XCTAssertNil(WorkspaceMetadataIndex.existingIndex(root: root.appending(path: "sub")))

        WorkspaceMetadataIndex.release(second)
        // Acquiring again before the interval ends keeps the index.
        let third = WorkspaceMetadataIndex.acquire(root: root)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(third === first)
        WorkspaceMetadataIndex.release(third)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(WorkspaceMetadataIndex.existingIndex(root: root))
    }

    func testSnapshotVersionsAreUniqueAcrossIndexes() async throws {
        let one = WorkspaceMetadataIndex(root: root)
        let two = WorkspaceMetadataIndex(root: root.appending(path: "other"))
        let first = await one.snapshot().version
        let second = await two.snapshot().version
        XCTAssertGreaterThan(WorkspaceMetadataSnapshot.empty().version, max(first, second))
        XCTAssertNotEqual(first, second)
    }

    // MARK: - Watching

    func testWatcherReportsNewFiles() async throws {
        try write("#before", to: "a.md")
        let index = WorkspaceMetadataIndex(root: root)
        await index.start()
        defer { Task { await index.stop() } }
        let stream = await index.snapshots()
        // Let the first scan finish so the event below is not folded into it.
        for await snapshot in stream where snapshot.isComplete { break }

        try write("#after", to: "b.md")
        let found = Task {
            for await snapshot in await index.snapshots()
            where snapshot.tags.contains(where: { $0.name == "after" }) {
                return true
            }
            return false
        }
        let timeout = Task {
            try await Task.sleep(for: .seconds(10))
            found.cancel()
        }
        let result = await found.value
        timeout.cancel()
        XCTAssertTrue(result, "the watcher never reported b.md")
    }

    func testWatcherAsksForRescanWhenFoldersChange() {
        let file = FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsFile | kFSEventStreamEventFlagItemModified)
        let folder = FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir | kFSEventStreamEventFlagItemRenamed)
        let dropped = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)

        XCTAssertEqual(WorkspaceDirectoryWatcher.change(paths: ["/w/a.md"], flags: [file]),
                       .files([URL(fileURLWithPath: "/w/a.md")]))
        XCTAssertEqual(WorkspaceDirectoryWatcher.change(paths: ["/w/a.md", "/w/sub"], flags: [file, folder]),
                       .rescan)
        XCTAssertEqual(WorkspaceDirectoryWatcher.change(paths: ["/w"], flags: [dropped]), .rescan)
    }
}
