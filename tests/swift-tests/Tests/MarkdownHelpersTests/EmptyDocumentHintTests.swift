import Foundation
import XCTest
@testable import MarkdownHelpers

final class EmptyDocumentHintTests: XCTestCase {
    private let hintClass = MarkdownHTML.emptyDocumentHintClass

    func testAnEmptyDocumentShowsTheHint() {
        for markdown in ["", "   ", "\n\n\n", " \t\n "] {
            let article = MarkdownHTML.render(markdown: markdown,
                                              emptyDocumentHint: "Press ⌘E to start writing").articleHTML
            XCTAssertEqual(article, "<p class=\"\(hintClass)\">Press ⌘E to start writing</p>",
                           "markdown: \(markdown.debugDescription)")
        }
    }

    func testADocumentWithContentRendersNormally() {
        for markdown in ["# Title", "text", "---\ntitle: x\n---\n"] {
            let article = MarkdownHTML.render(markdown: markdown,
                                              emptyDocumentHint: "Press ⌘E to start writing").articleHTML
            XCTAssertFalse(article.contains(hintClass), "markdown: \(markdown.debugDescription)")
        }
    }

    // Quick Look and exports pass no hint and keep the blank page.
    func testNoHintIsShownUnlessOneIsGiven() {
        XCTAssertFalse(MarkdownHTML.render(markdown: "").articleHTML.contains(hintClass))
    }

    func testTheHintIsEscaped() {
        let article = MarkdownHTML.render(markdown: "", emptyDocumentHint: "<b>&</b>").articleHTML
        XCTAssertTrue(article.contains("&lt;b&gt;&amp;&lt;/b&gt;"))
    }

    func testTheHintNeverPrints() throws {
        let html = MarkdownHTML.render(markdown: "", emptyDocumentHint: "hint").html
        let printBlock = try XCTUnwrap(html.components(separatedBy: "@media print {").dropFirst().first)
        let rule = try XCTUnwrap(printBlock.components(separatedBy: ".\(hintClass) {").dropFirst().first)
        XCTAssertEqual(rule.components(separatedBy: "}").first?
            .trimmingCharacters(in: .whitespacesAndNewlines), "display: none;")
    }
}
