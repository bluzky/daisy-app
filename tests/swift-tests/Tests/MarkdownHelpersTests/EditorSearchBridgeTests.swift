import WebKit
import XCTest
@testable import MarkdownHelpers

@MainActor
final class EditorSearchBridgeTests: XCTestCase {
    private final class Messages: NSObject, WKScriptMessageHandler {
        var results: [[String: Int]] = []

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  body["kind"] as? String == "findResult",
                  let index = body["index"] as? Int,
                  let total = body["total"] as? Int else { return }
            results.append(["index": index, "total": total])
        }
    }

    func testProductionPageExposesSearchAndReportsEditedMatchCounts() async throws {
        let script = try TestVendor.script("daisy/Vendor/CodeMirror/mdedit.min.js")
        let html = EditorHTML.render(markdown: "needle first\n\nneedle second", editorJavaScript: script)
        let editor = WebViewLayoutHarness(html: html, width: 900, isEditor: true)
        let messages = Messages()
        editor.webView.configuration.userContentController.add(messages, name: "mdEditorHost")
        defer {
            editor.webView.configuration.userContentController.removeScriptMessageHandler(forName: "mdEditorHost")
            editor.close()
        }
        _ = try await editor.layout(texts: ["needle first", "needle second"], imageCount: 0)
        let result = try await editor.webView.callAsyncJavaScript("""
            const first = window.__mdEditor.find('needle', false, { mode: 'substring', caseSensitive: false });
            const next = window.__mdEditor.find('needle', false, { mode: 'substring', caseSensitive: false });
            const highlighted = document.querySelector('.cm-find-current')?.textContent;
            window.__mdEditor.replaceMarkdown('needle first');
            return { first: first.index, next: next.index, total: next.total, highlighted };
            """, arguments: [:], in: nil, contentWorld: .page)
        let values = try XCTUnwrap(result as? [String: Any])
        XCTAssertEqual(values["first"] as? Int, 1)
        XCTAssertEqual(values["next"] as? Int, 2)
        XCTAssertEqual(values["total"] as? Int, 2)
        XCTAssertEqual(values["highlighted"] as? String, "needle")

        let deadline = Date().addingTimeInterval(2)
        while messages.results.isEmpty && Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(messages.results.last, ["index": 1, "total": 1])
    }

    func testProductionPageReplacesCurrentAndAllMatches() async throws {
        let script = try TestVendor.script("daisy/Vendor/CodeMirror/mdedit.min.js")
        let html = EditorHTML.render(markdown: "one two one two one", editorJavaScript: script)
        let editor = WebViewLayoutHarness(html: html, width: 900, isEditor: true)
        defer { editor.close() }
        _ = try await editor.layout(texts: ["one two one"], imageCount: 0)
        let result = try await editor.webView.callAsyncJavaScript("""
            const options = { mode: 'substring', caseSensitive: false };
            window.__mdEditor.find('one', false, options);
            const current = window.__mdEditor.replaceCurrent('1', 'one', options);
            const afterCurrent = window.__mdEditor.getMarkdown();
            const all = window.__mdEditor.replaceAll('uno', 'one', options);
            const regex = window.__mdEditor.replaceAll('<$1>', '(t)wo', { mode: 'regex', caseSensitive: false });
            const invalid = window.__mdEditor.find('(', false, { mode: 'regex', caseSensitive: false });
            return {
                afterCurrent, currentTotal: current.total, replacedCurrent: current.replaced,
                replacedAll: all.replaced, afterAll: window.__mdEditor.getMarkdown(),
                regexReplaced: regex.replaced, invalidError: invalid.error
            };
            """, arguments: [:], in: nil, contentWorld: .page)
        let values = try XCTUnwrap(result as? [String: Any])
        XCTAssertEqual(values["afterCurrent"] as? String, "1 two one two one")
        XCTAssertEqual(values["currentTotal"] as? Int, 2)
        XCTAssertEqual(values["replacedCurrent"] as? Int, 1)
        XCTAssertEqual(values["replacedAll"] as? Int, 2)
        XCTAssertEqual(values["regexReplaced"] as? Int, 2)
        XCTAssertEqual(values["afterAll"] as? String, "1 <t> uno <t> uno")
        XCTAssertEqual(values["invalidError"] as? Bool, true)
    }

    func testFindingADistantMatchRendersTheViewportAroundIt() async throws {
        let script = try TestVendor.script("daisy/Vendor/CodeMirror/mdedit.min.js")
        let paragraphs = (0..<3000).map { $0 == 2500 ? "distant needle here" : "filler paragraph \($0)" }
        let html = EditorHTML.render(markdown: paragraphs.joined(separator: "\n\n"), editorJavaScript: script,
                                     configuration: .init(usesPageScrolling: true))
        let editor = WebViewLayoutHarness(html: html, width: 900, isEditor: true)
        defer { editor.close() }
        _ = try await editor.layout(texts: ["filler paragraph 0"], imageCount: 0)
        let result = try await editor.webView.callAsyncJavaScript("""
            window.__mdEditor.find('needle', false, { mode: 'substring', caseSensitive: false });
            // Drive the frame clock the way a visible window would, without
            // sending any scroll event of our own.
            for (let i = 0; i < 30; i++) {
                window.__layoutTestFrame();
                await new Promise(resolve => setTimeout(resolve, 20));
            }
            const current = document.querySelector('.cm-find-current');
            const rect = current?.getBoundingClientRect();
            return {
                rendered: !!current,
                visible: !!rect && rect.top >= 0 && rect.bottom <= window.innerHeight,
                lines: document.querySelectorAll('.cm-line').length,
                scrollY: window.scrollY
            };
            """, arguments: [:], in: nil, contentWorld: .page)
        let values = try XCTUnwrap(result as? [String: Any])
        XCTAssertGreaterThan(values["scrollY"] as? Double ?? 0, 1000, "\(values)")
        XCTAssertEqual(values["rendered"] as? Bool, true, "match line was not rendered: \(values)")
        XCTAssertEqual(values["visible"] as? Bool, true, "match is not in the viewport: \(values)")
    }
}
