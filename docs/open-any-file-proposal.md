# Proposal: open any file from the file explorer

Status: Phase 1 and Phase 2 implemented on `feat/text-file-open`. The File > Open panel and Info.plist changes landed in Phase 2 as planned. `LaunchItemStore`'s "launch with" panel was left Markdown-only.

## Decisions

- `.txt` becomes `text` (code-only editor), not Markdown. The switch happens in
  Phase 2; Phase 1 leaves `.txt` as it is today so nothing regresses.
- The text whitelist is user-configurable (Phase 2), with a built-in default.
- Size cap for the code editor is 5 MB; larger files open externally.
- Unreadable files and broken symlinks are shown dimmed and are not openable.

## Goal

Every file in a workspace is visible and openable from the Files sidebar and
the omnisearch palette. How it opens depends on what it is:

| Kind       | Files                                   | Opens as                                   |
| ---------- | --------------------------------------- | ------------------------------------------ |
| `markdown` | `md markdown mdown mkd mdwn mdx mkdn`   | Edit mode by default; preview still works  |
| `text`     | whitelisted code and text files         | Code-only editor, no preview               |
| `external` | everything else (images, PDF, binaries) | System default app via `NSWorkspace.open`  |

Editing is whitelist-only. An unknown file is never loaded into the editor,
because saving a binary file as text would corrupt it.

## Why now

"Markdown only" is hardcoded in several places, and the lists disagree:

| Place                                                  | Accepts                                        |
| ------------------------------------------------------ | ---------------------------------------------- |
| `ProjectFileIndex.markdownExtensions`                  | `md markdown mdown mkd mdwn mdx`               |
| `FileNode.children()` (sidebar tree)                   | reuses the index list                          |
| `MarkdownDocumentController`, `LaunchItemStore`        | `md markdown mdown mdx txt`                    |
| `DocumentWindowController+OpenTargets`                 | `md markdown mdown mdx txt`                    |
| `FileSearchPanelController` (recents)                  | index list plus `txt`                          |
| `MarkdownWebView.isMarkdownDocument`                   | `md markdown mdown mkdn mkd mdx`               |
| `DocumentWindowController+DocumentOpening` (~line 169) | open-panel types built from extensions         |

The comment on `markdownExtensions` already says reconciling these lists
"belongs in its own PR". This is that PR. The fix is one classifier that every
call site asks.

## Design

### `FileKind`

One new file, for example `daisy/Helpers/FileKind.swift`:

```swift
enum FileKind { case markdown, text, external }

extension FileKind {
    nonisolated static func classify(_ url: URL) -> FileKind
}
```

Rules, in order:

1. Extension in the Markdown set gives `markdown`.
2. Extension in the text whitelist (built-in defaults plus the user's
   additions, see Phase 2), or file name in the known-names list (`Makefile`,
   `Dockerfile`, `.gitignore`, `.env`, and similar), gives `text`. `.txt` is in
   the default whitelist.
3. `UTType(filenameExtension:)` conforming to `.sourceCode` or `.plainText`
   gives `text`.
4. Anything else gives `external`.

The function must be `nonisolated` and cheap. The index walk calls it for
every file, off the main actor.

### Routing

One entry point, `openFile(_:)`, switches on `FileKind`. The sidebar, the
omnisearch, recents and the open panel all call it. No call site checks an
extension itself afterwards.

---

## Phase 1: classifier, all files visible, external files open

Phase 1 ships alone. After it, every file shows up and opens. `text` files
are routed to the system app until Phase 2 exists, so nothing is half-built.

### Scope

1. **Add `FileKind`** with `markdown` and `external` fully working. `text`
   exists in the enum and the whitelist, but is treated as `external`
   (behind one switch case) until Phase 2. Exception: `.txt` keeps its
   current Markdown behaviour in Phase 1 (one explicit special case, removed
   in Phase 2).
2. **Sidebar tree.** Drop the extension filter in `FileNode.children()`
   (`ProjectNavigatorView.swift`, ~line 38). Keep `skipsHiddenFiles`. Folders
   still sort first, then `localizedStandardCompare`.
3. **Row icons.** Markdown keeps its current icon. Other files use
   `NSWorkspace.shared.icon(forFile:)`, cached per extension, not per file,
   to keep scrolling cheap.
4. **Click routing.** In the tree-selection handler in
   `DocumentWindowController.swift` (~line 198):
   - `external` calls `NSWorkspace.shared.open(url)` and returns. It must not
     create a tab or touch the current document or its unsaved edits.
   - `markdown` follows the existing path.
5. **Omnisearch.** In `ProjectFileIndex`:
   - Replace the `markdownExtensions` guard in the walk (~line 126) so all
     files are indexed.
   - Add `kind` to `FileSearchMatcher.Candidate`.
   - The result row shows a small kind icon so an external file does not look
     like a document.
   - Open results through the same router.
6. **Index cap.** `maximumFileCount` is 20,000 and the walk stops at it.
   Indexing every file reaches the cap sooner. Handle it in one of these
   ways, in order of preference:
   - Keep the cap, but make the matcher rank `markdown` above `text` above
     `external`, so a truncated index still holds the useful files.
   - Raise the cap if the benchmark below allows.

   Pruned directories (`prunedDirectoryNames`, depth limit) stay as they are.
   Also measure walk time before and after on a large repository, and record
   the numbers in the PR.
7. **Recents.** Point `FileSearchPanelController` (~line 285) at the
   classifier. The File > Open panel stays Markdown-only in this phase:
   `NSDocumentController` has no document type for other files until Phase 2
   adds them to `Info.plist`, so widening it now would end in an error.
8. **Unify the lists.** Replace the Markdown extension lists in
   `MarkdownDocumentController`, `LaunchItemStore`, `OpenTargets` and
   `MarkdownWebView.isMarkdownDocument` with `FileKind`. `mkdn` joins the
   Markdown set.
9. **Docs in the same PR** (AGENTS.md rule):
   - `README.md`: Files sidebar, omnisearch and Edit Mode lines.
   - The comment above `ProjectFileIndex.markdownExtensions`.
   - `grep -rn "markdown" README.md samples/ tests/fixtures/ docs/` for other
     stale claims.

### Dimmed rows

Unreadable files and broken symlinks (not previewable) stay in the tree, drawn at reduced
alpha with no open action (click does nothing; tooltip says why). Check
readability with `isReadableKey` and `isSymbolicLinkKey` plus a destination
exists check, fetched in the same `resourceValues` call the tree already
makes so there is no extra stat per row. Omnisearch skips them.

### Tests

- Unit tests for `FileKind.classify`: each extension, mixed case, known
  names, a dotfile, no extension, `UTType` fallback, and a directory.
- `ProjectFileIndex`: a fixture tree with Markdown, text, image and binary
  files. Assert that all are indexed, that `kind` is correct, and that
  pruned directories are still skipped.
- Matcher ranking when the index is truncated.

### Verification

- `xcodebuild -project daisy.xcodeproj -scheme daisy -configuration Debug build`.
- Run the app against a folder containing `.md`, `.png`, `.pdf` and `.swift`.
  Confirm: all four appear; `.md` opens in edit mode; `.png` and `.pdf` open
  in the default app; the current tab and its unsaved edits are untouched;
  omnisearch finds all four.
- `git diff daisy.xcodeproj/project.pbxproj`: revert any `DEVELOPMENT_TEAM`
  rewrite.

### Out of scope

The code editor, `Info.plist` document types, widening the File > Open
panel, the configurable whitelist,
moving `.txt`.

---

## Phase 2: code-only editor for `text` files

Phase 2 starts with a short spike. I have not yet read `EditorHTML` or
`EditorViewController`, and how hard it is to disable the Markdown-specific
features sets the size of this phase.

### Spike (first, about half a day)

Read `Features/Editor/*`, `DocumentWindowController+EditMode.swift`,
`+EditSession.swift`, `+FormattingBar.swift`. Answer:

- Does the editor accept a plain-text mode, or are Markdown behaviours
  (live syntax styling, tables, slash commands, rich paste) built into it?
- Can `CodeHighlighter` and `CodeLanguageCatalog` drive highlighting for a
  whole file, or only for fenced blocks?

If Markdown behaviours cannot be switched off, the fallback is a separate,
simpler code view for `text` files, not a mode flag on the existing editor.
Update this document with the answer before building.

### Scope

1. **Document mode.** `MarkdownDocument` gets a `mode` (`.markdown`,
   `.code(language:)`) derived from `FileKind` and the extension. The file is
   read and written as UTF-8 with no Markdown processing.
2. **Configurable whitelist.** A "Code and text files" list in
   **Settings → General** (or **Extensions**), stored in `UserDefaults`.
   Built-in defaults are shown read-only; the user adds or removes their own
   extensions and file names (normalised: lowercase, no leading dot). The
   classifier reads a snapshot of the merged set so the off-main-actor index
   walk stays cheap and race-free; changing the list refreshes the sidebar
   and re-indexes. A user entry never overrides `markdown`. Add
   `en.lproj` and `zh-Hans.lproj` strings.
3. **`Info.plist` document types and the open panel.** The File > Open panel
   (`MarkdownDocumentController`, `LaunchItemStore`, the window controller's
   panel) accepts any file once these exist. Add `public.plain-text` and
   `public.source-code` with an Editor role, so `NSDocumentController`
   accepts these files. Check the `quick-look` extension is unaffected.
4. **Editor in code mode.**
   - Highlighting by language from `CodeLanguageCatalog`.
   - Preview toggle and `⌘E` disabled; the file is always in edit mode.
   - Formatting bar, Insert menu and slash commands hidden.
   - Paste is plain text only (no rich-text or HTML conversion).
   - Find and Replace keeps working.
   - Save (`⌘S`) writes the raw text. Existing autosave setting applies.
5. **Chrome.** Outline and inspector panels are hidden for code files, or
   show an empty state. The window title and toolbar make sense without a
   preview.
6. **Router.** The `text` case in `openFile(_:)` stops falling through to the
   system app and opens in the code editor.
7. **Safety.**
   - Size cap: files above 5 MB go to the external app.
   - Decode failure (not valid UTF-8): open externally, never in the editor.
   - File changed on disk while open: reuse the existing `FileWatcher` flow.
8. **`.txt` moves to `text`.** Remove the Phase 1 special case. Plain `.txt`
   files stop rendering as Markdown; call this out in the changelog and
   README.
9. **Docs in the same PR.** `README.md` Edit Mode section: the code-only
   editor, supported files, the size cap. Check `samples/` for claims about
   supported types.

### Tests

- Mode selection per `FileKind` and extension.
- Whitelist: user additions and removals change classification; a user entry
  cannot make a Markdown file `text`; input normalisation.
- Round-trip: open, edit, save, and compare bytes (line endings and trailing
  newline preserved).
- Non-UTF-8 and oversized files route externally.
- Markdown-only features are inert in code mode (no slash menu, plain paste).

### Verification

- Build the app, then run it against `.swift`, `.json`, `Makefile`, `.txt`
  and `.md`. Confirm highlighting, no preview toggle, save works, and `.md`
  is unchanged.
- Regression: Markdown edit, preview, find and replace behave as before.
- Confirm Quick Look still previews `.md`.

### Out of scope

LSP or autocomplete,
a binary or hex viewer.

---

## Risks

| Risk                                                      | Mitigation                                             |
| --------------------------------------------------------- | ------------------------------------------------------ |
| Index cap reached sooner, hurting omnisearch              | Rank by kind; measure before and after                 |
| Editor cannot disable Markdown behaviour                  | Spike first; fallback is a separate simple code view   |
| Binary file opened as text and corrupted on save          | Whitelist-only; UTF-8 decode check; size cap           |
| `.txt` behaviour change surprises users                   | Isolated to Phase 2; changelog and README entry        |
| Xcode rewrites `DEVELOPMENT_TEAM` while building          | Check `git diff` on `project.pbxproj` before committing |

## Open questions

None blocking. The Phase 2 spike may add some.
