import WebKit
import XCTest
@testable import MarkdownHelpers

/// The preview builds its search pattern in SearchPatternScript; the source
/// editor builds the same one in scripts/editor-bundle/src/find.js, and
/// scripts/editor-bundle/smoke/find.mjs runs this fixture against it.
@MainActor
final class SearchPatternParityTests: XCTestCase {
    private struct Case: Decodable {
        let query: String
        let mode: String
        let caseSensitive: Bool
        let text: String
        let matches: [String]
        let error: Bool?
    }

    private func loadCases() throws -> [Case] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("fixtures/find-parity.json")
        return try JSONDecoder().decode([Case].self, from: Data(contentsOf: url))
    }

    func testPreviewPatternMatchesSharedFixture() async throws {
        let cases = try loadCases()
        XCTAssertFalse(cases.isEmpty)
        let page = WebViewLayoutHarness(html: "<!doctype html><body><article class=\"markdown-body\"></article></body>",
                                        width: 400, isEditor: false)
        defer { page.close() }
        _ = try await page.layout(texts: [], imageCount: 0)

        for item in cases {
            let result = try await page.webView.callAsyncJavaScript("""
                \(SearchPatternScript.javaScript)
                if (!query) return { matches: [], error: false };
                try {
                    const pattern = window.__mdSearchPattern(query, mode, caseSensitive);
                    const matches = [...text.matchAll(pattern)].map(m => m[0]).filter(m => m);
                    return { matches, error: false };
                } catch (e) {
                    return { matches: [], error: true };
                }
                """,
                arguments: ["query": item.query, "mode": item.mode,
                            "caseSensitive": item.caseSensitive, "text": item.text],
                in: nil, contentWorld: .page)
            let values = try XCTUnwrap(result as? [String: Any])
            let label = "\(item.mode) \(item.caseSensitive ? "case " : "")\"\(item.query)\" in \"\(item.text)\""
            XCTAssertEqual(values["matches"] as? [String], item.matches, label)
            XCTAssertEqual(values["error"] as? Bool, item.error ?? false, label)
        }
    }
}
