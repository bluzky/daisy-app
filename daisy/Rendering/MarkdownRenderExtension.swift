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
/// by the same id (see `registerEditorExtension` in `scripts/editor-bundle/src/extensions.js`).
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
    TaskMetadataExtension(),
    SlashCommandsExtension(),
    MetadataCompletionExtension()
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

  /// Shows `due:`, `scheduled:` and `p:` on checkbox task lines as badges, in
  /// the editor (the `task-metadata` module) and in Read mode. The Markdown is
  /// never changed. Quick Look and HTML export never load the page script, and
  /// PDF/PNG export switch the page back to the literal text, so the badges
  /// stay an in-app presentation.
  struct TaskMetadataExtension: MarkdownRenderExtension {
    let id = "task-metadata"
    let descriptor = RenderExtensionDescriptor(
      titleKey: "Task metadata",
      descriptionKey: nil,
      defaultEnabled: true,
      userToggleable: true
    )
    let order = 200
    let editor: (any EditorCapability)? = EditorModule(
      moduleID: "task-metadata",
      css: MarkdownHTML.taskMetadataStylesheet,
      options: MarkdownHTML.taskMetadataLabels()
    )

    /// Mirrors the extractor's field grammar closely enough to load the script
    /// only for documents that can have a badge; the script validates.
    func isActive(in context: RenderContext) -> Bool {
      context.markdown.contains(Self.fieldPattern)
    }

    func assets(mode: VendorLoading) -> RenderAssets {
      guard mode == .lazy else { return RenderAssets(css: MarkdownHTML.taskMetadataStylesheet) }
      return RenderAssets(
        css: MarkdownHTML.taskMetadataStylesheet,
        bodyJS: MarkdownHTML.taskMetadataScript(labels: MarkdownHTML.taskMetadataLabels()),
        scriptAssetIDs: [id]
      )
    }

    nonisolated(unsafe) private static let fieldPattern =
      /(?:^|\s)(?:(?:due|scheduled):\d{4}-\d{2}-\d{2}|p:(?:high|medium|low))/
  }

  /// Badge text and accessibility names, shared by the editor module and the
  /// Read mode script.
  static func taskMetadataLabels() -> [String: String] {
    let keys: [(id: String, key: String)] = [
      ("due", "Due"), ("scheduled", "Scheduled"), ("overdue", "Overdue"), ("priority", "Priority"),
      ("high", "High"), ("medium", "Medium"), ("low", "Low")
    ]
    var labels: [String: String] = ["locale": Bundle.main.preferredLocalizations.first ?? "en"]
    for entry in keys {
      labels[entry.id] = NSLocalizedString(entry.key, comment: "Task metadata badge")
    }
    return labels
  }

  /// Read mode: wraps each valid field on a task's first line in
  /// `.mdp-task-field`, holding the literal text (shown when printing or
  /// exporting) and the badge. The rules match the extractor in
  /// `scripts/editor-bundle/src/workspace-metadata.js`.
  static func taskMetadataScript(labels: [String: String]) -> String {
    let data = (try? JSONSerialization.data(withJSONObject: labels, options: [.sortedKeys])) ?? Data("{}".utf8)
    let json = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "</", with: "<\\/")
    return """
    <script>
    (function() {
      const labels = \(json);
      const FIELD = /(^|\\s)(?:(due|scheduled):(\\d{4}-\\d{2}-\\d{2})|p:(high|medium|low))(?=$|[\\s,;.!?])/g;
      const SKIP = 'code, pre, a, kbd, script, style, .mdp-task-field, .katex, .mermaid';
      const ICONS = {
        due: '<circle cx="10" cy="10" r="6.5"/><path d="M10 6.5V10l2.5 1.5"/>',
        scheduled: '<rect x="3.5" y="4.5" width="13" height="12" rx="2"/><path d="M3.5 8.5h13M7 3v3M13 3v3"/>',
      };
      const pad = (n) => String(n).padStart(2, '0');
      const localDate = (value) => {
        const [y, m, d] = value.split('-').map(Number);
        const date = new Date(2000, 0, 1);
        date.setFullYear(y, m - 1, d);
        return date.getFullYear() === y && date.getMonth() === m - 1 && date.getDate() === d ? date : null;
      };
      const today = () => {
        const now = new Date();
        return `${String(now.getFullYear()).padStart(4, '0')}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
      };
      const format = (date, options) => {
        try { return new Intl.DateTimeFormat(labels.locale, options).format(date); }
        catch (e) { return new Intl.DateTimeFormat('en', options).format(date); }
      };
      function badge(key, value, done) {
        const element = document.createElement('span');
        element.className = 'mdp-task-badge mdp-task-badge-' + key;
        element.setAttribute('role', 'img');
        if (key === 'p') {
          const text = labels[value] || value;
          element.classList.add('mdp-task-badge-priority', 'mdp-task-badge-' + value);
          element.textContent = text.toLocaleUpperCase(labels.locale);
          element.setAttribute('aria-label', labels.priority + ': ' + text);
          return element;
        }
        const date = localDate(value);
        const overdue = key === 'due' && !done && value < today();
        if (overdue) element.classList.add('mdp-task-badge-overdue');
        element.innerHTML = '<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + ICONS[key] + '</svg>';
        element.appendChild(document.createTextNode(value + ' ' + format(date, { weekday: 'short' })));
        element.setAttribute('aria-label', labels[key] + ': ' + format(date, { dateStyle: 'full' })
          + (overdue ? ', ' + labels.overdue : ''));
        return element;
      }
      // Text nodes of a task's first line: up to the first line break or
      // nested block, skipping code, links and other literal content. The
      // item's text is either inline or in its first paragraph.
      function firstLineTextNodes(item) {
        const nodes = [];
        const paragraph = item.querySelector(':scope > p');
        const walker = document.createTreeWalker(item, NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT, {
          acceptNode(node) {
            if (node.nodeType === Node.TEXT_NODE) return NodeFilter.FILTER_ACCEPT;
            if (node.matches(SKIP)) return NodeFilter.FILTER_REJECT;
            return NodeFilter.FILTER_SKIP;
          }
        });
        for (let node = walker.nextNode(); node; node = walker.nextNode()) {
          if (node.nodeType !== Node.TEXT_NODE) continue;
          let stop = false;
          for (let ancestor = node.parentNode; ancestor && ancestor !== item; ancestor = ancestor.parentNode) {
            if (ancestor === paragraph) continue;
            if (/^(UL|OL|P|BLOCKQUOTE|TABLE|DIV|PRE)$/.test(ancestor.tagName)) { stop = true; break; }
          }
          if (stop) break;
          nodes.push(node);
          if (node.nodeValue.includes('\\n')) break;
          if (node.nextSibling && node.nextSibling.nodeName === 'BR') break;
        }
        return nodes;
      }
      function decorate(item) {
        const box = item.querySelector(':scope > .task-list-item-checkbox, :scope > p:first-of-type > .task-list-item-checkbox');
        if (!box) return;
        const done = box.checked;
        let previous = ' ';
        for (const node of firstLineTextNodes(item)) {
          const text = node.nodeValue.split('\\n')[0];
          const startsAfterSpace = /\\s/.test(previous);
          previous = node.nodeValue.slice(-1) || previous;
          const parts = [];
          let last = 0;
          FIELD.lastIndex = 0;
          for (let match; (match = FIELD.exec(text));) {
            if (match.index === 0 && !match[1] && !startsAfterSpace) continue;
            const key = match[2] || 'p';
            const value = match[3] || match[4];
            if (match[3] && !localDate(value)) continue;
            const start = match.index + match[1].length;
            const end = match.index + match[0].length;
            parts.push(text.slice(last, start));
            // No `data-mdp-ext`: that keeps a node through a Read mode
            // morph, and a field wraps source text, so a kept one would sit
            // beside the fresh text and be decorated again on every update.
            const field = document.createElement('span');
            field.className = 'mdp-task-field';
            const source = document.createElement('span');
            source.className = 'mdp-task-field-source';
            source.textContent = text.slice(start, end);
            field.append(source, badge(key, value, done));
            parts.push(field);
            last = end;
          }
          if (!parts.length) continue;
          parts.push(node.nodeValue.slice(last));
          node.replaceWith(...parts);
        }
      }
      window.MdPreview?.registerExtension({
        id: 'task-metadata',
        render(root) { root.querySelectorAll('li.task-list-item').forEach(decorate); }
      });
    })();
    </script>
    """
  }

  /// Badges for the editor and Read mode. `.mdp-task-field-source` is the
  /// literal Markdown kept beside a Read mode badge; printing (PDF) and
  /// `data-mdp-literal-task-metadata` (set around PNG capture) show it instead.
  static let taskMetadataStylesheet = """
    :root {
      --mdp-task-red: #d70015;
      --mdp-task-orange: #c45500;
      --mdp-task-blue: #0062cc;
    }
    :root[data-mdp-color-scheme="dark"] {
      --mdp-task-red: #ff6961;
      --mdp-task-orange: #ffa94d;
      --mdp-task-blue: #64a8ff;
    }
    @media (prefers-color-scheme: dark) {
      :root:not([data-mdp-color-scheme="light"]) {
        --mdp-task-red: #ff6961;
        --mdp-task-orange: #ffa94d;
        --mdp-task-blue: #64a8ff;
      }
    }
    .mdp-task-badge {
      display: inline-flex;
      align-items: center;
      gap: 0.3em;
      padding: 0.08em 0.55em;
      border-radius: 0.55em;
      background: color-mix(in srgb, var(--text) 8%, transparent);
      color: var(--secondary);
      font: 500 0.82em/1.45 -apple-system, system-ui, sans-serif;
      font-variant-numeric: tabular-nums;
      letter-spacing: normal;
      white-space: nowrap;
      /* Center on the text: a pill's baseline would otherwise come from its
         first child (the icon), lifting date pills above priority tags. */
      vertical-align: middle;
      text-decoration: none;
      cursor: text;
    }
    .mdp-task-badge svg { flex: none; width: 1.05em; height: 1.05em; }
    .mdp-task-badge-overdue {
      color: var(--mdp-task-red);
      background: color-mix(in srgb, var(--mdp-task-red) 12%, transparent);
    }
    /* Smaller type in a box as tall as a date pill: 0.82 × 1.45 = 0.72 × 1.65. */
    .mdp-task-badge-priority {
      font-size: 0.72em;
      line-height: 1.65;
      padding-block: 0.09em;
      font-weight: 700;
      letter-spacing: 0.05em;
    }
    .mdp-task-badge-high {
      color: var(--mdp-task-red);
      background: color-mix(in srgb, var(--mdp-task-red) 12%, transparent);
    }
    .mdp-task-badge-medium {
      color: var(--mdp-task-orange);
      background: color-mix(in srgb, var(--mdp-task-orange) 13%, transparent);
    }
    .mdp-task-badge-low {
      color: var(--mdp-task-blue);
      background: color-mix(in srgb, var(--mdp-task-blue) 12%, transparent);
    }
    .mdp-task-field-source { display: none; }
    :root[data-mdp-literal-task-metadata] .mdp-task-field-source { display: inline; }
    :root[data-mdp-literal-task-metadata] .mdp-task-field .mdp-task-badge { display: none; }
    @media print {
      .mdp-task-field-source { display: inline; }
      .mdp-task-field .mdp-task-badge { display: none; }
    }
    """

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

  /// Command ids match `SLASH_COMMANDS` and `TASK_FIELD_COMMANDS` in the
  /// editor bundle. A missing label falls back to the bundle's English one.
  static func slashCommandLabels() -> [String: String] {
    let commands: [(id: String, key: String)] = [
      ("h1", "Heading 1"), ("h2", "Heading 2"), ("h3", "Heading 3"),
      ("quote", "Block Quote"), ("divider", "Divider"),
      ("bullet", "Bulleted List"), ("ordered", "Numbered List"), ("task", "Checklist"),
      ("code", "Code Block"), ("table", "Table"), ("image", "Image"),
      ("link", "Link to File"), ("mermaid", "Mermaid diagram"),
      ("math", "Math Block"), ("note", "Note"), ("tip", "Tip"),
      ("important", "Important"), ("warning", "Warning"), ("caution", "Caution"),
      ("today", "Today"), ("now", "Now"), ("templates", "Templates"),
      ("priority-high", "Priority: High"), ("priority-medium", "Priority: Medium"),
      ("priority-low", "Priority: Low"), ("priority-none", "Priority: None"),
      ("due", "Due Date"), ("schedule", "Schedule"),
      ("due-clear", "Clear Due Date"), ("schedule-clear", "Clear Schedule")
    ]
    let groups: [(id: String, key: String)] = [
      ("text", "Text"), ("lists", "Lists"), ("blocks", "Blocks"), ("insert", "Insert"),
      ("task", "Task")
    ]
    // Accessibility names for the date picker's month buttons.
    let interfaceLabels: [(id: String, key: String)] = [
      ("previousMonth", "Previous Month"), ("nextMonth", "Next Month")
    ]
    // Language for the names a template variable writes, such as {{weekday}}.
    var labels: [String: String] = ["locale": Bundle.main.preferredLocalizations.first ?? "en"]
    for command in commands {
      labels["cmd.\(command.id)"] = NSLocalizedString(command.key, comment: "Slash command")
    }
    for group in groups {
      labels["group.\(group.id)"] = NSLocalizedString(group.key, comment: "Slash command group")
    }
    for label in interfaceLabels {
      labels["label.\(label.id)"] = NSLocalizedString(label.key, comment: "Slash command date picker")
    }
    return labels
  }

  /// A completion menu built by `completionExtensions` in the editor bundle,
  /// whose classes start with `cm-md-<prefix>`. The menu is attached to
  /// <body>, outside `#editor`, so it is styled with the page's own color
  /// variables and follows light and dark appearance.
  static func completionMenuStylesheet(prefix: String) -> String {
    """
    .cm-md-\(prefix)-menu {
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
    .cm-md-\(prefix)-menu[hidden] { display: none; }
    .cm-md-\(prefix)-menu::-webkit-scrollbar { width: 10px; }
    .cm-md-\(prefix)-menu::-webkit-scrollbar-track { background: transparent; }
    .cm-md-\(prefix)-menu::-webkit-scrollbar-thumb {
      background: color-mix(in srgb, var(--text) 24%, transparent);
      border: 3px solid transparent;
      border-radius: 6px;
      background-clip: content-box;
    }
    .cm-md-\(prefix)-group {
      padding: 8px 10px 4px;
      font-size: 11px;
      font-weight: 500;
      color: var(--secondary);
    }
    .cm-md-\(prefix)-group:first-child { padding-top: 2px; }
    .cm-md-\(prefix)-item {
      display: flex;
      align-items: center;
      gap: 14px;
      height: 34px;
      padding: 0 10px;
      border-radius: 10px;
      cursor: default;
    }
    .cm-md-\(prefix)-item.cm-md-\(prefix)-selected {
      background: color-mix(in srgb, var(--text) 9%, transparent);
    }
    .cm-md-\(prefix)-icon {
      flex: none;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      width: 22px;
      color: var(--text);
    }
    .cm-md-\(prefix)-label {
      min-width: 0;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }
    .cm-md-\(prefix)-label { flex: 1; }
    .cm-md-\(prefix)-chevron {
      flex: none;
      color: var(--secondary);
      font-size: 18px;
      line-height: 1;
    }
    .cm-md-\(prefix)-back {
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
    .cm-md-\(prefix)-back .cm-md-\(prefix)-chevron { width: 22px; text-align: center; }
    .cm-md-\(prefix)-detail {
      flex: none;
      color: var(--secondary);
      font-size: 12px;
      font-variant-numeric: tabular-nums;
    }
    """
  }

  /// The slash menu: the shared menu plus priority tints and the date picker.
  static let slashCommandsEditorStylesheet = completionMenuStylesheet(prefix: "slash") + "\n" + """
    .cm-md-slash-tint-high { color: #ff3b30; }
    .cm-md-slash-tint-medium { color: #ff9500; }
    .cm-md-slash-tint-low { color: #007aff; }
    @media (prefers-color-scheme: dark) {
      .cm-md-slash-tint-high { color: #ff453a; }
      .cm-md-slash-tint-medium { color: #ff9f0a; }
      .cm-md-slash-tint-low { color: #0a84ff; }
    }
    /* The month grid has a fixed height, so it never scrolls. */
    .cm-md-slash-menu.cm-md-slash-calendar-menu {
      max-height: none;
      overflow: visible;
    }
    .cm-md-slash-calendar-head {
      display: flex;
      align-items: center;
      justify-content: space-between;
      height: 30px;
      padding: 0 4px;
    }
    .cm-md-slash-calendar-title { font-weight: 600; }
    .cm-md-slash-calendar-nav {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      width: 28px;
      height: 28px;
      border-radius: 8px;
      color: var(--secondary);
      font-size: 18px;
      line-height: 1;
      cursor: default;
    }
    .cm-md-slash-calendar-nav:hover {
      background: color-mix(in srgb, var(--text) 9%, transparent);
    }
    .cm-md-slash-calendar-grid {
      display: grid;
      grid-template-columns: repeat(7, 1fr);
      gap: 2px;
      padding: 4px 0;
    }
    .cm-md-slash-weekday {
      padding: 4px 0;
      font-size: 11px;
      font-weight: 500;
      text-align: center;
      color: var(--secondary);
    }
    .cm-md-slash-day {
      height: 32px;
      line-height: 32px;
      border-radius: 8px;
      text-align: center;
      font-variant-numeric: tabular-nums;
      cursor: default;
    }
    .cm-md-slash-day:hover {
      background: color-mix(in srgb, var(--text) 6%, transparent);
    }
    .cm-md-slash-day-outside { color: var(--secondary); opacity: 0.6; }
    .cm-md-slash-day-today { font-weight: 700; }
    .cm-md-slash-day.cm-md-slash-selected,
    .cm-md-slash-day.cm-md-slash-selected:hover {
      background: var(--accent);
      color: #fff;
      opacity: 1;
    }
    .cm-md-slash-calendar-footer {
      padding: 8px 6px 2px;
      border-top: 0.5px solid color-mix(in srgb, var(--text) 14%, transparent);
    }
    """

  /// Editor-only: typing `#`, `@` or `+` suggests tags, contexts and projects
  /// from the document and the workspace (`metadata-completion.js` in the
  /// editor bundle). This declares the toggle and the menu styling. It never
  /// touches rendered output.
  struct MetadataCompletionExtension: MarkdownRenderExtension {
    let id = "metadata-completion"
    let descriptor = RenderExtensionDescriptor(
      titleKey: "Metadata suggestions",
      descriptionKey: nil,
      defaultEnabled: true,
      userToggleable: true
    )
    let order = 310
    let affectsPreview = false
    let editor: (any EditorCapability)? = EditorModule(
      moduleID: "metadata-completion",
      css: MarkdownHTML.completionMenuStylesheet(prefix: "metadata")
    )

    func isActive(in _: RenderContext) -> Bool { false }
  }
}
