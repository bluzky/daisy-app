import Foundation
import XCTest
@testable import MarkdownHelpers

final class MarkdownSectionInsertionTests: XCTestCase {
    private typealias Insertion = MarkdownSectionInsertion

    private func heading(_ title: String, in markdown: String) throws -> Insertion.Heading {
        try XCTUnwrap(Insertion.headings(in: markdown).first { $0.title == title })
    }

    private func insert(_ block: String, _ kind: Insertion.BlockKind = .paragraph, into markdown: String,
                        under title: String? = nil) throws -> String {
        let target = try title.map { try heading($0, in: markdown) }
        return Insertion.inserting(block, kind: kind, into: markdown, under: target).markdown
    }

    // MARK: - Headings

    func testHeadingsSkipFrontmatterAndFences() {
        let markdown = "---\ntitle: x\n---\n# One\n```\n# not\n```\n## Two ##\nText\n===\n- item\n---\n"
        XCTAssertEqual(Insertion.headings(in: markdown), [
            .init(line: 4, lastLine: 4, level: 1, title: "One"),
            .init(line: 8, lastLine: 8, level: 2, title: "Two"),
            .init(line: 9, lastLine: 10, level: 1, title: "Text"),
        ])
    }

    func testHashtagIsNotAHeading() {
        XCTAssertEqual(Insertion.headings(in: "#tag\n#\n"), [.init(line: 2, lastLine: 2, level: 1, title: "")])
    }

    // MARK: - End of file

    func testEndOfFileAddsBlankLine() throws {
        XCTAssertEqual(try insert("Moved", into: "Intro\n"), "Intro\n\nMoved\n")
        XCTAssertEqual(try insert("Moved", into: "Intro"), "Intro\n\nMoved\n")
        XCTAssertEqual(try insert("Moved", into: "Intro\n\n\n"), "Intro\n\nMoved\n\n\n")
    }

    func testEmptyFile() throws {
        XCTAssertEqual(try insert("- [ ] Task", .listItem, into: ""), "- [ ] Task\n")
    }

    func testListItemJoinsListOfSameKind() throws {
        XCTAssertEqual(try insert("- c", .listItem, into: "- a\n  - b\n"), "- a\n  - b\n- c\n")
        XCTAssertEqual(try insert("* c", .listItem, into: "- a\n"), "- a\n\n* c\n")
        XCTAssertEqual(try insert("- c", .listItem, into: "Text\n"), "Text\n\n- c\n")
    }

    func testOrderedItemTakesNextNumberOrOne() throws {
        XCTAssertEqual(try insert("7. c", .listItem, into: "1. a\n2. b\n"), "1. a\n2. b\n3. c\n")
        XCTAssertEqual(try insert("7. c", .listItem, into: "Text\n"), "Text\n\n1. c\n")
    }

    func testParagraphNeverJoinsList() throws {
        XCTAssertEqual(try insert("- not a list", .paragraph, into: "- a\n"), "- a\n\n- not a list\n")
    }

    // MARK: - Sections

    func testSectionIncludesSubheadings() throws {
        let markdown = "# A\nText\n## Sub\nMore\n\n# B\nOther\n"
        XCTAssertEqual(try insert("Moved", into: markdown, under: "A"),
                       "# A\nText\n## Sub\nMore\n\nMoved\n\n# B\nOther\n")
    }

    func testNextHeadingKeepsBlankLineAbove() throws {
        XCTAssertEqual(try insert("Moved", into: "# A\nText\n# B\n", under: "A"),
                       "# A\nText\n\nMoved\n\n# B\n")
    }

    func testEmptySectionGetsBlockUnderHeading() throws {
        XCTAssertEqual(try insert("Moved", into: "# A\n\n# B\n", under: "A"), "# A\n\nMoved\n\n# B\n")
    }

    func testLastSectionEndsFile() throws {
        XCTAssertEqual(try insert("- c", .listItem, into: "# A\n- a\n- b", under: "A"), "# A\n- a\n- b\n- c\n")
    }

    func testFenceInsideSectionIsNotAHeading() throws {
        let markdown = "# A\n```\n# B\n```\n# C\n"
        XCTAssertEqual(try insert("Moved", into: markdown, under: "A"), "# A\n```\n# B\n```\n\nMoved\n\n# C\n")
    }

    func testSetextSection() throws {
        XCTAssertEqual(try insert("Moved", into: "A\n===\nText\n\nB\n===\n", under: "A"),
                       "A\n===\nText\n\nMoved\n\nB\n===\n")
    }

    func testCRLFFileKeepsCRLF() throws {
        XCTAssertEqual(try insert("Moved\nTwo", into: "# A\r\nText\r\n# B\r\n", under: "A"),
                       "# A\r\nText\r\n\r\nMoved\r\nTwo\r\n\r\n# B\r\n")
    }

    // MARK: - Undo

    func testRemovingRestoresTheFile() {
        let original = "# A\nText\n\n# B\n"
        let heading = Insertion.headings(in: original)[0]
        let insertion = Insertion.inserting("Moved", kind: .paragraph, into: original, under: heading)
        XCTAssertEqual(Insertion.removing(insertion.inserted, at: insertion.offset, from: insertion.markdown), original)
    }

    func testRemovingFindsTheOnlyCopyAfterAnEditAbove() {
        let insertion = Insertion.inserting("Moved", kind: .paragraph, into: "Intro\n", under: nil)
        let edited = "Added line\n" + insertion.markdown
        XCTAssertEqual(Insertion.removing(insertion.inserted, at: insertion.offset, from: edited), "Added line\nIntro\n")
    }

    func testRemovingRefusesEditedOrDuplicatedCopies() {
        let insertion = Insertion.inserting("Moved", kind: .paragraph, into: "Intro\n", under: nil)
        XCTAssertNil(Insertion.removing(insertion.inserted, at: insertion.offset, from: "Intro\n\nMoved, edited\n"))
        XCTAssertNil(Insertion.removing(insertion.inserted, at: 0,
                                        from: "Intro\n\nMoved\nIntro\n\nMoved\n"))
    }

    // MARK: - Links

    func testLinksAreRebasedForTheTargetFolder() {
        let root = URL(fileURLWithPath: "/workspace")
        let source = root.appending(path: "notes/today.md")
        let target = root.appending(path: "projects/daisy/plan.md")
        let block = "- See [spec](spec.md#goals) ![](img/a%20b.png) [web](https://x.org) [top](#here)"
        XCTAssertEqual(Insertion.rebasingLinks(in: block, from: source, to: target),
                       "- See [spec](../../notes/spec.md#goals) ![](../../notes/img/a%20b.png) [web](https://x.org) [top](#here)")
    }

    func testCodeAndSameFolderAreLeftAlone() {
        let root = URL(fileURLWithPath: "/workspace")
        let block = "`[a](b.md)` [c](d.md)\n```\n[e](f.md)\n```"
        XCTAssertEqual(Insertion.rebasingLinks(in: block, from: root.appending(path: "x/one.md"),
                                               to: root.appending(path: "y/two.md")),
                       "`[a](b.md)` [c](../x/d.md)\n```\n[e](f.md)\n```")
        XCTAssertEqual(Insertion.rebasingLinks(in: block, from: root.appending(path: "x/one.md"),
                                               to: root.appending(path: "x/two.md")), block)
    }

    func testReferenceDefinitionIsRebased() {
        let root = URL(fileURLWithPath: "/workspace")
        XCTAssertEqual(Insertion.rebasingLinks(in: "[ref]: docs/a.md \"Title\"", from: root.appending(path: "one.md"),
                                               to: root.appending(path: "sub/two.md")),
                       "[ref]: ../docs/a.md \"Title\"")
    }
}
