import { syntaxTree } from "@codemirror/language"
import { tableEditors } from "../table/editors.js"

// The table a widget-rendered table occupies when the cursor touches it.
function tableTouching(state, pos) {
  const field = state.field(tableEditors, false)
  if (!field) return null
  let table = null
  syntaxTree(state).iterate({
    from: pos,
    to: pos,
    enter(node) {
      if (node.name !== "Table") return
      let rendered = false
      field.between(node.from, node.to, () => { rendered = true })
      if (rendered && (pos === node.from || pos === node.to)) table = { from: node.from, to: node.to }
      return false
    },
  })
  return table
}

// A rendered table at the end of the file has no line below it to move to.
// Entering/arrowing past it opens one.
export function openLineBelowTable(view) {
  const { state } = view
  const selection = state.selection.main
  if (!selection.empty || selection.head !== state.doc.length) return false
  const table = tableTouching(state, selection.head)
  if (!table || table.to !== state.doc.length) return false
  view.dispatch({
    changes: { from: table.to, insert: "\n" },
    selection: { anchor: table.to + 1 },
    userEvent: "input",
    scrollIntoView: true,
  })
  return true
}

// The cursor beside a rendered table counts as one character: Backspace after
// it, or Delete before it, removes the whole table.
function deleteTable(view, atEnd) {
  const { state } = view
  const selection = state.selection.main
  if (!selection.empty) return false
  const table = tableTouching(state, selection.head)
  if (!table || selection.head !== (atEnd ? table.to : table.from)) return false
  let from = table.from
  let to = table.to
  if (to < state.doc.length) to++
  else if (from > 0) from--
  view.dispatch({
    changes: { from, to },
    selection: { anchor: from },
    userEvent: "delete",
    scrollIntoView: true,
  })
  return true
}

export const deleteTableBackward = (view) => deleteTable(view, true)
export const deleteTableForward = (view) => deleteTable(view, false)
