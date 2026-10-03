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
  <em>Edit Markdown directly with a native formatting toolbar:</em>
</p>

<p align="center">
  <img src="docs/screenshot-edit-mode.png" width="820" alt="Edit Mode with document outline and Markdown formatting toolbar" />
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
- **Edit Mode** — edit in place with a formatting toolbar, Markdown syntax that previews as you type, and inline table editing (<kbd>⌘E</kbd> to toggle, <kbd>⌘S</kbd> to save).
- **Slash commands** — type `/` at the start of a line or after a space to turn it into a heading, list, quote, divider, code block, table, image, Mermaid diagram, math block, or callout.
- **Extensions** — code highlighting, callouts, KaTeX math, Mermaid diagrams, and colorful and collapsible headings, each switchable in **Settings → Extensions**. Mermaid, colorful headings and slash commands also apply in Edit Mode.
- **Quick Look** — system-wide `.md` previews from Finder, Spotlight, and Mail.
- **Search** — in-document search (<kbd>⌘F</kbd>) and Search for Document (<kbd>⇧⌘O</kbd>) to find a file by name.
- **Reading settings** — text size and zoom, content width, text alignment, strict line breaks, and themes with font, spacing, and color customization.



- **Command line and URL scheme** — `mdp .` from a shell, or `daisy://file/<absolute path>` from a browser link. `md-preview://` links still work.


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

Build and run the `daisy` scheme. Swift Package Manager will resolve [Sparkle](https://github.com/sparkle-project/Sparkle), [Sentry](https://github.com/getsentry/sentry-cocoa), and [swift-markdown](https://github.com/swiftlang/swift-markdown) on first build.

### Crash reporting

Release builds submit native crash reports to the `pluk-inc/markdown-preview` Sentry project. The integration does not collect performance traces, session data, breadcrumbs, network requests, user information, document contents, or file paths. Users can turn reporting off in Daisy > Settings > Privacy; on later launches, the Sentry SDK will not initialize at all.

The committed DSN is a public client key. Release archives upload the app dSYM with `sentry-cli`; authenticate locally with `sentry-cli login` and keep that authentication token outside the repository.

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
2. Run the app and verify the change end-to-end (UI changes need a manual smoke test — there's no UI test suite yet).
3. Keep PRs focused; one logical change per PR.
4. Match the existing Swift style (no formatter is enforced; mirror nearby code).

## Acknowledgments
- [Amore](http://amore.computer/) — MacOS release automation (signing, notarization, DMG, hosting, appcast)
- [swift-markdown](https://github.com/swiftlang/swift-markdown) — Markdown parser (Apple, cmark-gfm-backed)
- [Mermaid](https://mermaid.js.org/) — Bundled diagram renderer for `mermaid` fenced code blocks
- [KaTeX](https://katex.org/) — Bundled math typesetter for inline `$…$`, display `$$…$$`, and ` ```math ` blocks
- [Sparkle](https://sparkle-project.org) — Auto-update framework
- [Sentry](https://sentry.io) — Privacy-filtered native crash reporting

## License

[MIT](LICENSE)
