import WebKit
import XCTest
@testable import MarkdownHelpers

/// Text size (⌘+ / ⌘−) grows the type, never the Content Width column: the
/// column keeps its on-screen measure in the preview and in the editor.
@MainActor
final class TextScaleLayoutTests: XCTestCase {
    private struct Metrics {
        /// Column width and body font size in view points.
        let columnWidth: Double
        let fontSize: Double
    }

    private func measure(_ page: WebViewLayoutHarness, isEditor: Bool) async throws -> Metrics {
        _ = try await page.layout(texts: [], imageCount: 0)
        let result = try await page.webView.callAsyncJavaScript("""
            const column = document.querySelector(isEditor ? '.cm-content' : 'article.markdown-body');
            const text = document.querySelector(isEditor ? '.cm-line' : 'article p');
            return [column.getBoundingClientRect().width, parseFloat(getComputedStyle(text).fontSize)];
            """, arguments: ["isEditor": isEditor], in: nil, contentWorld: .page) as? [Double]
        let values = try XCTUnwrap(result)
        let zoom = Double(page.webView.pageZoom)
        return Metrics(columnWidth: values[0] * zoom, fontSize: values[1] * zoom)
    }

    func testPreviewTextScaleKeepsColumnMeasure() async throws {
        let markdown = String(repeating: "Body text that wraps across the column. ", count: 40)
        for (contentWidth, column) in [(MarkdownHTML.ContentWidth.centered, MarkdownHTML.contentColumnWidth),
                                       (.narrow, MarkdownHTML.narrowColumnWidth)] {
            for scale in [1.0, 1.5] {
                let html = MarkdownHTML.render(markdown: markdown, allowsScroll: true,
                                               contentWidth: contentWidth, documentFont: .system,
                                               readerLayout: ReaderLayoutSetting(),
                                               textScale: scale).html
                let page = WebViewLayoutHarness(html: html, width: 1600, isEditor: false, height: 600)
                defer { page.close() }
                let metrics = try await measure(page, isEditor: false)
                XCTAssertEqual(metrics.columnWidth, Double(column), accuracy: 0.5, "\(contentWidth) at \(scale)")
                XCTAssertEqual(metrics.fontSize, Double(MarkdownHTML.bodyFontSize) * scale, accuracy: 0.1)
            }
        }
    }

    func testPreviewTextScaleAppliesLive() async throws {
        let html = MarkdownHTML.render(markdown: "Body.", allowsScroll: true, documentFont: .system,
                                       readerLayout: ReaderLayoutSetting()).html
        let page = WebViewLayoutHarness(html: html, width: 1600, isEditor: false, height: 600)
        defer { page.close() }
        _ = try await measure(page, isEditor: false)
        _ = try await page.webView.evaluateJavaScript(
            "document.documentElement.style.setProperty('\(MarkdownHTML.textScaleProperty)', '2')")
        let metrics = try await measure(page, isEditor: false)
        XCTAssertEqual(metrics.columnWidth, Double(MarkdownHTML.contentColumnWidth), accuracy: 0.5)
        XCTAssertEqual(metrics.fontSize, Double(MarkdownHTML.bodyFontSize) * 2, accuracy: 0.1)
    }

    func testEditorPageZoomKeepsColumnMeasure() async throws {
        let script = try TestVendor.script("daisy/Vendor/CodeMirror/mdedit.min.js")
        let markdown = String(repeating: "Body text that wraps across the column. ", count: 40)
        for zoom in [1.0, 1.5] {
            let html = EditorHTML.render(markdown: markdown, editorJavaScript: script,
                                         configuration: .init(pageZoom: zoom))
            let page = WebViewLayoutHarness(html: html, width: 1600, isEditor: true, zoom: zoom, height: 600)
            defer { page.close() }
            let metrics = try await measure(page, isEditor: true)
            XCTAssertEqual(metrics.columnWidth, Double(MarkdownHTML.contentColumnWidth), accuracy: 0.5, "zoom \(zoom)")
            XCTAssertEqual(metrics.fontSize, Double(MarkdownHTML.bodyFontSize) * zoom, accuracy: 0.1)
        }
    }
}
