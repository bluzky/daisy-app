# Workspace metadata and completion proposal

Status: Proposed. This document describes planned behavior, not currently shipped features.

## Summary

Add todo.txt-inspired metadata to Markdown content, with searchable inline completion modeled on the existing slash-command menu:

```markdown
- [ ] Review proposal +daisy @alex @work #review p:high scheduled:2026-10-20 due:2026-10-23
```

Keep Markdown files authoritative. Index only folders the user explicitly opens with **File → Open Workspace…**; opening a folder or file any other way never starts indexing. Store the disposable index in the app's container, never inside the workspace.

## Goals and scope

- Search and select tags, contexts, and projects while typing; set priorities and dates through slash commands.
- Treat people as contexts rather than maintaining a separate people directory.
- Support scheduled and due dates without a task dashboard, reminders, or recurrence execution.
- Preserve readable, editable Markdown outside Daisy.
- Reuse completion infrastructure instead of implementing a separate menu for every prefix.
- Make future metadata fields possible without introducing a plugin loader now.
- Reuse indexed suggestions across tabs and app launches.
- Index only explicitly opened workspaces, and never write into the user's folders.

Non-goals for the initial release:

- Accounts, contact integration, person identity verification, or mention notifications.
- Automatic task assignment from a person context.
- Task dashboards, calendar synchronization, notifications, or recurring task generation.
- Full todo.txt format compatibility.
- Runtime third-party extension loading.

## Existing foundations

- `scripts/editor-bundle/src/slash.js`: trigger detection, ranked matching, menu rendering, keyboard selection, template submenus, and insertion transactions.
- `scripts/editor-bundle/src/task-list.js`: Markdown checkbox widgets, task-list continuation, and Cmd+Enter state cycling.
- `scripts/editor-bundle/src/api.js`: editor API and host-supplied data updates.
- `daisy/Features/Editor/EditorViewController.swift`: Swift/editor bridge.
- `daisy/Features/FileSearch/ProjectFileIndex.swift`: bounded workspace file discovery and short-lived caching. This indexes file names, not metadata content.
- `daisy/Features/Sidebar/BookmarkStore.swift`: security-scoped bookmark persistence for navigator pins.
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
- Unknown tag, context, or project names are valid. Offer “Use <token>” without a separate creation dialog.
- Empty results must not erase typed text or prevent normal editing.
- Provide accessible labels and selected-option state; verify keyboard and VoiceOver behavior.

For indexed names, rank exact matches before prefixes and hierarchical segment prefixes; use usage frequency and deterministic lexical ordering as tie-breakers. Do not change slash-command ranking during the refactor.

### Dates and priorities

Dates and priorities are set with new slash commands, available on checkbox task lines:

| Command | Submenu | Writes |
| --- | --- | --- |
| `/due` | Today, Tomorrow, In one week, Choose date, Clear | `due:YYYY-MM-DD` |
| `/schedule` | Same as `/due` | `scheduled:YYYY-MM-DD` |
| Priority: High, Priority: Medium, Priority: Low, Priority: None | No submenu; each is its own top-level command | `p:high`, `p:medium`, `p:low`; None removes the field |

The priority commands are listed directly in the slash menu, so `/pri` shows all of them and `/high` finds Priority: High. Each command inserts the field if absent or replaces it if exactly one exists; Clear (dates) or Priority: None removes it. If duplicates exist, require the user to choose an occurrence rather than silently collapsing them. Choose date opens a calendar; show the resolved date before acceptance. Natural-language date parsing is deferred. Add aliases (for example `deadline`, `date`) through the existing slash alias mechanism, and verify the new commands do not displace current top results for common queries.

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

- Open and persist workspaces, and manage their security-scoped access.
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

Dates and priorities stay out of the workspace index. If a native feature later needs them, a narrow Swift reader is acceptable because those fields are confined to task marker lines and do not depend on block structure.

## Workspaces

A workspace is a folder the user opens with **File → Open Workspace…**. Only workspaces are indexed. Open Folder…, opening a file, drag and drop, and the command-line tool keep their current behavior: they never start indexing, never walk ancestors looking for a workspace, and never write anything into the folder.

- Open Workspace… presents the system folder picker, so the chosen folder carries a user-selected grant. Persist it as a security-scoped bookmark so the workspace reopens across launches and can appear in a recent-workspaces list.
- The chosen folder is both the workspace root and the navigator root. There is no marker-file discovery and no ancestor walk.
- A file opened directly that lies inside an open workspace joins that workspace and receives its suggestions, mirroring today's reuse of a containing open folder. If several open workspaces contain it, the deepest root wins. A file outside every open workspace gets current-buffer suggestions only.
- Key workspaces by canonical root (standardized, symlinks resolved). Opening the same folder twice reuses one index service. Do not follow symlinks out of the root or into cycles.
- Overlapping workspaces (for example `repo/` and `repo/subproject/` both opened) index independently. Each editor queries only its own workspace, so overlap cannot double-count within one suggestion list. An unsaved buffer contributes to every open workspace that contains it.
- Track workspaces in a dedicated `WorkspaceRegistry`. Leave `SidebarWorkspaceRegistry` and Open Folder behavior unchanged.

```text
File → Open Workspace…  → repo/            indexed; suggestions from all of repo/
File → Open Folder…     → repo/docs/       not indexed; no files written
Open repo/docs/a.md     while repo/ is an open workspace → joins repo/
Open ~/notes/b.md       with no containing workspace     → current-buffer suggestions only
```

### Sandbox limits

Daisy's read-only temporary exception for `/` means reads succeed almost everywhere, but writes require a user-selected or bookmarked grant. Workspaces come only from the folder picker, and the index lives in the app container (below), so indexing never needs write access to the workspace and never broadens access.

If a workspace bookmark is stale or cannot be resolved, show the workspace as unavailable and offer to choose it again. Do not silently fall back to path-only access.

## Index storage

Store each workspace's index in the app's sandbox container, not in the workspace:

```text
<app container>/Library/Caches/WorkspaceIndex/<root-id>.sqlite
```

`<root-id>` is derived from the canonical root path and its volume identifier. Daisy writes nothing into the workspace folder: no marker directory, no `.gitignore`, no cache. This keeps `git status` clean and keeps SQLite out of iCloud Drive, Dropbox, and network folders, where synced database files are a known source of corruption. A possible future `.daisy/config.json` for intentional, shareable workspace settings is reserved; it is not part of this implementation.

### Cache contents

- Schema version and parser version.
- Root identity (canonical path and volume identifier) sufficient to detect an incompatible or relocated cache.
- Workspace-relative file paths, modification times, sizes, and content hashes.
- Per-file tokens and occurrence counts; aggregate projects, contexts, and tags.

Do not store full document copies or unsaved-buffer text. The database is disposable derived data, not a source of truth.

Use SQLite for incremental updates, transactions, aggregation, and crash recovery. Own connections and work through the Swift workspace index service. Use bounded transactions and handle contention without blocking typing.

Treat a cache from disk as untrusted input: validate schema and paths, prevent paths from escaping the workspace root, and rebuild on corruption or incompatible versions. Cache contents may reveal project names and person/context handles even without full document text; keep them local and out of analytics.

### Failure behavior

- Cache creation/write failure: continue with an in-memory index and a nonblocking status.
- Corrupt or incompatible cache: discard derived data and rebuild.
- Missing cache (first open, or purged by the system): rebuild in the background.
- Exclude the cache directory from watcher feedback.
- “Rebuild Workspace Index” deletes and recreates that workspace's cache file only.
- Removing a workspace from the recent-workspaces list deletes its cache file.
- If the root moves and its bookmark resolves to a new path, re-key or rebuild the cache rather than trusting stale paths.

## Index lifecycle

| Event | Action |
| --- | --- |
| Folder or file opened outside a workspace | No indexing; current-buffer suggestions only |
| Workspace opens | Load compatible cached candidates, then reconcile in background |
| Another tab opens the same workspace | Reuse the shared index service |
| Initial cache is absent | Discover eligible Markdown and parse with bounded concurrency |
| User types `#`, `@`, or `+` | Query memory; never scan the filesystem |
| Buffer changes | Update debounced in-memory tokens; current editor updates immediately |
| File saves or changes externally | Reparse that file and persist its token set |
| File is created, removed, or renamed | Add, remove, or move its contribution |
| App regains focus or watcher loses events | Reconcile filesystem state |
| Last workspace consumer closes | Stop watching and release service after an idle interval |

Background reconciliation discovers additions and deletions and compares fingerprints. Modification time and size provide fast checks, not absolute proof of unchanged content. Use hashes when validating uncertain files; provide a full rebuild path.

Publish partial results during initial indexing. Show current-buffer suggestions immediately and indicate “Indexing workspace…” or partial coverage when appropriate. Disclose scan limits and skipped inaccessible files; never present capped results as complete.

Reuse existing discovery exclusions where appropriate, classify eligible Markdown consistently, and add explicit file-size and scan-budget limits. Watchers must coalesce changes and avoid following symlinks outside authorized scope.

Unsaved buffers replace, rather than add to, saved-file contributions. Deduplicate shared document buffers across tabs; the current editor's version takes precedence for its own suggestions. Closing an unsaved buffer without saving restores the disk contribution.

`/due`, `/schedule`, and the Priority commands work without a workspace index.

## Rendering and portability

The first implementation may keep metadata literal in both Edit and Read modes. Rich badges are optional follow-up work and must not become necessary to understand the file.

If badges are introduced, preserve caret editing and accessible text, and explicitly cover Read mode, Quick Look, and exports rather than implying universal styling. Plain-text fallback must always retain meaning.

## Implementation phases

1. **Grammar and extractor:** finalize token boundaries, normalization, priority values, task scope, and duplicate handling; build the single JS extractor and its JavaScriptCore bridge.
2. **Shared completion controller:** extract slash behavior with regression tests, then add `/due`, `/schedule`, the Priority commands, and current-buffer name suggestions.
3. **Workspaces:** add Open Workspace…, persisted security-scoped bookmarks, the workspace registry, and file-to-workspace membership.
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
- Open Workspace persists and restores bookmarks; a stale bookmark prompts re-selection.
- Open Folder, direct file opens, and the command-line tool never index or write into the folder.
- Files inside an open workspace join it; the deepest workspace wins; files outside every workspace get buffer-only suggestions.
- Overlapping workspaces index independently; symlink aliases share one service; symlinks outside the root are not followed.
- Nothing is written inside a workspace folder.
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
