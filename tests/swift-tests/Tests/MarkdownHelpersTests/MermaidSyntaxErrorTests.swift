import WebKit
import XCTest
@testable import MarkdownHelpers

/// A diagram with a syntax error must not leave Mermaid's error graphic in the
/// page (it lands in the document body, outside the column) in either mode.
@MainActor
final class MermaidSyntaxErrorTests: XCTestCase {
    let markdown = "# Capture\n\n```mermaid\nflowchart TD\n  A -- > [[[ broken\n```\n\n```mermaid\nflowchart TD\n  A --> B\n```\n\nAfter\n"

    func page(_ harness: WebViewLayoutHarness) async throws -> [String: Any] {
        _ = try await harness.layout(texts: ["After"], imageCount: 0)
        // Mermaid loads and renders after first paint.
        for _ in 0..<40 {
            let done = try await harness.webView.evaluateJavaScript(
                "document.querySelectorAll('svg[id*=\"mermaid\"]').length > 0"
                    + " && !document.body.innerText.includes('Rendering diagram')") as? Bool
            if done == true { break }
            try await Task.sleep(for: .milliseconds(250))
        }
        let json = try await harness.webView.evaluateJavaScript("""
            JSON.stringify({
              errorGraphics: document.body.innerText.split('Syntax error').length - 1,
              diagrams: document.querySelectorAll('svg[id*="mermaid"]').length,
              text: document.body.innerText })
            """) as? String
        return try JSONSerialization.jsonObject(with: Data(XCTUnwrap(json).utf8)) as? [String: Any] ?? [:]
    }

    func testReadModeShowsSourceInsteadOfErrorGraphic() async throws {
        let html = MarkdownHTML.render(markdown: markdown, allowsScroll: true, contentWidth: .centered,
                                       documentFont: .system, readerLayout: ReaderLayoutSetting(),
                                       pageTopClearance: 0).html
        let harness = WebViewLayoutHarness(html: html, width: 700, isEditor: false, zoom: 1, height: 1200)
        defer { harness.close() }
        let result = try await page(harness)
        XCTAssertEqual(result["errorGraphics"] as? Int, 0)
        XCTAssertEqual(result["diagrams"] as? Int, 1)
        XCTAssertTrue((result["text"] as? String ?? "").contains("A -- > [[[ broken"))
    }

    func testEditModeShowsMessageInsteadOfErrorGraphic() async throws {
        let script = try TestVendor.script("daisy/Vendor/CodeMirror/mdedit.min.js")
        let html = EditorHTML.render(markdown: markdown, editorJavaScript: script, includesMermaid: true,
                                     configuration: .init(fullWidth: false, usesPageScrolling: false))
        let harness = WebViewLayoutHarness(html: html, width: 700, isEditor: true, zoom: 1, height: 1200)
        defer { harness.close() }
        let result = try await page(harness)
        XCTAssertEqual(result["errorGraphics"] as? Int, 0)
        XCTAssertEqual(result["diagrams"] as? Int, 1)
        XCTAssertTrue((result["text"] as? String ?? "").contains("Unable to render Mermaid diagram"))
    }
}
