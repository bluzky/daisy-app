import XCTest
@testable import MarkdownHelpers

final class ProjectContentSearcherTests: XCTestCase {

    func testMatchIsCaseInsensitiveAndUsesTheFirstLine() throws {
        let text = "# Title\n\nFirst line\nThe Quick brown fox\nquick again\n"
        let match = try XCTUnwrap(ProjectContentSearcher.match(query: "QUICK", in: text))
        XCTAssertEqual(match.snippet, "The Quick brown fox")
        XCTAssertEqual(match.snippetRanges, [4..<9])
    }

    func testNoMatchAndBlankQueryReturnNil() {
        XCTAssertNil(ProjectContentSearcher.match(query: "zebra", in: "quick brown fox"))
        XCTAssertNil(ProjectContentSearcher.match(query: "   ", in: "quick brown fox"))
    }

    func testLongLinesAreWindowedAroundTheMatchWithEllipses() throws {
        let line = String(repeating: "a", count: 100) + "needle" + String(repeating: "b", count: 100)
        let match = try XCTUnwrap(ProjectContentSearcher.match(query: "needle", in: line))
        XCTAssertTrue(match.snippet.hasPrefix("…"))
        XCTAssertTrue(match.snippet.hasSuffix("…"))
        XCTAssertEqual(match.snippet.count, 1 + 40 + 6 + 40 + 1)
        let range = try XCTUnwrap(match.snippetRanges.first)
        let characters = Array(match.snippet)
        XCTAssertEqual(String(characters[range]), "needle")
    }

    func testRangesStayCorrectWithEmojiBeforeTheMatch() throws {
        let match = try XCTUnwrap(ProjectContentSearcher.match(query: "plan", in: "🎉🎉 the plan"))
        let range = try XCTUnwrap(match.snippetRanges.first)
        XCTAssertEqual(String(Array(match.snippet)[range]), "plan")
    }

    func testShortQueriesAreNotSearchable() {
        XCTAssertFalse(ProjectContentSearcher.isSearchable("ab"))
        XCTAssertFalse(ProjectContentSearcher.isSearchable("  a  "))
        XCTAssertTrue(ProjectContentSearcher.isSearchable("abc"))
    }

    func testScanFindsFilesInProjectOrderAndHonoursSkipping() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "mention of rhubarb here".write(to: directory.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try "nothing relevant".write(to: directory.appendingPathComponent("b.md"), atomically: true, encoding: .utf8)
        try "rhubarb rhubarb".write(to: directory.appendingPathComponent("c.md"), atomically: true, encoding: .utf8)
        let snapshot = ProjectFileIndex.Snapshot(
            root: directory,
            candidates: ["a.md", "b.md", "c.md"].map { .init(relativePath: $0) },
            isTruncated: false)

        let box = HitBox()
        try await ProjectContentSearcher.scan(query: "rhubarb", snapshot: snapshot, skipping: []) { hits, done in
            if done { await box.set(hits) }
        }
        let all = await box.hits
        XCTAssertEqual(all.map(\.candidate.relativePath), ["a.md", "c.md"])

        let skipBox = HitBox()
        let skipped = directory.appendingPathComponent("a.md").standardizedFileURL
        try await ProjectContentSearcher.scan(query: "rhubarb", snapshot: snapshot, skipping: [skipped]) { hits, done in
            if done { await skipBox.set(hits) }
        }
        let remaining = await skipBox.hits
        XCTAssertEqual(remaining.map(\.candidate.relativePath), ["c.md"])
    }

    func testScanStopsOnceEnoughHitsAreFound() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let names = (0..<20).map { "note-\($0).md" }
        for name in names {
            try "common phrase".write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let snapshot = ProjectFileIndex.Snapshot(root: directory, candidates: names.map { .init(relativePath: $0) },
                                                 isTruncated: false)
        let box = HitBox()
        try await ProjectContentSearcher.scan(query: "common", snapshot: snapshot, skipping: []) { hits, done in
            if done { await box.set(hits) }
        }
        let hits = await box.hits
        XCTAssertEqual(hits.count, ProjectContentSearcher.displayLimit)
        XCTAssertEqual(hits.map(\.candidate.relativePath), Array(names.prefix(ProjectContentSearcher.displayLimit)))
    }
}

private actor HitBox {
    private(set) var hits: [ProjectContentSearcher.Hit] = []
    func set(_ hits: [ProjectContentSearcher.Hit]) { self.hits = hits }
}
