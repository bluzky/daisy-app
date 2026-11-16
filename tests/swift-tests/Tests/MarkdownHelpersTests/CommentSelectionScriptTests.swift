import Foundation
import WebKit
import XCTest
@testable import MarkdownHelpers

/// Runs the shipped Add Comment script against a rendered page in WebKit.
@MainActor
final class CommentSelectionScriptTests: XCTestCase {

    private func page(_ markdown: String) async throws -> WKWebView {
        let article = MarkdownHTML.render(markdown: markdown).articleHTML
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        webView.loadHTMLString("<html><body><article class=\"markdown-body\">\(article)</article></body></html>",
                               baseURL: nil)
        for _ in 0..<200 {
            // The blank page that exists before the load reports "complete" too.
            if try await webView.evaluateJavaScript("document.querySelector('article') !== null") as? Bool == true {
                return webView
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("page did not load")
        return webView
    }

    /// Selects `text` in the first text node that holds it, like dragging.
    private func select(_ text: String, occurrence: Int = 0, in webView: WKWebView) async throws {
        let literal = EditorHTML.jsStringLiteral(text)
        _ = try await webView.evaluateJavaScript("""
        (() => {
            const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
            let seen = 0;
            while (walker.nextNode()) {
                let from = 0, index;
                while ((index = walker.currentNode.nodeValue.indexOf(\(literal), from)) !== -1) {
                    if (seen++ === \(occurrence)) {
                        const range = document.createRange();
                        range.setStart(walker.currentNode, index);
                        range.setEnd(walker.currentNode, index + \(text.utf16.count));
                        const selection = getSelection();
                        selection.removeAllRanges();
                        selection.addRange(range);
                        return true;
                    }
                    from = index + 1;
                }
            }
            return false;
        })()
        """)
    }

    private func run(_ webView: WKWebView) async throws -> [String: Any]? {
        try await webView.evaluateJavaScript(CommentSelectionScript.source) as? [String: Any]
    }

    func testSelectionInAParagraphReportsItsSourceLines() async throws {
        let webView = try await page("# Title\n\nsome text to pick here\n\nsecond block")
        try await select("text to pick", in: webView)
        let picked = try await run(webView)
        let result = try XCTUnwrap(picked)
        XCTAssertEqual(result["text"] as? String, "text to pick")
        XCTAssertEqual(result["start"] as? Int, 3)
        XCTAssertEqual(result["end"] as? Int, 3)
        XCTAssertEqual(result["occurrence"] as? Int, 0)
        XCTAssertNotNil(result["rect"] as? [String: Any])
    }

    func testRepeatedTextCountsEarlierCopiesInItsBlock() async throws {
        let webView = try await page("go go go")
        try await select("go", occurrence: 2, in: webView)
        let picked = try await run(webView)
        let result = try XCTUnwrap(picked)
        XCTAssertEqual(result["occurrence"] as? Int, 2)
    }

    func testNothingSelectedGivesNull() async throws {
        let webView = try await page("plain")
        let result = try await run(webView)
        XCTAssertNil(result)
    }

    func testCodeAndTablesAreUnsupported() async throws {
        let webView = try await page("```\ncode here\n```\n\n| a | b |\n| - | - |\n| cell | x |")
        try await select("code here", in: webView)
        let code = try await run(webView)
        XCTAssertEqual(code?["unsupported"] as? Bool, true)
        try await select("cell", in: webView)
        let table = try await run(webView)
        XCTAssertEqual(table?["unsupported"] as? Bool, true)
    }

    func testSelectionAcrossBlocksIsUnsupported() async throws {
        let webView = try await page("first block\n\nsecond block")
        _ = try await webView.evaluateJavaScript("""
        (() => {
            const paragraphs = document.querySelectorAll('p');
            const range = document.createRange();
            range.setStart(paragraphs[0].firstChild, 2);
            range.setEnd(paragraphs[1].firstChild, 4);
            getSelection().removeAllRanges();
            getSelection().addRange(range);
            return true;
        })()
        """)
        let result = try await run(webView)
        XCTAssertEqual(result?["unsupported"] as? Bool, true)
    }

    /// Selects from `startOffset` of `startPath`'s node to `endOffset` of the
    /// text node `endText`'s text, with `startPath` evaluated as JavaScript.
    private func selectRange(start: String, startOffset: Int, endText: String, endOffset: Int,
                             in webView: WKWebView) async throws {
        _ = try await webView.evaluateJavaScript("""
        (() => {
            const startNode = \(start);
            const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
            let endNode = null;
            while (walker.nextNode()) { if (walker.currentNode.nodeValue.includes(\(EditorHTML.jsStringLiteral(endText)))) { endNode = walker.currentNode; break; } }
            const range = document.createRange();
            range.setStart(startNode, \(startOffset));
            range.setEnd(endNode, \(endOffset));
            getSelection().removeAllRanges();
            getSelection().addRange(range);
            return true;
        })()
        """)
    }

    /// A selection that begins at the first character of a task line starts
    /// on the list item, after its checkbox, not inside its text.
    func testSelectionFromTheFirstCharacterOfATaskLineIsSupported() async throws {
        let webView = try await page("- [ ] first task\n- [ ] link token mention\n- [x] done")
        // Start on the <li> itself, just after the checkbox: child index 1.
        try await selectRange(start: "document.querySelectorAll('li')[1]", startOffset: 1,
                              endText: "link token mention", endOffset: 18, in: webView)
        let picked = try await run(webView)
        let result = try XCTUnwrap(picked)
        XCTAssertNil(result["unsupported"], "a selection that begins on the list item is still one block")
        XCTAssertEqual((result["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), "link token mention")
        XCTAssertEqual(result["start"] as? Int, 2)
    }

    func testSelectionStartingOnTheItemOfALooseListIsSupported() async throws {
        let webView = try await page("- [ ] one\n\n- [ ] two words here")
        try await selectRange(start: "document.querySelectorAll('li')[1]", startOffset: 0,
                              endText: "two words here", endOffset: 14, in: webView)
        let picked = try await run(webView)
        let result = try XCTUnwrap(picked)
        XCTAssertNil(result["unsupported"])
        XCTAssertEqual(result["start"] as? Int, 3)
    }

    func testSelectionAcrossTwoTaskLinesIsStillUnsupported() async throws {
        let webView = try await page("- [ ] one task\n- [ ] two task")
        try await selectRange(start: "document.querySelectorAll('li')[0]", startOffset: 1,
                              endText: "two task", endOffset: 8, in: webView)
        let picked = try await run(webView)
        XCTAssertEqual(picked?["unsupported"] as? Bool, true)
    }
}
