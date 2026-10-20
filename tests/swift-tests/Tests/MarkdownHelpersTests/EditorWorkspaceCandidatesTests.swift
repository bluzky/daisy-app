import WebKit
import XCTest
@testable import MarkdownHelpers

@MainActor
final class EditorWorkspaceCandidatesTests: XCTestCase {
    private func snapshot(version: Int, tags: [String]) -> WorkspaceMetadataSnapshot {
        WorkspaceMetadataSnapshot(version: version, tags: tags.map { .init(name: $0, count: 2) },
                                  contexts: [.init(name: "alex", count: 1)], projects: [],
                                  isComplete: true, isTruncated: false)
    }

    func testLiteralMatchesTheEditorSnapshotShape() throws {
        let literal = EditorHTML.workspaceCandidatesLiteral(snapshot(version: 7, tags: ["Roadmap/Q1"]))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(literal.utf8)) as? [String: Any])
        XCTAssertEqual(object["version"] as? Int, 7)
        XCTAssertEqual(object["tags"] as? [[String: AnyHashable]], [["name": "Roadmap/Q1", "count": 2]])
        XCTAssertEqual(object["contexts"] as? [[String: AnyHashable]], [["name": "alex", "count": 1]])
        XCTAssertEqual(object["projects"] as? [[String: AnyHashable]], [])
    }

    func testPageKeepsCandidatesForTheNextDocumentAndRefusesStaleOnes() async throws {
        let script = try TestVendor.script("daisy/Vendor/CodeMirror/mdedit.min.js")
        let html = EditorHTML.render(markdown: "First", editorJavaScript: script)
        let editor = WebViewLayoutHarness(html: html, width: 900, isEditor: true)
        defer { editor.close() }
        _ = try await editor.layout(texts: ["First"], imageCount: 0)

        let current = EditorHTML.workspaceCandidatesLiteral(snapshot(version: 20, tags: ["workspace"]))
        let stale = EditorHTML.workspaceCandidatesLiteral(snapshot(version: 10, tags: ["stale"]))
        let result = try await editor.webView.callAsyncJavaScript("""
            window.__mdEditor.setWorkspaceCandidates(\(current));
            window.__mdEditor.setWorkspaceCandidates(\(stale));
            window.__mdLoadEditor("Second ", "", undefined);
            // Not at a line start, where `#` waits for a name character.
            window.__mdEditor.insertTextAt("#", 7, 7);
            await new Promise((resolve) => setTimeout(resolve, 50));
            return Array.from(document.querySelectorAll(".cm-md-metadata-menu .cm-md-metadata-label"))
                .map((label) => label.textContent);
            """, arguments: [:], in: nil, contentWorld: .page)
        XCTAssertEqual(result as? [String], ["#workspace"])
    }
}
