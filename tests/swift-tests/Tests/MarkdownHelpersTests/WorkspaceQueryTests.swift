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

    func testTitleIsTheFrontmatterTitleOrTheFileName() throws {
        let records = [
            try record("---\ntitle: Weekly Plan\n---\n- [ ] Call", at: "notes/plan.md"),
            try record("---\ntitle: \"\"\n---\nEmpty title", at: "empty.md"),
            try record("No frontmatter", at: "Ideas.md"),
        ]
        func run(_ source: WorkspaceQuery.Source, _ filter: WorkspacePredicate,
                 sort: [WorkspaceSortKey] = []) -> [String] {
            paths(WorkspaceQuery(source: source, filter: filter, sort: sort).evaluate(records))
        }
        XCTAssertEqual(run(.files, .and([]), sort: [WorkspaceSortKey(key: "title")]),
                       ["empty.md", "Ideas.md", "notes/plan.md"], "empty, Ideas, Weekly Plan")
        XCTAssertEqual(run(.files, .attribute("title", .equal, .text("ideas"))), ["Ideas.md"])
        XCTAssertEqual(run(.files, .hasAttribute("title")), ["Ideas.md", "empty.md", "notes/plan.md"],
                       "every file has a title")
        XCTAssertEqual(run(.tasks, .attribute("title", .equal, .text("weekly plan"))), ["notes/plan.md:4"],
                       "a task reads its file's title")
        XCTAssertEqual(records[0].title, "Weekly Plan")
        XCTAssertEqual(records[1].title, "empty", "an empty title falls back to the file name")
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

    func testTasksHaveTheirFileFrontmatterTokens() async throws {
        let all = ["projects/a.md:9", "projects/a.md:10", "projects/a.md:11"]
        XCTAssertEqual(try run(.tasks, .hasToken(.tag, key: "area/sub", includingDescendants: false)), all)
        XCTAssertEqual(try run(.tasks, .hasToken(.tag, key: "area", includingDescendants: true)), all)
        XCTAssertEqual(try run(.tasks, .hasToken(.tag, key: "area", includingDescendants: false)), [],
                       "a name in the body is not the file's")
        XCTAssertEqual(try run(.tasks, .not(.hasToken(.tag, key: "area/sub", includingDescendants: false))),
                       ["b.md:6"])
        let task = try record("---\ntags: [work]\n---\n- [ ] Call", at: "a.md").tasks.first
        XCTAssertEqual(task?.tokens, [], "a task's own tokens stay its line's")

        let a = try write("---\ntags: [work]\n---\n- [ ] Call", to: "a.md")
        let index = WorkspaceMetadataIndex(root: root)
        await index.reconcile()
        let work = WorkspaceQuery(source: .tasks, filter: .hasToken(.tag, key: "work", includingDescendants: false))
        let saved = paths(await index.run(work))
        XCTAssertEqual(saved, ["a.md:4"])
        await index.setOverlay("---\ntags: [home]\n---\n- [ ] Call", for: a, owner: UUID())
        let edited = paths(await index.run(work))
        XCTAssertEqual(edited, [], "an unsaved frontmatter edit counts")
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

    func testReferenceListGroupsLinksAndMentionsByFileAndLine() async throws {
        try write("# #Area/Sub\n[self](%23area--sub.md) #area/sub", to: "pages/#area--sub.md")
        try write("---\ntags: [area/sub]\n---\nUses #AREA/sub\n\nNothing\nAgain #area/sub #area/sub",
                  to: "a.md")
        try write("[p](../pages/%23area--sub.md) and #area/sub\n[again](../pages/%23area--sub.md)",
                  to: "notes/b.md")
        try write("Child #area/sub/deeper, other [x](a.md)", to: "c.md")
        let index = WorkspaceMetadataIndex(root: root)
        await index.reconcile()

        let page = await index.referenceList(to: "pages/#area--sub.md")
        XCTAssertEqual(page.linked, [
            .init(path: "notes/b.md", occurrences: [
                .init(line: 1, excerpt: "[p](../pages/%23area--sub.md) and #area/sub"),
                .init(line: 2, excerpt: "[again](../pages/%23area--sub.md)"),
            ]),
        ])
        XCTAssertEqual(page.mentions.map(\.path), ["a.md", "notes/b.md"],
                       "a descendant token is not a mention, and the page never lists itself")
        XCTAssertEqual(page.mentions[0].occurrences.map(\.line), [2, 4, 7],
                       "frontmatter tags count; two tokens on one line make one row")
        XCTAssertEqual(page.mentions[1].occurrences.map(\.line), [1])

        let file = await index.referenceList(to: "a.md")
        XCTAssertEqual(file.linked.map(\.path), ["c.md"])
        XCTAssertEqual(file.mentions, [], "only a page has mentions")

        let url = root.appending(path: "notes/b.md")
        let byURL = await index.referenceList(toFile: url)
        XCTAssertEqual(byURL, WorkspaceReferences())
        let outside = await index.referenceList(toFile: root.deletingLastPathComponent().appending(path: "x.md"))
        XCTAssertNil(outside, "a file the index doesn't cover has no list")
    }

    func testReferenceListFollowsOverlays() async throws {
        let a = try write("Nothing yet", to: "a.md")
        try write("# Target", to: "t.md")
        let index = WorkspaceMetadataIndex(root: root)
        await index.reconcile()
        let owner = UUID()
        await index.setOverlay("See [t](t.md)", for: a, owner: owner)
        let added = await index.referenceList(to: "t.md")
        XCTAssertEqual(added.linked.map(\.path), ["a.md"])
        await index.restoreDiskContribution(for: a, owner: owner)
        let removed = await index.referenceList(to: "t.md")
        XCTAssertTrue(removed.isEmpty)
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

    func testQueryBlocksGroupRows() async throws {
        try write("---\nprojects: [Site]\n---\n- [ ] Both +Daisy due:2026-03-02 p:low\n- [ ] Only site",
                  to: "notes/a.md")
        try write("- [ ] Ship +daisy due:2026-03-01 p:high\n- [ ] Loose p:medium\n- [x] Done +daisy", to: "b.md")
        let index = WorkspaceMetadataIndex(root: root)
        await index.reconcile()
        func groups(_ text: String) async -> [String] {
            let (results, _) = await QueryBlocks.results(for: [QueryBlockRequest(id: "g", source: .tasks, text: text)],
                                                         index: index)
            return results[0].groups.map { group in
                "\(group.label?.text ?? "-")/\(group.kind): " + group.rows.map(\.text).joined(separator: ",")
            }
        }
        let byProject = await groups("is:open $group:project")
        XCTAssertEqual(byProject, ["+daisy/names: Ship +daisy,Both +Daisy", "+Site/names: Both +Daisy,Only site",
                                   "No project/none: Loose"],
                       "one group per name, ignoring case, with frontmatter names; a row in each of its groups")
        let byPriority = await groups("is:open $group:p")
        XCTAssertEqual(byPriority, ["high/p: Ship +daisy", "medium/p: Loose", "low/p: Both +Daisy",
                                    "No priority/none: Only site"], "priority from high to low")
        let byDue = await groups("is:open $group:due sort:-text")
        XCTAssertEqual(byDue, ["2026-03-01/due: Ship +daisy", "2026-03-02/due: Both +Daisy",
                               "No due date/none: Only site,Loose"],
                       "groups in date order; rows keep the query's order inside them")
        let limited = await groups("is:open $group:due sort:-text limit:2")
        XCTAssertEqual(limited, ["2026-03-01/due: Ship +daisy", "No due date/none: Only site"],
                       "limit caps the rows before grouping")
        let byFile = await groups("$group:file")
        XCTAssertEqual(byFile.map { $0.components(separatedBy: ":")[0] }, ["a/value", "b/value"])
        func details(_ text: String, _ source: QueryBlockRequest.Source = .tasks) async -> [String] {
            let (results, _) = await QueryBlocks.results(for: [QueryBlockRequest(id: "d", source: source, text: text)],
                                                         index: index)
            return results[0].rows.map(\.detail)
        }
        let byFileDetails = await details("is:open $group:file")
        XCTAssertEqual(byFileDetails, ["", "", "", ""], "a file header leaves the row's file out")
        let byProjectDetails = await details("is:open $group:project")
        XCTAssertEqual(Set(byProjectDetails), ["a", "b"], "other groups keep it")
        let byFolderDetails = await details("$group:folder", .notes)
        XCTAssertEqual(byFolderDetails, ["", ""], "a folder header leaves a note's folder out")
        let ungrouped = await groups("is:done")
        XCTAssertEqual(ungrouped, ["-/none: Done +daisy"], "no $group: gives one group without a label")
    }

    func testQueryBlockTablesFillTheirCells() async throws {
        try write("---\npartner: [Acme, Globex]\nparent: \"[Up](index.md)\"\n---\n- [ ] Ship +daisy due:2026-03-01",
                  to: "notes/a.md")
        let index = WorkspaceMetadataIndex(root: root)
        await index.reconcile()
        let request = QueryBlockRequest(id: "t", source: .tasks,
                                        text: "$columns:done,text,due,p,project,partner,parent,file,folder")
        let (results, _) = await QueryBlocks.results(for: [request], index: index)
        let result = try XCTUnwrap(results.first)
        XCTAssertEqual(result.view, "table")
        XCTAssertEqual(result.columns.map(\.kind), ["done", "text", "due", "p", "names", "value", "value", "value",
                                                    "value"])
        XCTAssertEqual(result.columns.map(\.label), ["Done", "Task", "Due", "Priority", "Projects", "partner",
                                                     "parent", "File", "Folder"])
        let cells = try XCTUnwrap(result.rows.first?.cells)
        XCTAssertEqual(cells.map { $0.map(\.text) }, [[], [], ["2026-03-01"], [], ["+daisy"], ["Acme", "Globex"],
                                                       ["Up"], ["a"], ["notes"]])
        XCTAssertEqual(cells[6].first?.path, "notes/index.md", "a link value opens its file")
        XCTAssertEqual(cells[7].first?.path, "notes/a.md")

        let list = await QueryBlocks.results(for: [QueryBlockRequest(id: "l", source: .tasks, text: "is:open")],
                                             index: index).results[0]
        XCTAssertEqual(list.view, "list")
        XCTAssertEqual(list.columns, [])
        XCTAssertNil(list.rows.first?.cells, "a list has no cells")
    }

    func testQueryBlockTitleCellsOpenTheirFile() async throws {
        try write("---\ntitle: Weekly plan\n---\nBody", to: "notes/plan.md")
        try write("---\ntitle: Weekly plan\n---\nBody", to: "b.md")
        let index = WorkspaceMetadataIndex(root: root)
        await index.reconcile()
        let table = await QueryBlocks.results(
            for: [QueryBlockRequest(id: "t", source: .notes, text: "$columns:title,file sort:file.name")],
            index: index).results[0]
        XCTAssertEqual(table.rows.map { $0.cells?[0].first?.path }, ["b.md", "notes/plan.md"],
                       "a title opens its file, as the file column does")
        XCTAssertEqual(table.rows.map { $0.cells?[0].first?.path }, table.rows.map { $0.cells?[1].first?.path })
        let grouped = await QueryBlocks.results(
            for: [QueryBlockRequest(id: "g", source: .notes, text: "$group:title")], index: index).results[0]
        XCTAssertEqual(grouped.groups.map(\.rows.count), [2], "grouping by title still merges a shared title")
        XCTAssertNil(grouped.groups.first?.label?.path)
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
