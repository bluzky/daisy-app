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
        "slash-commands"
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
          titleKey: "Slash commands",
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
      ["mermaid": true, "colorful-headings": true, "slash-commands": true]
    )
  }

  func testEditorExtensionStateFollowsUserToggle() {
    let configuration = MarkdownHTML.RenderExtensionConfiguration(
      enabledIDs: Set(MarkdownHTML.renderExtensions.map(\.id)).subtracting(["mermaid"])
    )
    XCTAssertEqual(
      MarkdownHTML.editorExtensionState(configuration: configuration),
      ["mermaid": false, "colorful-headings": true, "slash-commands": true]
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

  func testOnlySlashCommandsSkipThePreview() {
    XCTAssertEqual(
      MarkdownHTML.renderExtensions.filter { !$0.affectsPreview }.map(\.id),
      ["slash-commands"]
    )
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
