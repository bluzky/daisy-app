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

Highlight, Callout, KaTeX, and Mermaid participate in the same registry but
are always enabled and do not appear in Settings. Heading color is a theme
setting (`--heading`), not an extension.

Slides (`SlidesExtension`) is registered too, but is not toggleable: a deck
is something the document asks for, not a reading preference. Splitting a
document into slides happens earlier, in the formatter: when frontmatter has
`slides: true` (or `marp: true`), or the host passes `forcesSlides`,
`EscapingHTMLFormatter` walks `SlideDeck` instead of the document's blocks and
emits `.mdp-deck` with one `section.mdp-slide-frame` per slide. Slide directives
(`layout`, `_class`, `color`, `step`) are HTML comments, which the sanitizer
removes, so `SlideDeck` reads them in Swift and the formatter writes them as
classes and `data-*` attributes. The extension activates on that markup and
adds the slide stylesheet and the `MdPreviewSlides` script in every host: the
script applies image sizes and slide colors (styles the sanitizer would
strip) and, while presenting, marks the current and next slide and the
revealed steps. The presentation windows turn presenting on with the
`slides-presenting` and `slides-presenter` host states, and the Slide Preview
pane uses `slides-pane`. A deck's theme is emitted by `render` itself, in the
page head, not by the extension.

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

An extension may also be editor-only (`SlashCommandsExtension`, `MetadataCompletionExtension`): it returns
`false` from `isActive` and `affectsPreview`, so it never touches rendered
output and Settings captions it "Editor". The capability can also carry
`css` (static, emitted into the editor page, so scope it to a class the module
adds) and `options` (plain string pairs, such as localized labels, passed to
the module's `extensions(options, host)` at creation; `host.callbacks` holds the
callbacks the page gave the editor).

### Host state

The Settings toggle is app-wide. An extension that also needs a value per
window, such as whether the window hides completed tasks, reads it as host
state: `MainSplitViewController.setExtensionHostState(_:for:)` keeps a
`[extension id: Bool]` map for the window and sends it to both surfaces,
including an editor created later.

- **Read mode:** `MarkdownWebView.extensionHostState` writes each entry as a
  `data-mdp-<id>` attribute on `<html>`, present while the value is true, on
  every page load and on each change, then calls `MdPreview.reapplyExtensions`.
  A stylesheet keyed on the attribute needs no script.
- **Editor:** `EditorViewController.setExtensionHostState` sends the map with
  `__mdEditor.setHostState`. A module reads its own value with
  `hostFlag(host, id)` from `scripts/editor-bundle/src/extensions.js`, a state
  field that starts false and follows the host.

Quick Look and export never set host state. `hide-completed-tasks` is the
first extension built on it (`HideCompletedTasksExtension`,
`scripts/editor-bundle/src/hide-completed-tasks.js`); its value comes from the
app-wide View ▸ Hide Completed Tasks setting, which every window passes in.

A slash command normally carries a template (`convert`). One with `host` names a
host action instead (`SLASH_HOST_ACTIONS`, e.g. `pickImage`), posts a message to
the app, and is hidden when the page has no matching callback. One with
`insert(now)` (`/today`, `/now`) replaces only the typed `/query` with its
text and leaves the rest of the line alone; it reads the same clock as template
variables (`slashClock`).

Templates are not part of `options`, which are fixed when the editor is created.
`TemplateStore` reads the file the user chose (a security-scoped bookmark),
`TemplateFileParser` splits it at `<!-- template: Name -->` marker lines (or, when the file has none, at H2 headings), and the app pushes the result with
`window.__mdEditor.setSlashTemplates([{ name, body }])` when the page is ready and
whenever `TemplateStore.didChangeNotification` fires. The slash menu lists them
behind a **Templates** row, a second menu level. Variables (`{{date}}`, `{{time}}`, `{{datetime}}`, `{{weekday}}`, `{{cursor}}`) are expanded in the editor bundle when a template is picked (`slashExpandTemplate`), using the `locale` option for day names; `slashClock` in the page callbacks overrides the clock in tests. Opening it clears the typed query, and the level searches template names only; the top level never lists templates.

Both editor menus are built on the completion controller in
`scripts/editor-bundle/src/completion.js`, which takes a provider (trigger,
rows, apply) and draws the menu with classes named after the provider's
`classPrefix`. `MarkdownHTML.completionMenuStylesheet(prefix:)` supplies the
shared menu CSS for a prefix (`slash`, `metadata`). The metadata module
(`metadata-completion.js`) suggests `#` tags, `@` contexts and `+` projects from
the document and from the names the host passes with
`window.__mdEditor.setWorkspaceCandidates({ version, tags, contexts, projects })`;
a snapshot older than the one held is ignored.

## Assets and fast path

Every page shell emits CSS for every enabled extension. JavaScript emits only
for active extensions. An extension whose page script is an in-app presentation
returns it only for `.lazy` (the app's Read mode), so Quick Look and HTML export,
which render `.inline`, never run it (`TaskMetadataExtension`). `RenderedHTML.scriptAssetIDs` records required runtime
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
   there, and add a case to the matching section in `scripts/editor-bundle/smoke/`
   (`smoke-test.mjs` runs the sections in order).
7. For a value per window, pass it as host state (see [Host state](#host-state))
   rather than adding a separate setter through each layer.

Run:

```bash
(cd scripts/editor-bundle && npm run build && node smoke-test.mjs)
swift test --package-path tests/swift-tests
xcodebuild -project daisy.xcodeproj -scheme daisy -configuration Debug build
```
