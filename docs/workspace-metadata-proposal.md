# Workspace metadata and completion proposal

Status: Implemented, apart from the runtime test pass in the [implementation plan](workspace-metadata-implementation-plan.md) (Phase 6). README.md describes the behavior for readers; this document keeps the design reasoning.

## Summary

Add todo.txt-inspired metadata to Markdown content, with searchable inline completion modeled on the existing slash-command menu:

```markdown
- [ ] Review proposal +daisy @alex @work #review p:high scheduled:2026-10-20 due:2026-10-23
```

Keep Markdown files authoritative. A workspace is a folder containing a `.daisy/config.json` marker, created with **File → Initialize Workspace**. Only a folder window on a workspace folder is indexed; opening a plain folder or a file never starts indexing. Store the disposable index in the app's container, never inside the workspace.

## Goals and scope

- Search and select tags, contexts, and projects while typing; set priorities and dates through slash commands.
- Treat people as contexts rather than maintaining a separate people directory.
- Support scheduled and due dates without reminders or recurrence execution. (A dated-task view was later added as the Tasks sidebar; see [the Tasks sidebar proposal](tasks-sidebar-proposal.md).)
- Preserve readable, editable Markdown outside Daisy.
- Reuse completion infrastructure instead of implementing a separate menu for every prefix.
- Make future metadata fields possible without introducing a plugin loader now.
- Reuse indexed suggestions across tabs and app launches.
- Index only folders the user has made workspaces, and write nothing into the user's folders except the marker that Initialize Workspace creates the metadata pages the user explicitly opens (see the implementation plan, Phase 4.5), and the journal entries the user explicitly opens (`journals/YYYY-MM-DD.md`, from Today's Journal or the toolbar calendar), plus, with journal carry-over turned on, the earlier entries whose unfinished tasks move into today's new one, and the files whose tasks the user checks off in the Tasks sidebar.

Non-goals for the initial release:

- Accounts, contact integration, person identity verification, or mention notifications.
- Automatic task assignment from a person context.
- Calendar synchronization, notifications, or recurring task generation.
- Full todo.txt format compatibility.
- Runtime third-party extension loading.

## Existing foundations

- `scripts/editor-bundle/src/slash.js`: trigger detection, ranked matching, menu rendering, keyboard selection, template submenus, and insertion transactions.
- `scripts/editor-bundle/src/task-list.js`: Markdown checkbox widgets, task-list continuation, and Cmd+Enter state cycling.
- `scripts/editor-bundle/src/api.js`: editor API and host-supplied data updates.
- `daisy/Features/Editor/EditorViewController.swift`: Swift/editor bridge.
- `daisy/Features/FileSearch/ProjectFileIndex.swift`: bounded workspace file discovery and short-lived caching. This indexes file names, not metadata content.
- `daisy/Features/Sidebar/BookmarkStore.swift`: security-scoped bookmark persistence for navigator pins.
- `daisy/Features/Launch/LastSessionStore.swift`: bookmark persistence for the last window's folder and file, used by Reopen last session.
- `scripts/editor-bundle/smoke/slash-commands.mjs`: existing slash-command regression tests.

The current slash matcher ranks exact, prefix, and word-prefix matches; it is not a general fuzzy matcher. Preserve its existing behavior during extraction.

## Markdown syntax

| Syntax | Meaning | Scope |
| --- | --- | --- |
| `#review` | General tag or topic | Eligible Markdown prose |
| `@alex`, `@work`, `@phone` | Context, including people | Eligible Markdown prose |
| `+daisy` | Project | Eligible Markdown prose |
| `scheduled:2026-10-20` | Planned work date | Checkbox task item |
| `due:2026-10-23` | Deadline | Checkbox task item |
| `p:high` | Priority | Checkbox task item |

Borrow contexts, projects, and `key:value` notation from the todo.txt ecosystem. Retain Markdown checkboxes and `#tags`; do not claim complete todo.txt compatibility. In particular, todo.txt's `t:` convention means a threshold or “do not start before” date, not a planned work date, so Daisy uses explicit `scheduled:`.

### Proposed token rules

- Metadata tokens begin at the start of a line or after whitespace. Punctuation-adjacent activation can be considered later.
- Tags, contexts, and projects allow Unicode letters and numbers, `_`, `-`, and `/` for hierarchical names. Require at least one letter; disallow empty hierarchy segments.
- Spaces are not part of a name. Trailing sentence punctuation is not part of the token.
- Matching is case-insensitive using one documented normalization algorithm shared by tests. Preserve source spelling; select a deterministic display spelling for indexed suggestions.
- Field keys are lowercase and case-sensitive. Initial recognized keys are `scheduled`, `due`, and `p`.
- Field values are nonempty, whitespace-free tokens. The initial grammar does not support quoting, embedded colons, timestamps, or free-form recurrence expressions.
- Initial priority values are `high`, `medium`, and `low`. No priority field means unspecified, not implicitly medium.
- Dates use valid Gregorian calendar dates in `YYYY-MM-DD`, interpreted as local calendar dates rather than UTC instants.
- Unknown fields remain ordinary text. Preserve malformed values and duplicate fields; do not silently rewrite or discard them.
- Scope field semantics to the task item's marker line initially. Continuation-line metadata is deferred.
- Exclude code, frontmatter, HTML, links, images, and URLs. Initially retain the slash menu's table restriction for completion and metadata extraction.

These details are proposed defaults to lock down through grammar fixtures before implementation.

### Markdown compatibility

- `# Heading` and `## Heading` remain headings. Space or another `#` dismisses a tag picker without accepting a suggestion.
- `+ item` remains a Markdown list item. Space after a bare `+` dismisses the project picker.
- `name@example.com`, `C#`, URL fragments, and embedded prefixes do not activate completion.
- Inline code is the escape hatch for literal examples such as `due:2026-10-23`.
- Ordinary Markdown readers display metadata as text. Custom badges are optional presentation, not a storage requirement.

## Completion experience

| Trigger | Source | Behavior |
| --- | --- | --- |
| `/` | Existing commands and templates | Preserve current slash behavior |
| `#` | Indexed tags plus live buffers | Filter and insert a tag |
| `@` | Indexed contexts plus live buffers | Filter and insert a context |
| `+` | Indexed projects plus live buffers | Filter and insert a project |

Typing a field key such as `due:`, `scheduled:`, or `p:` does not open a picker; those fields are set with slash commands (below). Typed field text is still parsed as metadata.

### Shared interactions

- Arrow keys move through results; Enter or Tab accepts; Escape dismisses without altering text.
- Mouse selection preserves editor focus.
- Only one completion session is active at a time.
- A dismissed session stays closed until its token is exited or a new trigger begins.
- Opening a document or moving the caret alone does not automatically open a picker.
- Do not intercept IME composition or nonempty/multiple selections in the initial implementation.
- Completion replaces the entire active token, including any existing suffix, while preserving surrounding text.
- Each accepted completion is one undoable edit.
- Unknown tag, context, or project names are valid and need no creation step. The menu lists only known names; when none match, it closes and the typed name stays as written.
- Empty results must not erase typed text or prevent normal editing.
- Provide accessible labels and selected-option state; verify keyboard and VoiceOver behavior.

For indexed names, rank exact matches before prefixes and hierarchical segment prefixes; use usage frequency and deterministic lexical ordering as tie-breakers. Do not change slash-command ranking during the refactor.

Implemented in the editor (`scripts/editor-bundle/src/metadata-completion.js`, Settings → Extensions → Metadata suggestions):

- A `#` or `+` at the start of a line (after indentation or `>`) waits for a name character before opening, so typing a heading or a `+` list item never flashes the picker. Elsewhere, a bare trigger lists every name of that kind.
- Filtering uses the text before the caret; accepting replaces the whole token, including name characters after the caret, and leaves the caret after the name. No space is added.
- Rows show the marker and the name; use counts only order them. The token being typed is left out of the current document's names, so a half-typed name never suggests itself.
- The current document's names come from the shared extractor. When a name also appears in the workspace snapshot, the document's most used spelling is shown and the larger of the two counts is used, because the snapshot already counts the saved copy of this document.
- The host sends workspace names with `setWorkspaceCandidates({ version, indexing, truncated, tags, contexts, projects })`, each kind a list of `{ name, count }` without the marker. A snapshot with a lower version than the one held is ignored; invalid names are dropped. While `indexing` or `truncated` is true, the menu notes under its rows that the workspace is still being indexed or is over the file limit.

### Dates and priorities

Dates and priorities are set with new slash commands, available on checkbox task lines:

| Command | Opens | Writes |
| --- | --- | --- |
| `/due` (Due Date) | Date picker, starting on the existing date or today | `due:YYYY-MM-DD` |
| `/schedule` (Schedule) | Same as `/due` | `scheduled:YYYY-MM-DD` |
| Clear Due Date, Clear Schedule | Nothing; shown only when the task has that date | Removes the field |
| Priority: High, Priority: Medium, Priority: Low, Priority: None | Nothing; each is its own top-level command | `p:high`, `p:medium`, `p:low`; None removes the field |

The priority commands are listed directly in the slash menu, so `/pri` shows all of them and `/high` finds Priority: High. Each command inserts the field if absent (a priority at the start of the task text, dates at the end) or replaces it in place if exactly one exists; Clear Due Date, Clear Schedule, or Priority: None removes it. If duplicates exist, require the user to choose an occurrence rather than silently collapsing them. The date picker opens directly, without a preset submenu: Enter accepts today, arrow keys move by day or week, Page Up/Down or the month buttons by month, and typing is ignored while the picker is open; show the resolved date before acceptance. Natural-language date parsing is deferred. Add aliases (for example `deadline`, `date`) through the existing slash alias mechanism, and verify the new commands do not displace current top results for common queries.

Opening a submenu or calendar must not commit a partial document edit: cancel restores or preserves the original text; acceptance removes the typed command and applies the field in one transaction. Discard a pending picker result if its document/session is no longer valid.

Completing a task preserves metadata. Creating the next task must not copy dates, priorities, or context/project tokens from the previous task's text.

## Provider architecture

Extract a shared completion controller from the slash implementation. Providers define:

- Trigger and allowed syntax context.
- Query and replacement range.
- Candidate source and ranking.
- Optional submenu or calendar presentation.
- Validation and application behavior.

The controller owns session state, positioning, keyboard handling, dismissal, accessibility, and transaction lifecycle. Slash-specific block conversion and template behavior remain in their provider.

Illustrative registrations, not committed API signatures:

```ts
registerCompletionProvider({
  id: "context",
  trigger: { prefix: "@" },
  scope: "prose",
  source: { type: "workspace", kind: "context" },
});

defineTaskField({
  key: "due",
  value: { type: "date" },
  command: { id: "due", aliases: ["deadline"] },
});
```

Separate completion from stored semantics. Field definitions supply validation, the extractor's parsing rule, and the slash commands that write the field, so values a command writes cannot drift from values the parser accepts.

CodeMirror autocomplete is already a dependency and is an alternative implementation substrate. Prefer extracting the existing picker initially to preserve slash submenus and behavior, rather than replacing the entire interaction model in the same change.

## JS and Swift responsibilities

### JavaScript / CodeMirror

- Detect active prefixes using document state, cursor position, and syntax context.
- Own the single metadata extractor (`workspace-metadata.js`), used by both the editor and the Swift indexer.
- Parse live-buffer metadata and produce any editor decorations.
- Filter local suggestion snapshots and render completion UI.
- Validate and apply slash-command date/priority selections through CodeMirror transactions.
- Maintain immediate suggestions from the current unsaved buffer.

Do not require a Swift round-trip on every keystroke.

### Swift

- Detect the workspace marker when a folder opens, and create or remove it on request.
- Discover files, run the shared extractor on saved files, and maintain the cache.
- Watch and reconcile filesystem changes.
- Aggregate workspace candidates and send versioned snapshots to editors.
- Coordinate unsaved-buffer overlays across windows and tabs.

### One extractor, two hosts

Metadata extraction has exactly one implementation, in JavaScript. Which text counts as metadata depends on Markdown structure — code, links, HTML, frontmatter, and tables are excluded — and the editor decides that from the Lezer syntax tree. A Swift reimplementation would use swift-markdown (cmark-gfm), which disagrees with Lezer on edge cases such as HTML blocks, lazy continuation lines, and table boundaries. Fixtures only catch the cases someone wrote down, and any gap shows up as index suggestions that contradict the editor.

- Build the extractor as a second, DOM-free output of the editor bundle (for example `daisy/Vendor/CodeMirror/metadata-extract.min.js`) that imports only `@lezer/markdown` and its GFM extensions.
- Expose one entry point, `extractMetadata(markdown)`, returning normalized tags, contexts, and projects with source spelling and occurrence counts.
- The Swift indexer loads that bundle into JavaScriptCore and calls it per file, following the precedent of `daisy/Rendering/CodeHighlighter.swift`. JavaScriptCore serializes calls per context, so initial indexing uses a small bounded pool of contexts; partial results are published while it runs.
- Unicode normalization therefore happens in one place, and Swift needs no matching algorithm.

The index also keeps each file's tasks, with their text, checked state, dates and priority, for the Tasks sidebar (see [the Tasks sidebar proposal](tasks-sidebar-proposal.md)). They are read by the same extractor, stored per file rather than aggregated, and never sent to editors in completion snapshots.

## Workspaces

A workspace is a folder whose root contains `.daisy/config.json`. Opening that folder as a folder window, in any way, makes the window a workspace window, and only workspace windows are indexed. Opening a folder without the marker, or opening a file, keeps today's behavior and never starts indexing.

Detection checks only the folder being opened. Daisy does not walk parent directories or descend into subfolders looking for a marker, A file can join a workspace only through a window that is already open on it (below).

- **Detection.** Every folder open goes through `AppDelegate.openFolder`: File → Open… on a folder, Finder, drag and drop, the command-line tool, the Open Folder… buttons in OmniSearch and the navigator, and Reopen last session. When the opened root contains `.daisy/config.json`, the window is a workspace window. Nothing extra is persisted: restoring the folder finds the marker again.
- **Folder windows only.** A window opened for a single file roots its navigator at the file's parent folder. That root is never checked for a marker, because checking it would be a one-level parent walk. To use a workspace, open its folder.
- **Initialize Workspace.** File → Initialize Workspace is enabled in a folder window whose root has no marker. It creates `.daisy/config.json` and turns every open folder window on that root into a workspace window. If the write fails, show an error and leave the window a plain folder.
- **Remove Workspace.** File → Remove Workspace, enabled in a workspace window, deletes `.daisy/config.json` (and `.daisy/` once nothing else is in it) and that workspace's cache, and turns its windows back into plain folder windows. Deleting the marker by hand has the same effect the next time Daisy becomes active.
- **The marker.** `.daisy/config.json` contains only `{"version": 1}`. Its presence makes the folder a workspace; Daisy does not read its contents, and later versions will ignore content they do not recognise, so a marker that arrives with a cloned repository can turn on indexing and nothing else. It holds no cache or per-user state, so committing it is harmless and shares the workspace with collaborators; adding it to `.gitignore` keeps it personal. Initialize Workspace is the only command that writes the marker; the other writes into a workspace folder are listed under Goals and scope.
- **Window scope.** A workspace window keeps its workspace whatever file it shows next, as a folder window keeps its navigator root today. Every document it shows gets that workspace's suggestions; only files inside the root contribute to the index. Open in New Tab or Open in New Window for a file inside the root, and a new untitled document created from the window, carry the workspace over, as they already carry the navigator root.
- **Files opened directly.** A file opened from Finder, ⌘O, Open Recent, drag and drop, or the command-line tool joins, as a tab, the frame of the innermost open window whose folder contains it, and gets that window's workspace if it has one. With no such window open, it gets a plain window and current-buffer suggestions only, even if it lies inside a workspace folder.
- **Shared index.** Key workspaces by canonical root (symlinks resolved, then standardized, as `SidebarWorkspace.canonicalURL` does). The index service is shared by canonical root, so a second workspace window on the same root does not index again. Do not follow symlinks out of the root or into cycles. There is no workspace registry; leave `SidebarWorkspaceRegistry` and folder-opening behavior unchanged.
- **Nested and overlapping workspaces.** If `repo/` and `repo/sub/` both have markers, opening `repo/` indexes everything under it, including `sub/`; opening `repo/sub/` indexes only `sub/`. They index independently, and each editor queries only its own window's workspace, so overlap cannot double-count within one suggestion list.

```text
Open repo/ (has .daisy/config.json)                  window A: workspace repo/, indexed
Open notes/ (no marker)                              window B: plain folder, not indexed, nothing written
File → Initialize Workspace in window B              writes notes/.daisy/config.json; window B becomes a workspace
Open in New Tab from window A → repo/docs/a.md       joins repo/
Finder → repo/docs/a.md                              tab in window A's frame, joins repo/
Finder → other/b.md (no open window contains it)     plain window, current-buffer suggestions only
```

### Sandbox limits

Daisy's read-only temporary exception for `/` means reads succeed almost everywhere, but writes require a user-selected or bookmarked grant. Detection and indexing only read, and the index lives in the app container (below), so a workspace needs no access beyond what a folder window already has, and indexing never broadens access. Workspace folders are restored through the existing folder bookmark in `LastSessionStore`. Only Initialize Workspace and Remove Workspace write, and they need the write grant a folder chosen in the open panel, opened from Finder, or dropped on the app already has; without it they fail with an error and change nothing.

## Index storage

Store each workspace's index in the app's sandbox container, not in the workspace:

```text
<app container>/Library/Caches/WorkspaceIndex/<root-id>.sqlite
```

`<root-id>` is derived from the canonical root path and its volume identifier. Apart from the `.daisy/config.json` marker, the pages and journal entries the user opens, the earlier entries journal carry-over takes tasks from, and the files whose tasks the user checks off in the Tasks sidebar, Daisy writes nothing into the workspace folder: no cache, no `.gitignore`, no per-user state. The marker is small, static, and safe to commit or sync; keeping the cache out keeps SQLite out of git, iCloud Drive, Dropbox, and network folders, where synced database files are a known source of corruption. Future shareable workspace settings may be added to `config.json` under a new version; per-user state never goes there.

### Cache contents

- Schema version and parser version.
- Root identity (canonical path and volume identifier) sufficient to detect an incompatible or relocated cache.
- Workspace-relative file paths, modification times, sizes, and content hashes.
- Per-file tokens and occurrence counts; aggregate projects, contexts, and tags.
- Per-file tasks (line, text, checked state, dates, priority), for the Tasks sidebar.

Do not store full document copies or unsaved-buffer text. The database is disposable derived data, not a source of truth.

Use SQLite for incremental updates, transactions, aggregation, and crash recovery. Own connections and work through the Swift workspace index service. Use bounded transactions and handle contention without blocking typing.

Treat a cache from disk as untrusted input: validate schema and paths, prevent paths from escaping the workspace root, and rebuild on corruption or incompatible versions. Cache contents may reveal project names and person/context handles even without full document text; keep them local and out of analytics.

### Failure behavior

- Cache creation/write failure: continue with an in-memory index and a nonblocking status.
- Corrupt or incompatible cache: discard derived data and rebuild.
- Missing cache (first open, or purged by the system): rebuild in the background.
- Exclude the cache directory from watcher feedback.
- “Rebuild Workspace Index” deletes and recreates that workspace's cache file only.
- Remove Workspace deletes that workspace's cache file.
- Cache files not opened for 30 days are deleted at launch, so caches for abandoned workspaces do not accumulate.
- If the root moves and its bookmark resolves to a new path, re-key or rebuild the cache rather than trusting stale paths.

## Index lifecycle

| Event | Action |
| --- | --- |
| Folder without a marker, or a file outside every open workspace window, opened | No indexing; current-buffer suggestions only |
| Initialize Workspace | Write the marker; index as for a workspace that opens |
| Folder with a marker opens | Load compatible cached candidates, then reconcile in background |
| Another window or tab binds the same workspace root | Reuse the shared index service |
| Initial cache is absent | Discover eligible Markdown and parse with bounded concurrency |
| User types `#`, `@`, or `+` | Query memory; never scan the filesystem |
| Buffer changes | Update debounced in-memory tokens; current editor updates immediately |
| File saves or changes externally | Reparse that file and persist its token set |
| File is created, removed, or renamed | Add, remove, or move its contribution |
| App regains focus or watcher loses events | Reconcile filesystem state; a removed marker turns the windows back into plain folders |
| Last workspace window on that root closes | Stop watching and release service after an idle interval |

Background reconciliation discovers additions and deletions and compares fingerprints. Modification time and size provide fast checks, not absolute proof of unchanged content. Use hashes when validating uncertain files; provide a full rebuild path.

Publish partial results during initial indexing. Show current-buffer suggestions immediately and indicate “Indexing workspace…” or partial coverage when appropriate. Disclose scan limits; never present capped results as complete. Oversized, unreadable, and non-UTF-8 files are left out silently.

Reuse existing discovery exclusions where appropriate, classify eligible Markdown consistently, and add explicit file-size and scan-budget limits. Watchers must coalesce changes and avoid following symlinks outside authorized scope.

Unsaved buffers replace, rather than add to, saved-file contributions, in the workspace of the window editing them; other workspaces containing the file pick up the change when it is saved. Deduplicate shared document buffers across tabs; the current editor's version takes precedence for its own suggestions. Closing an unsaved buffer without saving restores the disk contribution.

`/due`, `/schedule`, and the Priority commands work without a workspace index.

## Rendering and portability

Valid `due:`, `scheduled:`, and `p:` fields on a checkbox task's marker line render as badges in the editor and in Read mode, through the `task-metadata` render extension (Settings → Extensions → Task metadata):

- Dates show `YYYY-MM-DD` and a short weekday, with a clock icon for due and a calendar icon for scheduled. A due date before today on an open task is marked overdue.
- Priorities show as tinted uppercase tags: HIGH (red), MEDIUM (orange), LOW (blue).
- In the editor, putting the caret on a field (or landing on it with Find) shows its source text for editing, like other live-preview markup. Clicking a badge does the same.
- Each badge has an accessible name, for example “Due: Friday, October 23, 2026, Overdue”.
- Quick Look and HTML export never load the badge script and show the literal text. PDF (print) and PNG export switch Read mode back to the literal text.

The Markdown is never changed, and badges are not needed to understand the file: the literal text carries the meaning.

## Implementation phases

1. **Grammar and extractor:** finalize token boundaries, normalization, priority values, task scope, and duplicate handling; build the single JS extractor and its JavaScriptCore bridge.
2. **Shared completion controller:** in three parts — 2a extracts slash behavior with no change, 2c adds `/due`, `/schedule`, and the Priority commands, then 2b adds `#`/`@`/`+` suggestions.
3. **Workspaces:** detect the `.daisy/config.json` marker on folder open, add Initialize Workspace and Remove Workspace, and window-scoped workspace membership.
4. **Workspace indexing:** add bounded extraction, unsaved overlays, snapshots, filesystem reconciliation, and cache persistence in the app container.
5. **Integration and documentation:** wire workspace candidates into providers; update README and samples; verify runtime interaction and failure modes.

Keep changes independently testable. No release or version bump is implied by this proposal.

## Verification

### Editor tests

- Existing slash commands, ranking, templates, and keyboard navigation remain unchanged.
- Trigger detection, exact replacement ranges, and one-step undo/redo.
- Heading/list collisions, emails, URLs, code, frontmatter, HTML, links, and tables.
- Unicode names, case normalization, hierarchy segments, trailing punctuation, and empty results.
- IME composition, focus, stale picker sessions, Escape, and loaded documents.
- ISO date validation, leap years, month/year rollover, and deterministic preset calculations using an injected clock.
- `/due`, `/schedule`, and the Priority commands: availability only on task lines, existing-field updates, duplicate fields, Clear, cancel behavior, and slash ranking with the new commands.
- Task completion and task-list continuation.

### Swift and integration tests

- The JavaScriptCore bridge returns the same results as the editor for every fixture.
- Opening a folder with a marker, by any route including Reopen last session, gives a workspace window; a folder without one stays plain; only the opened root is checked.
- Initialize Workspace writes only `.daisy/config.json`; Remove Workspace deletes it and the cache, keeping other files in `.daisy/`; a failed write changes nothing; unknown marker content is ignored.
- Folder opens without a marker, direct file opens, and the command-line tool never index or write into the folder.
- Only workspace windows, and tabs, windows, and untitled documents created from them, are bound to a workspace; a file opened from outside joins the workspace of an open window containing it, and otherwise gets buffer-only suggestions; no parent directory is ever walked.
- Overlapping workspaces index independently; workspace windows on the same root, including symlink aliases, share one index service; symlinks outside the root are not followed.
- Nothing other than the marker and explicitly opened metadata pages is written inside a workspace folder.
- Cached reopen, incremental updates, rename/deletion, watcher reconciliation, and scan truncation.
- Cache corruption/version mismatch, system purge, root relocation, path validation, contention, write failure, and cache-only rebuild.
- Multiple tabs share results without duplicate counts; unsaved overlays supersede cached data.

Run editor tests, relevant Swift tests, and an app build for implementation changes. Perform runtime checks for keyboard interaction, calendar UI, accessibility, large workspaces, and permission prompts. Documentation-only proposal changes do not require an app build.

## References and alternatives

- [todo.txt format](https://github.com/todotxt/todo.txt): projects, contexts, and extensible `key:value` notation.
- [todo.txt due and threshold conventions](https://swiftodoapp.com/todotxt-syntax/due-dates-and-threshold-dates/): distinction between due and threshold dates.
- [TaskPaper dates](https://guide.taskpaper.com/using-taskpaper/using-dates-and-reminders.html): date-aware tag completion.
- [Obsidian Tasks dates](https://github.com/obsidian-tasks-group/obsidian-tasks/blob/main/docs/Getting%20Started/Dates.md): scheduled/due distinction and emoji notation.
- [Dataview inline fields](https://blacksmithgu.github.io/obsidian-dataview/annotation/add-metadata/): `[key:: value]` alternative, not selected here.
- [CodeMirror autocomplete](https://codemirror.net/examples/autocompletion/): completion sources and syntax-aware filtering.

Earlier alternatives included emoji date markers, Dataview brackets, and custom brace blocks. This proposal selects compact todo.txt-inspired tokens while retaining Daisy's Markdown document model.
