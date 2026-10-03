//
//  MarkdownRenderExtension.swift
//  md-preview
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
}

nonisolated extension MarkdownRenderExtension {
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
    CollapsibleHeadersExtension()
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
}
