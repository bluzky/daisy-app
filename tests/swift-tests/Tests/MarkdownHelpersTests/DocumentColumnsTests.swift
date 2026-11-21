import XCTest
@testable import MarkdownHelpers

final class DocumentColumnsTests: XCTestCase {

    private func html(_ markdown: String) -> String {
        MarkdownHTML.render(markdown: markdown).articleHTML
    }

    func testTwoColumnsWrapEachSide() {
        let out = html("Intro\n\n<!-- columns -->\nLeft text\n\n<!-- column -->\nRight text\n\n<!-- end-columns -->\n\nAfter")
        XCTAssertTrue(out.contains("<div class=\"md-columns\" data-columns=\"2\">"))
        XCTAssertEqual(out.components(separatedBy: "<div class=\"md-column\">").count - 1, 2)
        XCTAssertTrue(out.contains("Left text"))
        XCTAssertTrue(out.contains("Right text"))
        // Content outside the group stays outside it.
        let columnsEnd = out.range(of: "After")!.lowerBound
        XCTAssertGreaterThan(columnsEnd, out.range(of: "Right text")!.upperBound)
    }

    func testBlocksInAColumnKeepTheirSourceLines() {
        let out = html("<!-- columns -->\nLeft\n\n<!-- column -->\nRight\n\n<!-- end-columns -->")
        XCTAssertTrue(out.contains("data-source-start=\"2\""))
        XCTAssertTrue(out.contains("data-source-start=\"5\""))
    }

    func testAuthoredBlankLinesSurviveAroundAndInsideAGroup() {
        let spacer = "md-source-blank-line"
        let before = html("Intro\n\n\n\n<!-- columns -->\nL\n\n<!-- column -->\nR\n\n<!-- end-columns -->")
        let opener = before.range(of: "<div class=\"md-columns\"")!.lowerBound
        XCTAssertEqual(before[..<opener].components(separatedBy: spacer).count - 1, 3)

        let inside = html("<!-- columns -->\nA\n\n\nB\n\n<!-- column -->\nR\n\n<!-- end-columns -->")
        XCTAssertEqual(inside.components(separatedBy: spacer).count - 1, 2)
    }

    func testThreeColumnsAndAFifthBreakStaysInTheLast() {
        let breaks = (1...5).map { "<!-- column -->\nc\($0)\n\n" }.joined()
        let out = html("<!-- columns -->\nc0\n\n\(breaks)<!-- end-columns -->")
        XCTAssertTrue(out.contains("data-columns=\"4\""))
    }

    func testWithoutAnEndTheContentStaysPlain() {
        let out = html("<!-- columns -->\nLeft\n\n<!-- column -->\nRight")
        XCTAssertFalse(out.contains("md-columns"))
        XCTAssertTrue(out.contains("Left"))
        XCTAssertTrue(out.contains("Right"))
    }

    func testASingleColumnStaysPlain() {
        let out = html("<!-- columns -->\nOnly\n\n<!-- end-columns -->")
        XCTAssertFalse(out.contains("md-columns"))
        XCTAssertTrue(out.contains("Only"))
    }

    func testEmptyColumnsAreDropped() {
        let out = html("<!-- columns -->\n<!-- column -->\nA\n\n<!-- column -->\nB\n\n<!-- end-columns -->")
        XCTAssertTrue(out.contains("data-columns=\"2\""))
    }

    func testABareColumnBreakDoesNothingInADocument() {
        let out = html("Left\n\n<!-- column -->\n\nRight")
        XCTAssertFalse(out.contains("md-columns"))
    }

    func testABreakInsideAListIsIgnored() {
        let out = html("<!-- columns -->\n- item\n  <!-- column -->\n  more\n\n<!-- end-columns -->")
        XCTAssertFalse(out.contains("md-columns"))
    }

    func testTwoGroupsInOneDocument() {
        let group = "<!-- columns -->\nA\n\n<!-- column -->\nB\n\n<!-- end-columns -->\n\n"
        let out = html(group + "Between\n\n" + group)
        XCTAssertEqual(out.components(separatedBy: "class=\"md-columns\"").count - 1, 2)
    }
}
