# List and task-list editing behaviour

Status: implemented. `|` marks the caret. Rules marked **(proposed)** are defaults
nobody has confirmed yet. IME composition handling is out of scope.

## 1. Scope

- **1.1** Rules apply to bullet (`-` `*` `+`), ordered (`1.` `1)`) and task
  items, including inside blockquotes (`> - item`). A task is a bullet or
  ordered marker followed by a box: `- [ ]`, `- [x]`, `1. [ ]`, `1. [x]`.
  A box with nothing after it (`- [ ]`) is still a task.
- **1.2** Not inside fenced or indented code, front matter or HTML blocks: there,
  Enter, Tab and Backspace behave as plain text.
- **1.3** Pasted text is inserted literally: no reindenting, renumbering or
  marker changes.
- **1.4** Out of scope: checkbox writes from outside the editor (Agenda/Tasks
  sidebar, Read Mode) and moving items (Alt-↑/↓).

## 2. Enter

- **2.1** Mid-item: split the item and continue with the same marker, indent
  and delimiter. `- fo|o` → `- fo` / `- |o`
- **2.2** After a task item, the new item is always an unchecked task, even
  after `[x]`. `- [x] done|` → `- [ ] |`; `1. [x] done|` → `2. [ ] |`
- **2.3** Empty top-level item: exit the list, leaving an empty paragraph line
  with any leading indent removed, and insert a blank separator line so the
  next paragraph is not a lazy continuation of the list. This applies to all
  lists, not only task lists.
- **2.4** Empty nested item: outdent one level first; exit only from the top
  level.
- **2.5** **(proposed)** Caret at the start of a non-empty item: insert an
  empty item above.
- **2.6** **(proposed)** Loose lists (blank lines between items) stay loose;
  tight lists stay tight.
- **2.7** Typing at the left margin of an empty line directly below a list
  starts a paragraph: a blank line is inserted above it first, so Markdown
  does not read the text as a lazy continuation of the last item. Typing
  whitespace, `-`, `*`, `+` or a digit there does not, so a continuation line
  or a new item can still begin on that line.

## 3. Tab / Shift-Tab

- **3.1** Indent or outdent the current item, or every item touched by the
  selection.
- **3.2** Continuation lines and child items move with their item.
- **3.3** **(proposed)** Indent to the parent item's text column (2 spaces for
  `- `, 3 for `1. `, 4 for `10. `).
- **3.4** **(proposed)** Tab on the first item of a list does nothing.
- **3.5** **(proposed)** Shift-Tab on a top-level item does nothing.

## 4. Backspace and Delete

- **4.1** Caret just after a marker on a non-empty item: remove the marker,
  so the line becomes continuation text of the item above. A nested item
  outdents instead.
- **4.2** Empty item: remove the marker, and the task box if any, in one press.
  **(proposed)** A nested empty item outdents first, matching 2.4.
- **4.3** At the start of a line with no marker: the normal join with the line
  above.
- **4.4** Deleting a selection that spans items: the markers inside the
  selection are removed with the text, so the remainder joins the first
  item. `- fo|o` / `- ba|r` → `- fo|r`. Following items are not renumbered.

## 5. Converting lists

- **5.1** Toolbar, shortcut and slash commands switch the selected paragraphs
  between plain, bullet, ordered and task. Item text and indentation never
  change.
- **5.2** **(proposed)** If every selected line already has the target style,
  the style is removed. In a mixed selection, every line becomes the target
  style.
- **5.3** Converting to or from a task adds or removes only the box; the
  bullet character or number stays. `1. a` → `1. [ ] a`
- **5.4** Task → plain, bullet or ordered drops the checked state. This is
  intended.
- **5.5** Cmd-Enter cycles each selected list line, bullet or ordered: item → open task → done
  task → item. Each line moves on from its own state, so a mixed selection
  stays mixed.
- **5.6** Ordered numbering is per nesting level, never one flat sequence
  across the selection.

## 6. Ordered numbering

- **6.1** A new item continues the number. A non-1 start (`3.`) and the `)`
  delimiter are kept.
- **6.2** After Enter, Tab, Shift-Tab, deleting an item, or converting,
  following items at the same level are renumbered, stopping where the list
  ends. Deleting a selection across items is the exception (4.4).
- **6.3** Renumber only lists that were already sequential. Lists written as
  `1. 1. 1.` are left alone.

## 7. Checkboxes

- **7.1** For now, clicking changes only `[ ]` ↔ `[x]`. Text, nesting, marker
  and whitespace are kept. Task metadata such as a future `done:` completion
  date is carved out of this rule when it is added.
- **7.2** `[X]` counts as done. **(proposed)** Rewriting it to `[x]` when
  re-checked is acceptable.
- **7.3** A click doesn't move the caret or selection, scroll, or expand the
  line's source.
- **7.4** Space toggles a focused checkbox. Its label says "Mark task complete"
  or "Mark task incomplete".
- **7.5** Checking a parent doesn't check its children, and the reverse.
- **7.6** No checkbox appears inside code.

## 8. Multi-line items

- **8.1** Continuation lines indented to the item's text column belong to the
  item. Code blocks inside an item follow 1.2.
- **8.2** **(proposed)** Shift-Enter adds a continuation line at the text
  column.
- **8.3** **(proposed)** Enter on a continuation line starts a new sibling
  item.

## 9. Undo, selections, display

- **9.1** Each of these is one undo step, separate from nearby typing:
  checkbox change, conversion, indent or outdent, and renumbering together
  with the edit that caused it.
- **9.2** All rules work with multiple cursors. **(proposed)** Each cursor is
  handled on its own.
- **9.3** In live preview, "item start" means just after the rendered marker,
  which is where Home and Cmd-Left already stop. The caret never rests in
  front of a rendered marker: a click there, or Up / Down to column 0, lands
  after it, and Left from the start of the item text goes on to the end of the
  line above.

## Decisions

Settled: A (ordered items with a box are tasks; so is a box with no text), B (Backspace after a marker removes the marker), C (empty task: box and marker go
together), D (renumber only sequential lists), E (mixed selection: each line
from its own state), F (7.1 holds for now; task metadata carved out later),
G (blank separator on exit for all lists).

## Implementation

The editor rules live in `scripts/editor-bundle/src/commands/lists.js`, with
smoke tests in `scripts/editor-bundle/smoke/list-editing.mjs`. Read Mode
renders an empty `- [ ]` as a checkbox (`EscapingHTMLFormatter.visitListItem`).

Known limits:

- **5.1:** when a conversion changes a marker's width (`-` → `1.`), the
  item's children and continuation lines shift with its text column, so the
  nesting is kept. Their own indentation changes; their text does not.
- **6.3:** "already sequential" is judged per list before the edit. Lists
  numbered neither sequentially nor all alike keep their numbers; new items
  in them take the previous number plus one.
- **9.2:** two cursors in the same list fall back to CodeMirror's own Enter
  and Backspace.
