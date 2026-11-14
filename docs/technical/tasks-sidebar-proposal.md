# Tasks sidebar proposal

Status: Implemented, including the optional filter menu (without Group by File) and Upcoming section. README.md describes the behavior for readers; this document keeps the design reasoning.

## Summary

Replace the Inspector, the right-hand pane, with a **Tasks** sidebar: a month calendar of the workspace's dated tasks, plus a list of what is scheduled, due or overdue on the chosen day. Tasks can be checked off from the list.

This is not a journal calendar. The toolbar's Journal popover stays as it is. The Tasks sidebar is about the `scheduled:` and `due:` fields on checkbox tasks (see [workspace metadata](workspace-metadata-proposal.md#dates-and-priorities)):

```markdown
- [ ] Review proposal +daisy @alex p:high scheduled:2026-10-20 due:2026-10-23
```

## Goals and scope

- See which days have scheduled or due tasks, and what is overdue, across the whole workspace.
- Open the file a task lives in, at the task.
- Check a task off, or back on, without opening its file.
- Only in workspace windows: the data comes from the workspace index.
- Not in this proposal: rescheduling by dragging, a `done:` completion date, recurrence, reminders, week view.

This reverses two decisions in the workspace metadata proposal: "Support scheduled and due dates without a task dashboard" and "Dates and priorities stay out of the workspace index". Both statements must be updated in the same change that adds the sidebar.

## Removing the Inspector

The Inspector shows word count, modification date, the document's links and its frontmatter. It isn't needed for now, and its pane is where the Tasks sidebar goes.

- Keep the right `NSSplitViewItem(inspectorWithViewController:)` in `MainSplitViewController`, along with its collapse, autosave and toggle plumbing, and give it `TaskCalendarViewController` in place of `InspectorViewController`.
- View → Inspector becomes **View → Tasks** and keeps ⇧⌘I. The toolbar's Inspector item becomes a **Tasks** item (`checklist` symbol).
- Keymap: add `KeymapCommand.viewToggleTasks = "view.toggleTasks"`. `view.toggleInspector` can't be an enum case: `Keymap` would show it in Settings → Shortcuts, and with no case, `KeymapCommand(rawValue:)` rejects it as "Unknown command" (`Keymap.swift:413`), which drops the user's binding.
  - Add a `KeymapCommand.legacyAliases: [String: KeymapCommand]` table, `["view.toggleInspector": .viewToggleTasks]`.
  - While loading the keymap file, map each `commandID` through the table **before** the enum lookup, so an old binding loads as the new command with no diagnostic.
  - The alias appears nowhere else: not in `allCases`, the Settings list, defaults, or conflict reporting.
  - When Settings writes the keymap file back, it writes the new ID.
  - Tests: a keymap file binding `view.toggleInspector` loads as `.viewToggleTasks` with no diagnostic, and the old ID is absent from the Settings command list.
- Delete `InspectorView.swift` and `InspectorViewController.swift` (and `DocumentMetadata` if nothing else uses it). Keep `DocumentLinks.swift`, which the editor's Cmd+click and `LinkTarget` use, and move it to `daisy/Document/`.
- Remove the Inspector strings from `en` and `zh-Hans`.
- Users who left the Inspector open have a saved split state. Collapse the new pane once on first launch, using a defaults key.
- `addJournalToolbarItemIfNeeded` inserts the Journal item before `.inspector`. That becomes the Tasks item, or `.share`.

## Sidebar UI

Shown at the minimum width, 270 pt.

### Default: opens on today

```
┌──────────────────────────────────┐
│ Tasks                    Today ⌄ │  header: title + filter menu
├──────────────────────────────────┤
│  ‹       October 2026        ›   │
│                                  │
│   M    T    W    T    F    S    S│
│             1    2    3    4    5│
│   6    7    8    9   10   11   12 │
│        ·                  ·      │
│  13   14   15   16   17   18   19 │
│   ·              ·         ▴     │
│  20  (21)  22   23   24   25   26 │
│   ·    ·    ·    ▴               │
│  27   28   29   30   31          │
│             ·                    │
├──────────────────────────────────┤
│ ▾ OVERDUE                     2  │  red label; only on today
│   ○ Send invoice to Acme         │
│     ▴ Oct 18 · work.md           │
│   ○ Reply to Linh @alex          │
│     ▴ Oct 19 · inbox.md          │
│                                  │
│ ▾ TODAY · WED 21              3  │
│   ○ Review proposal +daisy   !!  │  !! = p:high
│     ◷ scheduled · 2026-10-20.md  │
│   ○ Draft release notes          │
│     ◷ scheduled · release.md     │
│   ○ Ship 1.8 build           !   │
│     ▴ due · daisy.md             │
│                                  │
│ ▸ UPCOMING · NEXT 7 DAYS      4  │  collapsed
└──────────────────────────────────┘
  ·  scheduled that day     ▴  due that day (red when overdue)
 (21) today, accent ring     ○  open task
```

### Another day selected

```
├──────────────────────────────────┤
│  ‹       October 2026        ›   │
│  ...                             │
│  20  (21)  22  [23]  24   25   26 │  [23] = selected, filled accent
│   ·    ·    ·    ▴               │
├──────────────────────────────────┤
│ FRIDAY, OCTOBER 23            2  │
│                                  │
│ Due                              │
│   ○ Review proposal +daisy   !!  │
│     daisy/proposal.md            │
│ Scheduled                        │
│   ○ Book flights                 │
│     personal.md                  │
│                                  │
│               Back to Today ↩    │
└──────────────────────────────────┘
```

### Hovered or focused row

```
│   ○ Review proposal +daisy   !!  │
│ ┌──────────────────────────────┐ │
│ │○ Draft release notes         │ │  row highlight
│ │  ◷ scheduled · release.md  ↗ │ │  ↗ = open file at line
│ └──────────────────────────────┘ │
│   ○ Ship 1.8 build           !   │
```

Right-clicking a row gives Open, Open in New Tab, Reveal in Files and Copy Task Text.

### Empty day, indexing, outside a workspace

```
│ SATURDAY, OCTOBER 24             │     │ ▾ TODAY · WED 21              1  │
│                                  │     │   ○ Review proposal +daisy   !!  │
│           ◷                      │     │                                  │
│     Nothing scheduled or due     │     │   ⟳ Indexing workspace…          │
│   Add dates to tasks with        │
│   /schedule or /due              │

┌──────────────────────────────────┐
│ Tasks                            │
├──────────────────────────────────┤
│              ☑                   │
│   Tasks are available in a       │
│   workspace.                     │
│     [ Initialize Workspace ]     │
└──────────────────────────────────┘
```

Outside a workspace the toggle and menu item are disabled with the same reason in their tooltip. The panel above only appears if the pane was already open, restored from the split state all windows share; then the toggle and menu item stay enabled so the pane can be closed.

### Filter menu

```
┌──────────────────────────┐
│ ✓ Scheduled              │
│ ✓ Due                    │
│ ──────────────────────── │
│   Show Completed         │
│ ✓ Show Overdue           │
│ ──────────────────────── │
│   Group by Day     ✓     │
│   Group by File          │
└──────────────────────────┘
```

The filter menu and the Upcoming section are optional for a first version.

### Layout and interaction notes

- **Grid:** cells stretch to the pane's width, never below 30 pt. Each day has at most one scheduled dot and one due triangle. The counts go in the accessibility label: "Wednesday, October 23, 2 due, 1 scheduled".
- **Task rows:** two lines. The first is the task text, truncated with a tail ellipsis, with `+project` and `@context` in the theme accent and priority on the right. The second is secondary text showing the date type and file name, with the full path in the tooltip.
- **List:** open tasks only by default. Within a group, sort by priority (high, medium, low, none), then by date, file path and line.
- **Completed tasks** (`- [x]`), with Show Completed off (the default):
  - They appear nowhere: no calendar marker, no row, no count.
  - A task checked from the sidebar stays as a struck-through row only for its ~2 s grace period, then leaves.
- **Completed tasks, with Show Completed on:**
  - **Never Overdue.** Overdue holds only open tasks whose `due:` is before today. A checked task with a past due date sits under its own day and nowhere else.
  - **Rows:** each sits in the day groups for its `scheduled:` and `due:` dates, as an open task does, but after all open tasks in that group, struck through in secondary color, in the same sort order. It keeps its marker so it can be unchecked.
  - **Calendar markers:** checked tasks use a hollow dot or triangle in secondary color. A day whose tasks are all done shows only hollow markers; a day with any open task shows the filled accent marker.
  - **Counts:** group counts and accessibility labels count open tasks, with done tasks separate: "2 due, 1 done".
  - **Upcoming:** lists only open tasks, whatever the setting.
- **Undated tasks** never appear: a task has to have `scheduled:` or `due:`. A task with both shows in both days' groups. Today's group shows it once, under Due.
- **Clicking the text** opens the file and scrolls to the task. Before building this, check whether Read and Edit Mode already have a way to scroll to a line; the outline's heading scroll may be reusable.
- **Keyboard:** Tab moves between the grid and the list. Arrows move inside each, Return opens, Space checks the selected task, and ⌘T jumps to today.
- **Day change:** the sidebar listens for `NSCalendarDayChanged` so today and Overdue move at midnight.
- **Grid code:** pull the month grid out of `JournalCalendarView` so both calendars share it. The Journal popover keeps its current behavior.

## Data: extending the workspace index

`WorkspaceMetadataIndex` already scans the workspace, watches it, counts unsaved buffers in place of their files, caches to SQLite outside the folder, and serves every window on a root. Its extractor already returns `tasks: [WorkspaceTaskMetadata]` with `line`, `due`, `scheduled` and `priority` for each file. `WorkspaceMetadataContribution.init(_:)` then drops them and keeps only tags, contexts and projects. Four changes:

1. **Extractor:** each task also returns `text` (the task line without the list marker, checkbox and fields) and `checked`. Change `scripts/editor-bundle/src/workspace-metadata.js` and the Swift decoder, then rebuild `workspace-metadata.min.js`. The parser version changes with the script, which already triggers a cache rebuild.
2. **Index:** keep each file's tasks next to its names. Tasks belong to one file, so they are stored per file, not added up like name counts. Unsaved buffers count through the existing overlay path, so the calendar updates as you type.
3. **Cache:** a `tasks(path, line, text, checked, due, scheduled, priority)` table, removed with its file row, plus a `schemaVersion` bump.
   - The cache can't be skipped. On reopen, `reconcileOnce` re-reads only files whose modification date or size changed. If tasks aren't cached, every unchanged file comes back with no tasks.
   - The alternative is re-reading every file (up to 20,000) on every open, which undoes the cache's purpose.
4. **Hand-off:** an on-demand `index.tasks()` plus a separate change signal. The sidebar fetches only while it is visible.
   - Tasks don't go into `WorkspaceMetadataSnapshot`. That snapshot is sent to every editor's JavaScript for completion, so each keystroke would push every task into every editor.
   - The task signal has to bypass `publish()`. `publish()` sends nothing unless names, counts or scan state changed (`WorkspaceMetadataIndex.swift:236`), so editing only a task's `due:`, `scheduled:`, checked state or text would never reach the sidebar.
   - The index keeps a `taskRevision: Int` and a `taskChanges()` `AsyncStream<Int>` of its own. Whenever a file's task list differs from its previous one, it bumps the revision and yields. That covers:
     - a file read from disk (scan, watcher, Rebuild);
     - an overlay set or cleared (unsaved buffer edits, the editor closing);
     - a rename or delete;
     - a cache load;
     - the optimistic update after a direct write (below);
     - the first scan finishing.
   - Unchanged task lists don't bump the revision, so renaming a tag elsewhere in a file sends nothing. The sidebar fetches `index.tasks()` again when the revision changes and it is visible, or when it becomes visible with a revision it hasn't seen.

## Checking a task off

### What the reader sees

```
 before                      click ○                        ~2 s later
│ ○ Draft release notes   │ │ ● D̶r̶a̶f̶t̶ ̶r̶e̶l̶e̶a̶s̶e̶ ̶n̶o̶t̶e̶s̶   │ │ (row fades out)   │
│   ◷ scheduled·release.md│ │   ◷ scheduled·release.md│ │                   │

                  ┌───────────────────────────────────┐
                  │ ✓ Completed “Draft release…”  Undo │   bottom of pane, 5 s
                  └───────────────────────────────────┘
```

- Clicking the circle, or pressing Space, checks the task right away. The row leaves after about 2 s, and clicking it again in that time unchecks it.
- **Undo** in the banner, or ⌘Z with the pane focused while the banner shows, unchecks it the same way. Once the banner has gone, ⌘Z no longer undoes the check-off.
- If the write fails, the circle springs back and the row says why, for example: "release.md changed. Open to check it off."

### How it writes

```
click ○ ──► is the file open in any Daisy window?
              │
      ┌───────┴─────────────────────────┐
     yes                                no
      │                                  │
  in Edit Mode or has unsaved edits?   write it directly:
      │                                read → find line → flip → atomic
  ┌───┴────┐                           replace if unchanged since read
 no       yes
  │        │
 Read Mode  editor transaction:
 path that  flip the marker in the
 exists     buffer; it saves like any
 today      other edit
```

If the file's window has a save or an editor exit under way, wait for it first: a change made to the buffer or draft while a commit runs, or while the editor closes, would be overwritten when it finishes. Then:

1. **Open, nothing unsaved:** forward to that window's `toggleTaskCheckbox(onLine:checked:)` (`DocumentWindowController+EditSession.swift`). That gives the same save, external-change conflict and re-render as clicking the box in Read Mode.
2. **Open with unsaved edits:** writing to disk would clash with the buffer. Instead, send the editor a new `setTaskChecked(line, checked)` that runs a CodeMirror transaction. The change joins the buffer, marks the document edited, saves with everything else, and is undoable in the editor.
3. **Not open:** a new `WorkspaceFileWriter.replace(relativePath:root:expected:with:)`. Flip the marker with `TaskCheckboxSource.settingChecked(_:onLine:in:)`.
   - `WorkspaceJournal.replaceEntry` can't simply be generalized. It writes one fixed file name inside a `journals/` descriptor that `openJournalsFolder` already opened and checked.
   - A workspace-relative path such as `projects/daisy/notes.md` passes through several directories, and any of them can be a symlink or be swapped for one between the check and the write. Resolving the URL and then checking only the last component leaves that gap open.
   - The writer's contract:
     1. Split `relativePath` into components and refuse empty, `.` and `..` components, absolute paths, and NUL bytes.
     2. `open(root, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)` and check it is the index's canonical root, matching the device and inode captured when the window bound the index. If they couldn't be captured, nothing is written.
     3. Walk every directory component with `openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)`, closing each parent as you go. A symlink anywhere fails with `ELOOP` or `ENOTDIR`, and the write is refused.
     4. Open the file with `openat(dir, name, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)` and `fstat` it. It must be a regular file (`S_ISREG`) with one link (`st_nlink == 1`, so a hard link elsewhere can't be rewritten). Read it through that descriptor and compare the bytes with `expected`.
     5. Create the temporary file in the **same final directory descriptor**: `openat(dir, ".name.<uuid>.tmp", O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode & 0o777)`. Copy the original's extended attributes (Finder tags among them) and ACL with `fcopyfile`, and its creation date, best effort. Write it, `fsync`, close.
     6. Re-read the target through `dir` (open, `fstat`, compare device, inode and bytes with step 4). Then `renameat(dir, tmp, dir, name)`. On any failure, `unlinkat(dir, tmp, 0)`.
   - Steps 4 to 6 always use the parent descriptor from step 3, never a path, so swapping a directory for a symlink partway through changes nothing.
   - The window between the re-read and the rename can't be closed without a file lock. An outside edit that lands there is overwritten, the same limit `replaceEntry` has.
   - `replaceEntry` can then be reimplemented on top of the writer.

### Finding the line

The indexed line number can be stale. Before flipping:

- Use the stored line if it is still a task whose text matches the indexed text.
- Otherwise use the only task in the file with that exact text.
- If there is none, or more than one, write nothing, report that the file changed, and offer to open it.

After a successful write, update the task list straight away, as an index update that bumps `taskRevision`, so it doesn't flicker. The directory watcher then re-reads the file and confirms it.

### Deferred

- An optional `done:YYYY-MM-DD` appended on completion (Settings → Extensions → Task metadata → Add completion date, off by default). It adds a field to the grammar.

## Documentation to update with the change

- `README.md`: Read Mode's inspector panel (line 43), a Tasks sidebar entry in the features list, and the list of what Daisy writes into a workspace (line 49), which gains checking tasks off from the sidebar.
- `docs/technical/workspace-metadata-proposal.md`: line 19, line 199, and the workspace-write statements at lines 24 and 238.
- `docs/technical/workspace-metadata-implementation-plan.md`: the workspace-write statements at lines 237, 294, 300 and 322.
- `docs/technical/open-any-file-proposal.md`: the inspector mention at line 215.
- Comments that mention the inspector in `LinkTarget.swift`, `LinkHandler.swift` and `MarkdownFrontmatter.swift`.

## Implementation phases

Each phase builds and works on its own.

1. **Data:** the extractor gains `text` and `checked`; the index keeps tasks per file; the cache gets a `tasks` table and a schema bump; add `index.tasks()` plus a change signal.
2. **Read-only sidebar:** `TaskCalendarViewController`, the shared month grid, grouping, empty, indexing and no-workspace states, midnight rollover, opening a task at its line; the Inspector removed, with the menu, shortcut, toolbar and keymap alias; README and design docs updated.
3. **Check off:** the three write paths, finding the line, updating the list straight away, Undo, error states, and the workspace-write docs.

## Verification

- **Extractor:** text and checked state for nested tasks, tasks in quotes, and tasks with several fields; tasks in code blocks are still ignored.
- **Index:** tasks added, edited and removed when files are saved, renamed or deleted; an unsaved buffer counts in place of its file.
- **Cache:** old caches migrate to the new schema; reopening restores tasks without re-reading unchanged files.
- **Task signal:** `taskRevision` changes after edits to only `due:`, only `scheduled:`, only checked state or only task text; after an overlay is set or cleared, a rename or delete, a cache load, and a direct write. It doesn't change after a tag-only edit or a re-read that changed nothing.
- **Grouping:** overdue, today and upcoming, including leap days and month and year boundaries, with an injected clock.
- **Completed filter:**
  - a checked task with a past `due:` is never Overdue;
  - with Show Completed off, checked tasks make no markers, rows or counts;
  - with it on, they sort after open tasks, use hollow markers, and are left out of Upcoming.
- **Keymap alias:** `view.toggleInspector` in a keymap file loads as `view.toggleTasks` with no diagnostic and isn't listed in Settings.
- **Finding the line:** line unchanged, line moved, duplicate text, task already checked, task removed.
- **Writer:**
  - unchanged file, changed file, permissions kept;
  - `..`, absolute and empty components refused;
  - the target is a symlink;
  - a nested directory component is a symlink, both inside and pointing outside the root;
  - the target is a hard link;
  - the target is a directory or FIFO;
  - a directory component is swapped for a symlink between the walk and the write, injected through a test hook between steps;
  - the target is replaced between the read and the rename;
  - no temporary file is left behind after any failure.
- **Editor:** `setTaskChecked` changes only the marker and is undoable.
- **App run-through:**
  - toggling with ⇧⌘I, the menu and the toolbar;
  - a non-workspace window;
  - a task added with `/due` appearing before it is saved;
  - opening a task at its line;
  - checking off in each of the three cases, plus Undo;
  - a file edited in another app between indexing and the click;
  - midnight rollover;
  - VoiceOver labels.
