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

Colorful and Collapsible headings are user-toggleable. Highlight, Callout,
KaTeX, and Mermaid participate in the same registry but are always enabled
and do not appear in Settings.

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

1. Add extension source under `md-preview/Rendering/`.
2. Add it to registry with unique `id` and `order`.
3. Add target membership and test-package symlink when needed.
4. Add locale keys for descriptor title/description.
5. Test activation, assets, lifecycle behavior, and Quick Look mode.

Run:

```bash
swift test --package-path tests/swift-tests
xcodebuild -project md-preview.xcodeproj -scheme md-preview -configuration Debug build
```
