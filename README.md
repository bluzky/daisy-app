<h1 align="center">Daisy</h1>

<p align="center">
  <img src="docs/daisy-logo.png" width="128" alt="Daisy logo" />
</p>

<p align="center">
  A fast, native macOS app for reading & editing Markdown files.
</p>

> **Note:** Daisy is an opinionated build of [Markdown Preview](https://github.com/pluk-inc/markdown-preview) by pluk-inc. It follows its own direction and has more features in some areas and fewer in others, so it is not a drop-in replacement. For the original app, use the [upstream repository](https://github.com/pluk-inc/markdown-preview).

<p align="center"><img alt="Platform" src="https://img.shields.io/badge/platform-macOS%2015%2B-blue" />&nbsp;<img alt="Swift" src="https://img.shields.io/badge/swift-6.0-orange" />&nbsp;<img alt="License" src="https://img.shields.io/badge/license-MIT-green" />&nbsp;<img alt="Latest release" src="https://img.shields.io/github/v/release/bluzky/daisy-app" /></p>

---

> Drop a `.md` on the icon (or set Daisy as your default handler) and get a clean, scrollable preview with a real document outline — no Electron, no browser tab.

## Installation

Grab the latest signed and notarized DMG from the [Releases](https://github.com/bluzky/daisy-app/releases) page.

## Screenshots

<p align="center">
  <em>Read long Markdown documents with a sidebar outline:</em>
</p>

<p align="center">
  <img src="docs/screenshot-main.png" width="820" alt="Read Mode showing a Markdown document and sidebar outline" />
</p>

<p align="center">
  <em>Edit Markdown in place, with source syntax visible as you type:</em>
</p>

<p align="center">
  <img src="docs/screenshot-edit-mode.png" width="820" alt="Edit Mode showing Markdown source and sidebar outline" />
</p>

## Features

- **Read Mode** — native `WKWebView` rendering with a document outline and file navigator. Task checkboxes save straight to the file.
- **Workspaces** — each window frame belongs to one folder, its workspace, and every file you open from that folder is a tab in it. Opening a folder gives it a new frame, or brings forward the one already open on it. Opening a file from Finder, **File → Open** or Open Recent adds it as a tab to the frame of the open workspace that contains it; a file outside every open workspace gets a new frame bound to its parent folder, with the sidebar hidden and the window narrowed for reading. Clicking a file in the Files sidebar opens it in a preview tab, shown in italics, which the next click replaces; double-click the file or edit it to keep its tab, and clicking a file that's already open selects its tab. Right-click for **Open in New Tab**, or **Open in New Window** for a separate frame on the same workspace. Windows on the same folder share folder expansion. A window with no file open shows hints for OmniSearch, New File, Open and the sidebar, with your current shortcuts. The Files sidebar lists every file in the folder: Markdown and source or text files open in Daisy, any other file opens in its default app, and files that can't be read are dimmed.
- **Bookmarks** — right-click a file or folder in the file navigator and choose **Bookmark** to pin it in a Bookmarks section at the top of the Files tab. Click a bookmarked file to open it, or a folder to open it as a workspace in its own window; remove one from its right-click menu.
- **Edit Mode** — Markdown files chosen from the Files sidebar or OmniSearch open straight into it; files opened from Finder, **File → Open**, Open Recent or the command line open in Read Mode. Edit in place with Format and Insert menus (image, link to file, code block, table), Markdown syntax that previews as you type, inline table editing, and safe rich-text paste conversion. Pasting web content preserves common Markdown formatting, including absolute http(s) images; HTML tables and spreadsheet TSV become GFM tables. Pasted images and files copied in Finder (any type) are copied into a `<document>-assets` folder beside the Markdown file and linked — images as images, other files as links (<kbd>⌘E</kbd> to toggle, <kbd>⌘S</kbd> to save). On a list item, <kbd>⌘↩</kbd> steps it from list item to checklist item to checked item and back.
- **Slash commands** — type `/` at the start of a line or after a space to turn it into a heading, list, quote, divider, code block, table, image, link to file, Mermaid diagram, math block, or callout. `/today` and `/now` insert the current date (`2026-10-19`) or date and time (`2026-10-19 14:05`) where you type them.
- **Tags, contexts and projects** — write `#tag`, `@context` (a person or a place, such as `@alex` or `@phone`) and `+project` in Markdown text, and on a checklist item `due:2026-10-23`, `scheduled:2026-10-20` and `p:high` (or `medium`, `low`). They stay plain text in the file, so any editor reads them; Daisy shows the task fields as badges in Read Mode and Edit Mode, while Quick Look and exports show the text as written. Set the task fields from the slash menu: `/due` and `/schedule` open a date picker, and **Priority: High**, **Medium**, **Low** and **None** set or clear `p:`. Typing `#`, `@` or `+` lists the names of that kind already used in the document and, in an indexed workspace, in every Markdown file of it; pick one with the arrow keys and <kbd>↩</kbd> or <kbd>⇥</kbd>, or keep typing a new name. Text in code, links and frontmatter is never metadata. Each part can be turned off in **Settings → Extensions** (Task metadata, Metadata suggestions, Metadata links).
- **Indexed workspaces** — in a folder window, **File → Initialize Workspace** writes `.daisy/config.json`, which holds only a version and is safe to commit; in the Files sidebar a workspace folder shows a book icon instead of a folder. Daisy then reads the folder's Markdown files to suggest names from all of them. It checks only the window's own folder, so opening a file, or a plain folder, never starts indexing; a file opened from Finder joins an open workspace window that contains it. Hidden folders, `node_modules`, `build` and similar folders, files over 1 MB or not UTF-8, and files more than 12 folders deep are skipped, and the scan stops at 20,000 files. Until the first scan finishes the suggestions say *Indexing workspace…*, and they say so when the file limit was reached. In a workspace each tag, context and project is a link — click it in Read Mode, <kbd>⌘</kbd>-click it in Edit Mode — to its page, `pages/#review.md` for `#review` (`#area/sub` uses `pages/#area--sub.md`), which is created holding just a heading the first time you open it. In Edit Mode <kbd>⌘</kbd>-click also follows ordinary Markdown links, in any window. The index is cached in Daisy's own container, never in the folder: **File → Rebuild Workspace Index** builds it again from the files, and **File → Remove Workspace** deletes the marker and the cache, leaving your pages and journal. Besides the marker, the pages and journal entries you open, the earlier entries that journal carry-over takes unfinished tasks from, and the files whose tasks you check off in the Agenda sidebar, Daisy writes nothing into the folder.
- **Journal** — in a workspace, each day has a Markdown file, `journals/2026-10-21.md`. Click **Journal** in the toolbar for a month calendar: a dot marks the days that already have an entry, and clicking a day, or choosing it with the arrow keys and <kbd>↩</kbd>, opens its entry, creating it the first time from the template chosen in **Settings → Extensions → New entry template** (any template from your [template file](#templates)), or, with none chosen, holding just `# 2026-10-21`. **Go → Today's Journal** (<kbd>⇧⌘J</kbd>) opens today's, and on an entry **Go → Previous Journal Entry** and **Next Journal Entry** (<kbd>⌥⌘←</kbd> and <kbd>⌥⌘→</kbd>) step to the nearest day that has one, skipping empty days and creating nothing. The Journal button joins the toolbar the first time you open a workspace window; outside a workspace it is dimmed. Turn on **Settings → Extensions → Carry over unfinished tasks** and creating today's entry moves every unchecked `- [ ]` task from the entries of the previous 7 days (**Days to look back**, 1 to 30) into it, with what is nested under it, and removes it from the day it was on; checked tasks, and the tasks nested under them, stay. Moved tasks keep their text and go where the template has `{{carryover}}`, or after the rest of the entry. Opening an entry that already exists, or creating one for another day, moves nothing. An entry open with unsaved edits keeps its tasks, and one that changed while the tasks were being moved keeps them too, so they then appear in both entries and Daisy says which days. Carry-over is off by default. To move tasks by hand, for example after today's entry already exists, open it in Edit Mode and choose **Insert → Unfinished Tasks from Earlier Days**: the tasks go in at the caret, on lines of their own, and leave their old entries once today's is saved; this works with carry-over off too, and has no default shortcut (bind one in **Settings → Shortcuts**, `insert.carriedOverTasks`). Turn the journal off in **Settings → Extensions** to hide the button and the Go menu items; entries you wrote stay in place. Shortcuts can be changed in **Settings → Shortcuts**.
- **Agenda sidebar** — in a workspace, click **Agenda** in the toolbar or choose **View → Agenda** (<kbd>⇧⌘I</kbd>, rebindable in **Settings → Shortcuts**) for a pane with a calendar of every checklist item that has a `scheduled:` or `due:` date, showing a month or, with **Week** in its header, one week at a time. A dot marks a day with scheduled or due tasks, red when a due date has passed and hollow once they are all checked off. Below it, today lists **Overdue** (open tasks due before today), **Today**, and **Upcoming** for the next 7 days (collapsed until you open it); click another day for its due and scheduled tasks, each marked as under Today, and click today or press <kbd>⌘T</kbd> to return. Within a group, high priority comes first. Click a task to open its file at that line, or right-click for **Open in New Tab**, **Reveal in Files** and **Copy Task Text**. Click its checkbox, or press <kbd>Space</kbd>, to check it off: it stays struck through for a moment, and **Undo** in the banner, or <kbd>⌘Z</kbd> while the banner shows, unchecks it. A file open in Edit Mode, or with unsaved edits, gets the change in its editor and saves it with everything else; any other file is written at once, keeping its permissions and Finder tags, and only if it hasn't changed since Daisy read it, so a task whose file changed says so and leaves the file alone. The filter menu shows or hides scheduled and due tasks, completed tasks (hidden by default; never Overdue or Upcoming) and Overdue. Outside a workspace the button and menu item are dimmed, unless the pane is already open, when they close it. The sidebar replaces the old inspector pane; a shortcut you bound to `view.toggleInspector` now toggles the Agenda.
- **Code and text files** — source and text files (`.txt`, `.json`, `.swift`, `.py`, `Makefile` and more) open straight into a code editor: syntax highlighting, line numbers, find and replace, and no preview or Markdown formatting. Add your own extensions or file names in **Settings → General → Code and text files**. Files over 5 MB, or not valid UTF-8, open in their default app instead.
- **Link to File** — in Edit Mode, choose **Insert → Link to File…** or type `/link` to search the project's files by name or folder path and insert a Markdown link to the one you pick, written relative to the current document (`[Setup](../guides/setup.md)`). Selected text becomes the link text; otherwise the file name is used. Any file type can be linked. The command needs a saved document inside an open folder and has no default shortcut; bind one in **Settings → Shortcuts** (`insert.linkToFile`).
- **Templates** — insert your own Markdown snippets from the slash menu. Choose a template file in **Settings → General → Templates**; see [Templates](#templates) below.
- **Extensions** — code highlighting, callouts, KaTeX math, Mermaid diagrams, colorful headings, and the workspace journal, each switchable in **Settings → Extensions**. Mermaid, colorful headings and slash commands also apply in Edit Mode for Markdown files; the code editor for source and text files uses none of them.
- **Quick Look** — system-wide `.md` previews from Finder, Spotlight, and Mail.
- **Search** — in-document search (<kbd>⌘F</kbd>) and OmniSearch (<kbd>⌘K</kbd>), one box for recent files, files by name or by their folder path (any file type; non-Markdown files open in their default app; words typed apart, such as `vifon meeting`, can match different folders, and these path matches come after name matches), text inside Markdown and text files and menu commands. Type `>` first to list commands only. Type a name that matches no file and the top result offers to create it (`notes/roadmap` makes `notes/roadmap.md`; type a Markdown, source or text extension, such as `notes/todo.txt` or `src/main.swift`, to get that file instead) and opens it for editing.
- **Quick Capture** — turn on the shortcut in Settings, then press it from any app (<kbd>⌃⌥Space</kbd> by default, changeable there) to open `Inbox.md` from your capture folder in the editor. Each time adds a new `## yyyy-MM-dd HH:mm` heading at the end and puts the cursor under it.
- **Custom shortcuts** — rebind Daisy commands in **Settings → Shortcuts**. Daisy reads and writes `~/.config/daisy/keymap.json`; bindings apply only in their Global, Reading, Editing, or Search context. Project Navigator file commands (New File <kbd>⌥⌘N</kbd>, New Folder <kbd>⇧⌘N</kbd>, Rename, Move to Trash) are in the File menu and act on the selected sidebar item; Rename and Move to Trash have no default shortcut.
- **Reading settings** — text size and zoom, content width, text alignment, strict line breaks, and themes with font, spacing, and color customization.
- **Export** — **File → Export** has one item per format — **PDF…**, **HTML…**, **PNG…** and **Word…** (`.docx`) — each with its own save dialog. Word exports use real Word headings, lists, tables and code blocks, include Mermaid diagrams as pictures when the Mermaid extension is enabled (otherwise they remain code), and have a **Theme** picker: GitHub (default), Serif, Minimal and Document. Add your own by dropping a `docx-theme-<id>.json` file into `~/.config/daisy/docx-themes/`; see [Building a DOCX export theme](docs/docx-theme-authoring.md).



- **Command line and URL scheme** — `daisy .` opens from a shell; `daisy export report.md --format docx --output report.docx` writes a Word document. [CLI docs](docs/command-line.md) cover export. Browser links use `daisy://file/<absolute path>`.


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

Any template can also be what a new [journal](#features) entry starts with: pick it in **Settings → Extensions → New entry template**. There `{{date}}` and `{{weekday}}` are the entry's day, which may not be today, `{{time}}` is when the entry is created, `{{carryover}}` is where tasks moved by [carry-over](#features) go (it means nothing when the template is inserted from the slash menu), and `{{cursor}}` is left out. Changing the template never changes entries that already exist. If the chosen template is renamed or removed from the file, new entries hold just their date until you pick another.

## Supported file types

Rendered as Markdown: `.md`, `.markdown`, `.mdown`, `.mkd`, `.mdwn`, `.mdx`, `.mkdn`
UTI: `net.daringfireball.markdown`

Edited as code, with no preview: `.txt` and common source, config and text files (see **Settings → General → Code and text files** for the list and to add more).

Anything else opens in its default app.

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

Releases are published to GitHub: `scripts/release.sh` builds, signs and notarizes a DMG, attaches it to a GitHub release, and publishes the Sparkle appcast on the `gh-pages` branch (served by GitHub Pages).

To prepare a release PR, start from latest `main`, update both `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `Version.xcconfig`, and add the matching `CHANGELOG.md` entry with contributor credits. Submit these together in a ready PR; see the [release-process skill](.agents/skills/release-process/SKILL.md) for naming and validation.

When ready to publish the prepared release, run the following from a clean working tree. This builds, notarizes, tags, and publishes the release to GitHub:

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
- [swift-markdown](https://github.com/swiftlang/swift-markdown) — Markdown parser (Apple, cmark-gfm-backed)
- [Mermaid](https://mermaid.js.org/) — Bundled diagram renderer for `mermaid` fenced code blocks
- [KaTeX](https://katex.org/) — Bundled math typesetter for inline `$…$`, display `$$…$$`, and ` ```math ` blocks
- [Sparkle](https://sparkle-project.org) — Auto-update framework

## License

[MIT](LICENSE)
