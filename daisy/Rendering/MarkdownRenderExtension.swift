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
    MetadataLinksExtension(),
    QueryBlocksExtension(),
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
      ("today", "Today"), ("now", "Now"), ("carryover", "Carry over unfinished tasks"),
      ("move", "Move to…"), ("templates", "Templates"),
      ("priority-high", "Priority: High"), ("priority-medium", "Priority: Medium"),
      ("priority-low", "Priority: Low"), ("priority-none", "Priority: None"),
      ("due", "Due Date"), ("schedule", "Schedule"),
      ("due-clear", "Clear Due Date"), ("schedule-clear", "Clear Schedule")
    ]
    let groups: [(id: String, key: String)] = [
      ("text", "Text"), ("lists", "Lists"), ("blocks", "Blocks"), ("insert", "Insert"),
      ("task", "Task"), ("actions", "Actions")
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
    .cm-md-\(prefix)-footer {
      padding: 8px 10px 2px;
      margin-top: 4px;
      border-top: 0.5px solid color-mix(in srgb, var(--text) 14%, transparent);
      font-size: 12px;
      color: var(--secondary);
    }
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
  /// `#tag`, `@context` and `+project` tokens as links to their workspace
  /// page. Read mode wraps each token in `.mdp-metadata-link`; it reads as a
  /// link and opens on click only while the page has `data-mdp-workspace`,
  /// which the host sets on workspace windows. The editor module styles the
  /// tokens the same way and opens them with Cmd+click. Quick Look and HTML
  /// export never load the script.
  struct MetadataLinksExtension: MarkdownRenderExtension {
    let id = "metadata-links"
    let descriptor = RenderExtensionDescriptor(
      titleKey: "Metadata links",
      descriptionKey: nil,
      defaultEnabled: true,
      userToggleable: true
    )
    let order = 210
    let editor: (any EditorCapability)? = EditorModule(
      moduleID: "metadata-links",
      css: MarkdownHTML.metadataLinksStylesheet
    )

    func isActive(in context: RenderContext) -> Bool {
      context.markdown.contains(Self.tokenPattern)
    }

    func assets(mode: VendorLoading) -> RenderAssets {
      guard mode == .lazy else { return RenderAssets() }
      return RenderAssets(
        css: MarkdownHTML.metadataLinksStylesheet,
        bodyJS: MarkdownHTML.metadataLinksScript,
        scriptAssetIDs: [id]
      )
    }

    nonisolated(unsafe) private static let tokenPattern = /(?:^|\s)[#@+][\p{L}\p{N}_\-]/
  }

  /// Read mode half of `metadata-links`. The token rules match
  /// `scripts/editor-bundle/src/metadata-names.js`; the character before a
  /// token is taken from the source it renders, so `**#tag**` (after `*`)
  /// stays text, as it does for the extractor.
  static let metadataLinksScript = #"""
    <script>
    (function() {
      const TOKEN = /(^|\s)([#@+])([\p{L}\p{N}_-][\p{L}\p{M}\p{N}_\-\/]*)/gu;
      const LETTER = /\p{L}/u;
      const SKIP = 'code, pre, a, kbd, script, style, table, svg, .md-frontmatter, .mdp-metadata-link, .mdp-task-field, .katex, .mermaid';
      const INLINE = /^(STRONG|B|EM|I|DEL|S|MARK|SPAN|SUB|SUP|U)$/;
      const isWorkspace = () => document.documentElement.hasAttribute('data-mdp-workspace');
      const valid = (name) => LETTER.test(name) && name.split('/').every(Boolean);
      // The source character before a text node: whitespace at a block
      // start, a line break or a checkbox; Markdown punctuation next to
      // inline formatting, code and other elements.
      function previousCharacter(node) {
        const sibling = node.previousSibling;
        if (sibling) {
          if (sibling.nodeType === Node.TEXT_NODE) return sibling.nodeValue.slice(-1) || ' ';
          return sibling.nodeName === 'BR' || sibling.nodeName === 'INPUT' ? ' ' : 'x';
        }
        return INLINE.test(node.parentNode.nodeName) ? 'x' : ' ';
      }
      function wrap(root) {
        const nodes = [];
        const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT, {
          acceptNode(node) {
            if (node.nodeType === Node.TEXT_NODE) return NodeFilter.FILTER_ACCEPT;
            return node.matches(SKIP) ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_SKIP;
          }
        });
        for (let node = walker.nextNode(); node; node = walker.nextNode()) {
          if (/[#@+]/.test(node.nodeValue)) nodes.push(node);
        }
        for (const node of nodes) {
          const text = node.nodeValue;
          const before = previousCharacter(node);
          const parts = [];
          let last = 0;
          TOKEN.lastIndex = 0;
          for (let match; (match = TOKEN.exec(text));) {
            if (match.index === 0 && !match[1] && !/\s/.test(before)) continue;
            if (!valid(match[3])) continue;
            const start = match.index + match[1].length;
            const end = match.index + match[0].length;
            parts.push(text.slice(last, start));
            // No `data-mdp-ext`, like task fields: a kept node would sit
            // beside the fresh text after a Read mode morph.
            const link = document.createElement('span');
            link.className = 'mdp-metadata-link';
            link.setAttribute('role', 'link');
            link.tabIndex = 0;
            link.textContent = text.slice(start, end);
            parts.push(link);
            last = end;
          }
          if (!parts.length) continue;
          parts.push(text.slice(last));
          node.replaceWith(...parts);
        }
      }
      function unwrap(root) {
        for (const link of root.querySelectorAll('.mdp-metadata-link')) {
          const parent = link.parentNode;
          link.replaceWith(document.createTextNode(link.textContent));
          parent.normalize();
        }
      }
      function open(event) {
        const link = event.target.closest && event.target.closest('.mdp-metadata-link');
        if (!link || !isWorkspace()) return;
        event.preventDefault();
        event.stopPropagation();
        try {
          window.webkit.messageHandlers.mdPreviewHost.postMessage({ kind: 'openMetadata', token: link.textContent });
        } catch (e) {}
      }
      document.addEventListener('click', open, true);
      document.addEventListener('keydown', (event) => { if (event.key === 'Enter') open(event); }, true);
      window.MdPreview?.registerExtension({
        id: 'metadata-links',
        render(root) { isWorkspace() ? wrap(root) : unwrap(root); }
      });
    })();
    </script>
    """#

  /// Shared by Read mode and the editor; tokens look like links only in a
  /// workspace window (`data-mdp-workspace` in Read mode, `cm-metadata-links`
  /// on the editor).
  static let metadataLinksStylesheet = """
    :root[data-mdp-workspace] .mdp-metadata-link,
    .cm-metadata-links .cm-md-metadata-link {
      color: var(--link);
    }
    .cm-metadata-links .cm-md-metadata-link:hover { text-decoration: underline; }
    .cm-mod-held.cm-metadata-links .cm-md-metadata-link:hover { cursor: pointer; }
    :root[data-mdp-workspace] .mdp-metadata-link { cursor: pointer; }
    :root[data-mdp-workspace] .mdp-metadata-link:hover { text-decoration: underline; }
    @media print {
      :root[data-mdp-workspace] .mdp-metadata-link { color: inherit; }
    }
    """

  /// ```` ```tasks ```` and ```` ```notes ```` blocks list what their query
  /// matches in the workspace, in Read mode in a workspace window. The page
  /// posts each block's text to the host (`runQueries`), which parses it
  /// (`WorkspaceQueryParser`), runs it on the workspace index and answers
  /// through `MdPreview.queryResults`, again whenever the index changes. The
  /// block's source stays in the page and shows wherever results don't:
  /// outside a workspace, before the first answer, when printing, and in PNG
  /// export (`data-mdp-literal-task-metadata`). Quick Look and HTML export
  /// never load the script. The editor module (`query-blocks` in
  /// `scripts/editor-bundle/src/query-blocks.js`) shows the same results in
  /// place of the block until the caret enters it, like a Mermaid diagram.
  struct QueryBlocksExtension: MarkdownRenderExtension {
    let id = "query-blocks"
    let descriptor = RenderExtensionDescriptor(
      titleKey: "Query blocks",
      descriptionKey: nil,
      defaultEnabled: true,
      userToggleable: true
    )
    let order = 220
    let editor: (any EditorCapability)? = EditorModule(
      moduleID: "query-blocks",
      css: MarkdownHTML.queryBlocksEditorStylesheet,
      options: MarkdownHTML.taskMetadataLabels()
    )

    func isActive(in context: RenderContext) -> Bool {
      context.markdown.contains(Self.fencePattern)
    }

    func assets(mode: VendorLoading) -> RenderAssets {
      guard mode == .lazy else { return RenderAssets() }
      return RenderAssets(
        // Task badges and name links look as they do in the document, even
        // where it has none of its own and those extensions stay unloaded.
        css: MarkdownHTML.queryBlocksStylesheet + "\n" + MarkdownHTML.taskMetadataStylesheet,
        bodyJS: MarkdownHTML.queryBlocksScript(labels: MarkdownHTML.taskMetadataLabels()),
        scriptAssetIDs: [id]
      )
    }

    nonisolated(unsafe) private static let fencePattern = /(?m)^[ \t]{0,3}(?:```|~~~)[ \t]*(?:tasks|notes)[ \t]*$/
  }

  /// Read mode half of `query-blocks`. Every string it shows comes from the
  /// host and is set as text, never as HTML.
  static func queryBlocksScript(labels: [String: String]) -> String {
    let data = (try? JSONSerialization.data(withJSONObject: labels, options: [.sortedKeys])) ?? Data("{}".utf8)
    let json = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "</", with: "<\\/")
    return #"""
    <script>
    (function() {
      const SELECTOR = 'pre > code.language-tasks, pre > code.language-notes';
      const isWorkspace = () => document.documentElement.hasAttribute('data-mdp-workspace');
      const post = (message) => {
        try { window.webkit.messageHandlers.mdPreviewHost.postMessage(message); } catch (e) {}
      };
      const hash = (text) => {
        let h = 5381;
        for (let i = 0; i < text.length; i++) h = ((h << 5) + h + text.charCodeAt(i)) >>> 0;
        return h.toString(36);
      };
      const results = new Map();
      let requested = null;

      // A task row shows its line as the document does: `due:`,
      // `scheduled:` and `p:` as the task-metadata badges, `#`/`@`/`+`
      // names as links to their pages. The rules mirror
      // `scripts/editor-bundle/src/task-line-segments.js`.
      const labels = \#(json);
      const FIELD = /^(?:(due|scheduled):(\d{4}-\d{2}-\d{2})|p:(high|medium|low))(?=$|[\s,;.!?])/u;
      const TOKEN = /^([#@+])([\p{L}\p{N}_-][\p{L}\p{M}\p{N}_\-\/]*)/u;
      const LETTER = /\p{L}/u;
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
        const node = document.createElement('span');
        node.className = 'mdp-task-badge mdp-task-badge-' + (key === 'p' ? 'priority' : key);
        node.setAttribute('role', 'img');
        if (key === 'p') {
          const text = labels[value] || value;
          node.classList.add('mdp-task-badge-' + value);
          node.textContent = text.toLocaleUpperCase(labels.locale);
          node.setAttribute('aria-label', labels.priority + ': ' + text);
          return node;
        }
        const date = localDate(value);
        const overdue = key === 'due' && !done && value < today();
        if (overdue) node.classList.add('mdp-task-badge-overdue');
        node.innerHTML = '<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + ICONS[key] + '</svg>';
        node.appendChild(document.createTextNode(value + ' ' + format(date, { weekday: 'short' })));
        node.setAttribute('aria-label', labels[key] + ': ' + format(date, { dateStyle: 'full' })
          + (overdue ? ', ' + labels.overdue : ''));
        return node;
      }
      function rowText(row, done) {
        const text = element('span', 'mdp-query-text');
        const source = Array.from(row.source || row.text);
        let plain = '';
        const flush = () => { if (plain) text.append(element('span', 'mdp-query-plain', plain)); plain = ''; };
        for (let index = 0; index < source.length;) {
          const atBoundary = index === 0 || /\s/.test(source[index - 1]);
          const rest = source.slice(index).join('');
          const field = row.source && atBoundary ? FIELD.exec(rest) : null;
          if (field && (!field[2] || localDate(field[2]))) {
            flush();
            text.append(badge(field[1] || 'p', field[2] || field[3], done));
            index += Array.from(field[0]).length;
            continue;
          }
          const token = atBoundary ? TOKEN.exec(rest) : null;
          if (token && LETTER.test(token[2]) && token[2].split('/').every(Boolean)) {
            flush();
            const link = element('span', 'mdp-query-token', token[0]);
            link.setAttribute('role', 'link');
            text.append(link);
            index += Array.from(token[0]).length;
            continue;
          }
          plain += source[index];
          index++;
        }
        flush();
        return text;
      }

      // An empty block is not a query: it stays code and is never run.
      function blocks(root) {
        return Array.from(root.querySelectorAll(SELECTOR), (code) => {
          const source = code.classList.contains('language-tasks') ? 'tasks' : 'notes';
          const text = code.textContent;
          return { pre: code.parentElement, source, text, id: source + ':' + hash(text) };
        }).filter((block) => block.text.trim());
      }

      function element(tag, className, text) {
        const node = document.createElement(tag);
        if (className) node.className = className;
        if (text != null) node.textContent = text;
        return node;
      }

      function fill(container, result) {
        container.replaceChildren();
        container.classList.toggle('mdp-query-pending', !result);
        if (!result) return;
        if (result.problems.length) {
          const problems = element('ul', 'mdp-query-problems');
          for (const problem of result.problems) problems.append(element('li', null, problem));
          container.append(problems);
        }
        const groups = result.groups || [];
        if (!groups.some((group) => group.rows.length)) {
          container.append(element('p', 'mdp-query-empty', result.empty));
          return;
        }
        for (const group of groups) {
          const rows = result.view === 'table' ? table(result, group.rows) : list(result, group.rows);
          if (!group.label) {
            container.append(rows);
            continue;
          }
          // Not an h1–h6: the outline reads those, and a group is part of
          // the block, not the document's structure.
          const section = element('section', 'mdp-query-group');
          const header = element('div', 'mdp-query-group-header');
          header.setAttribute('role', 'heading');
          header.setAttribute('aria-level', '4');
          header.append(values(group.kind, [group.label], false),
                        element('span', 'mdp-query-group-count', String(group.rows.length)));
          section.append(header, rows);
          container.append(section);
        }
      }

      function checkbox(row) {
        const box = element('input', 'task-list-item-checkbox mdp-query-checkbox');
        box.type = 'checkbox';
        box.checked = row.checked;
        box.dataset.path = row.path;
        box.dataset.line = row.line;
        box.setAttribute('aria-label', row.text);
        return box;
      }

      // The row's text, opening its line; in a table, without the fields
      // its own columns show.
      function rowLink(row, result, withSource) {
        const link = rowText(withSource ? row : { text: row.text }, result.source === 'tasks' && row.checked);
        link.classList.add('mdp-query-link');
        link.setAttribute('role', 'link');
        link.setAttribute('aria-label', row.text);
        link.dataset.path = row.path;
        link.dataset.line = row.line;
        return link;
      }

      // A cell's or a group label's values, drawn by kind.
      function values(kind, list, done) {
        const node = element('span', 'mdp-query-values' + (kind === 'none' ? ' mdp-query-none' : ''));
        list.forEach((value, index) => {
          if (index) node.append(document.createTextNode(kind === 'value' ? ', ' : ' '));
          if (kind === 'due' || kind === 'scheduled' || kind === 'p') {
            const text = kind === 'p' ? value.text.toLowerCase() : value.text;
            if (kind === 'p' ? labels[text] : localDate(text)) {
              node.append(badge(kind, text, done));
              return;
            }
          }
          if (kind === 'names') {
            const token = element('span', 'mdp-query-token', value.text);
            token.setAttribute('role', 'link');
            node.append(token);
          } else if (value.path) {
            const link = element('span', 'mdp-query-link', value.text);
            link.setAttribute('role', 'link');
            link.dataset.path = value.path;
            link.dataset.line = 1;
            node.append(link);
          } else {
            node.append(element('span', null, value.text));
          }
        });
        return node;
      }

      // The article's own list markup, so rows look like the document's
      // tasks and lists.
      function list(result, rows) {
        const list = element('ul', 'mdp-query-results mdp-query-' + result.source);
        for (const row of rows) {
          const item = element('li', 'mdp-query-row' + (result.source === 'tasks' ? ' task-list-item' : ''));
          // The space the document's own task items have after the box.
          if (result.source === 'tasks') item.append(checkbox(row), document.createTextNode(' '));
          item.append(rowLink(row, result, true));
          if (row.detail) {
            const detail = element('span', 'mdp-query-detail', row.detail);
            detail.title = row.path;
            item.append(detail);
          }
          list.append(item);
        }
        return list;
      }

      // The article's table markup and scroll wrapper, so it looks like
      // the document's tables.
      function table(result, rows) {
        const scroll = element('div', 'md-table-scroll mdp-query-table-scroll');
        const table = element('table', 'mdp-query-table mdp-query-' + result.source);
        const head = element('tr');
        for (const column of result.columns) {
          const cell = element('th', 'mdp-query-cell-' + column.kind, column.kind === 'done' ? '' : column.label);
          cell.scope = 'col';
          if (column.kind === 'done') cell.setAttribute('aria-label', column.label);
          head.append(cell);
        }
        const body = element('tbody');
        for (const row of rows) {
          const line = element('tr', 'mdp-query-row' + (row.checked ? ' mdp-query-done' : ''));
          result.columns.forEach((column, index) => {
            const cell = element('td', 'mdp-query-cell-' + column.kind);
            if (column.kind === 'done') cell.append(checkbox(row));
            else if (column.kind === 'text') cell.append(rowLink(row, result, false));
            else cell.append(values(column.kind, (row.cells || [])[index] || [], row.checked));
            line.append(cell);
          });
          body.append(line);
        }
        table.append(element('thead'), body);
        table.firstChild.append(head);
        scroll.append(table);
        return scroll;
      }

      // The block's frame: the code wrapper with its header, once the page
      // has added it, otherwise the `pre` itself.
      const frame = (pre) => pre.parentElement && pre.parentElement.classList.contains('md-code-wrap')
        ? pre.parentElement : pre;

      function render(root) {
        const found = isWorkspace() ? blocks(root) : [];
        const wanted = new Set();
        for (const block of found) {
          const anchor = frame(block.pre);
          let container = Array.from(root.querySelectorAll('.mdp-query'))
            .find((node) => node.dataset.queryId === block.id && !wanted.has(node)
              && (node.previousElementSibling === anchor || node.previousElementSibling === block.pre));
          if (!container) {
            // Kept through a Read mode morph, like other extension controls.
            container = element('div', 'mdp-query');
            container.setAttribute('data-mdp-ext', '');
            container.dataset.queryId = block.id;
          }
          if (container.previousElementSibling !== anchor) anchor.after(container);
          wanted.add(container);
          fill(container, results.get(block.id));
        }
        for (const container of root.querySelectorAll('.mdp-query')) {
          if (!wanted.has(container)) container.remove();
        }
        const queries = found.map(({ id, source, text }) => ({ id, source, text }));
        const key = JSON.stringify(queries);
        if (key !== requested) {
          requested = key;
          post({ kind: 'runQueries', queries });
        }
      }

      window.MdPreview && (window.MdPreview.queryResults = (list) => {
        for (const result of list) results.set(result.id, result);
        for (const container of document.querySelectorAll('.mdp-query')) {
          fill(container, results.get(container.dataset.queryId));
        }
      });
      document.addEventListener('click', (event) => {
        const token = event.target.closest && event.target.closest('.mdp-query-token');
        if (token) {
          event.preventDefault();
          event.stopPropagation();
          post({ kind: 'openMetadata', token: token.textContent });
          return;
        }
        const link = event.target.closest && event.target.closest('.mdp-query-link');
        if (!link) return;
        event.preventDefault();
        event.stopPropagation();
        post({ kind: 'openQueryResult', path: link.dataset.path, line: Number(link.dataset.line) });
      }, true);
      // Capturing, and stopped here: the page's own task checkboxes share
      // the class and would otherwise post a change to this document.
      document.addEventListener('change', (event) => {
        const box = event.target;
        if (!box.matches || !box.matches('.mdp-query-checkbox')) return;
        event.stopImmediatePropagation();
        post({ kind: 'queryTaskCheckbox', path: box.dataset.path, line: Number(box.dataset.line),
               checked: box.checked });
      }, true);
      window.MdPreview?.registerExtension({ id: 'query-blocks', render });
    })();
    </script>
    """#
  }

  /// Results replace the block's source on screen only; print and PNG
  /// export show the source.
  static let queryBlocksStylesheet = """
    @media screen {
      :root[data-mdp-workspace]:not([data-mdp-literal-task-metadata]) :is(pre, .md-code-wrap):has(+ .mdp-query:not(.mdp-query-pending)) {
        display: none;
      }
    }
    .mdp-query-pending { display: none; }
    .mdp-query-problems { color: var(--mdp-task-red, #d70015); }
    .mdp-query-link { cursor: pointer; }
    .mdp-query-link:hover .mdp-query-plain { text-decoration: underline; }
    .mdp-query-token { color: var(--link); cursor: pointer; }
    .mdp-query-token:hover { text-decoration: underline; }
    .mdp-query-detail {
      float: inline-end;
      margin-inline-start: 1em;
      color: var(--secondary);
      font-size: 0.85em;
      text-decoration: none;
    }
    .mdp-query-empty { color: var(--secondary); }
    .mdp-query-group + .mdp-query-group { margin-top: 1.2em; }
    .mdp-query-group-header {
      display: flex;
      align-items: baseline;
      gap: 0.5em;
      padding-bottom: 0.3em;
      border-bottom: 1px solid var(--grid);
      font-weight: 600;
    }
    .mdp-query-group-count {
      color: var(--secondary);
      font-size: 0.85em;
      font-weight: 400;
      font-variant-numeric: tabular-nums;
    }
    .mdp-query-none { color: var(--secondary); }
    .mdp-query-group > ul { margin-top: 0.5em; }
    .mdp-query-group > .mdp-query-table-scroll { margin-top: 0; }
    .mdp-query-group > .mdp-query-table-scroll tr:first-child > th { border-top: 0; }
    .mdp-query-table .mdp-query-checkbox { margin: 0; vertical-align: middle; }
    .mdp-query-table .mdp-query-cell-done { width: 1px; }
    .mdp-query-table :is(.mdp-query-cell-due, .mdp-query-cell-scheduled, .mdp-query-cell-p) { white-space: nowrap; }
    .mdp-query-table .mdp-query-done .mdp-query-text { color: var(--secondary); text-decoration: line-through; }
    :root[data-mdp-literal-task-metadata] .mdp-query { display: none; }
    @media print {
      .mdp-query { display: none; }
    }
    """

  /// The editor's results, laid out like the document's task list: the
  /// checkbox hangs in the marker column, as `.cm-md-task-marker` does.
  static let queryBlocksEditorStylesheet = """
    .cm-md-query { cursor: text; }
    .cm-md-query ul { list-style: none; margin: 0; padding: 0; padding-inline-start: 2.1em; }
    .cm-md-query-problems { color: var(--mdp-task-red, #d70015); }
    .cm-md-query-row { position: relative; }
    /* Notes are an unordered list: the circle `.cm-md-bullet` paints. */
    .cm-md-query-notes > .cm-md-query-row::before {
      content: "";
      position: absolute;
      inset-inline-start: calc(-0.75em - 0.4em);
      top: calc(0.5lh - 0.2em);
      width: 0;
      height: 0;
      border: 0.2em solid var(--link);
      border-radius: 50%;
    }
    /* Rows after the first are spaced like list items (`.cm-md-list-item-gap`). */
    .cm-md-query-row + .cm-md-query-row { padding-top: \(MarkdownHTML.textScaled(MarkdownHTML.listItemSpacing)); }
    .cm-md-query-done { color: var(--secondary); text-decoration: line-through; }
    .cm-md-query-checkbox {
      appearance: none;
      -webkit-appearance: none;
      font: inherit;
      width: 0.9em;
      height: 0.9em;
      margin: 0;
      margin-inline-start: calc(-0.9em - 0.25em);
      margin-inline-end: 0.25em;
      vertical-align: calc(0.5cap - 0.45em);
      border: 1.5px solid var(--grid);
      border-radius: 25%;
      background: transparent;
      position: relative;
      cursor: pointer;
    }
    .cm-md-query-checkbox:checked { border-color: var(--accent); background: var(--accent); }
    .cm-md-query-checkbox:checked::after {
      content: "";
      position: absolute;
      inset: 0;
      background-image: url('data:image/svg+xml;utf8,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><path d="M4.4 8.4 L7 11 L11.6 5.4" fill="none" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>');
      background-repeat: no-repeat;
      background-position: center;
      background-size: 100% 100%;
    }
    .cm-md-query-link { cursor: pointer; }
    .cm-md-query-link:hover .cm-md-query-plain { text-decoration: underline; }
    .cm-md-query-token:hover { text-decoration: underline; cursor: pointer; }
    .cm-md-query-detail {
      float: inline-end;
      margin-inline-start: 1em;
      color: var(--secondary);
      font-size: 0.85em;
    }
    .cm-md-query-empty { margin: 0; padding-inline-start: 2.1em; color: var(--secondary); }
    .cm-md-query-group + .cm-md-query-group { margin-top: 1.2em; }
    .cm-md-query-group-header {
      display: flex;
      align-items: baseline;
      gap: 0.5em;
      margin-bottom: 0.4em;
      padding-bottom: 0.3em;
      border-bottom: 1px solid var(--grid);
      font-weight: 600;
    }
    .cm-md-query-group-count {
      color: var(--secondary);
      font-size: 0.85em;
      font-weight: 400;
      font-variant-numeric: tabular-nums;
    }
    .cm-md-query-none { color: var(--secondary); }
    /* As the document's tables (`.cm-md-table-grid`). */
    .cm-md-query-table-scroll { width: 100%; max-width: 100%; overflow-x: auto; }
    .cm-md-query-table { width: 100%; border-collapse: collapse; table-layout: auto; }
    .cm-md-query-table :is(th, td) {
      padding: 8px 12px;
      border-top: 1px solid var(--grid);
      border-bottom: 1px solid var(--grid);
      text-align: start;
      vertical-align: top;
      overflow-wrap: break-word;
      word-break: normal;
    }
    .cm-md-query-table th { font-weight: 600; }
    .cm-md-query-group .cm-md-query-table tr:first-child > th { border-top: 0; }
    .cm-md-query-table .cm-md-query-checkbox { margin: 0; vertical-align: middle; }
    .cm-md-query-table .cm-md-query-cell-done { width: 1px; }
    .cm-md-query-table :is(.cm-md-query-cell-due, .cm-md-query-cell-scheduled, .cm-md-query-cell-p) { white-space: nowrap; }
    .cm-md-query-table .cm-md-query-done .cm-md-query-text { color: var(--secondary); text-decoration: line-through; }
    """

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
      css: MarkdownHTML.completionMenuStylesheet(prefix: "metadata"),
      options: MarkdownHTML.metadataCompletionLabels()
    )

    func isActive(in _: RenderContext) -> Bool { false }
  }

  /// The note under the suggestions while the workspace's names are
  /// incomplete. A missing label falls back to the bundle's English one.
  static func metadataCompletionLabels() -> [String: String] {
    [
      "label.indexing": NSLocalizedString("Indexing workspace…", comment: "Metadata suggestions note"),
      "label.truncated": NSLocalizedString("Some files are not indexed: the workspace is over the file limit.",
                                           comment: "Metadata suggestions note")
    ]
  }
}
