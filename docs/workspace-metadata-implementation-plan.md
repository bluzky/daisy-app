# Workspace metadata implementation plan

Status: Phase 1 complete; Phases 2–6 planned. This plan implements [`workspace-metadata-proposal.md`](workspace-metadata-proposal.md) in independently testable phases. It does not imply a release or version bump.

## Sequencing

```text
1. Grammar and single extractor — complete
        ↓
2. Shared completion controller
        ↓
3. Open Workspace
        ↓
4. In-memory workspace index
        ↓
5. Persistent cache and lifecycle
        ↓
6. Integration, documentation, runtime validation
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

### Goal

Extract reusable completion behavior without changing slash-command behavior, then add local metadata providers.

### Tasks

1. Refactor `scripts/editor-bundle/src/slash.js` into generic controller/session code and slash-specific provider code.
2. Keep existing slash ranking, templates, submenus, insertion transactions, keyboard behavior, CSS compatibility, and smoke coverage intact.
3. Define provider contract:
   - trigger and syntax guard;
   - query and replacement range;
   - candidate source and ranking;
   - validation and application;
   - optional submenu/calendar presentation.
4. Add `#`, `@`, and `+` providers backed by live-buffer extraction.
5. Add top-level slash commands Priority: High, Priority: Medium, Priority: Low, and Priority: None, with no submenu, shown only on checkbox task lines.
6. Add `/due` and `/schedule` with injected-clock presets, a date chooser, and Clear. All field commands share one application path that inserts, replaces, or removes the field.
7. Do not add `p:`, `due:`, or `scheduled:` typing triggers.
8. Add versioned workspace-candidate API in `scripts/editor-bundle/src/api.js`; expose it through `daisy/Features/Editor/EditorHTML.swift` and `daisy/Features/Editor/EditorViewController.swift`.

### Required tests

- Existing slash commands, templates, ranking, keyboard navigation, and undo/redo.
- Entire active token gets replaced; one undoable transaction per accepted value.
- Escape, stale session, empty result, nonempty/multiple selection, and IME composition behavior.
- Blocked Markdown contexts and heading/list collisions.
- Date validation and deterministic presets with injected clock.
- `/due`, `/schedule`, Priority commands: task-line-only availability, existing-field updates, duplicate-field choice, Clear, cancel behavior, and unchanged top results for existing slash queries.
- Task completion preserves metadata; task continuation does not copy dates, priority, context, or project tokens.

### Exit criteria

- Existing slash-command test suite passes unchanged.
- Metadata providers work with no workspace index.
- No Swift round trip occurs per keystroke.

## Phase 3 — Open Workspace

### Goal

Make indexing opt-in: only folders opened with **File → Open Workspace…** become workspaces. Every other way of opening a folder or file keeps today's behavior.

### Tasks

1. Add a **File → Open Workspace…** command that presents the system folder picker; add a recent-workspaces list. Localize new strings in `en.lproj` and `zh-Hans.lproj`.
2. Persist each workspace as a security-scoped bookmark, reusing the bookmark resolution approach in `daisy/Features/Sidebar/BookmarkStore.swift`. A stale or unresolvable bookmark marks the workspace unavailable and offers re-selection; never fall back to path-only access.
3. Add `daisy/Features/WorkspaceMetadata/WorkspaceRegistry.swift`, keyed by canonical root (standardized, symlinks resolved), so equivalent opens share one service.
4. Use the workspace root as the navigator root for workspace windows. Leave `SidebarWorkspaceRegistry` in `daisy/Features/Sidebar/SidebarViewController.swift` and the Open Folder path unchanged.
5. Resolve membership for directly opened files in `daisy/Document/DocumentWindowController+DocumentOpening.swift`: a file inside open workspaces joins the deepest one; otherwise it gets current-buffer suggestions only.
6. Ensure Open Folder…, file opens, drag and drop, and the command-line tool never index, walk ancestors, or write into the folder.

### Required tests

- Bookmark persistence, restore across launch, and stale-bookmark re-selection.
- Deepest containing workspace wins; files outside every workspace get no workspace service.
- Symlink aliases resolve to one service; overlapping workspaces stay independent.
- Open Folder and direct file opens create no workspace and write nothing.

### Exit criteria

- One canonical root identifies one shared workspace service.
- Indexing starts only from Open Workspace…; Open Folder behavior is unchanged.

## Phase 4 — In-memory workspace index

### Goal

Aggregate saved-file and unsaved-buffer name metadata per resolved workspace.

### Tasks

1. Add root-scoped actor/service under `daisy/Features/WorkspaceMetadata/WorkspaceMetadataIndex.swift`.
2. Reuse Markdown discovery rules, exclusions, caps, and file classification from `daisy/Features/FileSearch/ProjectFileIndex.swift`.
3. Index only saved Markdown tags, contexts, and projects. Do not index dates or priorities.
4. Exclude hidden/pruned paths, oversized files, inaccessible files, and symlink targets outside the workspace root. Index overlapping workspaces independently.
5. Track per-file fingerprints, token counts, deterministic display spelling, and aggregate candidate counts.
6. Publish partial, versioned snapshots while initial scanning runs.
7. Query in-memory candidates only when user types; never scan filesystem during completion.
8. Add debounced unsaved-buffer overlays from `EditorViewController` and `daisy/Document/DocumentWindowController+EditSession.swift`.
9. Replace saved-file contribution with shared unsaved document contribution; restore disk data on discard/close.
10. Reuse one service across tabs and windows; release watcher/service after idle interval once last consumer closes. Apply an unsaved overlay to every open workspace containing the document.
11. Add coalesced directory watching and reconcile on focus or lost events.

### Required tests

- Initial partial results, save/external edit/create/rename/delete updates, and watcher reconciliation.
- Shared tabs do not duplicate counts.
- Unsaved overlay supersedes saved contribution and restores correctly.
- Scan limits, excluded paths, inaccessible files, overlapping workspaces, and symlink safety.

### Exit criteria

- Editors receive stable versioned candidate snapshots.
- Current editor reflects local unsaved metadata immediately.
- No filesystem scan occurs in completion path.

## Phase 5 — SQLite cache in the app container

### Goal

Persist disposable derived index data outside the workspace, with graceful fallback.

### Tasks

1. Add `WorkspaceIndexStore` under `daisy/Features/WorkspaceMetadata/` and isolate SQLite operations there.
2. Store one database per workspace at `<app container>/Library/Caches/WorkspaceIndex/<root-id>.sqlite`, with `<root-id>` derived from the canonical root path and volume identifier. Write nothing into the workspace folder.
3. Store schema/parser versions, root identity, safe workspace-relative paths, fingerprints, hashes, per-file tokens, and aggregates.
4. Validate cache as untrusted input; reject path escapes, corruption, relocated/incompatible roots, and schema/parser mismatch.
5. Load compatible candidates at workspace open, then reconcile in background. Treat a missing or system-purged cache as a rebuild.
6. Fall back to in-memory index on cache creation, reading, writing, or contention failure.
7. Implement the rebuild action, which recreates only that workspace's cache file; delete the cache file when a workspace is removed from the recent list.
8. Re-key or rebuild the cache when a workspace bookmark resolves to a moved root.
9. Link the system SQLite library in `daisy.xcodeproj/project.pbxproj` and `tests/swift-tests/Package.swift` if needed.

### Required tests

- Cached reopen, incompatible schema/parser rebuild, cache corruption, system purge, root relocation, path validation, write failure, contention, and cache-only rebuild.
- Persistent-cache-disabled fallback.
- No file is created inside the workspace; cache directory is excluded from watcher feedback.

### Exit criteria

- Cache is optional and disposable.
- Persistent cache failure never blocks editing or completion.
- Daisy writes nothing into workspace folders.

## Phase 6 — Integration, docs, and runtime validation

### Goal

Ship coherent behavior with accurate documentation and end-to-end validation.

### Tasks

1. Subscribe editor completion providers to workspace index snapshots.
2. Display nonblocking indexing/partial-coverage state and disclose scan limits/skipped inaccessible files.
3. Add "Rebuild Workspace Index" UI/action for the current workspace.
4. Update `README.md`, samples, and behavior comments only after final behavior exists.
5. Review Quick Look and export implications before adding any rich metadata badges. Initial release may render literal metadata only.
6. Perform runtime tests for keyboard navigation, mouse selection, VoiceOver labels/selection state, date chooser cancel/accept, two-tab overlays, Open Workspace and recent workspaces, Open Folder staying unindexed, overlapping workspaces, stale bookmarks, synced folders (nothing written), large workspaces, and cache corruption.

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
| Slash refactor regresses mature editor behavior | Preserve existing tests first; extract controller without changing ranking or templates; gate Phase 2 on old smoke suite. |
| Indexing surprises users or broadens access | Index only folders chosen through Open Workspace…; no ancestor walk; access only through picker-granted bookmarks. |
| Workspace files leak into git or sync | Write nothing into workspace folders; keep the cache in the app container. |
| Multiple tabs double-count metadata | Workspace service owns one document overlay per shared document identity. |
| SQLite cache corrupts, cannot write, or is purged | Treat cache as untrusted/disposable; transactional store; memory fallback; rebuild on absence. |
| Filesystem watcher misses changes | Coalesce watcher events and reconcile on focus/lost-event conditions. |
| Rich presentation harms portability | Keep metadata literal initially; require separate Read mode, Quick Look, export, caret, and accessibility scope before badges. |
