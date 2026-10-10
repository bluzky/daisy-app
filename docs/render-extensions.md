# Render extensions

Render extensions are compiled-in Markdown enhancements. They are trusted app
code, not installable plugins. App and Quick Look share one registry; vendor
loading differs by host.

## Registry

`MarkdownHTML.renderExtensions` is an explicitly ordered registry. Every
extension provides:

- `id` — stable identifier.
- `descriptor` — localized title key, optional description key,
  `defaultEnabled`, and `userToggleable`.
- `order` — unique ascending pipeline position.
- `isActive(in:)` — pure, evaluated once against article HTML after footnotes
  and prior active transforms.
- `transform(_:)` — optional HTML rewrite; identity by default.
- `assets(mode:)` — static CSS and JavaScript declaration.

Colorful headings are user-toggleable. Highlight, Callout,
KaTeX, and Mermaid participate in the same registry but are always enabled
and do not appear in Settings.

## Editor capability

An extension may also contribute to the CodeMirror editor. It declares this
with `editor: (any EditorCapability)?` (nil by default, so render-only
extensions are unchanged). The capability only names a `moduleID`; the
behaviour is a module compiled into the editor bundle and registered under
that id:

```js
registerEditorExtension({ id, extensions: () => [...], precedence? })
```

Descriptor, order and the Settings toggle are shared, so a both-sided extension
(Mermaid today) switches on and off as one unit. `MarkdownHTML.editorExtensionState`
maps the current configuration to `{ moduleID: enabled }`. The editor page
embeds it at creation, and `EditorViewController.applyExtensionState` pushes it
to an open editor through `__mdEditor.setExtensionState`. Each module lives in
its own `Compartment`, so toggling reconfigures it live without recreating the
editor or losing selection and undo history. A module the host does not
mention stays enabled. Quick Look never loads the editor, so it only sees the
render side.

An extension may also be editor-only (`SlashCommandsExtension`): it returns
`false` from `isActive` and `affectsPreview`, so it never touches rendered
output and Settings captions it "Editor". The capability can also carry
`css` (static, emitted into the editor page, so scope it to a class the module
adds) and `options` (plain string pairs, such as localized labels, passed to
the module's `extensions(options, host)` at creation; `host.callbacks` holds the
callbacks the page gave the editor).

A slash command normally carries a template (`convert`). One with `host` names a
host action instead (`SLASH_HOST_ACTIONS`, e.g. `pickImage`), posts a message to
the app, and is hidden when the page has no matching callback.

Templates are not part of `options`, which are fixed when the editor is created.
`TemplateStore` reads the file the user chose (a security-scoped bookmark),
`TemplateFileParser` splits it at `<!-- template: Name -->` marker lines (or, when the file has none, at H2 headings), and the app pushes the result with
`window.__mdEditor.setSlashTemplates([{ name, body }])` when the page is ready and
whenever `TemplateStore.didChangeNotification` fires. The slash menu lists them
behind a **Templates** row, a second menu level. Variables (`{{date}}`, `{{time}}`, `{{datetime}}`, `{{weekday}}`, `{{cursor}}`) are expanded in the editor bundle when a template is picked (`slashExpandTemplate`), using the `locale` option for day names; `slashClock` in the page callbacks overrides the clock in tests. Opening it clears the typed query, and the level searches template names only; the top level never lists templates.

## Assets and fast path

Every page shell emits CSS for every enabled extension. JavaScript emits only
for active extensions. `RenderedHTML.scriptAssetIDs` records required runtime
capabilities; a body swap runs only when next set is subset of loaded set.

## Page lifecycle

Page scripts register through `window.MdPreview.registerExtension`:

```js
MdPreview.registerExtension({
  id,
  setup?(host),
  render(root, { host, reason, snapshot }),
  beforeUpdate?(root, host),
  reveal?(element, host),
  onThemeChange?(theme, host),
  dispose?(host)
})
```

`beforeUpdate` synchronously returns plain state. Core scopes it to extension
and document ID, consumes it once on next render, and isolates hook failures.
`reveal` expands hidden content before native navigation or find measures its
target. Extension-owned injected DOM uses `data-mdp-ext`; hidden renderer
mirrors excluded from find use `data-mdp-search-exclude`.

## Add extension

1. Add extension source under `daisy/Rendering/`.
2. Add it to registry with unique `id` and `order`.
3. Add target membership and test-package symlink when needed.
4. Add locale keys for descriptor title/description.
5. Test activation, assets, lifecycle behavior, and Quick Look mode.
6. For editor behaviour, set `editor` to `EditorModule(moduleID:)`, register the
   module with `registerEditorExtension` (see `scripts/editor-bundle/src/`), rebuild with `npm run build`
   there, and add a case to `smoke-test.mjs`.

Run:

```bash
(cd scripts/editor-bundle && npm run build && node smoke-test.mjs)
swift test --package-path tests/swift-tests
xcodebuild -project daisy.xcodeproj -scheme daisy -configuration Debug build
```
