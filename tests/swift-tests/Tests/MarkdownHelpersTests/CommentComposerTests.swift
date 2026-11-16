import Foundation
import WebKit
import XCTest
@testable import MarkdownHelpers

/// Runs the shipped Read mode comment bubble against a rendered page.
@MainActor
final class CommentComposerTests: XCTestCase {

    private final class Inbox: NSObject, WKScriptMessageHandler {
        var messages: [[String: Any]] = []
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if let body = message.body as? [String: Any] { messages.append(body) }
        }
    }

    /// `commentsOn: false` leaves out the Comments stylesheet, as a page with
    /// the extension switched off in Settings lacks it.
    private func page(_ markdown: String, inbox: Inbox, commentsOn: Bool = true) async throws -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(inbox, name: "mdPreviewHost")
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        let article = MarkdownHTML.render(markdown: markdown).articleHTML
        let styles = commentsOn ? MarkdownHTML.commentsStylesheet + MarkdownHTML.commentsComposerStylesheet : ""
        // Stands in for the page bridge, which supplies `post`, `hasHostBridge`
        // and `window.MdPreview` to the bubble's code.
        webView.loadHTMLString("""
        <html><head><style>\(styles)</style></head>
        <body><article class="markdown-body">\(article)</article>
        <script>
        (() => {
            const hasHostBridge = true;
            const post = (message) => window.webkit.messageHandlers.mdPreviewHost.postMessage(message);
            window.MdPreview = { registerExtension() { return true; } };
            \(MarkdownHTML.commentsComposerBody())
        })();
        </script></body></html>
        """, baseURL: nil)
        for _ in 0..<200 {
            if try await webView.evaluateJavaScript("document.querySelector('article') !== null") as? Bool == true {
                return webView
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("page did not load")
        return webView
    }

    private func js(_ script: String, in webView: WKWebView) async throws -> Any? {
        try await webView.evaluateJavaScript(script)
    }

    private func selectAndRelease(_ text: String, in webView: WKWebView) async throws {
        let literal = EditorHTML.jsStringLiteral(text)
        _ = try await js("""
        (() => {
            const walker = document.createTreeWalker(document.querySelector('article'), NodeFilter.SHOW_TEXT);
            while (walker.nextNode()) {
                const index = walker.currentNode.nodeValue.indexOf(\(literal));
                if (index === -1) continue;
                const range = document.createRange();
                range.setStart(walker.currentNode, index);
                range.setEnd(walker.currentNode, index + \(text.utf16.count));
                getSelection().removeAllRanges();
                getSelection().addRange(range);
                document.dispatchEvent(new MouseEvent('mouseup', { bubbles: true }));
                return true;
            }
            return false;
        })()
        """, in: webView)
        try await Task.sleep(for: .milliseconds(100))
    }

    func testBubbleAppearsAtTheEndOfTheSelectionThenOpensAFieldThatPostsTheNote() async throws {
        let inbox = Inbox()
        let webView = try await page("# Title\n\nsome text to pick here", inbox: inbox)
        try await selectAndRelease("text to pick", in: webView)

        let bubble = try await js("""
        (() => { const b = document.querySelector('.mdp-comment-add'); if (!b) return null;
                 const r = b.getBoundingClientRect(); return { x: r.x, y: r.y, w: r.width }; })()
        """, in: webView) as? [String: Any]
        let placed = try XCTUnwrap(bubble, "the bubble should show for a selection")
        let selectionEnd = try await js("""
        (() => { const rects = getSelection().getRangeAt(0).getClientRects(); const last = rects[rects.length - 1];
                 return last.right })()
        """, in: webView) as? Double ?? 0
        XCTAssertGreaterThan(placed["x"] as? Double ?? 0, selectionEnd - 1, "the bubble sits after the last character")

        _ = try await js("document.querySelector('.mdp-comment-add').click(); true", in: webView)
        let hasField = try await js("""
        document.querySelector('.mdp-comment-composer input') === document.activeElement
            && !document.querySelector('.mdp-comment-add')
        """, in: webView) as? Bool
        XCTAssertEqual(hasField, true, "the bubble becomes a focused field")

        _ = try await js("""
        (() => { const form = document.querySelector('.mdp-comment-composer');
                 form.querySelector('input').value = '  check this  ';
                 form.dispatchEvent(new Event('submit', { cancelable: true })); return true; })()
        """, in: webView)
        try await Task.sleep(for: .milliseconds(100))
        let message = try XCTUnwrap(inbox.messages.first)
        XCTAssertEqual(message["kind"] as? String, "addComment")
        XCTAssertEqual(message["note"] as? String, "check this")
        XCTAssertEqual(message["text"] as? String, "text to pick")
        XCTAssertEqual(message["start"] as? Int, 3)
        let left = try await js("document.querySelector('.mdp-comment-composer, .mdp-comment-add') === null", in: webView) as? Bool
        XCTAssertEqual(left, true, "the field closes after sending")
    }

    func testNothingShowsForCodeOrAnEmptyField() async throws {
        let inbox = Inbox()
        let webView = try await page("```\ncode here\n```\n\nplain words", inbox: inbox)
        try await selectAndRelease("code here", in: webView)
        let shown = try await js("document.querySelector('.mdp-comment-add') !== null", in: webView) as? Bool
        XCTAssertEqual(shown, false)

        try await selectAndRelease("plain", in: webView)
        _ = try await js("document.querySelector('.mdp-comment-add').click(); true", in: webView)
        _ = try await js("document.querySelector('.mdp-comment-composer').dispatchEvent(new Event('submit', { cancelable: true })); true", in: webView)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(inbox.messages.isEmpty, "an empty note sends nothing")
    }

    func testEscapeClosesTheField() async throws {
        let inbox = Inbox()
        let webView = try await page("some words", inbox: inbox)
        try await selectAndRelease("words", in: webView)
        _ = try await js("document.querySelector('.mdp-comment-add').click(); true", in: webView)
        _ = try await js("""
        document.querySelector('.mdp-comment-composer input')
            .dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })); true
        """, in: webView)
        let gone = try await js("document.querySelector('.mdp-comment-composer, .mdp-comment-add') === null", in: webView) as? Bool
        XCTAssertEqual(gone, true)
    }

    func testNoBubbleWhenTheCommentsExtensionIsOff() async throws {
        let inbox = Inbox()
        let webView = try await page("some words", inbox: inbox, commentsOn: false)
        try await selectAndRelease("words", in: webView)
        let shown = try await js("document.querySelector('.mdp-comment-add') !== null", in: webView) as? Bool
        XCTAssertEqual(shown, false)
    }

    func testRepliesAreListedWithABulletAndAHangingIndentButASingleNoteIsNot() async throws {
        let inbox = Inbox()
        let webView = try await page("{==a==}{>>first<<}{>>second<<} and {==b==}{>>only<<}", inbox: inbox)
        let styles = try await js("""
        (() => {
            const [many, one] = document.querySelectorAll('mark.mdp-comment');
            return JSON.stringify({
                manyText: many.getAttribute('data-comment'),
                manyIndent: getComputedStyle(many, '::after').textIndent,
                oneText: one.getAttribute('data-comment'),
                oneIndent: getComputedStyle(one, '::after').textIndent
            });
        })()
        """, in: webView) as? String
        let data = try XCTUnwrap(styles?.data(using: .utf8))
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(result["manyText"], "\u{2022} first\n\u{2022} second")
        XCTAssertTrue(result["manyIndent"]?.contains("hanging") == true, "indent: \(result["manyIndent"] ?? "-")")
        XCTAssertEqual(result["oneText"], "only")
        XCTAssertEqual(result["oneIndent"], "0px")
    }
}
