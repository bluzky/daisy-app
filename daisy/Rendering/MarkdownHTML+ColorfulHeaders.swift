//
//  MarkdownHTML+ColorfulHeaders.swift
//  daisy
//
//  Colorful heading render extension.
//

import Foundation

nonisolated extension MarkdownHTML {
  /// Heading palette shared by the preview and the editor page.
  static let colorfulHeaderPalette = """
    :root {
      --mdp-heading-h1: #d14f6a;
      --mdp-heading-h2: #b97839;
      --mdp-heading-h3: #548e6f;
      --mdp-heading-h4: #527ecb;
      --mdp-heading-h5: #7665c4;
      --mdp-heading-h6: #9d7145;
    }
    :root[data-mdp-color-scheme="dark"] {
      --mdp-heading-h1: #ff7893;
      --mdp-heading-h2: #e7a45f;
      --mdp-heading-h3: #77bd94;
      --mdp-heading-h4: #7da9ff;
      --mdp-heading-h5: #a99aff;
      --mdp-heading-h6: #d5a575;
    }
    @media (prefers-color-scheme: dark) {
      :root:not([data-mdp-color-scheme="light"]) {
        --mdp-heading-h1: #ff7893;
        --mdp-heading-h2: #e7a45f;
        --mdp-heading-h3: #77bd94;
        --mdp-heading-h4: #7da9ff;
        --mdp-heading-h5: #a99aff;
        --mdp-heading-h6: #d5a575;
      }
    }
    """

  static let colorfulHeaderStylesheet = colorfulHeaderPalette + """
    .markdown-body h1 { color: var(--mdp-heading-h1); }
    .markdown-body h2 { color: var(--mdp-heading-h2); }
    .markdown-body h3 { color: var(--mdp-heading-h3); }
    .markdown-body h4 { color: var(--mdp-heading-h4); }
    .markdown-body h5 { color: var(--mdp-heading-h5); }
    .markdown-body h6 { color: var(--mdp-heading-h6); }
    """

  /// The editor tags heading lines `cm-md-h1`…`cm-md-h6`; the module adds
  /// `cm-colorful-headings` to the editor, so these rules apply only while
  /// it is enabled. `#editor` outranks the base heading rules.
  static let colorfulHeaderEditorStylesheet = colorfulHeaderPalette + (1...6).map {
    "#editor .cm-colorful-headings .cm-md-h\($0) { color: var(--mdp-heading-h\($0)); }"
  }.joined(separator: "\n")

  struct ColorfulHeadersExtension: MarkdownRenderExtension {
    let id = "colorful-headings"
    let descriptor = RenderExtensionDescriptor(
      titleKey: "Colorful headings",
      descriptionKey: nil,
      defaultEnabled: true,
      userToggleable: true
    )
    let order = 100
    let editor: (any EditorCapability)? = EditorModule(
      moduleID: "colorful-headings",
      css: MarkdownHTML.colorfulHeaderEditorStylesheet
    )

    func isActive(in context: RenderContext) -> Bool {
      context.html.range(
        of: #"<h[1-6]\b"#,
        options: .regularExpression
      ) != nil
    }

    func assets(mode _: VendorLoading) -> RenderAssets {
      RenderAssets(css: colorfulHeaderStylesheet)
    }
  }
}
