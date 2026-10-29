# Keyboard shortcuts

Daisy's default shortcuts. You can rebind the commands in the first four tables in **Settings → Shortcuts**, or by editing `~/.config/daisy/keymap.json` (see [Customizing](#customizing)).

Each shortcut belongs to a context:

- **Global** works in any document window.
- **Reading** works while the Read mode preview has focus.
- **Editing** works while the Edit Mode editor has focus.
- **Search** works while the OmniSearch panel is open.

When a Global shortcut and a Reading, Editing or Search shortcut use the same keys, the Global one wins.

## Global

| Shortcut | Command | ID |
| --- | --- | --- |
| <kbd>⌘K</kbd> | OmniSearch… | `file.omniSearch` |
| <kbd>⌘L</kbd> | Toggle Sidebar | `view.toggleSidebar` |
| <kbd>⌃⌘1</kbd> | Table of Contents | `view.showOutline` |
| <kbd>⌃⌘2</kbd> | Project Navigator | `view.showProjectNavigator` |
| <kbd>⇧⌘I</kbd> | Agenda | `view.toggleTasks` |
| <kbd>⇧⌘R</kbd> | References | `view.toggleReferences` |
| <kbd>⌘E</kbd> | Toggle Edit Mode | `view.toggleEditMode` |
| <kbd>⌥⌘T</kbd> | Show Toolbar | `view.toggleToolbar` |
| <kbd>⌃⌘T</kbd> | Always on Top | `view.toggleAlwaysOnTop` |
| <kbd>⌘F</kbd> | Find… | `find.find` |
| <kbd>⌥⌘F</kbd> | Find and Replace… | `find.replace` |
| <kbd>⌘G</kbd> | Find Next | `find.next` |
| <kbd>⇧⌘G</kbd> | Find Previous | `find.previous` |
| <kbd>⌘J</kbd> | Jump to Selection | `find.jumpToSelection` |
| <kbd>⌘[</kbd> | Back | `go.back` |
| <kbd>⌘]</kbd> | Forward | `go.forward` |
| <kbd>⇧⌘J</kbd> | Today’s Journal | `go.todayJournal` |
| <kbd>⌥⌘←</kbd> | Previous Journal Entry | `go.previousJournalEntry` |
| <kbd>⌥⌘→</kbd> | Next Journal Entry | `go.nextJournalEntry` |

The journal commands appear only while the Journal extension is on.

## Reading

| Shortcut | Command | ID |
| --- | --- | --- |
| <kbd>↑</kbd> | Up | `go.lineUp` |
| <kbd>↓</kbd> | Down | `go.lineDown` |
| <kbd>⇞</kbd> | Page Up | `go.pageUp` |
| <kbd>⇟</kbd> | Page Down | `go.pageDown` |
| <kbd>⌥↑</kbd> | Previous Item | `go.previousItem` |
| <kbd>⌥↓</kbd> | Next Item | `go.nextItem` |
| <kbd>⌘↑</kbd> | Top of Document | `go.top` |
| <kbd>⌘↓</kbd> | Bottom of Document | `go.bottom` |

## Editing

| Shortcut | Command | ID |
| --- | --- | --- |
| <kbd>⌥⇧⌘V</kbd> | Paste and Match Style | `edit.pasteAndMatchStyle` |
| <kbd>⌥⌘0</kbd> | Body | `format.body` |
| <kbd>⌥⌘1</kbd> | Heading 1 | `format.heading1` |
| <kbd>⌥⌘2</kbd> | Heading 2 | `format.heading2` |
| <kbd>⌥⌘3</kbd> | Heading 3 | `format.heading3` |
| <kbd>⌘B</kbd> | Bold | `format.bold` |
| <kbd>⌘I</kbd> | Italic | `format.italic` |
| <kbd>⇧⌘X</kbd> | Strikethrough | `format.strikethrough` |
| <kbd>⇧⌘M</kbd> | Inline Code | `format.inlineCode` |
| <kbd>⇧⌘7</kbd> | Bulleted List | `format.bulletList` |
| <kbd>⇧⌘9</kbd> | Numbered List | `format.orderedList` |
| <kbd>⇧⌘L</kbd> | Checklist | `format.checklist` |
| <kbd>⌘'</kbd> | Block Quote | `format.quote` |
| <kbd>⌘.</kbd> | Open Link at Caret | `go.openLinkAtCaret` |
| — | Link | `format.link` |
| — | Link to File… | `insert.linkToFile` |
| — | Unfinished Tasks from Earlier Days | `insert.carriedOverTasks` |

The last three have no default shortcut. Bind one if you want it.

Open Link at Caret opens the Markdown link, URL, `#tag`, `@context` or `+project` that the caret is in or right next to, the same way Cmd+click does. Tags, contexts and projects open only in a workspace window.

Headings use <kbd>⌥⌘</kbd> because macOS reserves <kbd>⇧⌘3</kbd>–<kbd>⇧⌘5</kbd> for screenshots. Inline Code uses <kbd>⇧⌘M</kbd>, Apple Notes' Monostyled shortcut.

## Search

| Shortcut | Command | ID |
| --- | --- | --- |
| <kbd>↑</kbd> | Previous Result | `search.selectPrevious` |
| <kbd>↓</kbd> | Next Result | `search.selectNext` |
| <kbd>↩</kbd> | Open Result | `search.openResult` |
| <kbd>⌘↩</kbd> | Open Result in New Tab | `search.openResultInNewTab` |
| <kbd>⌥↩</kbd> | Open Result in New Window | `search.openResultInNewWindow` |

## Built into the editor

These keys are part of the Edit Mode editor. You can't rebind them.

| Shortcut | What it does |
| --- | --- |
| <kbd>⌘↩</kbd> | Steps a list item through list item → open task → done task → list item |
| <kbd>↩</kbd> | Continues a list, or leaves it from an empty item. Also opens a code fence or leaves a code block or table |
| <kbd>⇧↩</kbd> | A new line in the same list item |
| <kbd>⇥</kbd> / <kbd>⇧⇥</kbd> | Indents / outdents list items |
| <kbd>⌘↑</kbd> / <kbd>⌘↓</kbd> | Start / end of the document. Add <kbd>⇧</kbd> to select |
| <kbd>⌘←</kbd>, <kbd>⌃A</kbd> | Start of the line, stopping first after a list marker |
| <kbd>⌘Z</kbd> / <kbd>⇧⌘Z</kbd> | Undo / redo |
| Cmd+click | Opens the link, `#tag`, `@context` or `+project` under the pointer |

The rest of CodeMirror's standard keys work too, except <kbd>⌘[</kbd> and <kbd>⌘]</kbd>, which are left free for Back and Forward.

## Quick Capture

<kbd>⌃⌥Space</kbd> opens Quick Capture from any app. Change it in Settings, not in `keymap.json`.

## Customizing

Settings → Shortcuts records a new shortcut, clears or resets one, and can **Export All Defaults** into the file. The file holds only your changes, grouped by context:

```json
{
  "version": 1,
  "editing": {
    "cmd+.": null,
    "ctrl+o": "go.openLinkAtCaret"
  },
  "global": {
    "shift+cmd+j": null
  }
}
```

- A key is optional modifiers, then a key, joined by `+`. The modifiers are `ctrl`, `opt`, `shift` and `cmd`. The key is a single character, `f1`–`f20`, or one of `up`, `down`, `left`, `right`, `pageup`, `pagedown`, `home`, `end`, `space`, `return`, `escape`, `tab`, `delete` or `forwarddelete`.
- The value is a command ID from the tables above. `null` unbinds a default.
- A command goes only in its own context's section. Daisy reports a command in the wrong section, or an unknown command, and ignores it.
- Daisy reloads the file when it changes. If the JSON is invalid, it keeps the last map that loaded.
