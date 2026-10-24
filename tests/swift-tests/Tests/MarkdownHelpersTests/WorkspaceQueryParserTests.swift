import Foundation
import XCTest
@testable import MarkdownHelpers

final class WorkspaceQueryParserTests: XCTestCase {
    private let today = JournalDay(string: "2026-10-23")!
    private var parser: WorkspaceQueryParser {
        WorkspaceQueryParser(knownKeys: ["status", "rating", "title"], today: today)
    }

    private func day(_ value: String) -> WorkspaceAttributeValue { .date(JournalDay(string: value)!) }
    private func tag(_ key: String) -> WorkspacePredicate { .hasToken(.tag, key: key, includingDescendants: true) }
    private func project(_ key: String) -> WorkspacePredicate {
        .hasToken(.project, key: key, includingDescendants: true)
    }

    func testTerms() {
        let cases: [(String, WorkspacePredicate)] = [
            ("", .and([])),
            ("#Work", .and([tag("work")])),
            ("@phone", .and([.hasToken(.context, key: "phone", includingDescendants: true)])),
            ("+daisy,site", .and([.or([project("daisy"), project("site")])])),
            ("-#a,b", .and([.not(.or([tag("a"), tag("b")]))])),
            ("is:open", .and([.checked(false)])),
            ("-is:done", .and([.not(.checked(true))])),
            ("is:open,done", .and([.or([.checked(false), .checked(true)])])),
            ("due:today", .and([.attribute("due", .equal, day("2026-10-23"))])),
            ("due:<=7d", .and([.attribute("due", .lessOrEqual, day("2026-10-30"))])),
            ("scheduled:>-2w", .and([.attribute("scheduled", .greater, day("2026-10-09"))])),
            ("due:>=2026-01-02", .and([.attribute("due", .greaterOrEqual, day("2026-01-02"))])),
            ("due:<2026-01-02", .and([.attribute("due", .less, day("2026-01-02"))])),
            ("p:high,MEDIUM", .and([.or([.attribute("priority", .equal, .text("high")),
                                        .attribute("priority", .equal, .text("medium"))])])),
            ("-p:low", .and([.not(.attribute("priority", .equal, .text("low")))])),
            ("in:notes/", .and([.inFolder("notes/")])),
            ("links:a.md", .and([.linksTo(path: "a.md")])),
            ("text:call", .and([.textContains("call")])),
            ("has:p", .and([.hasAttribute("priority")])),
            ("has:Status", .and([.hasAttribute("status")])),
            ("Status:active", .and([.attribute("status", .equal, .text("active"))])),
            ("rating:>3", .and([.attribute("rating", .greater, .text("3"))])),
            ("title:\"weekly sync\"", .and([.attribute("title", .equal, .text("weekly sync"))])),
            ("-status:a,b", .and([.not(.or([.attribute("status", .equal, .text("a")),
                                            .attribute("status", .equal, .text("b"))]))])),
            ("file.size:>100", .and([.attribute("file.size", .greater, .text("100"))])),
        ]
        for (text, filter) in cases {
            let result = parser.parse(text, source: .tasks)
            XCTAssertEqual(result.query.filter, filter, text)
            XCTAssertEqual(result.problems, [], text)
        }
    }

    func testOrSplitsGroupsAndBindsLooserThanAnd() {
        let result = parser.parse("+daisy p:high OR @phone due:today", source: .tasks)
        XCTAssertEqual(result.query.filter, .or([
            .and([project("daisy"), .attribute("priority", .equal, .text("high"))]),
            .and([.hasToken(.context, key: "phone", includingDescendants: true),
                  .attribute("due", .equal, day("2026-10-23"))]),
        ]))
        XCTAssertEqual(result.problems, [])
    }

    func testLowercaseOrAndQuotedOrStayText() {
        XCTAssertEqual(parser.parse("#a or #b", source: .tasks).problems, [.bareWord("or")])
        XCTAssertEqual(parser.parse("#a \"OR\" #b", source: .tasks).problems, [.bareWord("OR")])
        XCTAssertEqual(parser.parse("title:\"x OR y\"", source: .files).query.filter,
                       .and([.attribute("title", .equal, .text("x OR y"))]))
    }

    func testSortAndLimitApplyAnywhere() {
        let result = parser.parse("sort:due #a OR limit:5 #b sort:-p,title", source: .tasks)
        XCTAssertEqual(result.query.sort, [WorkspaceSortKey(key: "due"),
                                           WorkspaceSortKey(key: "priority", descending: true),
                                           WorkspaceSortKey(key: "title")])
        XCTAssertEqual(result.query.limit, 5)
        XCTAssertEqual(result.query.filter, .or([.and([tag("a")]), .and([tag("b")])]))
        XCTAssertEqual(result.problems, [])
    }

    func testProblemsLeaveTheTermOutAndTheRestRuns() {
        let cases: [(String, WorkspaceQueryParser.Problem)] = [
            ("word", .bareWord("word")),
            ("status:", .missingValue("status:")),
            ("status:a,", .missingValue("status:a,")),
            ("due:soon", .badDate("due:soon")),
            ("due:2026-02-30", .badDate("due:2026-02-30")),
            ("p:urgent", .badPriority("p:urgent")),
            ("status:=<a", .badOperator("status:=<a")),
            ("status:<>a", .badOperator("status:<>a")),
            ("in:<a", .unsupported("in:<a")),
            ("-sort:due", .unsupported("-sort:due")),
            ("limit:a", .badLimit("limit:a")),
            ("limit:-1", .badLimit("limit:-1")),
            ("is:closed", .badState("is:closed")),
            ("#123", .badName("#123")),
            ("#a//b", .badName("#a//b")),
            ("statu:x", .unknownKey("statu", suggestion: "status")),
            ("color:red", .unknownKey("color", suggestion: nil)),
        ]
        for (text, problem) in cases {
            let result = parser.parse("#kept \(text)", source: .tasks)
            XCTAssertEqual(result.problems, [problem], text)
            XCTAssertEqual(result.query.filter, .and([tag("kept")]), text)
        }
    }

    func testEmptyGroups() {
        for text in ["OR #a", "#a OR", "#a OR OR #b"] {
            let result = parser.parse(text, source: .tasks)
            XCTAssertEqual(result.problems, [.emptyGroup], text)
        }
        XCTAssertEqual(parser.parse("#a OR OR #b", source: .tasks).query.filter,
                       .or([.and([tag("a")]), .and([tag("b")])]))
    }

    func testAGroupOfOnlyProblemsMatchesNothing() {
        XCTAssertEqual(parser.parse("color:red", source: .files).query.filter, .or([]))
        XCTAssertEqual(parser.parse("color:red OR #a", source: .files).query.filter, .and([tag("a")]))
        XCTAssertEqual(parser.parse("sort:due limit:3", source: .tasks).query.filter, .and([]),
                       "options alone list everything")
    }

    func testWithoutKnownKeysEveryKeyRuns() {
        let result = WorkspaceQueryParser(today: today).parse("color:red", source: .files)
        XCTAssertEqual(result.problems, [])
        XCTAssertEqual(result.query.filter, .and([.attribute("color", .equal, .text("red"))]))
    }

    func testParsedQueryRunsOnRecords() throws {
        TestVendor.installWorkspaceMetadataExtractor()
        let root = URL(fileURLWithPath: "/workspace")
        let markdown = "- [ ] a +daisy due:2026-10-25 p:high\n- [x] b +daisy due:2026-10-24\n- [ ] c @phone due:2026-12-01"
        let metadata = try XCTUnwrap(WorkspaceMetadataExtractor.extract(markdown))
        let record = WorkspaceFileRecord(path: "a.md", metadata: metadata, root: root)
        let query = parser.parse("+daisy -is:done due:<=7d OR @phone\nsort:-due", source: .tasks).query
        let texts = query.evaluate([record]).compactMap { match -> String? in
            guard case let .task(task) = match else { return nil }
            return task.task.text
        }
        XCTAssertEqual(texts, ["c @phone", "a +daisy"])
    }
}
