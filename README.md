<h1 align="center">Daisy</h1>

<p align="center">
  <img src="docs/daisy-logo.png" width="128" alt="Daisy logo" />
</p>

<p align="center">
  A fast, native macOS app for reading & editing Markdown files.
</p>

> **Note:** Daisy is an opinionated build of [Markdown Preview](https://github.com/pluk-inc/markdown-preview) by pluk-inc. It follows its own direction and has more features in some areas and fewer in others, so it is not a drop-in replacement. For the original app, use the [upstream repository](https://github.com/pluk-inc/markdown-preview).

<p align="center"><img alt="Platform" src="https://img.shields.io/badge/platform-macOS%2015%2B-blue" />&nbsp;<img alt="Swift" src="https://img.shields.io/badge/swift-6.0-orange" />&nbsp;<img alt="License" src="https://img.shields.io/badge/license-MIT-green" />&nbsp;<img alt="Latest release" src="https://img.shields.io/github/v/release/bluzky/daisy-app" />&nbsp;<img alt="Homebrew cask" src="https://img.shields.io/homebrew/cask/v/markdown-preview" /></p>

---

> Drop a `.md` on the icon (or set Daisy as your default handler) and get a clean, scrollable preview with a real document outline — no Electron, no browser tab.

## Installation

Daisy is available through the [Homebrew cask repository](https://formulae.brew.sh/cask/markdown-preview) (the cask is still published as `markdown-preview` while it is renamed):

```sh
brew install --cask markdown-preview
```

Or grab the latest signed and notarized DMG from the [Releases](https://github.com/bluzky/daisy-app/releases) page.

## Screenshots

<p align="center">
  <img src="docs/screenshot-main.png" width="820" alt="Main window with document outline sidebar" />
</p>

<p align="center">
  <em>Edit Markdown directly with the Format and Insert menus:</em>
</p>

<p align="center">
  <img src="docs/screenshot-edit-mode.png" width="820" alt="Edit Mode with document outline" />
</p>

<p align="center">
  <em>Quick Look preview — spacebar a <code>.md</code> in Finder:</em>
</p>

<p align="center">
  <img src="docs/screenshot-quicklook.png" width="640" alt="Quick Look preview from Finder" />
</p>

<p align="center">
  <em>Customize the toolbar — drag in Print, Copy, Zoom and the rest from <em>View → Customize Toolbar…</em></em>
</p>

<p align="center">
  <img src="docs/screenshot-toolbar-customize.png" width="820" alt="Native macOS toolbar customization sheet showing draggable items" />
</p>

## Features

- **Read Mode** — native `WKWebView` rendering with a document outline, file navigator and inspector panel. Task checkboxes save straight to the file.
- **Bookmarks** — right-click a file or folder in the file navigator and choose **Bookmark** to pin it in a Bookmarks section at the top of the Files tab. Click a bookmarked file to open it, or a folder to make it the project root; remove one from its right-click menu.
- **Edit Mode** — edit in place with Format and Insert menus (image, code block, table), Markdown syntax that previews as you type, inline table editing, and safe rich-text paste conversion. Pasting web content preserves common Markdown formatting, including absolute http(s) images; HTML tables and spreadsheet TSV become GFM tables. Image pastes still use Daisy's native asset flow (<kbd>⌘E</kbd> to toggle, <kbd>⌘S</kbd> to save).
- **Slash commands** — type `/` at the start of a line or after a space to turn it into a heading, list, quote, divider, code block, table, image, Mermaid diagram, math block, or callout.
- **Templates** — insert your own Markdown snippets from the slash menu. Choose a template file in **Settings → General → Templates**; see [Templates](#templates) below.
- **Extensions** — code highlighting, callouts, KaTeX math, Mermaid diagrams, and colorful headings, each switchable in **Settings → Extensions**. Mermaid, colorful headings and slash commands also apply in Edit Mode.
- **Quick Look** — system-wide `.md` previews from Finder, Spotlight, and Mail.
- **Search** — in-document search (<kbd>⌘F</kbd>) and OmniSearch (<kbd>⌘K</kbd>), one box for recent files, files by name, text inside files and menu commands. Type `>` first to list commands only. Type a name that matches no file and the top result offers to create it (`notes/roadmap` makes `notes/roadmap.md`) and opens it for editing.
- **Quick Capture** — turn on the shortcut in Settings, then press it from any app (<kbd>⌃⌥Space</kbd> by default, changeable there) to open `Inbox.md` from your capture folder in the editor. Each time adds a new `## yyyy-MM-dd HH:mm` heading at the end and puts the cursor under it.
- **Custom shortcuts** — rebind Daisy commands in **Settings → Shortcuts**. Daisy reads and writes `~/.config/daisy/keymap.json`; bindings apply only in their Global, Reading, Editing, or Search context. Project Navigator file commands (New File <kbd>⌥⌘N</kbd>, New Folder <kbd>⇧⌘N</kbd>, Rename, Move to Trash) are in the File menu and act on the selected sidebar item; Rename and Move to Trash have no default shortcut.
- **Reading settings** — text size and zoom, content width, text alignment, strict line breaks, and themes with font, spacing, and color customization.
- **Export** — **File → Export** has one item per format — **PDF…**, **HTML…**, **PNG…** and **Word…** (`.docx`) — each with its own save dialog. Word exports use real Word headings, lists, tables and code blocks, include Mermaid diagrams as pictures when the Mermaid extension is enabled (otherwise they remain code), and have a **Theme** picker: GitHub (default), Serif, Minimal and Document. Add your own by dropping a `docx-theme-<id>.json` file into `~/.config/daisy/docx-themes/`; see [Building a DOCX export theme](docs/docx-theme-authoring.md).



- **Command line and URL scheme** — `mdp .` from a shell, or `daisy://file/<absolute path>` from a browser link. `md-preview://` links still work.


### Templates

Keep your reusable notes in one Markdown file and pick it in **Settings → General → Templates**. In Edit Mode, type `/`, open **Templates** (or type `/templates` and press <kbd>Enter</kbd>), then type part of a name to search only your templates. <kbd>Enter</kbd> inserts the chosen one. Edits to the file show up in the menu without restarting.

Each template starts at a marker line and runs to the next one, so its body can hold any heading, `##` included:

```markdown
<!-- template: Meeting notes -->

# Meeting — {{date}}

## Attendees

- {{cursor}}

<!-- template: Daily standup -->

- **Yesterday:**
- **Today:**
```

Everything before the first marker is ignored. A file with no marker falls back to one template per `##` heading, named after it. See [`samples/templates.md`](samples/templates.md) for a full example.

Variables are filled in when you insert a template:

| Variable | Inserts |
| --- | --- |
| `{{date}}` | Today's date, `2026-10-04` |
| `{{time}}` | The time, `14:05` |
| `{{datetime}}` | Both, `2026-10-04 14:05` |
| `{{weekday}}` | The day's name, in the app's language |
| `{{cursor}}` | Nothing; the caret lands here (the first one counts) |

Write `\{{` for a literal `{{`. An unknown name is left as typed.

## Supported file types

`.md`, `.markdown`, `.mdown`, `.mdx`, `.txt`
UTI: `net.daringfireball.markdown`

## Requirements

- macOS 15 or later
- Apple Silicon or Intel

## Building from source

```sh
git clone git@github.com:bluzky/daisy-app.git
cd daisy-app
open daisy.xcodeproj
```

Build and run the `daisy` scheme. Swift Package Manager will resolve [Sparkle](https://github.com/sparkle-project/Sparkle) and [swift-markdown](https://github.com/swiftlang/swift-markdown) on first build.

### Anonymous usage analytics

Release builds can submit at most one anonymous `app became active` event per installation per UTC day when Daisy becomes active. The event contains a random installation identifier, app version, macOS major version, processor architecture, locale country or region, and the flag that prevents PostHog from creating a person profile. It is used to count daily and monthly active installations and understand basic platform compatibility. It does not contain document contents, file names or paths, actions, screens, precise location, personal information, or advertising identifiers. Users can disable it from Settings > Privacy.

The PostHog project token is injected from the gitignored `Secrets.xcconfig`. Copy `Secrets.xcconfig.example` to `Secrets.xcconfig` and set `POSTHOG_PROJECT_TOKEN` before making a release build. If the token is absent, or for a Debug build, analytics remains disabled. Every event disables GeoIP enrichment, and the PostHog project must also be configured to discard IP data in Project Settings > General.

## Project layout

```
daisy/         Main app target (AppKit, WKWebView)
quick-look/         Quick Look extension (.appex)
scripts/            Release & rollback automation
Version.xcconfig    Marketing & build version (single source of truth)
appcast.xml         Sparkle update feed
```

[Render extension guide](docs/render-extensions.md) — compiled-in Markdown transforms, active-only assets, and extension authoring.

## Releasing

Releases are driven by [Amore](http://amore.computer/) — it handles building, code signing, notarization, DMG creation, S3 upload, and Sparkle appcast publishing in one shot.

To prepare a release PR, start from latest `main`, update both `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `Version.xcconfig`, and add the matching `CHANGELOG.md` entry with contributor credits. Submit these together in a ready PR; see the [release-process skill](.agents/skills/release-process/SKILL.md) for naming and validation.

When ready to publish the prepared release, run the following from a clean working tree. This builds, notarizes, uploads, tags, and publishes the release:

```sh
./scripts/release.sh
```

Use `./scripts/rollback-release.sh` to revert the appcast pointer if a release misbehaves.

### Contributing


Pull requests are welcome. For larger changes, please open an issue first to discuss what you'd like to change.

1. Fork the repo and create your branch from `main`.
2. The editor's JavaScript bundle (`daisy/Vendor/CodeMirror/mdedit.min.js`) is built, not checked in. Install Node.js; an Xcode build runs `npm ci && npm run build` in `scripts/editor-bundle` when the bundle is missing or stale. `swift test` reads the same file, so build once in Xcode or run those two commands first. Editor behaviour is covered by `npm test` in that folder.
3. Run the app and verify the change end-to-end (UI changes need a manual smoke test — there's no UI test suite yet).
4. Keep PRs focused; one logical change per PR.
5. Match the existing Swift style (no formatter is enforced; mirror nearby code).

## Acknowledgments
- [Amore](http://amore.computer/) — MacOS release automation (signing, notarization, DMG, hosting, appcast)
- [swift-markdown](https://github.com/swiftlang/swift-markdown) — Markdown parser (Apple, cmark-gfm-backed)
- [Mermaid](https://mermaid.js.org/) — Bundled diagram renderer for `mermaid` fenced code blocks
- [KaTeX](https://katex.org/) — Bundled math typesetter for inline `$…$`, display `$$…$$`, and ` ```math ` blocks
- [Sparkle](https://sparkle-project.org) — Auto-update framework

## License

[MIT](LICENSE)
