import Foundation
import XCTest
@testable import MarkdownHelpers

final class WorkspaceQueryTests: XCTestCase {
    private var root: URL!

    override class func setUp() {
        super.setUp()
        TestVendor.installWorkspaceMetadataExtractor()
    }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspaceQueryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        root = WorkspaceMetadataIndex.canonicalRoot(root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func record(_ markdown: String, at path: String) throws -> WorkspaceFileRecord {
        let metadata = try XCTUnwrap(WorkspaceMetadataExtractor.extract(markdown))
        return WorkspaceFileRecord(path: path, metadata: metadata, root: root)
    }

    @discardableResult
    private func write(_ text: String, to path: String) throws -> URL {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func paths(_ matches: [WorkspaceQueryMatch]) -> [String] {
        matches.map { match in
            switch match {
            case let .file(record): record.path
            case let .task(task): "\(task.path):\(task.task.line)"
            }
        }
    }

    // MARK: - Link targets

    func testLinkTargetsResolveAgainstTheRoot() {
        let cases: [(destination: String, from: String, target: String?)] = [
            ("b.md", "a.md", "b.md"),
            ("b.md", "notes/a.md", "notes/b.md"),
            ("../b.md", "notes/a.md", "b.md"),
            ("./sub/../c.md", "notes/a.md", "notes/c.md"),
            ("../b.md", "a.md", nil),
            ("../../x/b.md", "notes/a.md", nil),
            ("b.md#part", "a.md", "b.md"),
            ("my%20file.md", "a.md", "my file.md"),
            ("my file.md", "a.md", "my file.md"),
            (root.appending(path: "notes/b.md").path, "a.md", "notes/b.md"),
            ("/etc/hosts", "a.md", nil),
            (root.appending(path: "notes/b.md").absoluteString, "a.md", "notes/b.md"),
            ("file:///etc/hosts", "a.md", nil),
        ]
        for (destination, from, target) in cases {
            XCTAssertEqual(WorkspaceFileRecord.target(of: destination, from: from, root: root), target,
                           "\(destination) from \(from)")
        }
    }

    func testRecordResolvesLinksAndKeepsTheDestination() throws {
        let record = try record("[b](../b.md#x) [out](../../out.md)\n---\n", at: "notes/a.md")
        XCTAssertEqual(record.links, [
            WorkspaceLinkOccurrence(destination: "../b.md#x", target: "b.md", line: 1,
                                    excerpt: "[b](../b.md#x) [out](../../out.md)"),
            WorkspaceLinkOccurrence(destination: "../../out.md", target: nil, line: 1,
                                    excerpt: "[b](../b.md#x) [out](../../out.md)"),
        ])
    }

    func testFrontmatterTagsCountForCompletion() async throws {
        try write("---\ntags: [Work, home]\ncontexts: phone\n---\nBody #work", to: "a.md")
        let index = WorkspaceMetadataIndex(root: root)
        await index.reconcile()
        let snapshot = await index.snapshot()
        XCTAssertEqual(snapshot.tags.map(\.name), ["home", "Work"])
        XCTAssertEqual(snapshot.tags.map(\.count), [1, 2])
        XCTAssertEqual(snapshot.contexts.map(\.name), ["phone"])
    }

    // MARK: - Predicates

    private func corpus() throws -> [WorkspaceFileRecord] {
        [
            try record("""
                ---
                status: active
                rating: 4
                tags: [area/sub]
                reviewers: [Ana, Bo]
                published: true
                deadline: 2026-03-01
                ---
                - [ ] Call @phone +daisy due:2026-02-01 p:high
                - [x] Done +daisy due:2026-01-15 p:low
                - [ ] Later [spec](spec.md) scheduled:2026-04-01
                """, at: "projects/a.md"),
            try record("""
                ---
                status: Archived
                rating: 10
                ---
                Mentions #area and [a](projects/a.md).
                - [ ] Elsewhere @desk p:medium
                """, at: "b.md"),
            try record("No frontmatter at all", at: "notes/c.md"),
        ]
    }

    private func run(_ source: WorkspaceQuery.Source, _ filter: WorkspacePredicate,
                     sort: [WorkspaceSortKey] = [], limit: Int? = nil) throws -> [String] {
        let query = WorkspaceQuery(source: source, filter: filter, sort: sort, limit: limit)
        return paths(query.evaluate(try corpus(), info: { path in
            WorkspaceFileInfo(modified: nil, created: nil, size: path.count)
        }))
    }

    func testFilePredicates() throws {
        XCTAssertEqual(try run(.files, .and([])), ["b.md", "notes/c.md", "projects/a.md"])
        XCTAssertEqual(try run(.files, .attribute("status", .equal, .text("archived"))), ["b.md"])
        XCTAssertEqual(try run(.files, .attribute("rating", .greater, .text("5"))), ["b.md"])
        XCTAssertEqual(try run(.files, .attribute("rating", .lessOrEqual, .number(4, text: "4"))), ["projects/a.md"])
        XCTAssertEqual(try run(.files, .attribute("reviewers", .equal, .text("bo"))), ["projects/a.md"])
        XCTAssertEqual(try run(.files, .attribute("published", .equal, .text("true"))), ["projects/a.md"])
        XCTAssertEqual(try run(.files, .attribute("deadline", .less, .date(JournalDay(string: "2026-04-01")!))),
                       ["projects/a.md"])
        XCTAssertEqual(try run(.files, .hasAttribute("status")), ["b.md", "projects/a.md"])
        XCTAssertEqual(try run(.files, .hasToken(.tag, key: "area", includingDescendants: false)), ["b.md"])
        XCTAssertEqual(try run(.files, .hasToken(.tag, key: "area", includingDescendants: true)),
                       ["b.md", "projects/a.md"])
        XCTAssertEqual(try run(.files, .linksTo(path: "projects/a.md")), ["b.md"])
        XCTAssertEqual(try run(.files, .inFolder("projects/")), ["projects/a.md"])
        XCTAssertEqual(try run(.files, .inFolder("")), ["b.md", "notes/c.md", "projects/a.md"])
        XCTAssertEqual(try run(.files, .textContains("C.MD")), ["notes/c.md"])
        XCTAssertEqual(try run(.files, .checked(false)), [])
        XCTAssertEqual(try run(.files, .attribute("file.size", .greater, .text("8"))), ["notes/c.md", "projects/a.md"])
        XCTAssertEqual(try run(.files, .attribute("file.name", .equal, .text("b.md"))), ["b.md"])
    }

    func testTaskPredicates() throws {
        XCTAssertEqual(try run(.tasks, .checked(false)), ["b.md:6", "projects/a.md:9", "projects/a.md:11"])
        XCTAssertEqual(try run(.tasks, .hasToken(.project, key: "daisy", includingDescendants: false)),
                       ["projects/a.md:9", "projects/a.md:10"])
        XCTAssertEqual(try run(.tasks, .attribute("due", .lessOrEqual, .text("2026-01-31"))), ["projects/a.md:10"])
        XCTAssertEqual(try run(.tasks, .attribute("priority", .greaterOrEqual, .text("medium"))),
                       ["b.md:6", "projects/a.md:9"])
        XCTAssertEqual(try run(.tasks, .hasAttribute("scheduled")), ["projects/a.md:11"])
        XCTAssertEqual(try run(.tasks, .linksTo(path: "projects/spec.md")), ["projects/a.md:11"])
        // A task reads its file's frontmatter after its own fields.
        XCTAssertEqual(try run(.tasks, .attribute("status", .equal, .text("active"))),
                       ["projects/a.md:9", "projects/a.md:10", "projects/a.md:11"])
        XCTAssertEqual(try run(.tasks, .textContains("call")), ["projects/a.md:9"])
    }

    func testBooleanLogic() throws {
        let daisy = WorkspacePredicate.hasToken(.project, key: "daisy", includingDescendants: false)
        XCTAssertEqual(try run(.tasks, .and([daisy, .not(.checked(true))])), ["projects/a.md:9"])
        XCTAssertEqual(try run(.tasks, .or([.checked(true), .hasToken(.context, key: "desk",
                                                                      includingDescendants: false)])),
                       ["b.md:6", "projects/a.md:10"])
        XCTAssertEqual(try run(.tasks, .not(.or([daisy, .checked(true)]))), ["b.md:6", "projects/a.md:11"])
    }

    func testSortingAndLimit() throws {
        XCTAssertEqual(try run(.tasks, .and([]), sort: [WorkspaceSortKey(key: "due")]),
                       ["projects/a.md:10", "projects/a.md:9", "b.md:6", "projects/a.md:11"],
                       "tasks without the key sort last")
        XCTAssertEqual(try run(.tasks, .and([]), sort: [WorkspaceSortKey(key: "due", descending: true)]),
                       ["projects/a.md:9", "projects/a.md:10", "b.md:6", "projects/a.md:11"])
        XCTAssertEqual(try run(.tasks, .hasAttribute("priority"), sort: [WorkspaceSortKey(key: "priority",
                                                                                         descending: true)]),
                       ["projects/a.md:9", "b.md:6", "projects/a.md:10"])
        XCTAssertEqual(try run(.files, .hasAttribute("rating"), sort: [WorkspaceSortKey(key: "rating")]),
                       ["projects/a.md", "b.md"], "numbers sort as numbers, not text")
        XCTAssertEqual(try run(.files, .hasAttribute("status"), sort: [WorkspaceSortKey(key: "status")]),
                       ["projects/a.md", "b.md"])
        XCTAssertEqual(try run(.files, .and([]), limit: 2), ["b.md", "notes/c.md"])
    }

    // MARK: - References

    func testReferencesListLinksAndPageTokens() async throws {
        try write("# #Area/Sub\n[self](%23area--sub.md) #area/sub", to: "pages/#area--sub.md")
        try write("Uses #AREA/sub", to: "a.md")
        try write("Uses #area--sub and +area/sub", to: "b.md")
        try write("Links [p](pages/%23area--sub.md)", to: "c.md")
        try write("Nothing #area", to: "d.md")
        let index = WorkspaceMetadataIndex(root: root)
        await index.reconcile()

        let references = paths(await index.references(to: "pages/#area--sub.md"))
        XCTAssertEqual(references, ["a.md", "b.md", "c.md"])
        let none = paths(await index.references(to: "a.md"))
        XCTAssertEqual(none, [])
    }

    // MARK: - Index

    func testQueriesSeeOverlaysAndDeletions() async throws {
        let a = try write("Nothing yet", to: "a.md")
        try write("# Target", to: "t.md")
        let index = WorkspaceMetadataIndex(root: root)
        await index.reconcile()
        let linksToTarget = WorkspaceQuery(source: .files, filter: .linksTo(path: "t.md"))
        let revisions = await index.recordChanges()
        var iterator = revisions.makeAsyncIterator()
        let first = await iterator.next()

        let owner = UUID()
        await index.setOverlay("[t](t.md)", for: a, owner: owner)
        let withOverlay = paths(await index.run(linksToTarget))
        XCTAssertEqual(withOverlay, ["a.md"])
        let second = await iterator.next()
        XCTAssertNotEqual(first, second)

        await index.restoreDiskContribution(for: a, owner: owner)
        let restored = paths(await index.run(linksToTarget))
        XCTAssertEqual(restored, [])

        try write("[t](t.md)", to: "a.md")
        await index.filesChanged([a])
        let saved = paths(await index.run(linksToTarget))
        XCTAssertEqual(saved, ["a.md"])
        try FileManager.default.removeItem(at: a)
        await index.filesChanged([a])
        let deleted = paths(await index.run(linksToTarget))
        XCTAssertEqual(deleted, [])
    }

    func testQueryBlockResultsListRowsAndProblems() async throws {
        try write("---\ntitle: Weekly plan\n---\n- [ ] Call +daisy\n- [x] Done +daisy", to: "notes/plan.md")
        try write("+daisy", to: "b.md")
        let index = WorkspaceMetadataIndex(root: root)
        await index.reconcile()
        let requests = [QueryBlockRequest(id: "t", source: .tasks, text: "+daisy -is:done wrd"),
                        QueryBlockRequest(id: "f", source: .notes, text: "+daisy sort:-file.name"),
                        QueryBlockRequest(id: "e", source: .notes, text: "titel:x")]
        let (results, matches) = await QueryBlocks.results(for: requests, index: index)
        XCTAssertEqual(results[0].rows, [.init(path: "notes/plan.md", line: 4, text: "Call +daisy", checked: false,
                                               detail: "plan", source: "Call +daisy")])
        XCTAssertEqual(results[0].problems.count, 1)
        XCTAssertEqual(results[1].rows.map(\.text), ["Weekly plan", "b"])
        XCTAssertEqual(results[1].rows.map(\.detail), ["notes", ""])
        XCTAssertEqual(results[2].rows, [])
        XCTAssertEqual(results[2].problems.count, 1, "an unknown key is a problem, with a suggestion")
        XCTAssertTrue(results[2].problems[0].contains("title"))
        XCTAssertFalse(results[2].empty.isEmpty)
        let (empty, _) = await QueryBlocks.results(for: [QueryBlockRequest(id: "x", source: .tasks, text: " \n ")],
                                                   index: index)
        XCTAssertEqual(empty, [], "an empty block is never run")
        guard case .task? = matches[QueryBlocks.key(path: "notes/plan.md", line: 4)] else {
            return XCTFail("a task row maps back to its task")
        }
    }

    func testTasksRunOnTheQuery() async throws {
        try write("- [ ] b2\n- [ ] b5", to: "b.md")
        try write("- [x] a1", to: "a.md")
        let index = WorkspaceMetadataIndex(root: root)
        await index.reconcile()
        let tasks = await index.tasks()
        XCTAssertEqual(tasks.map { "\($0.path):\($0.task.text)" }, ["a.md:a1", "b.md:b2", "b.md:b5"])
    }
}
