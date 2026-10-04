import XCTest
@testable import MarkdownHelpers

final class TemplateFileParserTests: XCTestCase {
    func testEachH2IsATemplateNamedAfterIt() {
        let text = """
        ## Meeting notes

        - Attendees

        ## Daily standup
        - Yesterday
        """
        XCTAssertEqual(TemplateFileParser.parse(text), [
            MarkdownTemplate(name: "Meeting notes", body: "- Attendees"),
            MarkdownTemplate(name: "Daily standup", body: "- Yesterday"),
        ])
    }

    func testTitleAndIntroBeforeTheFirstH2AreIgnored() {
        let text = "# My templates\n\nSome intro.\n\n## One\nbody"
        XCTAssertEqual(TemplateFileParser.parse(text), [MarkdownTemplate(name: "One", body: "body")])
    }

    func testDeeperHeadingsStayInTheBody() {
        let text = "## Review\n### Summary\n\ntext\n#### Detail"
        XCTAssertEqual(TemplateFileParser.parse(text).first?.body, "### Summary\n\ntext\n#### Detail")
    }

    func testAnH1InsideATemplateStaysInTheBody() {
        let text = "## One\n# Not a split\nafter"
        XCTAssertEqual(TemplateFileParser.parse(text), [MarkdownTemplate(name: "One", body: "# Not a split\nafter")])
    }

    func testH2InsideAFencedCodeBlockDoesNotSplit() {
        let text = "## Doc\n```md\n## Inside\n```\nend\n## Next\nx"
        let templates = TemplateFileParser.parse(text)
        XCTAssertEqual(templates.map(\.name), ["Doc", "Next"])
        XCTAssertEqual(templates[0].body, "```md\n## Inside\n```\nend")
    }

    func testLongerFenceIsNotClosedByAShorterOne() {
        let text = "## Doc\n````\n```\n## Inside\n````\n## Next"
        XCTAssertEqual(TemplateFileParser.parse(text).map(\.name), ["Doc", "Next"])
    }

    func testTildeFenceHidesH2() {
        let text = "## Doc\n~~~\n## Inside\n~~~\n## Next"
        XCTAssertEqual(TemplateFileParser.parse(text).map(\.name), ["Doc", "Next"])
    }

    func testBodyIsTrimmedOfBlankLinesButKeepsInnerOnes() {
        let text = "## One\n\n\nfirst\n\nsecond\n\n\n## Two"
        XCTAssertEqual(TemplateFileParser.parse(text).first?.body, "first\n\nsecond")
    }

    func testDuplicateNamesGetASuffix() {
        let text = "## Note\na\n## Note\nb\n## Note\nc"
        XCTAssertEqual(TemplateFileParser.parse(text).map(\.name), ["Note", "Note (2)", "Note (3)"])
    }

    func testEmptyHeadingIsSkipped() {
        XCTAssertEqual(TemplateFileParser.parse("##\nlost\n## Kept\nx").map(\.name), ["Kept"])
    }

    func testTemplateWithNoBodyIsKeptEmpty() {
        XCTAssertEqual(TemplateFileParser.parse("## Blank"), [MarkdownTemplate(name: "Blank", body: "")])
    }

    func testClosingHashesAndExtraSpacesAreStrippedFromTheName() {
        XCTAssertEqual(TemplateFileParser.parse("##   Spaced  ##  \nx").first?.name, "Spaced")
        XCTAssertEqual(TemplateFileParser.parse("## C#\nx").first?.name, "C#")
    }

    func testHashWithoutSpaceIsNotAHeading() {
        XCTAssertEqual(TemplateFileParser.parse("##nospace\n## Real\nx").map(\.name), ["Real"])
    }

    func testIndentedCodeStyleHeadingIsNotAnH2() {
        XCTAssertEqual(TemplateFileParser.parse("## One\n    ## code\n## Two").map(\.name), ["One", "Two"])
    }

    func testCRLFAndCRLineEndings() {
        XCTAssertEqual(TemplateFileParser.parse("## A\r\nx\r\n## B\r\ny").map(\.body), ["x", "y"])
        XCTAssertEqual(TemplateFileParser.parse("## A\rx\r## B\ry").map(\.body), ["x", "y"])
    }

    func testFileWithoutH2sHasNoTemplates() {
        XCTAssertTrue(TemplateFileParser.parse("# Only a title\n\ntext").isEmpty)
        XCTAssertTrue(TemplateFileParser.parse("").isEmpty)
    }
}

// MARK: - Marker form

extension TemplateFileParserTests {
    func testMarkerStartsATemplateAndKeepsH2sInTheBody() {
        let text = """
        <!-- template: Weekly review -->
        ## Wins
        - one
        ## Misses
        <!-- template: Daily -->
        - today
        """
        XCTAssertEqual(TemplateFileParser.parse(text), [
            MarkdownTemplate(name: "Weekly review", body: "## Wins\n- one\n## Misses"),
            MarkdownTemplate(name: "Daily", body: "- today"),
        ])
    }

    func testOnceAMarkerExistsH2sNoLongerSplit() {
        let text = "## Intro\nignored\n<!-- template: A -->\nbody\n## Not a split"
        XCTAssertEqual(TemplateFileParser.parse(text), [MarkdownTemplate(name: "A", body: "body\n## Not a split")])
    }

    func testFileWithoutMarkersStillSplitsOnH2() {
        XCTAssertEqual(TemplateFileParser.parse("## A\nx\n## B\ny").map(\.name), ["A", "B"])
    }

    func testMarkerSpellingIsForgiving() {
        let text = "<!--template:Tight-->\na\n<!--   TEMPLATE :   Loose Name   -->\nb"
        XCTAssertEqual(TemplateFileParser.parse(text).map(\.name), ["Tight", "Loose Name"])
    }

    func testMarkerInsideAFencedBlockDoesNotSplit() {
        let text = "<!-- template: Doc -->\n```\n<!-- template: Inside -->\n```\nend"
        let templates = TemplateFileParser.parse(text)
        XCTAssertEqual(templates.map(\.name), ["Doc"])
        XCTAssertEqual(templates[0].body, "```\n<!-- template: Inside -->\n```\nend")
    }

    func testOrdinaryCommentsStayInTheBody() {
        let text = "<!-- template: A -->\n<!-- note to self -->\nbody"
        XCTAssertEqual(TemplateFileParser.parse(text).first?.body, "<!-- note to self -->\nbody")
    }

    func testMarkerMustBeAloneOnItsLine() {
        XCTAssertTrue(TemplateFileParser.parse("text <!-- template: A --> more\nbody").isEmpty)
    }

    func testEmptyMarkerNameIsSkippedButStillSwitchesToMarkerMode() {
        let text = "## H2\n<!-- template: -->\nlost\n<!-- template: Kept -->\nx"
        XCTAssertEqual(TemplateFileParser.parse(text).map(\.name), ["Kept"])
    }

    func testDuplicateMarkerNamesGetASuffix() {
        let text = "<!-- template: N -->\na\n<!-- template: N -->\nb"
        XCTAssertEqual(TemplateFileParser.parse(text).map(\.name), ["N", "N (2)"])
    }
}
