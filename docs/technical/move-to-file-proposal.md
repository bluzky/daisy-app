# Move to file proposal

Status: Implemented. README.md describes the behaviour for readers; this document keeps the design reasoning.

## Summary

A `/move` slash command moves the block under the caret to another file in the workspace: to the end of that file, or to the end of one of its heading sections. The block is written to the target first and removed from the current file only after that write succeeds. An **Undo** button on the confirmation message reverses both files; ⌘Z only ever undoes the current file.

```markdown
- [ ] Review proposal p:high due:2026-10-30   ← type /move here
  - [ ] Read the plan
  - [ ] Leave comments
```

The task and both subtasks move together.

## Goals and scope

- Refile a task, list item, paragraph or section without cutting and pasting between tabs.
- Only in a saved document inside a mounted workspace, the same condition as Link to File (`canInsertLinkToFile`).
- Not in this proposal: moving from Read Mode, moving several selected blocks, moving out of blockquotes or callouts, re-leveling headings.

## The command

- `/move`, with no aliases. Label "Move to…" in an "Actions" group, localized through `options["cmd.move"]` and `options["group.actions"]` like the other commands.
- A host command, like `pickLink` in `SLASH_HOST_ACTIONS` (`scripts/editor-bundle/src/slash.js`): it is listed only when the host passes `onPickMoveTarget` and has turned it on with `setMoveBlocks(true)` (a saved Markdown document in a project folder), and only on a line with text besides the typed `/move`, outside a quote.
- A trailing `/move` is removed with the space before it, so the moved line doesn't keep it.
- `/` is already blocked inside code, tables, frontmatter, HTML and links (`SLASH_BLOCKED`), so none of those can be moved.

## What moves

The block is decided by the line the `/move` was typed on, after the typed `/move` is removed.

| Line                                     | Block                                                                              |
| ---------------------------------------- | ---------------------------------------------------------------------------------- |
| List item or task (`-`, `1.`, `- [ ]`)   | The item, its continuation lines and all nested items                              |
| Paragraph                                | The whole paragraph                                                                |
| Heading                                  | The heading and its section: up to the next heading of the same or a higher level  |
| Blockquote or callout                    | Not offered                                                                        |

- List item extents come from `analyze()` in `commands/lists.js`, which already computes `item.index … item.end` (children, lazy continuation lines, fenced code inside the item). Export a `listItemExtent(state, lineNumber)` from there rather than writing a second parser.
- The block is normalized before it leaves the editor: its first line moves to column 0 and the rest shifts by the same amount (as `moveItem` does), so a nested item becomes a top-level one.
- Headings keep their level. No re-leveling.

## Choosing the target

1. OmniSearch opens in a new `FileSearchPanelController.Mode.moveTarget`. It keeps fuzzy matching and the **Create file** row.
2. Choosing a file opens a second step: **End of file** first, then the file's headings, indented by level and searchable.
   - Headings are read when the step opens: from the window's buffer when the file is open, otherwise from disk. They are not added to the workspace index.
   - The heading scan skips frontmatter and fenced code, and reads ATX and setext headings.
   - When the target is the current file and the block is a section, that section's heading and every heading inside it are left out, so a section can't be moved into itself.
3. Escape on the heading step goes back to the files; on the file step it closes the palette.
4. Large moves are not confirmed.

## Where the block goes

A pure function in `daisy/Features/WorkspaceMetadata/MarkdownSectionInsertion.swift`, with no AppKit, tested in `tests/swift-tests`.

- **End of file.** The file is made to end with a newline. A list item appended to a file that ends with a list of the same kind joins that list with no blank line; anything else gets one blank line before it.
- **Under a heading.** After the last line of the heading's whole section, subheadings included: just before the next heading of the same or a higher level, or at the end of the file. Trailing blank lines of the section are trimmed, the block is inserted at column 0, and one blank line is kept before the next heading. The block is never nested into a list or code block that ends the section.
  - Markdown can't express "a child of the parent after a subheading", so when the section ends with a subheading the block appears under that subheading. This matches org-refile.
- **Ordered items.** An item joining an ordered list takes the next number; otherwise it becomes `1.`.
- **Relative links and images** in the block are rewritten with `ProjectFileLink.destination` when the target is in a different folder, so `![](img/a.png)` keeps working.

## Writing

1. The editor posts `pickMoveTarget { from, to, text, kind }`. Nothing is deleted yet.
2. The host inserts the block into the target, using the three routes the Agenda check-off uses (`DocumentWindowController+Tasks.swift`):
   - The target is open in Edit Mode or has unsaved edits: change that window's buffer.
   - The target is open in Read Mode and clean: write it the way that window would.
   - The target is not open: `WorkspaceFileWriter.replace(expected:…)`, which refuses if the file changed since it was read.

   `editProjectFile` (`DocumentWindowController+Move.swift`) applies a pure transform to a project file along those three routes; the move and its Undo use it. The Agenda check-off keeps its own routing for now, since its Edit Mode path finds the task by line and text rather than by whole-buffer text.
   - The chosen heading is found again in the text the move is made against, by title and level and its position among headings with the same title and level. If it is gone, nothing is moved.
3. Only after the write succeeds, the editor deletes `from..<to`, and only if the range still holds `text`. If it was edited while the picker was open, the original stays and the message reads "Copied to X; the original was left in place."
4. The message reads "Moved to X › Heading" with **Undo** and **Open** buttons. The index catches up through `recordTaskWrite` and the file watcher. Task fields (`due:`, `p:` …) travel with the text.

A failure can leave the block in both files, never in neither.

**Same file as target:** the editor previews the buffer with the block removed (`removalPreview`), the host inserts into that text, and the editor applies the result as one transaction.

## Undo

⌘Z and ⌘⇧Z stay local to the current file. Only the **Undo** button reaches the target.

| Action                  | Current file                    | Target file             |
| ----------------------- | ------------------------------- | ----------------------- |
| ⌘Z after a move         | Block comes back (native undo)  | Copy stays              |
| ⌘⇧Z                     | Native redo                     | Untouched               |
| **Undo** button         | Block comes back                | Copy removed            |

**When the button is offered:** until the message is dismissed, the current file changes after the move, or Edit Mode ends. A message with no buttons (a failure) goes by itself after 8 seconds. The editor keeps the document as it was right after the move and compares against it, which covers typing, ⌘Z and anything else.

**What it does, in order:**

1. Run a native undo in the current file. Since nothing changed after the move, this is exactly the move and can't fail.
2. Remove the inserted text from the target through the same routing helper: at the recorded range if it is still there, otherwise at its single exact occurrence.
3. If the target was edited and the text is gone or appears more than once, leave the copy and say: "X was changed since the move; its copy was left in place."

Restoring the current file first means a failure leaves the block in both files.

After the button, ⌘⇧Z deletes the block from the current file again while the target copy is gone. That stays a local edit — one ⌘Z brings it back — and redo is not special-cased, so keystrokes never touch another file.

**Same file as target:** the button runs the same native undo, which reverses the whole transaction.

A `MoveRecord { id, targetPath, insertedText, insertedRange }` lives in `DocumentWindowController+Move.swift` for as long as its message.

## Decisions

- Section placement is the end of the whole section, subheadings included, as in org-refile.
- Headings move with their section and keep their level.
- A section can't be moved into itself.
- No confirmation for large moves.
- ⌘Z is local; cross-file undo is the **Undo** button only.
- The command is `/move`, with no aliases.

## Implementation

- `scripts/editor-bundle/src/move-block.js` (new): block extent (list item, paragraph, section), removal only when unchanged, the removal preview for moves within the document, `replaceIfUnchanged` for host writes into an open buffer, the "unchanged since move" tracking and undo of the move.
- `scripts/editor-bundle/src/slash.js`: the `move` command and its host action, with an icon.
- `scripts/editor-bundle/src/commands/lists.js`: export `listItemExtent`.
- `daisy/Features/Editor/EditorHTML.swift`, `EditorViewController.swift`: bridge `pickMoveTarget` and `moveStale`, `completeMove`, `applyMove`, `moveRemovalPreview`, `undoMove`, `forgetMove`, `replaceIfUnchanged`, `setMoveBlocksEnabled`.
- `daisy/Features/FileSearch/FileSearchPanelController.swift`: `.moveTarget` mode and the section step.
- `daisy/Features/WorkspaceMetadata/MarkdownSectionInsertion.swift` (new): `headings(in:)`, `inserting(_:into:at:)`, link rewriting.
- `daisy/Document/DocumentWindowController+Move.swift` (new): picking, writing, the banner and Undo. `saveReadModeMarkdown` is split out of `toggleTaskCheckbox` for the Read Mode route.
- `daisy/Features/Move/MoveBannerView.swift` (new): the message at the bottom of the window.
- `daisy/en.lproj/Localizable.strings`: command label, messages, buttons.
- `README.md`: add `/move` to the slash commands in the same change that ships it.
- Tests:
  - Swift: placement at end of file and under headings (nested subheadings, trailing blanks, frontmatter, fences in the target), list joining, ordered renumbering, link rewriting, undo removal (unchanged, moved, edited, duplicated).
  - `scripts/editor-bundle/smoke/`: extents for nested items, lazy lines, code inside an item, sections; removal refused after an edit.
