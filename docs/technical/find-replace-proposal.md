# Find and Replace Proposal

Status: implemented on `feature/find-replace` (not yet released). Differences from the original proposal are called out under "As built".

## Goals

- Add **Replace** and **Replace All** to the editor.
- Search modes: **Substring** (default), **Word**, **Regex**.
- **Match Case** toggle, independent of mode.
- Replace the always-visible toolbar search field with a find bar that appears
  only on ⌘F / ⌥⌘F, in the style of Zed and VS Code.
- Modes and case apply in both edit mode (source buffer) and read mode
  (rendered preview).

## Current state

| Piece | Where |
| --- | --- |
| Editor find engine (CodeMirror `StateField`, literal, case-insensitive) | `scripts/editor-bundle/src/find.js` |
| Editor bridge `window.__mdEditor.find(query, backwards, beginsWith)` | `scripts/editor-bundle/src/api.js` |
| Preview find (DOM text-node walk, `<mark>` wrapping) | `MarkdownWebView.highlightMatches` |
| Toolbar `NSSearchToolbarItem`, find overlay wiring | `DocumentWindowController+Find.swift` |
| Find bar (Contains / Begins With, count, prev/next, Done) | `daisy/Features/Find/FindBar.swift` |
| `SearchMode { contains, beginsWith }` | `MarkdownWebView.swift` |

The editor engine already knows every match range in the source buffer, so
replace is mostly UI and bridge work. The preview is a separate
implementation and searches one text node at a time.

## Search semantics

| Option | Values | Default |
| --- | --- | --- |
| Mode | Substring, Word, Regex | Substring |
| Match Case | on / off | off (today's behaviour) |

Both engines build their pattern from one shared function so they cannot drift:

```js
function buildPattern(query, { mode, caseSensitive }) {
  const flags = "gmu" + (caseSensitive ? "" : "i")
  const W = "[\\p{L}\\p{N}_]"
  switch (mode) {
    case "regex": return new RegExp(query, flags)                       // may throw
    case "word":  return new RegExp(`(?<!${W})${escape(query)}(?!${W})`, flags)
    default:      return new RegExp(escape(query), flags)
  }
}
```

- **Word** uses Unicode-aware lookarounds, not `\b` (ASCII-only; breaks on
  accented and CJK text). This also fixes the ASCII-only `isWordChar` in the
  preview today.
- **Regex** uses the `m` flag so `^` / `$` match per line.
- **Invalid regex**: catch the `SyntaxError`, return no matches, and surface
  `error: true`. The bar shows "Invalid pattern" instead of "No results".
- **Zero-length matches** are skipped.
- **Catastrophic backtracking** cannot be timed out in JS. Cap the match count
  (about 10k, shown as "10,000+") and document the risk.
- **Begins With is removed.** Regex covers it with `\bfoo`. Note the removal in
  the CHANGELOG.

### Replacement text

- Substring / Word: literal (`$1` stays `$1`).
- Regex: `$1`, `$<name>`, `$&`, `$$` expand per match from the `matchAll`
  result; `\n` / `\t` escapes are honoured. Building the expansion per match
  keeps Replace All a single `changes` array.

### Preview limitation

The preview searches one DOM text node at a time, so:

- a match cannot span inline formatting (`hello **world**` is not found by
  "hello world" in the preview; the editor finds it in the source);
- regex `^` / `$` anchor to each text node, not each line.

Document this rather than stitch text across nodes.

## Replace behaviour

| Action | Behaviour |
| --- | --- |
| Replace | Replaces the current match, then selects the next one. |
| Replace All | Replaces every match in one transaction; one ⌘Z undoes it. |
| Empty replacement | Allowed; deletes the match. |
| Read mode | Replace row hidden (preview is not editable). |

Editor sketch:

```js
replaceCurrent: (text, options) => {
  // dispatch one change, selection after insert, userEvent "input.replace"
  // advance by position (first match with from >= m.from + text.length),
  // not by index, so replacing "a" -> "aa" does not re-match its own output
},
replaceAll: (text, options) => {
  // one dispatch with changes: matches.map(...), userEvent "input.replace"
}
```

History stays enabled (do not copy the `addToHistory.of(false)` used by
`replaceMarkdown`). The normal `docChanged` path already drives dirty tracking
and autosave.

## UI

The toolbar search field is removed. The find bar owns the query field and
appears only on demand. It reuses the existing content-overlay mechanism (pads
the page below it, never reflows layout, does not sit above the native tab bar).

Find only (one row, 36pt):

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ ›  [🔍 Find                         ] [Aa] [ab] [.*]   3 of 12   [‹][›]   ✕ │
└──────────────────────────────────────────────────────────────────────────────┘
```

Replace expanded (edit mode only, 64pt):

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ ⌄  [🔍 Find                         ] [Aa] [ab] [.*]   3 of 12   [‹][›]   ✕ │
│    [↳ Replace                       ]  [Replace] [Replace All]               │
└──────────────────────────────────────────────────────────────────────────────┘
```

- `›` / `⌄` disclosure toggles the replace row (hidden in read mode).
- `Aa` Match Case; `ab` Word; `.*` Regex. `ab` and `.*` are mutually exclusive;
  neither selected means Substring.
- Count reads "3 of 12", "Not found", "Invalid pattern", or "N replaced" after Replace All.
- `✕` replaces the Done text button.
- Narrow windows: the query field shrinks (minimum 120pt) while the options, count and chevrons keep their size.
- Alternative considered: a VS Code-style floating widget. Rejected as the
  default because it can cover text at the top of the page.

### Keys

| Key | Action |
| --- | --- |
| ⌘F | Open the bar and focus the field |
| ⌥⌘F | Open with the replace row expanded (edit mode); same as ⌘F in read mode |
| ↩ / ⇧↩ | Next / previous match |
| ⌘G / ⇧⌘G | Next / previous match, also from the content |
| ↩ in replace field | Replace |
| ⌥⌘↩ | Replace All |
| ⌥⌘C / ⌥⌘W / ⌥⌘R | Toggle Match Case / Word / Regex |
| Esc | Close the bar, clear highlights, return focus to the content |

No "Use Selection for Find" key binding is added. The existing menu item of
that name (no key equivalent) is left as is.

### State

Options (mode, Match Case) and the query reset when the window closes, as in
VS Code. They persist while the window stays open, including across read / edit
switches.

## Implementation notes

**JS**
- `find.js`: shared `buildPattern`, error state, match cap, replace helpers.
- `api.js`: `find(query, backwards, {mode, caseSensitive})`, `replaceCurrent`,
  `replaceAll`, all taking the same options object.
- `MarkdownWebView.highlightMatches`: swap the `indexOf` loop for
  `pattern.exec` per text node using the shared pattern; drop `beginsWith` /
  `isWordChar`; the "same query" key becomes `query + mode + caseSensitive`.
  The shared source is injected into the page script from a Swift constant.

**Swift**
- `SearchMode` becomes `{ substring, word, regex }`; add `matchCase` next to
  `searchMode` on `DocumentWindowController`; add `error` to `FindResult`.
- `FindBar` owns the `NSSearchField` and its delegate (Enter / Esc handling
  moves in), the toggles, the replace row, and the "Invalid pattern" state.
- Remove `makeSearchItem` and the `.search` item from the default toolbar set.
- Forward `replaceCurrent` / `replaceAll` through `EditorViewController`,
  `ContentViewController`, `MainSplitViewController`, mirroring `find`.
- Call `findOverlayVisibilityChanged()` when the replace row toggles, since the
  overlay height changes.
- The existing Edit → Find submenu items ("Find…", "Find and Replace…" on
  ⌥⌘F, Find Next / Previous) keep routing through `handleFindAction`; it gains
  a case for the replace-row tag.
- Accessibility: toggle subrole, labels and tooltips including the shortcut.
- Localization: Replace, Replace All, Invalid pattern, No results, toggle
  tooltips (`en`, `zh-Hans`).

## Testing and docs

- Shared fixture of (query, mode, case, text → matches) run against both the
  editor engine and the preview script.
- `smoke/find.mjs`: mode and case matrices, Unicode word boundaries, regex
  capture-group replacement, invalid regex, zero-length matches, match cap,
  replacement containing the query, empty replacement, Replace All as one undo
  step in every mode, table widget re-render after replace.
- Swift: bridge option serialization (`EditorSearchBridgeTests`), preview script
  test.
- Runtime check of the find bar in read and edit mode.
- Docs: grep `README.md`, `samples/`, `tests/fixtures/` for find claims;
  CHANGELOG entry noting the removal of Begins With.

## Rollout

1. **PR 1: engine plus mode / case in both views.** Shared pattern, editor and
   preview ports, `SearchMode` change, new find bar and removal of the toolbar
   field. Find only, no replace.
2. **PR 2: Replace and Replace All.** Replace row, disclosure, bridge, edit
   mode only.

## As built

- **Toolbar:** no find item at all. The separate Search for Document (file
  search) toolbar item is unrelated and unchanged.
- **⌘F pre-fills** from a one-line selection (200 characters or fewer), else
  from the shared find pasteboard when the bar was closed.
- **State:** options (mode, Match Case) belong to the window and survive
  closing the bar; the query clears when the bar closes.
- **Count cap:** 10,000 highlighted matches, shown as "N of 10000+". Replace All
  ignores the cap.
- **Count text:** keeps the existing "Not found" wording rather than "No results".
- **Shortcuts:** the ⌥⌘C / ⌥⌘W / ⌥⌘R toggles and ⌥⌘↩ only act while a find bar
  control has focus, because ⌥⌘W is the Window menu's Close All.
- **Quick Look target:** `SearchOptions.swift` and `SearchPatternScript.swift`
  are listed in the `quick-look` membership exceptions in `project.pbxproj`
  because `MarkdownWebView.swift` is compiled into that target.
- **CHANGELOG:** not edited here; entries are written in the release PR.
