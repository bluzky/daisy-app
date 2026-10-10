import Foundation
@testable import MarkdownHelpers

/// Access to production assets and fixtures in the repository checkout.
/// MarkdownHelpers also bundles Vendor resources so renderer bootstrap paths
/// (including KaTeX and Mermaid) are the same in tests and the app.
enum TestVendor {
    /// Repository root, derived from this file's location at
    /// `tests/swift-tests/Tests/MarkdownHelpersTests/` (five levels deep).
    static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// Points the render-time highlighter at the repository's grammar bundle.
    /// CodeHighlighter has its own app-bundle lookup; install the same
    /// grammar explicitly for tests that exercise render-time highlighting.
    /// Call from `class func setUp()` in every suite that asserts on
    /// highlighted or `data-hljs-done` output.
    static func installHighlighterGrammar() {
        guard let source = try? String(
            contentsOf: repositoryRoot.appendingPathComponent("daisy/Vendor/Highlight/highlight.min.js"),
            encoding: .utf8
        ) else { return }
        CodeHighlighter.useGrammar(source: source)
    }

    /// Repo-relative vendored JS escaped for an inline `<script>` block.
    static func script(_ relativePath: String) throws -> String {
        let url = repositoryRoot.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw NSError(domain: "TestVendor", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "\(relativePath) is missing. The editor bundle is not checked in: run "
                + "`npm ci && npm run build` in scripts/editor-bundle (an Xcode build does it too)."])
        }
        return try String(contentsOf: url, encoding: .utf8)
            .replacingOccurrences(of: "</script", with: "<\\/script")
    }
}
