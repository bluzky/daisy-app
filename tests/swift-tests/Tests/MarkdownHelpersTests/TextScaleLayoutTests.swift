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

    func testEditorTextScaleAppliesLive() async throws {
        let script = try TestVendor.script("daisy/Vendor/CodeMirror/mdedit.min.js")
        let html = EditorHTML.render(markdown: "Body.", editorJavaScript: script)
        let page = WebViewLayoutHarness(html: html, width: 1600, isEditor: true, height: 600)
        defer { page.close() }
        _ = try await measure(page, isEditor: true)
        _ = try await page.webView.evaluateJavaScript(
            "document.documentElement.style.setProperty('\(MarkdownHTML.textScaleProperty)', '2')")
        let metrics = try await measure(page, isEditor: true)
        XCTAssertEqual(metrics.columnWidth, Double(MarkdownHTML.contentColumnWidth), accuracy: 0.5)
        XCTAssertEqual(metrics.fontSize, Double(MarkdownHTML.bodyFontSize) * 2, accuracy: 0.1)
    }

    func testEditorTextScaleKeepsColumnMeasure() async throws {
        let script = try TestVendor.script("daisy/Vendor/CodeMirror/mdedit.min.js")
        let markdown = String(repeating: "Body text that wraps across the column. ", count: 40)
        for scale in [1.0, 1.5] {
            let html = EditorHTML.render(markdown: markdown, editorJavaScript: script,
                                         configuration: .init(textScale: scale))
            let page = WebViewLayoutHarness(html: html, width: 1600, isEditor: true, height: 600)
            defer { page.close() }
            let metrics = try await measure(page, isEditor: true)
            XCTAssertEqual(metrics.columnWidth, Double(MarkdownHTML.contentColumnWidth), accuracy: 0.5, "scale \(scale)")
            XCTAssertEqual(metrics.fontSize, Double(MarkdownHTML.bodyFontSize) * scale, accuracy: 0.1)
        }
    }

    /// Tables always span the full content column, in the preview and the
    /// editor, however little their cells hold.
    func testTablesSpanTheFullColumnInBothModes() async throws {
        let script = try TestVendor.script("daisy/Vendor/CodeMirror/mdedit.min.js")
        let markdown = "| A | B |\n| --- | --- |\n| 1 | 2 |"
        let probe = """
            const column = document.querySelector(columnSelector).getBoundingClientRect();
            const table = document.querySelector(tableSelector).getBoundingClientRect();
            return [table.width, column.width];
            """
        let previewHTML = MarkdownHTML.render(markdown: markdown, allowsScroll: true, documentFont: .system,
                                              readerLayout: ReaderLayoutSetting()).html
        let preview = WebViewLayoutHarness(html: previewHTML, width: 1600, isEditor: false, height: 600)
        defer { preview.close() }
        _ = try await preview.layout(texts: [], imageCount: 0)
        let previewResult = try await preview.webView.callAsyncJavaScript(
            probe, arguments: ["columnSelector": "article.markdown-body", "tableSelector": "article table"],
            in: nil, contentWorld: .page)
        let previewWidths = try XCTUnwrap(previewResult as? [Double])
        XCTAssertEqual(previewWidths[0], previewWidths[1], accuracy: 1, "preview table width")

        let editorHTML = EditorHTML.render(markdown: markdown, editorJavaScript: script)
        let editor = WebViewLayoutHarness(html: editorHTML, width: 1600, isEditor: true, height: 600)
        defer { editor.close() }
        _ = try await editor.layout(texts: [], imageCount: 0)
        let editorResult = try await editor.webView.callAsyncJavaScript(
            probe, arguments: ["columnSelector": ".cm-md-table-widget", "tableSelector": ".cm-md-table-grid"],
            in: nil, contentWorld: .page)
        let editorWidths = try XCTUnwrap(editorResult as? [Double])
        XCTAssertEqual(editorWidths[0], editorWidths[1], accuracy: 1, "editor table width")
        XCTAssertEqual(editorWidths[0], Double(MarkdownHTML.contentColumnWidth) - 12, accuracy: 24,
                       "editor table fills the content column")
    }

    /// A table cell is the same size in both modes at every text size: the
    /// editor scales type through `--mdp-text-scale` like the preview, so the
    /// cell's fixed padding and borders must not grow with it.
    func testTableCellSizeMatchesPreviewAtTextScale() async throws {
        let script = try TestVendor.script("daisy/Vendor/CodeMirror/mdedit.min.js")
        let markdown = "| Alpha | Beta |\n| --- | --- |\n| One | Two |"
        let probe = "const cell = document.querySelector(selector); const box = cell.getBoundingClientRect(); return [box.width, box.height];"
        for scale in [1.0, 1.5] {
            let previewHTML = MarkdownHTML.render(markdown: markdown, allowsScroll: true, documentFont: .system,
                                                  readerLayout: ReaderLayoutSetting(),
                                                  textScale: scale).html
            let preview = WebViewLayoutHarness(html: previewHTML, width: 1600, isEditor: false, height: 600)
            defer { preview.close() }
            _ = try await preview.layout(texts: [], imageCount: 0)
            let previewResult = try await preview.webView.callAsyncJavaScript(
                probe, arguments: ["selector": "article td"], in: nil, contentWorld: .page)
            let previewBox = try XCTUnwrap(previewResult as? [Double])

            let editorHTML = EditorHTML.render(markdown: markdown, editorJavaScript: script,
                                               configuration: .init(textScale: scale))
            let editor = WebViewLayoutHarness(html: editorHTML, width: 1600, isEditor: true, height: 600)
            defer { editor.close() }
            _ = try await editor.layout(texts: [], imageCount: 0)
            let editorResult = try await editor.webView.callAsyncJavaScript(
                probe, arguments: ["selector": ".cm-md-table-grid td"], in: nil, contentWorld: .page)
            let editorBox = try XCTUnwrap(editorResult as? [Double])

            XCTAssertEqual(editorBox[0], previewBox[0], accuracy: 1, "cell width at \(scale)")
            XCTAssertEqual(editorBox[1], previewBox[1], accuracy: 1, "cell height at \(scale)")
        }
    }

    /// Vertical rhythm — list item pitch and the gap before a heading — scales
    /// with the text in both modes, so switching modes does not shift content.
    func testListAndHeadingSpacingMatchPreviewAtTextScale() async throws {
        let script = try TestVendor.script("daisy/Vendor/CodeMirror/mdedit.min.js")
        let markdown = "Intro paragraph.\n\n## Heading\n\n- one\n- two\n- three"
        let probe = """
            // Top of the element's last text run: padding and margins sit
            // outside it, so both modes compare where the text actually lands.
            const top = (selector, index) => {
                const walker = document.createTreeWalker(
                    document.querySelectorAll(selector)[index], NodeFilter.SHOW_TEXT);
                let last = null;
                while (walker.nextNode()) if (walker.currentNode.textContent.trim()) last = walker.currentNode;
                const range = document.createRange();
                range.selectNodeContents(last);
                return range.getBoundingClientRect().top;
            };
            return [top(...heading[1]) - top(...heading[0]), top(...items[1]) - top(...items[0])];
            """
        for scale in [1.0, 1.5] {
            let previewHTML = MarkdownHTML.render(markdown: markdown, allowsScroll: true, documentFont: .system,
                                                  readerLayout: ReaderLayoutSetting(),
                                                  textScale: scale).html
            let preview = WebViewLayoutHarness(html: previewHTML, width: 1600, isEditor: false, height: 900)
            defer { preview.close() }
            _ = try await preview.layout(texts: [], imageCount: 0)
            let previewResult = try await preview.webView.callAsyncJavaScript(
                probe, arguments: ["heading": [["article p", 0], ["article h2", 0]],
                                   "items": [["article li", 0], ["article li", 1]]],
                in: nil, contentWorld: .page)
            let previewGaps = try XCTUnwrap(previewResult as? [Double])

            let editorHTML = EditorHTML.render(markdown: markdown, editorJavaScript: script,
                                               configuration: .init(textScale: scale))
            let editor = WebViewLayoutHarness(html: editorHTML, width: 1600, isEditor: true, height: 900)
            defer { editor.close() }
            _ = try await editor.layout(texts: [], imageCount: 0)
            let editorResult = try await editor.webView.callAsyncJavaScript(
                probe, arguments: ["heading": [[".cm-line", 0], [".cm-md-h2", 0]],
                                   "items": [[".cm-md-list-item", 0], [".cm-md-list-item", 1]]],
                in: nil, contentWorld: .page)
            let editorGaps = try XCTUnwrap(editorResult as? [Double])

            XCTAssertEqual(editorGaps[0], previewGaps[0], accuracy: 0.5, "heading offset at \(scale)")
            XCTAssertEqual(editorGaps[1], previewGaps[1], accuracy: 0.5, "list item pitch at \(scale)")
        }
    }
}
