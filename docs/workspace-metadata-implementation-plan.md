# Workspace metadata implementation plan

Status: Phases 1, 2 (2a, 2c, 2b), 3, 4, 4.5, and 5 complete; 6 in progress (tasks 1–5 done, runtime tests pending). This plan implements [`workspace-metadata-proposal.md`](workspace-metadata-proposal.md) in independently testable phases. It does not imply a release or version bump.

## Sequencing

```text
1. Grammar and single extractor — complete
        ↓
2. Shared completion controller (2a → 2c → 2b) — complete
        ↓
3. Workspace marker and window scope — complete
        ↓
4. In-memory workspace index — complete
        ↓
4.5 Metadata links and pages — complete
        ↓
5. Persistent cache and lifecycle — complete
        ↓
6. Integration, documentation, runtime validation — in progress
```

Do not begin a later phase until its predecessor has passing automated tests. Phase 5 can begin only after Phase 4 has stable index semantics.

## Phase 1 — Grammar and single extractor

### Goal

Define one metadata grammar with one implementation, in JavaScript, that both the editor and the Swift indexer run.

### Tasks

1. Add a fixture corpus at `tests/fixtures/workspace-metadata.json`.
2. Specify token boundaries and a shared normalization algorithm.
3. Add the extractor in `scripts/editor-bundle/src/workspace-metadata.js`, importing only `@lezer/markdown` and its GFM extensions (no `@codemirror/view`, no DOM). Expose `extractMetadata(markdown)`.
4. Add a second esbuild output in `scripts/editor-bundle/build.mjs` (for example `daisy/Vendor/CodeMirror/metadata-extract.min.js`) and include it in the app bundle the same way as `mdedit.min.js`.
5. Add `daisy/Features/WorkspaceMetadata/WorkspaceMetadataExtractor.swift`, which loads that bundle into JavaScriptCore and calls `extractMetadata`, following `daisy/Rendering/CodeHighlighter.swift`. Support a small bounded pool of contexts for parallel indexing.
6. Add JavaScript fixture tests and register the new section in the list in `scripts/editor-bundle/smoke-test.mjs`.
7. Add bridge tests to `tests/swift-tests/Tests/MarkdownHelpersTests/WorkspaceMetadataExtractorTests.swift`, with source links under `tests/swift-tests/Sources/MarkdownHelpers/`, asserting the bridge reproduces every fixture.

### Required fixture coverage

- Tags, contexts, projects, hierarchy segments, Unicode, composed/decomposed forms, source spelling, occurrence counts.
- Task-marker-line-only `due:`, `scheduled:`, and `p:` fields.
- Priority values: `high`, `medium`, `low`.
- ISO dates, leap years, invalid dates, duplicate and malformed fields.
- Headings, list markers, emails, `C#`, URL fragments, links, images, HTML, frontmatter, code, fenced code, tables, and trailing punctuation.
- Unknown fields and malformed metadata preserved as ordinary text.

### Exit criteria

- Every fixture passes in the editor and through the JavaScriptCore bridge.
- No Swift reimplementation of metadata extraction exists.
- Parser does not mutate document content.
- Existing editor behavior unchanged.

## Phase 2 — Shared completion controller

Phase 2 ships in three parts, run in the order **2a → 2c → 2b**. Each part has passing tests before the next begins. 2c comes before 2b because slash commands reuse the existing `/` trigger, while 2b adds new triggers.

### Phase 2a — Extract the controller

Status: complete. The controller is `scripts/editor-bundle/src/completion.js`; the slash provider stays in `scripts/editor-bundle/src/slash.js`.

#### Goal

Split the slash menu into a reusable completion controller and a slash provider, with no change in behavior.

#### Tasks

1. Refactor `scripts/editor-bundle/src/slash.js` into generic controller/session code and slash-specific provider code.
2. Keep existing slash ranking, templates, submenus, insertion transactions, keyboard behavior, CSS compatibility, and smoke coverage intact.
3. Define provider contract:
   - trigger and syntax guard;
   - query and replacement range;
   - candidate source and ranking;
   - validation and application;
   - optional submenu/calendar presentation.

#### Required tests

- Existing slash commands, templates, ranking, keyboard navigation, and undo/redo, unchanged.

#### Exit criteria

- Existing slash-command test suite passes without edits to its assertions.
- No user-visible change.

### Phase 2c — Field slash commands

Status: complete. Field definitions shared with the extractor are in `scripts/editor-bundle/src/task-fields.js`; the single application path is `scripts/editor-bundle/src/task-field-commands.js`; tests are in `scripts/editor-bundle/smoke/task-field-commands.mjs`.

#### Goal

Set priorities and dates from the slash menu on checkbox task lines.

#### Tasks

1. Add top-level slash commands Priority: High, Priority: Medium, Priority: Low, and Priority: None, with no submenu, shown only on checkbox task lines.
2. Add `/due` and `/schedule`, which open a date picker directly (no preset submenu), plus Clear Due Date and Clear Schedule shown only when the task has that date.
3. Route all field commands through one application path that inserts, replaces, or removes the field.
4. Do not add `p:`, `due:`, or `scheduled:` typing triggers.

#### Required tests

- Task-line-only availability, existing-field updates, duplicate-field choice, Clear, and cancel behavior.
- Date validation and a deterministic picker (today, day/week/month steps) with injected clock.
- One undoable transaction per accepted value.
- Unchanged top results for existing slash queries.
- Task completion preserves metadata; task continuation does not copy dates or priority.

#### Exit criteria

- Field commands work with no workspace index.
- Values written by commands round-trip through the Phase 1 extractor.

### Phase 2b — Tag, context, and project suggestions

Status: complete. The provider is `scripts/editor-bundle/src/metadata-completion.js` (editor module and Settings toggle `metadata-completion`, "Metadata suggestions"); name rules shared with the extractor are in `scripts/editor-bundle/src/metadata-names.js`; the snapshot API is `setWorkspaceCandidates` in `scripts/editor-bundle/src/api.js`; tests are in `scripts/editor-bundle/smoke/metadata-completion.mjs`. Swift does not call `setWorkspaceCandidates` yet (Phase 4).

#### Goal

Suggest `#`, `@`, and `+` names while typing, from the current document and from host-supplied workspace candidates.

#### Tasks

1. Add `#`, `@`, and `+` providers backed by live-buffer extraction.
2. Add the versioned workspace-candidate API in `scripts/editor-bundle/src/api.js`: the host passes a candidate snapshot with a version number, and the editor ignores snapshots older than the one it holds. Test it with fixture snapshots; Swift wiring lands in Phase 4.
3. Merge live-buffer names with snapshot candidates; the current buffer's names take precedence for its own suggestions.

#### Required tests

- Entire active token gets replaced; one undoable transaction per accepted value.
- Escape, stale session, empty result, nonempty/multiple selection, and IME composition behavior.
- Blocked Markdown contexts and heading/list collisions.
- Ranking: exact, prefix, hierarchy segment, usage frequency, lexical tie-break; unknown names list nothing and keep the typed text.
- Stale snapshot versions are ignored.
- Task continuation does not copy context or project tokens.

#### Exit criteria

- Suggestions work with no workspace index.
- No Swift round trip occurs per keystroke.

## Phase 3 — Workspace marker and window scope

Status: complete. The marker is `daisy/Features/WorkspaceMetadata/WorkspaceMarker.swift` (tests in `tests/swift-tests/Tests/MarkdownHelpersTests/WorkspaceMarkerTests.swift`); window state and the two commands are in `daisy/Document/DocumentWindowController+Workspace.swift`; the menu items are installed by `installWorkspaceMenuItems` in `daisy/App/AppDelegate.swift`. `indexedWorkspaceRootURL` is the root the Phase 4 index uses.

### Goal

Make indexing opt-in and window-scoped: a folder window whose root contains `.daisy/config.json` is a workspace window, along with the tabs, windows, and untitled documents created from it. A file opened from Finder, ⌘O, or Open Recent joins the frame of an open window whose folder contains it (see `bindToOpenWorkspace` in `daisy/Document/DocumentWindowController+DocumentOpening.swift`), and gets that window's workspace along with its project. Every other way of opening a folder or file keeps today's behavior. Membership never comes from walking a file's parent directories on disk; only open windows are consulted.

### Tasks

1. Add `daisy/Features/WorkspaceMetadata/WorkspaceMarker.swift`: `isWorkspace(root:)` checks only that `<root>/.daisy/config.json` is a file, without reading it; `initialize(root:)` creates `.daisy/` and writes `{"version": 1}` atomically, keeping an existing marker; `remove(root:)` deletes `config.json`, then `.daisy/` if nothing else is in it. Keep it free of AppKit so it links into `tests/swift-tests`.
2. In `AppDelegate.openFolder`, after the window takes the folder, set `isWorkspace` on the `DocumentWindowController` from `WorkspaceMarker.isWorkspace(root:)`. This covers File → Open…, Finder, drag and drop, the command-line tool, the OmniSearch and navigator Open Folder… buttons, and Reopen last session; persist nothing new in `LastSessionStore`. Leave the existing window-reuse rules and `SidebarWorkspaceRegistry` in `daisy/Features/Sidebar/SidebarViewController.swift` unchanged. Add no workspace registry.
3. Expose `indexedWorkspaceRootURL` from the window: the canonical `projectRootURL` (`SidebarWorkspace.canonicalURL`) when `isWorkspace`, otherwise nil. Phase 4 keys its shared index service on this value. File windows, whose navigator root is the file's parent, are never checked.
4. Add **File → Initialize Workspace** and **File → Remove Workspace** after Open Recent, installed in code by `AppDelegate` like OmniSearch…. Initialize is enabled in a folder window opened through `openFolder` whose root has no marker; Remove in a workspace window. Each updates every open folder window on that root. A failed write shows an error and changes nothing. Localize new strings in `en.lproj/Localizable.strings` and `zh-Hans.lproj/Localizable.strings`.
5. Carry `isWorkspace` only along the paths that already carry a window's project: `inheritProject(from:containing:)` (Open in New Tab / New Window for a file inside the root) and `prepareSidebarForUntitledDocument(from:)` (new untitled document), both in `daisy/Document/DocumentWindowController+Sidebar.swift`. Plain opens in `daisy/Document/MarkdownDocument.swift` (Finder, ⌘O, Open Recent, drag and drop, command-line tool) go through `bindToOpenWorkspace`, which calls `inheritProject` for the innermost open window containing the file, so they inherit a workspace only from such a window.
6. Re-check the marker when the app becomes active, so a marker deleted or added outside Daisy takes effect without reopening the window.
7. Ensure folder opens without a marker, file opens, drag and drop, and the command-line tool never set `isWorkspace`, never walk parent directories, and never write into the folder.

### Required tests

- Marker: present, absent, `.daisy` as a file, `config.json` as a folder, malformed or unknown content; a marker in a parent or a subfolder is not detected.
- Initialize writes only `.daisy/config.json` and keeps an existing one; Remove deletes the marker and keeps other files in `.daisy/`; a failed write leaves the folder unchanged.
- `indexedWorkspaceRootURL` canonicalization: symlink aliases and `..` forms give the same root; nested workspaces stay distinct.
- Membership: Open in New Tab/Window inside the root and untitled documents inherit the workspace; a file opened from outside joins the workspace of an open window containing it and gets none when no such window is open; a file window is never a workspace window.
- Reopen last session on a folder with a marker gives a workspace window.

### Exit criteria

- A workspace window comes only from a folder open with a marker at its root, Initialize Workspace, or inheritance from an open workspace window; no code path derives one from a file's location on disk.
- No workspace registry or new bookmark store.
- Folder-opening and file-opening behavior is unchanged for folders without a marker.

## Phase 4 — In-memory workspace index

Status: complete. The index is the `WorkspaceMetadataIndex` actor in `daisy/Features/WorkspaceMetadata/WorkspaceMetadataIndex.swift`; FSEvents watching is `WorkspaceDirectoryWatcher.swift` beside it; tests are `tests/swift-tests/Tests/MarkdownHelpersTests/WorkspaceMetadataIndexTests.swift` and `EditorWorkspaceCandidatesTests.swift`. Window binding and unsaved overlays are in `daisy/Document/DocumentWindowController+Workspace.swift`. Notes on what was built:

- One index per canonical root, shared through `acquire`/`release`. It holds a use count, not a weak reference, so it can outlive the last window for `idleReleaseInterval` (60 s) and a reopened window does not rescan.
- Discovery reuses `ProjectFileIndex.build`, so it uses the same pruned folders, depth and file caps. Files over 1 MiB, unreadable files, and files that are not UTF-8 are left out without being counted. A symlink is indexed under its target's path, so it is counted once, and only when the target is inside the root.
- Snapshot versions come from one counter shared by all indexes. A window that leaves a workspace sends its editor an empty snapshot, which is always newer than what the editor has.
- Unsaved text is sent to the index 0.5 s after typing stops, keyed by file and window. Only the most recent buffer for a file counts. When the window has no unsaved changes left (after a save or a discard), the file is read from disk again and the buffer is dropped.
- The editor page stores the last snapshot it accepted, the same way it stores slash templates, and uses it again for the next document loaded in that page.

### Goal

Aggregate saved-file and unsaved-buffer name metadata per resolved workspace.

### Tasks

1. Add root-scoped actor/service under `daisy/Features/WorkspaceMetadata/WorkspaceMetadataIndex.swift`, shared by `indexedWorkspaceRootURL` through a static weak lookup inside the service (this replaces a separate registry).
2. Reuse Markdown discovery rules, exclusions, caps, and file classification from `daisy/Features/FileSearch/ProjectFileIndex.swift`.
3. Index only saved Markdown tags, contexts, and projects. Do not index dates or priorities.
4. Exclude hidden/pruned paths, oversized files, inaccessible files, and symlink targets outside the workspace root. Index overlapping workspaces independently.
5. Track per-file fingerprints, token counts, deterministic display spelling, and aggregate candidate counts.
6. Publish partial, versioned snapshots while initial scanning runs.
7. Query in-memory candidates only when user types; never scan filesystem during completion.
8. Send workspace candidate snapshots to editors through the Phase 2b API, exposed via `daisy/Features/Editor/EditorHTML.swift` and `daisy/Features/Editor/EditorViewController.swift`.
9. Add debounced unsaved-buffer overlays from `EditorViewController` and `daisy/Document/DocumentWindowController+EditSession.swift`.
10. Replace saved-file contribution with shared unsaved document contribution; restore disk data on discard/close.
11. Reuse one service across the workspace windows on a root; release watcher/service after an idle interval once the last one closes. Apply an unsaved overlay to the workspace of the window editing the document; other workspaces pick up the change on save.
12. Add coalesced directory watching and reconcile on focus or lost events.

### Required tests

- Initial partial results, save/external edit/create/rename/delete updates, and watcher reconciliation.
- Shared tabs do not duplicate counts.
- Unsaved overlay supersedes saved contribution and restores correctly.
- Scan limits, excluded paths, inaccessible files, overlapping workspaces, and symlink safety.

### Exit criteria

- Editors receive stable versioned candidate snapshots.
- Current editor reflects local unsaved metadata immediately.
- No filesystem scan occurs in completion path.

## Phase 4.5 — Metadata links and pages

Status: complete. Pages are `daisy/Features/WorkspaceMetadata/WorkspacePage.swift`; every link opens through `LinkHandler.open` (`daisy/Document/LinkHandler.swift`) with a `LinkTarget` (`daisy/Document/LinkTarget.swift`); Read mode is the `metadata-links` render extension in `daisy/Rendering/MarkdownRenderExtension.swift`; the editor is `scripts/editor-bundle/src/metadata-links.js` (module and Settings toggle "Metadata links") and `scripts/editor-bundle/src/link-open.js` (Cmd+click). Tests are `WorkspacePageTests.swift`, the `metadata-links` cases in `MarkdownRenderExtensionTests.swift`, and `scripts/editor-bundle/smoke/metadata-links.mjs`. Differences from the tasks below:

- Read mode sends a clicked token to the host as an `openMetadata` bridge message instead of a `daisy-metadata:` link, so tokens are never `<a>` elements and add no link annotations to PDFs. The script wraps tokens only while the page has `data-mdp-workspace`, and removes the wrapping when it is cleared.
- The editor does not open `#section` links on Cmd+click: the preview they would scroll is hidden while editing.

### Goal

Make each tag, context, and project in a workspace window a link to its page: a Markdown file in the workspace's `pages/` folder, created on first open. Read mode opens it with a click; the editor opens it, and any Markdown link, with Cmd+click.

### Behavior

- **Scope.** Links exist only in a workspace window (`indexedWorkspaceRootURL` is non-nil). Elsewhere, metadata shows as it does today. Quick Look and exports show the literal text.
- **Page location.** `<root>/pages/<marker><name>.md`, flat, with no subfolders. The marker stays in the file name, so `#daisy`, `@daisy`, and `+daisy` open three different pages: `#daisy.md`, `@daisy.md`, and `+daisy.md`. Each `/` in a hierarchical name becomes `--`, so `#area/sub` opens `pages/#area--sub.md`. Names may contain `-`, so `#area--sub` and `#area/sub` share a page.
- **Lookup.** Case is ignored: the file name is compared with the extractor's `normalizedKey`, so `#Review` opens an existing `pages/#review.md`. When more than one file matches, the order is: exact spelling first, then lexical order.
- **Creation.** When no page exists, create `pages/` if needed and write the page holding `# <label>\n`. `<label>` is the token as written, marker included, with `/` kept: `#Review` gives `# #Review`, and `#area/sub` gives `# #area/sub`. The write is atomic and never replaces an existing file. If the write fails, show an error and leave the document as it was.
- **Opening.** A page opens the way a clicked local Markdown link does (`onOpenMarkdownLink`): in the same window, so it joins the workspace through the existing `inheritProject` path.
- **Writes into the workspace.** Opening a page that doesn't exist yet is the only action that writes into the workspace, apart from the marker. It happens only on an explicit click; indexing, rendering, and completion still never write. The new page reaches the index through the directory watcher like any other file.

### Tasks

1. Add `daisy/Features/WorkspaceMetadata/WorkspacePage.swift`, free of AppKit so it links into `tests/swift-tests`. It provides `resolve(name:root:) -> URL?` and `openOrCreate(name:label:root:) throws -> URL`. Validate the name with the extractor's rules before building a path: a valid name has no `.` or path separator after the `/` → `--` mapping, and the resolved path, symlinks included, must stay inside `<root>/pages/`.
2. Add `LinkHandler.open(_ link:in:)` in `daisy/Document/LinkHandler.swift`, the one place that opens links. `Link` is an enum: `.external(URL)`, `.file(URL, fragment:)`, `.section(String)`, `.metadata(token:)` (the token as written, marker included). `open` switches on it. Markdown files open in Daisy (`onOpenMarkdownLink`), other files in their default app, web links through `ExternalLinkOpener`, sections scroll the current document, and metadata calls `WorkspacePage.openOrCreate` and then opens the page as a Markdown file. It takes the window controller for scrolling, the workspace root, and error sheets. Read mode, the inspector, and the editor each build a `Link` and call it. `activateLink` in `daisy/Rendering/MarkdownWebView.swift` and `openInspectorLink` in `daisy/Document/MainSplitViewController.swift` keep only the conversion to `Link`; their dispatch code moves into `LinkHandler` with no visible change. In Read mode, metadata tokens use the link form `daisy-metadata:<percent-encoded token>`.
3. **Read mode:** add a `metadata-links` render extension next to `TaskMetadataExtension` in `daisy/Rendering/MarkdownRenderExtension.swift`. Enable it only when the render context has a workspace root. Its script wraps `#`/`@`/`+` tokens in `<a class="mdp-metadata-link" href="daisy-metadata:…">` and skips the same literal content as `taskMetadataScript` (code, links, `kbd`, KaTeX, Mermaid). It mirrors the rules in `metadata-names.js`. `activateLink` turns the `daisy-metadata` scheme into `.metadata`, and the link context menu leaves out "Copy Link" for it.
4. **Editor, metadata:** in a workspace window, give `#`/`@`/`+` tokens a link-style mark decoration, taken from the extractor's ranges. A plain click still places the caret. Cmd+click on a token sends a new `openLink` bridge message to `EditorViewController` and prevents CodeMirror's default Cmd+click (adding a cursor). The host turns the decoration on and off with the window's workspace state, in the same way `setWorkspaceCandidates` is driven.
5. **Editor, Markdown links:** Cmd+click on a `Link` node that has a URL, or on an autolink or bare URL, sends `openLink` with the raw destination. Swift builds the `Link` with `DocumentLink.target(relativeTo:)`, as the inspector does, and calls `LinkHandler.open`. This works in every window, workspace or not. Cmd+click anywhere else keeps today's behavior.
6. Hovering a link or token in the editor underlines it; while Cmd is held, it also shows the pointer cursor.
7. Localize the new strings (the error for a failed page write, and accessible names) in `en.lproj` and `zh-Hans.lproj`.

### Required tests

- `WorkspacePage`: an existing page; a case- or Unicode-variant match; the same name with different markers gives different pages; `/` → `--` mapping; the H1 keeps the marker; an existing file is never overwritten; a failed write leaves nothing behind; a symlink from `pages/` to outside the root is refused.
- Read mode script: tokens become links only where the extractor finds metadata (replay the fixture corpus); no links without a workspace root; Quick Look and export output unchanged.
- Editor smoke tests: Cmd+click on a token or link posts one `openLink` with the expected payload; a plain click only moves the caret; Cmd+click elsewhere is unchanged; no link decoration when the workspace state is off.
- `LinkHandler`: each case opens the right way; a relative, absolute, fragment-only, non-Markdown, or external destination from the editor builds the same `Link` as the inspector; Read mode and inspector clicks behave as before the move.

### Exit criteria

- Clicking a token in Read mode, or Cmd+clicking it in the editor, opens the same page, creating it with its H1 only when none exists.
- Cmd+click on a Markdown link in the editor goes where clicking it in Read mode goes.
- Nothing is written into the workspace except the marker and pages the user explicitly opens.

## Phase 5 — SQLite cache in the app container

Status: complete. The store is the `WorkspaceIndexStore` actor in `daisy/Features/WorkspaceMetadata/WorkspaceIndexStore.swift`, the only file with SQLite calls; `WorkspaceMetadataIndex` loads it before its first scan and saves changed files to it. The parser version is the SHA-256 of the extractor script (`WorkspaceMetadataExtractor.parserVersion`). Tests are `tests/swift-tests/Tests/MarkdownHelpersTests/WorkspaceIndexStoreTests.swift`. Differences from the tasks below:

- Aggregates are not stored. They are summed from the per-file rows on load, so they cannot disagree with them.
- A file whose size or date changed but whose SHA-256 matches its row keeps its names without running the extractor.
- A moved root is rebuilt, not re-keyed: its path gives it a new `<root-id>`, and a file copied to that id names the old root, so it is rejected. The old file is deleted by the 30-day purge.
- A cache folder inside the workspace is not used, so the cache never produces watcher events.
- A store that fails or is held by another connection past 200 ms is dropped for the life of that index, which carries on in memory. `rebuildCache` tries again. After Remove Workspace, an index that is still held writes no cache until it is released.
- `WorkspaceMetadataIndex.rebuildCache(root:)` is the rebuild action; the menu item and indexing status are Phase 6.
- No project or package change was needed: `import SQLite3` links the system library.

### Goal

Persist disposable derived index data outside the workspace, with graceful fallback.

### Tasks

1. Add `WorkspaceIndexStore` under `daisy/Features/WorkspaceMetadata/` and isolate SQLite operations there.
2. Store one database per workspace at `<app container>/Library/Caches/WorkspaceIndex/<root-id>.sqlite`, with `<root-id>` derived from the canonical root path and volume identifier. Write nothing into the workspace folder.
3. Store schema/parser versions, root identity, safe workspace-relative paths, fingerprints, hashes, per-file tokens, and aggregates.
4. Validate cache as untrusted input; reject path escapes, corruption, relocated/incompatible roots, and schema/parser mismatch.
5. Load compatible candidates at workspace open, then reconcile in background. Treat a missing or system-purged cache as a rebuild.
6. Fall back to in-memory index on cache creation, reading, writing, or contention failure.
7. Implement the rebuild action, which recreates only that workspace's cache file; delete the cache file on Remove Workspace; at launch, delete cache files not opened for 30 days.
8. Re-key or rebuild the cache when a workspace bookmark resolves to a moved root.
9. Link the system SQLite library in `daisy.xcodeproj/project.pbxproj` and `tests/swift-tests/Package.swift` if needed.

### Required tests

- Cached reopen, incompatible schema/parser rebuild, cache corruption, system purge, root relocation, path validation, write failure, contention, and cache-only rebuild.
- Persistent-cache-disabled fallback.
- The cache creates no file inside the workspace (the marker and Phase 4.5 pages are the only workspace writes); cache directory is excluded from watcher feedback.

### Exit criteria

- Cache is optional and disposable.
- Persistent cache failure never blocks editing or completion.
- Daisy writes nothing into workspace folders except the marker and pages the user explicitly opens (Phase 4.5).

## Phase 6 — Integration, docs, and runtime validation

Status: tasks 1–5 done; task 6, the runtime test pass, is pending. Notes on what was built:

- Task 1 was already in place from Phase 4: each workspace window subscribes to its index's snapshots and forwards them to its editor.
- Snapshots sent to the editor carry `indexing` (the first scan is still running) and `truncated` (the scan stopped at the file cap). The `#`/`@`/`+` menu shows either as a note under its rows (`footer` in `completion.js`, `role="status"`), so the note appears only when there are suggestions to qualify; it is never a selectable row. The note names no number because `MarkdownRenderExtension.swift` is also built into Quick Look, which has no `ProjectFileIndex`; README.md states the limits.
- **File → Rebuild Workspace Index** calls `WorkspaceMetadataIndex.rebuildCache(root:)`; it is enabled while the window holds an index.
- Task-metadata badges were re-checked: the `task-metadata` extension renders them in Read mode and the editor, and Quick Look and exports stay literal.

### Goal

Ship coherent behavior with accurate documentation and end-to-end validation.

### Tasks

1. Subscribe editor completion providers to workspace index snapshots.
2. Display nonblocking indexing/partial-coverage state and disclose scan limits.
3. Add "Rebuild Workspace Index" UI/action for the current workspace.
4. Update `README.md`, samples, and behavior comments only after final behavior exists.
5. Task metadata badges render in the editor and Read mode (`task-metadata` render extension); Quick Look and exports stay literal. Re-check this when wiring Phase 6 runtime tests.
6. Perform runtime tests for keyboard navigation, mouse selection, VoiceOver labels/selection state, date chooser cancel/accept, two-tab overlays, Initialize and Remove Workspace, marker detection on every folder-open route including last-session restore, folders without a marker staying unindexed, a Finder-opened file joining an open workspace window that contains it and staying plain when none is open, overlapping workspaces, unresolvable bookmarks, synced folders (nothing written but the marker and explicitly opened pages), metadata link click and Cmd+click in both modes, page creation, large workspaces, and cache corruption.

### Exit criteria

- Documentation matches shipped behavior.
- Metadata remains readable outside Daisy.
- No release/version bump unless separately requested.

## Verification commands

Run after relevant implementation changes:

```bash
cd scripts/editor-bundle && npm test
swift test --package-path tests/swift-tests
xcodebuild -project daisy.xcodeproj -scheme daisy -configuration Debug build
```

Run targeted JS and Swift tests during each phase. Before merge, run all commands above and inspect modified `daisy.xcodeproj/project.pbxproj` for unintended signing changes.

## Key risks

| Risk | Mitigation |
| --- | --- |
| Index and editor disagree on what is metadata | One JS extractor run in both hosts; bridge tests replay the fixture corpus. |
| JavaScriptCore throughput limits initial indexing | Bounded context pool; partial snapshots; incremental reparse after the first pass. |
| Slash refactor regresses mature editor behavior | Preserve existing tests first; extract controller without changing ranking or templates; ship Phase 2a alone, gated on the unchanged smoke suite. |
| Indexing surprises users or broadens access | Index only folder windows whose root has the marker; check only the opened root; workspaces bind to windows, and a file joins one only through an open window; indexing only reads. |
| A cloned repository's marker starts indexing unasked | The marker can only turn on read-only indexing with local storage; scan limits and progress state bound the cost; Remove Workspace turns it off. |
| Workspace files leak into git or sync | The marker holds only a version and is safe to commit; keep the cache and all per-user state in the app container. |
| Multiple tabs double-count metadata | Workspace service owns one document overlay per shared document identity. |
| SQLite cache corrupts, cannot write, or is purged | Treat cache as untrusted/disposable; transactional store; memory fallback; rebuild on absence. |
| Filesystem watcher misses changes | Coalesce watcher events and reconcile on focus/lost-event conditions. |
| Rich presentation harms portability | Badges are presentation only: the Markdown is unchanged, Quick Look and exports show literal text, the caret reveals the source, and each badge has an accessible name. |
