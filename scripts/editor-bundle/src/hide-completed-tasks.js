import { Decoration, EditorView } from "@codemirror/view"
import { StateField } from "@codemirror/state"
import { syntaxTree } from "@codemirror/language"
import { hostFlag, registerEditorExtension } from "./extensions.js"
import { currentFindTouches, documentFind } from "./find.js"

// Hide completed tasks: while the host turns it on (View ▸ Hide Completed
// Tasks), each checked task item's lines, nested items included, are folded
// out of the editor. The Markdown is never changed. An item the selection or
// the current find match is in stays shown, so a task just checked with the
// caret on it stays until the caret leaves, and the caret skips hidden items.
// Read mode hides the same items with `MarkdownHTML.hideCompletedTasksStylesheet`.

const hiddenItem = Decoration.replace({ block: true })

function selectionTouches(state, from, to) {
  return state.selection.ranges.some((range) => range.from <= to && range.to >= from)
}

// Whole-line ranges of checked task items that are not in use, outermost only.
function hiddenItems(state) {
  const ranges = []
  let lastTo = -1
  syntaxTree(state).iterate({
    enter(node) {
      if (node.name !== "TaskMarker") return
      const item = node.node.parent && node.node.parent.parent
      if (!item || item.name !== "ListItem" || item.from < lastTo) return false
      if (!/^\[[xX]\]$/.test(state.sliceDoc(node.from, node.to))) return false
      const from = state.doc.lineAt(item.from).from
      // A list item can end at the start of the line after it.
      const end = item.to > item.from && state.doc.lineAt(item.to).from === item.to ? item.to - 1 : item.to
      const to = state.doc.lineAt(end).to
      lastTo = to
      if (selectionTouches(state, from, to) || currentFindTouches(state, from, to)) return false
      ranges.push(hiddenItem.range(from, to))
      return false
    },
  })
  return Decoration.set(ranges)
}

function hideCompletedTasksExtensions(_options, host) {
  const on = hostFlag(host, "hide-completed-tasks")
  const hidden = StateField.define({
    create: (state) => (state.field(on) ? hiddenItems(state) : Decoration.none),
    update(value, transaction) {
      const { state, startState } = transaction
      if (!state.field(on)) return Decoration.none
      if (transaction.docChanged || transaction.selection || !startState.field(on)
          || syntaxTree(startState) !== syntaxTree(state)
          || startState.field(documentFind, false) !== state.field(documentFind, false)) {
        return hiddenItems(state)
      }
      return value
    },
    provide: (field) => [
      EditorView.decorations.from(field),
      EditorView.atomicRanges.of((view) => view.state.field(field)),
    ],
  })
  return [on, hidden]
}

registerEditorExtension({ id: "hide-completed-tasks", extensions: hideCompletedTasksExtensions })
