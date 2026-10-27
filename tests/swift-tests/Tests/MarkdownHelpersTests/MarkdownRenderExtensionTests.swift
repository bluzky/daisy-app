import Foundation
import WebKit
import XCTest

@testable import MarkdownHelpers

final class MarkdownRenderExtensionTests: XCTestCase {
  func testRegistryContainsBuiltInRenderExtensionsInPipelineOrder() {
    XCTAssertEqual(
      MarkdownHTML.renderExtensions.map(\.id),
      [
        "highlight", "callout", "katex", "mermaid", "colorful-headings",
        "task-metadata", "metadata-links", "query-blocks", "slash-commands", "metadata-completion"
      ]
    )
    let orders = MarkdownHTML.renderExtensions.map(\.order)
    XCTAssertEqual(orders, orders.sorted())
    XCTAssertEqual(Set(orders).count, orders.count)
  }

  func testRegistryDescriptorsDescribeBuiltInsAndToggleableExtensions() {
    XCTAssertEqual(
      MarkdownHTML.renderExtensions.map(\.descriptor),
      [
        .init(
          titleKey: "Code highlighting",
          descriptionKey: nil,
          defaultEnabled: true,
          userToggleable: true
        ),
        .init(
          titleKey: "Callouts",
          descriptionKey: nil,
          defaultEnabled: true,
          userToggleable: true
        ),
        .init(
          titleKey: "Math",
          descriptionKey: nil,
          defaultEnabled: true,
          userToggleable: true
        ),
        .init(
          titleKey: "Mermaid",
          descriptionKey: nil,
          defaultEnabled: true,
          userToggleable: true
        ),
        .init(
          titleKey: "Colorful headings",
          descriptionKey: nil,
          defaultEnabled: true,
          userToggleable: true
        ),
        .init(
          titleKey: "Task metadata",
          descriptionKey: nil,
          defaultEnabled: true,
          userToggleable: true
        ),
        .init(
          titleKey: "Metadata links",
          descriptionKey: nil,
          defaultEnabled: true,
          userToggleable: true
        ),
        .init(
          titleKey: "Query blocks",
          descriptionKey: nil,
          defaultEnabled: true,
          userToggleable: true
        ),
        .init(
          titleKey: "Slash commands",
          descriptionKey: nil,
          defaultEnabled: true,
          userToggleable: true
        ),
        .init(
          titleKey: "Metadata suggestions",
          descriptionKey: nil,
          defaultEnabled: true,
          userToggleable: true
        )
      ]
    )
  }

  func testDisabledExtensionsEmitNeitherTransformsNorAssets() {
    let rendered = MarkdownHTML.render(
      markdown: "# Heading\n\nBody text.",
      vendorLoading: .lazy,
      renderExtensionConfiguration: .init(enabledIDs: [])
    )

    XCTAssertFalse(rendered.html.contains("--mdp-heading-h1"))
  }

  func testDisabledCoreExtensionsPreserveSourceAndEmitNoAssets() {
    let rendered = MarkdownHTML.render(
      markdown: """
      ==Marked==

      > [!NOTE] Keep marker

      Inline $x^2$.

      ```swift
      let answer = 42
      ```

      ```mermaid
      graph TD; A-->B;
      ```
      """,
      vendorLoading: .lazy,
      renderExtensionConfiguration: .init(enabledIDs: [])
    )

    XCTAssertTrue(rendered.articleHTML.contains("==Marked=="))
    XCTAssertFalse(rendered.articleHTML.contains("md-highlight"))
    XCTAssertTrue(rendered.articleHTML.contains("<blockquote"))
    XCTAssertTrue(rendered.articleHTML.contains("[!NOTE] Keep marker"))
    XCTAssertFalse(rendered.articleHTML.contains("markdown-alert"))
    XCTAssertTrue(rendered.articleHTML.contains("$x^2$"))
    XCTAssertFalse(rendered.articleHTML.contains("class=\"math "))
    XCTAssertTrue(rendered.articleHTML.contains("<pre"))
    XCTAssertFalse(rendered.articleHTML.contains("data-hljs-done"))
    XCTAssertTrue(rendered.articleHTML.contains("language-mermaid"))
    XCTAssertFalse(rendered.articleHTML.contains("mermaid-figure"))
    XCTAssertFalse(rendered.html.contains("highlight.min.js"))
    XCTAssertFalse(rendered.html.contains("katex.min.js"))
    XCTAssertFalse(rendered.html.contains("mermaid.min.js"))
    XCTAssertTrue(rendered.scriptAssetIDs.isEmpty)
  }

  func testRenderExtensionPreferencesDefaultEveryRegistryIDToEnabled() throws {
    let (defaults, suiteName) = try makeDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let registryIDs = MarkdownHTML.renderExtensions.map(\.id)

    XCTAssertEqual(
      RenderExtensionPreferences.enabledIDs(from: defaults, registryIDs: registryIDs),
      Set(registryIDs)
    )
  }

  func testRenderExtensionPreferencesPersistOptOutWithSafeKey() throws {
    let (defaults, suiteName) = try makeDefaults()
    let registryIDs = ["math", "future/extension:日本語"]
    defer { defaults.removePersistentDomain(forName: suiteName) }

    RenderExtensionPreferences.setEnabled(false, for: registryIDs[1], in: defaults)

    XCTAssertFalse(RenderExtensionPreferences.isEnabled(registryIDs[1], in: defaults))
    XCTAssertEqual(
      RenderExtensionPreferences.enabledIDs(from: defaults, registryIDs: registryIDs),
      Set(["math"])
    )
    XCTAssertFalse(
      RenderExtensionPreferences.defaultsKey(for: registryIDs[1]).contains("/")
    )

    RenderExtensionPreferences.store(enabledIDs: Set(registryIDs), in: defaults, registryIDs: registryIDs)
    XCTAssertEqual(
      RenderExtensionPreferences.enabledIDs(from: defaults, registryIDs: registryIDs),
      Set(registryIDs)
    )
  }

  private func makeDefaults() throws -> (UserDefaults, String) {
    let suite = "doc.daisy.tests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    return (defaults, suite)
  }

  func testHeadingExtensionsEmitDocumentStylesOnlyWhenActive() {
    let headings = MarkdownHTML.render(
      markdown: "# First\n\nIntro\n\n## Nested\n\nDetails\n\n# Second",
      vendorLoading: .lazy
    )
    XCTAssertTrue(headings.html.contains("--mdp-heading-h1: #d14f6a"))
    XCTAssertTrue(headings.scriptAssetIDs.isEmpty)
  }

  func testWarmupEmitsEnabledExtensionCSSWithoutDocumentScripts() {
    let warmup = MarkdownHTML.render(
      markdown: "Plain text.",
      vendorLoading: .lazy,
      warmup: true
    )

    XCTAssertTrue(warmup.html.contains("--mdp-heading-h1: #d14f6a"))
    XCTAssertTrue(warmup.scriptAssetIDs.isEmpty)
  }

  func testBuiltInExtensionsEmitOnlyTheirActiveScriptAssets() {
    let plain = MarkdownHTML.render(markdown: "Plain text.", vendorLoading: .lazy)
    XCTAssertTrue(plain.scriptAssetIDs.isEmpty)
    XCTAssertTrue(plain.html.contains(".hljs-keyword"))

    let rendered = MarkdownHTML.render(
      markdown: """
      $x^2$

      ```swift
      let answer = 42
      ```

      ```mermaid
      graph TD; A-->B;
      ```
      """,
      vendorLoading: .lazy,
      highlightsCode: false
    )

    XCTAssertEqual(
      rendered.scriptAssetIDs,
      Set(["highlight", "code", "katex", "math", "mermaid"])
    )
    XCTAssertTrue(rendered.html.contains("MdPreviewLazy.lazyExtension"))
    XCTAssertFalse(rendered.html.contains("MdPreviewLazy.lazyRenderer"))
    XCTAssertFalse(rendered.html.contains("registerReapplier(highlightAll)"))
  }

  func testHeadingExtensionsActivateForHeadingsOnlyInFootnoteDefinitions() {
    let rendered = MarkdownHTML.render(
      markdown: "Body text with no heading.[^1]\n\n[^1]: ## Footnote heading",
      vendorLoading: .lazy
    )
    XCTAssertTrue(rendered.html.contains("<h2"))
    XCTAssertTrue(rendered.html.contains("--mdp-heading-h1: #d14f6a"))
  }

  func testActivationRunsOnceInExplicitOrderAgainstEarlierTransforms() {
    let firstCounter = ExtensionInvocationCounter()
    let secondCounter = ExtensionInvocationCounter()
    let first = TestExtension(
      id: "first",
      order: 10,
      counter: firstCounter,
      suffix: "<first/>"
    )
    let second = TestExtension(
      id: "second",
      order: 20,
      counter: secondCounter,
      suffix: "<second/>"
    )

    let run = MarkdownHTML.applyRenderExtensions(
      to: "<p>Body</p>",
      markdown: "Body",
      configuration: .init(enabledIDs: ["first", "second"]),
      extensions: [second, first]
    )

    XCTAssertEqual(run.html, "<p>Body</p><first/><second/>")
    XCTAssertEqual(firstCounter.inputs, ["<p>Body</p>"])
    XCTAssertEqual(secondCounter.inputs, ["<p>Body</p><first/>"])
  }

  func testHostBridgeProvidesExtensionAndReapplierLifecycle() {
    let bridge = MarkdownHTML.hostBridgeScript
    XCTAssertTrue(bridge.contains("window.MdPreview.registerExtension"))
    XCTAssertTrue(bridge.contains("window.MdPreview.reveal"))
    XCTAssertTrue(bridge.contains("window.MdPreview.registerReapplier"))
    XCTAssertFalse(bridge.contains("window.MdPreview.registerRenderer"))
  }

  func testEditorExtensionStateCoversOnlyEditorCapableExtensions() {
    let state = MarkdownHTML.editorExtensionState(configuration: .allEnabled)
    XCTAssertEqual(
      state,
      [
        "mermaid": true, "colorful-headings": true, "task-metadata": true, "metadata-links": true, "query-blocks": true,
        "slash-commands": true, "metadata-completion": true
      ]
    )
  }

  func testEditorExtensionStateFollowsUserToggle() {
    let configuration = MarkdownHTML.RenderExtensionConfiguration(
      enabledIDs: Set(MarkdownHTML.renderExtensions.map(\.id)).subtracting(["mermaid"])
    )
    XCTAssertEqual(
      MarkdownHTML.editorExtensionState(configuration: configuration),
      [
        "mermaid": false, "colorful-headings": true, "task-metadata": true, "metadata-links": true, "query-blocks": true,
        "slash-commands": true, "metadata-completion": true
      ]
    )
  }

  func testRenderOnlyExtensionsHaveNoEditorCapability() {
    let renderOnly = MarkdownHTML.renderExtensions.filter { $0.editor == nil }.map(\.id)
    XCTAssertEqual(
      renderOnly,
      ["highlight", "callout", "katex"]
    )
  }

  func testSlashCommandsIsEditorOnly() throws {
    let slash = try XCTUnwrap(MarkdownHTML.renderExtensions.first { $0.id == "slash-commands" })
    XCTAssertFalse(slash.affectsPreview)
    XCTAssertNotNil(slash.editor)
    let rendered = MarkdownHTML.render(
      markdown: "# Heading\n\n/table",
      vendorLoading: .lazy,
      renderExtensionConfiguration: .allEnabled
    )
    XCTAssertFalse(rendered.html.contains("cm-md-slash"))
    XCTAssertFalse(slash.isActive(in: .init(html: "<p>x</p>", markdown: "/")))
  }

  func testOnlyEditorMenusSkipThePreview() {
    XCTAssertEqual(
      MarkdownHTML.renderExtensions.filter { !$0.affectsPreview }.map(\.id),
      ["slash-commands", "metadata-completion"]
    )
  }

  func testMetadataCompletionIsEditorOnlyWithItsOwnMenuCSS() throws {
    let metadata = try XCTUnwrap(MarkdownHTML.renderExtensions.first { $0.id == "metadata-completion" })
    XCTAssertFalse(metadata.isActive(in: .init(html: "<p>#tag</p>", markdown: "#tag @alex +daisy")))
    XCTAssertEqual(metadata.editor?.moduleID, "metadata-completion")
    let css = try XCTUnwrap(metadata.editor?.css)
    XCTAssertTrue(css.contains(".cm-md-metadata-menu[hidden] { display: none; }"))
    XCTAssertTrue(css.contains(".cm-md-metadata-item.cm-md-metadata-selected {"))
    XCTAssertFalse(css.contains("cm-md-slash"))
    XCTAssertTrue(MarkdownHTML.slashCommandsEditorStylesheet.contains(".cm-md-slash-menu[hidden] { display: none; }"))
    XCTAssertTrue(MarkdownHTML.slashCommandsEditorStylesheet.contains(".cm-md-slash-calendar-footer {"))
    XCTAssertTrue(css.contains(".cm-md-metadata-footer {"))
    let options = try XCTUnwrap(MarkdownHTML.editorExtensionOptions()["metadata-completion"])
    XCTAssertEqual(Set(options.keys), ["label.indexing", "label.truncated"])
  }

  func testSlashCommandOptionsCarryEveryLabelKey() throws {
    let options = try XCTUnwrap(MarkdownHTML.editorExtensionOptions()["slash-commands"])
    let ids = [
      "h1", "h2", "h3", "quote", "divider", "bullet", "ordered", "task", "code",
      "table", "image", "mermaid", "math", "note", "tip", "important", "warning", "caution"
    ]
    for id in ids {
      XCTAssertNotNil(options["cmd.\(id)"], id)
    }
    for group in ["text", "lists", "blocks"] {
      XCTAssertNotNil(options["group.\(group)"], group)
    }
    XCTAssertNil(MarkdownHTML.editorExtensionOptions()["mermaid"])
  }

  func testEditorPageEmbedsExtensionOptionsAndMenuCSS() {
    let html = EditorHTML.render(
      markdown: "x",
      editorJavaScript: "",
      configuration: .init(
        extensionCSS: MarkdownHTML.editorExtensionCSS(),
        extensionOptions: ["slash-commands": ["cmd.h1": "标题 1</script>"]]
      )
    )
    XCTAssertTrue(html.contains(".cm-md-slash-menu"))
    XCTAssertTrue(html.contains(#"extensionOptions: {"slash-commands":{"cmd.h1":"标题 1\u003c\/script>"}}"#))
  }

  func testColorfulHeadingsEditorCSSIsScopedToTheModuleClass() {
    let css = MarkdownHTML.editorExtensionCSS()
    XCTAssertTrue(css.contains("--mdp-heading-h1: #d14f6a"))
    for level in 1...6 {
      XCTAssertTrue(
        css.contains("#editor .cm-colorful-headings .cm-md-h\(level) { color: var(--mdp-heading-h\(level)); }")
      )
    }
    XCTAssertFalse(css.contains(".markdown-body"))
  }

  func testEditorPageEmbedsExtensionCSS() {
    let html = EditorHTML.render(
      markdown: "x",
      editorJavaScript: "",
      configuration: .init(extensionCSS: ".cm-colorful-headings-marker{}")
    )
    XCTAssertTrue(html.contains(".cm-colorful-headings-marker{}"))
  }

  func testEditorExtensionStateLiteralIsSortedAndScriptSafe() {
    XCTAssertEqual(
      EditorHTML.extensionStateLiteral(["b": false, "a": true]),
      #"{"a":true,"b":false}"#
    )
    XCTAssertFalse(EditorHTML.extensionStateLiteral(["</script>": true]).contains("<"))
    XCTAssertEqual(EditorHTML.extensionStateLiteral([:]), "{}")
  }

  func testEditorPageEmbedsExtensionState() {
    let html = EditorHTML.render(
      markdown: "x",
      editorJavaScript: "",
      configuration: .init(extensionState: ["mermaid": false])
    )
    XCTAssertTrue(html.contains(#"extensionState: {"mermaid":false}"#))
    XCTAssertTrue(html.contains("setExtensionState"))
  }

  func testTaskMetadataActivatesOnlyForTaskFields() throws {
    let metadata = try XCTUnwrap(MarkdownHTML.renderExtensions.first { $0.id == "task-metadata" })
    XCTAssertTrue(metadata.affectsPreview)
    XCTAssertEqual(metadata.editor?.moduleID, "task-metadata")
    for markdown in ["- [ ] a due:2026-10-20", "- [ ] a\n- [ ] b scheduled:2026-01-01", "- [ ] a p:high"] {
      XCTAssertTrue(metadata.isActive(in: .init(html: "", markdown: markdown)), markdown)
    }
    for markdown in ["Plain text", "see http://example.com", "xdue:2026-10-20", "p:urgent"] {
      XCTAssertFalse(metadata.isActive(in: .init(html: "", markdown: markdown)), markdown)
    }
  }

  func testTaskMetadataScriptLoadsOnlyInTheApp() throws {
    let metadata = try XCTUnwrap(MarkdownHTML.renderExtensions.first { $0.id == "task-metadata" })
    let app = metadata.assets(mode: .lazy)
    XCTAssertTrue(app.bodyJS.contains("registerExtension"))
    XCTAssertEqual(app.scriptAssetIDs, ["task-metadata"])
    // Quick Look and HTML export render with inline vendors: literal text only.
    let inline = metadata.assets(mode: .inline)
    XCTAssertTrue(inline.headJS.isEmpty && inline.bodyJS.isEmpty)
    XCTAssertTrue(inline.scriptAssetIDs.isEmpty)
    let quickLook = MarkdownHTML.render(markdown: "- [ ] Buy due:2026-10-20", vendorLoading: .inline)
    XCTAssertFalse(quickLook.html.contains("mdp-task-field'"))
    XCTAssertFalse(quickLook.scriptAssetIDs.contains("task-metadata"))
  }

  func testMetadataLinksActivateOnlyForTokens() throws {
    let links = try XCTUnwrap(MarkdownHTML.renderExtensions.first { $0.id == "metadata-links" })
    XCTAssertEqual(links.editor?.moduleID, "metadata-links")
    for markdown in ["#review", "Ask @alex", "Ship +daisy", "a\n#tag"] {
      XCTAssertTrue(links.isActive(in: .init(html: "", markdown: markdown)), markdown)
    }
    for markdown in ["# Heading", "+ item", "name@example.com", "C#", "Plain text"] {
      XCTAssertFalse(links.isActive(in: .init(html: "", markdown: markdown)), markdown)
    }
    // Quick Look and HTML export never load the script.
    XCTAssertTrue(links.assets(mode: .inline).bodyJS.isEmpty)
    XCTAssertEqual(links.assets(mode: .lazy).scriptAssetIDs, ["metadata-links"])
  }

  @MainActor
  func testReadModeLinksTokensOnlyInAWorkspace() async throws {
    let rendered = MarkdownHTML.render(
      markdown: """
      Plan #review with @alex for +daisy and #area/sub, **#bold** C#x `#code` [#text](x.md)

      # Heading #inline

      | #cell |
      | --- |
      """,
      vendorLoading: .lazy
    )
    XCTAssertTrue(rendered.scriptAssetIDs.contains("metadata-links"))
    let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 600))
    webView.loadHTMLString(rendered.html, baseURL: nil)
    let deadline = Date().addingTimeInterval(10)
    while webView.isLoading && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
    let tokens = """
    Array.from(document.querySelectorAll('.mdp-metadata-link')).map(l => l.textContent).join('|')
    """
    func evaluate(_ script: String) async throws -> String? {
      try await webView.evaluateJavaScript(script) as? String
    }
    var outside: String?
    while Date() < deadline {
      outside = try await evaluate("window.MdPreview && window.MdPreview.reapplyExtensions ? (\(tokens)) : null")
      if outside != nil { break }
      try await Task.sleep(for: .milliseconds(50))
    }
    XCTAssertEqual(outside, "", "no links outside a workspace")

    let inside = try await evaluate("""
    document.documentElement.setAttribute('data-mdp-workspace', '');
    window.MdPreview.reapplyExtensions();
    \(tokens)
    """)
    XCTAssertEqual(inside, "#review|@alex|+daisy|#area/sub|#inline")
    let text = try await evaluate("document.querySelector('p').textContent")
    XCTAssertTrue(text?.hasPrefix("Plan #review with @alex for +daisy and #area/sub, #bold C#x #code #text") == true)

    let left = try await evaluate("""
    document.documentElement.removeAttribute('data-mdp-workspace');
    window.MdPreview.reapplyExtensions();
    (\(tokens)) + '/' + document.querySelector('p').textContent.startsWith('Plan #review with')
    """)
    XCTAssertEqual(left, "/true", "leaving the workspace restores the text")
  }

  func testQueryBlocksActivateOnlyForTasksAndNotesFences() throws {
    let blocks = try XCTUnwrap(MarkdownHTML.renderExtensions.first { $0.id == "query-blocks" })
    for markdown in ["```tasks\n#a\n```", "Intro\n\n~~~notes\nin:notes/\n~~~", "  ```tasks  \n```"] {
      XCTAssertTrue(blocks.isActive(in: .init(html: "", markdown: markdown)), markdown)
    }
    for markdown in ["```task\n```", "```files\n#a\n```", "```swift\ntasks\n```", "Plain tasks and files", "    ```tasks"] {
      XCTAssertFalse(blocks.isActive(in: .init(html: "", markdown: markdown)), markdown)
    }
    // Quick Look and HTML export never load the script.
    XCTAssertTrue(blocks.assets(mode: .inline).bodyJS.isEmpty)
    XCTAssertEqual(blocks.assets(mode: .lazy).scriptAssetIDs, ["query-blocks"])
  }

  @MainActor
  func testReadModeShowsQueryResultsOnlyInAWorkspace() async throws {
    let rendered = MarkdownHTML.render(
      markdown: """
      # Plan

      ```tasks
      +daisy -is:done
      ```

      ```swift
      let tasks = 1
      ```
      """,
      vendorLoading: .lazy
    )
    XCTAssertTrue(rendered.scriptAssetIDs.contains("query-blocks"))
    let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 600))
    webView.loadHTMLString(rendered.html, baseURL: nil)
    let deadline = Date().addingTimeInterval(10)
    while webView.isLoading && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
    func evaluate(_ script: String) async throws -> String? {
      try await webView.evaluateJavaScript(script) as? String
    }
    let state = """
    [document.querySelectorAll('.mdp-query').length,
     document.querySelector('pre:has(> code.language-tasks)').getClientRects().length ? 'shown' : 'hidden',
     Array.from(document.querySelectorAll('.mdp-query-row'), r => r.textContent).join('|'),
     document.querySelector('.mdp-query-problems')?.textContent ?? ''].join(';')
    """
    var outside: String?
    while Date() < deadline {
      outside = try await evaluate("window.MdPreview && window.MdPreview.queryResults ? (\(state)) : null")
      if outside != nil { break }
      try await Task.sleep(for: .milliseconds(50))
    }
    XCTAssertEqual(outside, "0;shown;;", "outside a workspace the block is its source")

    let pending = try await evaluate("""
    document.documentElement.setAttribute('data-mdp-workspace', '');
    window.MdPreview.reapplyExtensions();
    \(state)
    """)
    XCTAssertEqual(pending, "1;shown;;", "the source shows until the host answers")

    let id = try await evaluate("document.querySelector('.mdp-query').dataset.queryId")
    let answered = try await evaluate("""
    window.MdPreview.queryResults([{ id: '\(id ?? "")', source: 'tasks', problems: ['bad <b>term</b>'],
      empty: 'No matching tasks',
      groups: [{ label: null, kind: 'none',
                 rows: [{ path: 'a.md', line: 3, text: 'Ship <i>it</i>', checked: false, detail: 'a' }] }] }]);
    \(state)
    """)
    XCTAssertEqual(answered, "1;hidden; Ship <i>it</i>a;bad <b>term</b>", "rows replace the source, as text")
    let layout = try await evaluate("""
    const query = document.querySelector('.mdp-query');
    [query.previousElementSibling.className, query.closest('.md-code-wrap') ? 'inside' : 'outside',
     document.querySelector('.mdp-query-row').className,
     document.querySelector('.mdp-query-checkbox').className].join(';')
    """)
    XCTAssertEqual(layout, "md-code-wrap is-wrapped;outside;mdp-query-row task-list-item;task-list-item-checkbox mdp-query-checkbox",
                   "results follow the code frame and use the document's task markup")

    let decorated = try await evaluate("""
    window.MdPreview.queryResults([{ id: '\(id ?? "")', source: 'tasks', problems: [], empty: '',
      groups: [{ label: null, kind: 'none',
                 rows: [{ path: 'a.md', line: 3, text: 'Water plants @Daniel', checked: false, detail: 'a',
                          source: 'p:medium Water plants due:2026-10-24 @Daniel email@x.com C#' }] }] }]);
    const row = document.querySelector('.mdp-query-row');
    [Array.from(row.querySelectorAll('.mdp-task-badge'), b => b.className.split(' ').slice(1).join('+')).join(','),
     Array.from(row.querySelectorAll('.mdp-query-token'), t => t.textContent).join(','),
     row.querySelector('.mdp-query-link').textContent.includes('due:'),
     row.querySelector('.mdp-query-link').getAttribute('aria-label')].join(';')
    """)
    XCTAssertEqual(decorated,
                   "mdp-task-badge-priority+mdp-task-badge-medium,mdp-task-badge-due;@Daniel;false;Water plants @Daniel",
                   "a task row shows its fields as badges and its names as links")

    let literal = try await evaluate("""
    document.documentElement.setAttribute('data-mdp-literal-task-metadata', '');
    const shown = (node) => node.getClientRects().length ? 'shown' : 'hidden';
    const literal = shown(document.querySelector('pre:has(> code.language-tasks)'))
      + '/' + shown(document.querySelector('.mdp-query'));
    document.documentElement.removeAttribute('data-mdp-literal-task-metadata');
    literal
    """)
    XCTAssertEqual(literal, "shown/hidden", "PNG export shows the source")

    let left = try await evaluate("""
    document.documentElement.removeAttribute('data-mdp-workspace');
    window.MdPreview.reapplyExtensions();
    \(state)
    """)
    XCTAssertEqual(left, "0;shown;;", "leaving the workspace shows the source again")
  }

  @MainActor
  func testReadModeNotesAreAnUnorderedList() async throws {
    let rendered = MarkdownHTML.render(markdown: "```notes\nstatus:active\n```\n", vendorLoading: .lazy)
    let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 600))
    webView.loadHTMLString(rendered.html, baseURL: nil)
    let deadline = Date().addingTimeInterval(10)
    while webView.isLoading && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
    var id: String?
    while Date() < deadline {
      id = try await webView.evaluateJavaScript("""
      window.MdPreview && window.MdPreview.queryResults ? (document.documentElement.setAttribute('data-mdp-workspace', ''),
        window.MdPreview.reapplyExtensions(), document.querySelector('.mdp-query')?.dataset.queryId ?? null) : null
      """) as? String
      if id != nil { break }
      try await Task.sleep(for: .milliseconds(50))
    }
    let list = try await webView.evaluateJavaScript("""
    window.MdPreview.queryResults([{ id: '\(id ?? "")', source: 'notes', problems: [], empty: '',
      groups: [{ label: null, kind: 'none',
                 rows: [{ path: 'p.md', line: 1, text: 'Plan', checked: false, detail: 'projects' }] }] }]);
    const item = document.querySelector('.mdp-query-row');
    [item.parentElement.tagName, item.classList.contains('task-list-item'), !!item.querySelector('input'),
     getComputedStyle(item, '::before').content !== 'none'].join(';')
    """) as? String
    XCTAssertEqual(list, "UL;false;false;true", "a notes row is a bulleted list item, without a checkbox")
  }

  @MainActor
  func testReadModeDrawsGroupsAndTables() async throws {
    let rendered = MarkdownHTML.render(markdown: "# Doc\n\n```tasks\ngroup:project\n```\n", vendorLoading: .lazy)
    let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 600))
    webView.loadHTMLString(rendered.html, baseURL: nil)
    let deadline = Date().addingTimeInterval(10)
    while webView.isLoading && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
    var id: String?
    while Date() < deadline {
      id = try await webView.evaluateJavaScript("""
      window.MdPreview && window.MdPreview.queryResults ? (document.documentElement.setAttribute('data-mdp-workspace', ''),
        window.MdPreview.reapplyExtensions(), document.querySelector('.mdp-query')?.dataset.queryId ?? null) : null
      """) as? String
      if id != nil { break }
      try await Task.sleep(for: .milliseconds(50))
    }
    let row = { (line: Int, text: String) in
      "{ path: 'a.md', line: \(line), text: '\(text)', checked: false, detail: 'a', source: '\(text)' }"
    }
    let grouped = try await webView.evaluateJavaScript("""
    window.MdPreview.queryResults([{ id: '\(id ?? "")', source: 'tasks', problems: [], empty: '', groups: [
      { label: { text: '+daisy' }, kind: 'names', rows: [\(row(3, "Ship +daisy")), \(row(4, "Both +daisy +site"))] },
      { label: { text: 'No project' }, kind: 'none', rows: [\(row(5, "Loose"))] }] }]);
    const headers = Array.from(document.querySelectorAll('.mdp-query-group-header'));
    [headers.map(h => h.textContent).join('|'), headers.every(h => h.getAttribute('role') === 'heading'),
     document.querySelectorAll('.mdp-query :is(h1, h2, h3, h4, h5, h6)').length,
     Array.from(document.querySelectorAll('.mdp-query-group'), g => g.querySelectorAll('.mdp-query-row').length).join(),
     !!headers[0].querySelector('.mdp-query-token'), !!headers[1].querySelector('.mdp-query-none')].join(';')
    """) as? String
    XCTAssertEqual(grouped, "+daisy2|No project1;true;0;2,1;true;true",
                   "groups have headers that are not h1–h6, so the outline skips them")

    let table = try await webView.evaluateJavaScript("""
    window.MdPreview.queryResults([{ id: '\(id ?? "")', source: 'tasks', problems: [], empty: '', view: 'table',
      columns: [{ kind: 'done', label: 'Done' }, { kind: 'text', label: 'Task' }, { kind: 'p', label: 'Priority' },
                { kind: 'value', label: 'partner' }],
      groups: [{ label: null, kind: 'none', rows: [{ path: 'a.md', line: 3, text: 'Ship', checked: true, detail: 'a',
        source: 'Ship p:high', cells: [[], [], [{ text: 'high' }], [{ text: 'Acme' }, { text: 'Up', path: 'up.md' }]] }] }] }]);
    const table = document.querySelector('.mdp-query-table');
    const cells = Array.from(table.querySelectorAll('tbody td'));
    [table.parentElement.classList.contains('md-table-scroll'),
     Array.from(table.querySelectorAll('th'), th => th.textContent + '/' + th.scope).join(','),
     table.querySelector('th').getAttribute('aria-label'), cells[0].querySelector('input').checked,
     cells[1].querySelector('.mdp-query-link').dataset.line, !!cells[1].querySelector('.mdp-task-badge'),
     !!cells[2].querySelector('.mdp-task-badge-high'), cells[3].textContent,
     cells[3].querySelector('.mdp-query-link').dataset.path].join(';')
    """) as? String
    XCTAssertEqual(table, "true;/col,Task/col,Priority/col,partner/col;Done;true;3;false;true;Acme, Up;up.md",
                   "a table has the document's table markup and draws each cell by kind")
  }

  @MainActor
  func testReadModeLeavesAnEmptyQueryBlockAsCode() async throws {
    let rendered = MarkdownHTML.render(markdown: "```tasks\n\n```\n\n```notes\n  \n```\n", vendorLoading: .lazy)
    let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 600))
    webView.loadHTMLString(rendered.html, baseURL: nil)
    let deadline = Date().addingTimeInterval(10)
    while webView.isLoading && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
    var count: Int?
    while Date() < deadline {
      count = try await webView.evaluateJavaScript("""
      window.MdPreview && window.MdPreview.queryResults ? (document.documentElement.setAttribute('data-mdp-workspace', ''),
        window.MdPreview.reapplyExtensions(), document.querySelectorAll('.mdp-query').length) : null
      """) as? Int
      if count != nil { break }
      try await Task.sleep(for: .milliseconds(50))
    }
    XCTAssertEqual(count, 0, "an empty block is not a query")
  }

  func testTaskMetadataPrintsTheLiteralText() {
    let css = MarkdownHTML.taskMetadataStylesheet
    XCTAssertTrue(css.contains("@media print"))
    XCTAssertTrue(css.contains(":root[data-mdp-literal-task-metadata] .mdp-task-field-source { display: inline; }"))
  }

  func testTaskMetadataOptionsCarryEveryLabel() throws {
    let options = try XCTUnwrap(MarkdownHTML.editorExtensionOptions()["task-metadata"])
    for key in ["due", "scheduled", "overdue", "priority", "high", "medium", "low", "locale"] {
      XCTAssertNotNil(options[key], key)
    }
  }

  @MainActor
  func testReadModeRendersTaskFieldsAsBadges() async throws {
    let rendered = MarkdownHTML.render(
      markdown: """
      - [ ] Buy milk scheduled:2026-10-20 due:2000-01-03 p:high, `due:2026-01-01`
      - [x] Done due:2000-01-03 p:low
      - [ ] Wrong due:2026-02-30 p:urgent xdue:2026-10-20
      - Plain due:2026-10-20

      Paragraph due:2026-10-20
      """,
      vendorLoading: .lazy
    )
    XCTAssertTrue(rendered.scriptAssetIDs.contains("task-metadata"))
    let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 600))
    webView.loadHTMLString(rendered.html, baseURL: nil)
    let deadline = Date().addingTimeInterval(10)
    var result: [String: Any] = [:]
    while Date() < deadline {
      if !webView.isLoading {
        result = (try await webView.evaluateJavaScript("""
        (() => {
          const fields = Array.from(document.querySelectorAll('.mdp-task-field'));
          return {
            count: fields.length,
            sources: fields.map(f => f.querySelector('.mdp-task-field-source').textContent).join('|'),
            badges: fields.map(f => f.querySelector('.mdp-task-badge').textContent).join('|'),
            overdue: fields.map(f => f.querySelector('.mdp-task-badge-overdue') ? 1 : 0).join(''),
            text: document.querySelector('li').textContent,
            sourceHidden: fields.length ? getComputedStyle(fields[0].querySelector('.mdp-task-field-source')).display : '',
          };
        })()
        """)) as? [String: Any] ?? [:]
        if (result["count"] as? Int ?? 0) > 0 { break }
      }
      try await Task.sleep(for: .milliseconds(50))
    }
    XCTAssertEqual(result["count"] as? Int, 5)
    XCTAssertEqual(
      result["sources"] as? String,
      "scheduled:2026-10-20|due:2000-01-03|p:high|due:2000-01-03|p:low"
    )
    XCTAssertEqual(result["badges"] as? String, "2026-10-20 Tue|2000-01-03 Mon|HIGH|2000-01-03 Mon|LOW")
    XCTAssertEqual(result["overdue"] as? String, "01000", "only an open task's past due date is overdue")
    XCTAssertEqual(result["sourceHidden"] as? String, "none")
    XCTAssertTrue((result["text"] as? String ?? "").contains("due:2026-01-01"), "code stays literal")

    // Date pills and priority tags share one box height and center line.
    let geometry = try await webView.evaluateJavaScript("""
    (() => {
      const [date, , priority] = Array.from(document.querySelectorAll('li')[0].querySelectorAll('.mdp-task-badge'))
        .map(b => b.getBoundingClientRect());
      return JSON.stringify([date.height - priority.height, (date.top + date.bottom) / 2 - (priority.top + priority.bottom) / 2]);
    })()
    """) as? String
    let offsets = try JSONDecoder().decode([Double].self, from: Data(try XCTUnwrap(geometry).utf8))
    XCTAssertEqual(offsets[0], 0, accuracy: 1, "pill heights")
    XCTAssertEqual(offsets[1], 0, accuracy: 1, "pill centers")

    // The literal text returns for exports.
    let literal = try await webView.evaluateJavaScript("""
    (() => {
      document.documentElement.setAttribute('data-mdp-literal-task-metadata', '');
      const field = document.querySelector('.mdp-task-field');
      return getComputedStyle(field.querySelector('.mdp-task-field-source')).display + '|'
        + getComputedStyle(field.querySelector('.mdp-task-badge')).display;
    })()
    """) as? String
    XCTAssertEqual(literal, "inline|none")

    // Reapplying must not wrap fields twice.
    let again = try await webView.evaluateJavaScript("""
    (() => { window.MdPreview.reapplyExtensions(); return document.querySelectorAll('.mdp-task-field').length; })()
    """) as? Int
    XCTAssertEqual(again, 5)

    // Updating Read mode morphs the article toward fresh HTML (toggling Edit
    // and Read mode does this). Badges must not pile up across updates.
    let articleJSON = String(decoding: try JSONEncoder().encode([rendered.articleHTML]), as: UTF8.self)
    let updated = try await webView.evaluateJavaScript("""
    (() => {
      const [html] = \(articleJSON);
      window.MdPreview.update(html);
      window.MdPreview.update(html);
      const first = document.querySelector('li');
      return JSON.stringify({
        morph: typeof morphdom === 'function',
        count: document.querySelectorAll('.mdp-task-field').length,
        first: Array.from(first.querySelectorAll('.mdp-task-field-source')).map(s => s.textContent).join('|'),
      });
    })()
    """) as? String
    let state = try JSONSerialization.jsonObject(with: Data(try XCTUnwrap(updated).utf8)) as? [String: Any]
    XCTAssertEqual(state?["morph"] as? Bool, true, "the update must take the morph path")
    XCTAssertEqual(state?["count"] as? Int, 5)
    XCTAssertEqual(state?["first"] as? String, "scheduled:2026-10-20|due:2000-01-03|p:high")
  }

  private final class ExtensionInvocationCounter: @unchecked Sendable {
    var inputs: [String] = []
  }

  private struct TestExtension: MarkdownRenderExtension {
    let id: String
    let order: Int
    let counter: ExtensionInvocationCounter
    let suffix: String
    let descriptor = MarkdownHTML.RenderExtensionDescriptor(
      titleKey: "Test extension",
      descriptionKey: nil,
      defaultEnabled: true,
      userToggleable: true
    )

    func isActive(in context: MarkdownHTML.RenderContext) -> Bool {
      counter.inputs.append(context.html)
      return true
    }

    func transform(_ context: MarkdownHTML.RenderContext) -> String {
      context.html + suffix
    }
  }
}
