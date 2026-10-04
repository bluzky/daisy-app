//
//  MarkdownRenderExtension.swift
//  daisy
//
//  App-bundled Markdown rendering extensions.
//

import Foundation

/// Stores user overrides. Descriptor defaults apply when no override exists,
/// and values live in app-group defaults so both render hosts agree.
nonisolated enum RenderExtensionPreferences {
  static let defaultsKeyPrefix = "MarkdownPreview.renderExtension.enabled."

  static var currentConfiguration: MarkdownHTML.RenderExtensionConfiguration {
    configuration(from: sharedDefaults())
  }

  static func sharedDefaults(bundle: Bundle = .main) -> UserDefaults? {
    guard let identifier = bundle.object(
      forInfoDictionaryKey: AppearanceMode.appGroupInfoKey
    ) as? String,
      !identifier.isEmpty
    else { return nil }
    return UserDefaults(suiteName: identifier)
  }

  static func configuration(
    from defaults: UserDefaults?,
    registryIDs: [String] = MarkdownHTML.renderExtensions.map(\.id)
  ) -> MarkdownHTML.RenderExtensionConfiguration {
    MarkdownHTML.RenderExtensionConfiguration(
      enabledIDs: enabledIDs(from: defaults, registryIDs: registryIDs)
    )
  }

  static func enabledIDs(
    from defaults: UserDefaults?,
    registryIDs: [String] = MarkdownHTML.renderExtensions.map(\.id)
  ) -> Set<String> {
    Set(registryIDs.filter { isEnabled($0, in: defaults) })
  }

  static func isEnabled(_ id: String, in defaults: UserDefaults?) -> Bool {
    let descriptor = MarkdownHTML.renderExtensions.first { $0.id == id }?.descriptor
    guard descriptor?.userToggleable != false else { return true }
    guard let stored = defaults?.object(forKey: defaultsKey(for: id)) as? NSNumber else {
      return descriptor?.defaultEnabled ?? true
    }
    return stored.boolValue
  }

  static func setEnabled(_ enabled: Bool, for id: String, in defaults: UserDefaults?) {
    let key = defaultsKey(for: id)
    let descriptor = MarkdownHTML.renderExtensions.first { $0.id == id }?.descriptor
    let defaultEnabled = descriptor?.defaultEnabled ?? true
    if enabled == defaultEnabled {
      defaults?.removeObject(forKey: key)
    } else {
      defaults?.set(enabled, forKey: key)
    }
  }

  static func store(
    enabledIDs: Set<String>,
    in defaults: UserDefaults?,
    registryIDs: [String] = MarkdownHTML.renderExtensions.map(\.id)
  ) {
    for id in registryIDs {
      setEnabled(enabledIDs.contains(id), for: id, in: defaults)
    }
  }

  /// IDs may gain punctuation or Unicode. Encode them before forming a
  /// defaults key, avoiding collisions and invalid key-path semantics.
  static func defaultsKey(for id: String) -> String {
    let encoded = Data(id.utf8)
      .base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
    return defaultsKeyPrefix + encoded
  }
}

/// Owns deterministic Markdown-to-HTML behavior and static page assets.
/// Extensions deliberately have no access to view, file, or app state.
nonisolated protocol MarkdownRenderExtension: Sendable {
  var id: String { get }
  var descriptor: MarkdownHTML.RenderExtensionDescriptor { get }
  /// Ascending pipeline position. Registry validation rejects duplicates.
  var order: Int { get }

  /// Pure activation predicate. Receives output after footnotes and each
  /// earlier active transform, and runs exactly once per render.
  func isActive(in context: MarkdownHTML.RenderContext) -> Bool
  /// Optional rewrite after this extension activates.
  func transform(_ context: MarkdownHTML.RenderContext) -> String
  func assets(mode: MarkdownHTML.VendorLoading) -> MarkdownHTML.RenderAssets
  /// Editor-side half of this extension, when it has one. Render-only
  /// extensions return nil. The user toggle, order and descriptor are shared,
  /// so a both-sided extension switches on and off as one unit.
  var editor: (any EditorCapability)? { get }
  /// False for an extension that only changes the editor. Such an extension
  /// still conforms to this protocol; it returns false from `isActive`.
  var affectsPreview: Bool { get }
}

/// Declares that an extension also contributes to the CodeMirror editor. The
/// behaviour itself is a module compiled into the editor bundle and registered
/// by the same id (see `registerEditorExtension` in `entry-cm.js`).
nonisolated protocol EditorCapability: Sendable {
  var moduleID: String { get }
  /// Static CSS for the editor page. It is emitted whether or not the module
  /// is enabled, so scope every rule to a class the module adds.
  var css: String { get }
  /// Strings handed to the module at creation, typically localized labels.
  /// Keep them plain `String` pairs so they serialize to the editor page.
  var options: [String: String] { get }
}

nonisolated struct EditorModule: EditorCapability {
  let moduleID: String
  var css: String = ""
  var options: [String: String] = [:]
}

nonisolated extension MarkdownRenderExtension {
  var editor: (any EditorCapability)? { nil }
  var affectsPreview: Bool { true }

  func transform(_ context: MarkdownHTML.RenderContext) -> String {
    context.html
  }

  func assets(mode _: MarkdownHTML.VendorLoading) -> MarkdownHTML.RenderAssets {
    MarkdownHTML.RenderAssets()
  }
}

nonisolated extension MarkdownHTML {
  /// Input available to every extension.
  struct RenderContext: Sendable {
    let html: String
    let markdown: String
  }

  /// Static metadata for compiled-in render extensions. Keys, not localized
  /// strings, keep the registry independent from any particular UI.
  struct RenderExtensionDescriptor: Sendable, Equatable {
    let titleKey: String
    let descriptionKey: String?
    let defaultEnabled: Bool
    let userToggleable: Bool
  }

  /// CSS is emitted in `<head>` while JavaScript retains its existing
  /// head/body placement. This keeps Quick Look self-contained and lets app
  /// previews lazy-load large vendor bundles after first paint.
  struct RenderAssets: Sendable {
    var css: String = ""
    var headJS: String = ""
    var bodyJS: String = ""
    /// JavaScript capabilities supplied by these static assets. Include the
    /// extension id when its runtime must already exist for body swaps.
    var scriptAssetIDs: Set<String> = []
  }

  /// Snapshot passed from each render host. Rendering never reads defaults
  /// directly, keeping concurrent work deterministic while Settings changes.
  struct RenderExtensionConfiguration: Sendable, Equatable {
    let enabledIDs: Set<String>

    static var allEnabled: Self {
      Self(enabledIDs: Set(renderExtensions.map(\.id)))
    }

    func isEnabled(_ id: String) -> Bool {
      enabledIDs.contains(id)
    }

    func isEnabled(_ renderExtension: any MarkdownRenderExtension) -> Bool {
      !renderExtension.descriptor.userToggleable || enabledIDs.contains(renderExtension.id)
    }
  }

  /// Compiled-in extensions share one ordered lifecycle and user preference
  /// registry. Features that begin before extension transforms receive the
  /// same configuration from `render()`.
  static let renderExtensions: [any MarkdownRenderExtension] = validatedAndOrdered([
    HighlightExtension(),
    CalloutExtension(),
    KaTeXExtension(),
    MermaidExtension(),
    ColorfulHeadersExtension(),
    CollapsibleHeadersExtension(),
    SlashCommandsExtension()
  ])

  static func renderExtensionTitle(for id: String) -> String {
    guard let renderExtension = renderExtensions.first(where: { $0.id == id }) else { return id }
    return NSLocalizedString(renderExtension.descriptor.titleKey, comment: "Render extension setting")
  }

  struct RenderExtensionRun {
    let html: String
    let active: [any MarkdownRenderExtension]

    func contains(_ id: String) -> Bool {
      active.contains { $0.id == id }
    }
  }

  static func applyRenderExtensions(
    to html: String,
    markdown: String,
    configuration: RenderExtensionConfiguration = .allEnabled,
    extensions: [any MarkdownRenderExtension] = renderExtensions
  ) -> RenderExtensionRun {
    var rendered = html
    var active: [any MarkdownRenderExtension] = []
    for ext in validatedAndOrdered(extensions) where configuration.isEnabled(ext) {
      let context = RenderContext(html: rendered, markdown: markdown)
      if ext.isActive(in: context) {
        active.append(ext)
        rendered = ext.transform(context)
      }
    }
    return RenderExtensionRun(html: rendered, active: active)
  }

  static func enabledRenderExtensions(
    configuration: RenderExtensionConfiguration,
    extensions: [any MarkdownRenderExtension] = renderExtensions
  ) -> [any MarkdownRenderExtension] {
    validatedAndOrdered(extensions).filter { configuration.isEnabled($0) }
  }

  /// Enabled flag for every editor module, keyed by module id. Editor pages
  /// receive this at creation and again whenever Settings change.
  static func editorExtensionState(
    configuration: RenderExtensionConfiguration,
    extensions: [any MarkdownRenderExtension] = renderExtensions
  ) -> [String: Bool] {
    var state: [String: Bool] = [:]
    for ext in extensions {
      guard let editor = ext.editor else { continue }
      state[editor.moduleID] = configuration.isEnabled(ext)
    }
    return state
  }

  /// Module options keyed by module id, for modules that have any.
  static func editorExtensionOptions(
    extensions: [any MarkdownRenderExtension] = renderExtensions
  ) -> [String: [String: String]] {
    var options: [String: [String: String]] = [:]
    for ext in extensions {
      guard let editor = ext.editor, !editor.options.isEmpty else { continue }
      options[editor.moduleID] = editor.options
    }
    return options
  }

  /// Concatenated CSS of every editor-capable extension, for the editor page.
  static func editorExtensionCSS(
    extensions: [any MarkdownRenderExtension] = renderExtensions
  ) -> String {
    extensions.compactMap { $0.editor?.css }.filter { !$0.isEmpty }.joined(separator: "\n")
  }

  static func validatedAndOrdered(
    _ extensions: [any MarkdownRenderExtension]
  ) -> [any MarkdownRenderExtension] {
    let orders = extensions.map(\.order)
    precondition(Set(orders).count == orders.count, "Render extension orders must be unique")
    return extensions.sorted { $0.order < $1.order }
  }

  struct CalloutExtension: MarkdownRenderExtension {
    let id = "callout"
    let descriptor = RenderExtensionDescriptor(
      titleKey: "Callouts",
      descriptionKey: nil,
      defaultEnabled: true,
      userToggleable: true
    )
    let order = 20

    func isActive(in context: RenderContext) -> Bool {
      context.html.contains("markdown-alert")
    }
  }

  /// Editor-only: typing `/` on an empty line opens a block menu. The commands
  /// live in the editor bundle; this declares the toggle, the menu styling and
  /// the localized labels. It never touches rendered output.
  struct SlashCommandsExtension: MarkdownRenderExtension {
    let id = "slash-commands"
    let descriptor = RenderExtensionDescriptor(
      titleKey: "Slash commands",
      descriptionKey: nil,
      defaultEnabled: true,
      userToggleable: true
    )
    let order = 300
    let affectsPreview = false
    let editor: (any EditorCapability)? = EditorModule(
      moduleID: "slash-commands",
      css: MarkdownHTML.slashCommandsEditorStylesheet,
      options: MarkdownHTML.slashCommandLabels()
    )

    func isActive(in _: RenderContext) -> Bool { false }
  }

  /// Command ids match `SLASH_COMMANDS` in the editor bundle. A missing label
  /// falls back to the bundle's English one.
  static func slashCommandLabels() -> [String: String] {
    let commands: [(id: String, key: String)] = [
      ("h1", "Heading 1"), ("h2", "Heading 2"), ("h3", "Heading 3"),
      ("quote", "Block Quote"), ("divider", "Divider"),
      ("bullet", "Bulleted List"), ("ordered", "Numbered List"), ("task", "Checklist"),
      ("code", "Code Block"), ("table", "Table"), ("image", "Image"), ("mermaid", "Mermaid diagram"),
      ("math", "Math Block"), ("note", "Note"), ("tip", "Tip"),
      ("important", "Important"), ("warning", "Warning"), ("caution", "Caution"),
      ("templates", "Templates")
    ]
    let groups: [(id: String, key: String)] = [
      ("text", "Text"), ("lists", "Lists"), ("blocks", "Blocks")
    ]
    // Language for the names a template variable writes, such as {{weekday}}.
    var labels: [String: String] = ["locale": Bundle.main.preferredLocalizations.first ?? "en"]
    for command in commands {
      labels["cmd.\(command.id)"] = NSLocalizedString(command.key, comment: "Slash command")
    }
    for group in groups {
      labels["group.\(group.id)"] = NSLocalizedString(group.key, comment: "Slash command group")
    }
    return labels
  }

  /// The menu is attached to <body>, outside `#editor`, so it is styled with
  /// the page's own color variables and follows light and dark appearance.
  static let slashCommandsEditorStylesheet = """
    .cm-md-slash-menu {
      position: fixed;
      z-index: 1000;
      box-sizing: border-box;
      width: 280px;
      max-height: 340px;
      overflow-y: auto;
      overscroll-behavior: contain;
      padding: 8px;
      background: color-mix(in srgb, Canvas 86%, transparent);
      -webkit-backdrop-filter: blur(28px) saturate(1.7);
      backdrop-filter: blur(28px) saturate(1.7);
      color: var(--text);
      border: 0.5px solid color-mix(in srgb, var(--text) 14%, transparent);
      border-radius: 16px;
      box-shadow:
        0 14px 44px rgba(0, 0, 0, 0.18),
        0 2px 8px rgba(0, 0, 0, 0.08);
      font: 14px/1.25 -apple-system, system-ui, sans-serif;
      letter-spacing: normal;
      word-spacing: normal;
      -webkit-user-select: none;
      user-select: none;
    }
    .cm-md-slash-menu[hidden] { display: none; }
    .cm-md-slash-menu::-webkit-scrollbar { width: 10px; }
    .cm-md-slash-menu::-webkit-scrollbar-track { background: transparent; }
    .cm-md-slash-menu::-webkit-scrollbar-thumb {
      background: color-mix(in srgb, var(--text) 24%, transparent);
      border: 3px solid transparent;
      border-radius: 6px;
      background-clip: content-box;
    }
    .cm-md-slash-group {
      padding: 8px 10px 4px;
      font-size: 11px;
      font-weight: 500;
      color: var(--secondary);
    }
    .cm-md-slash-group:first-child { padding-top: 2px; }
    .cm-md-slash-item {
      display: flex;
      align-items: center;
      gap: 14px;
      height: 34px;
      padding: 0 10px;
      border-radius: 10px;
      cursor: default;
    }
    .cm-md-slash-item.cm-md-slash-selected {
      background: color-mix(in srgb, var(--text) 9%, transparent);
    }
    .cm-md-slash-icon {
      flex: none;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      width: 22px;
      color: var(--text);
    }
    .cm-md-slash-label {
      min-width: 0;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }
    .cm-md-slash-label { flex: 1; }
    .cm-md-slash-chevron {
      flex: none;
      color: var(--secondary);
      font-size: 18px;
      line-height: 1;
    }
    .cm-md-slash-back {
      display: flex;
      align-items: center;
      gap: 8px;
      height: 30px;
      padding: 0 10px;
      margin-bottom: 4px;
      border-radius: 10px;
      font-weight: 600;
      cursor: default;
    }
    .cm-md-slash-back .cm-md-slash-chevron { width: 22px; text-align: center; }
    """
}
