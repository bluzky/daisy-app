import { ViewPlugin } from "@codemirror/view"
import { Annotation, EditorState, EditorSelection } from "@codemirror/state"
import { markdown } from "@codemirror/lang-markdown"
import { formattingState } from "../formatting-state.js"
import { obsidianHighlight } from "../obsidian-highlight.js"
import { escapedTableCell, splitTableRow } from "./model.js"

// A table cell owns a native DOM selection, separate from CodeMirror's.
// Remember it when the native formatting toolbar or link popover takes focus.
export const tableFormattingTargets = new WeakMap()
export const tableCellCommit = Annotation.define()
export const tableFormattingCallbacks = new WeakMap()
export const tableInlineCommands = new Set(['bold', 'italic', 'strikethrough', 'highlight', 'code', 'link'])

export function tableCellSourceRange(view, target) {
  if (target.invalid || target.tableFrom < 0 || target.tableFrom >= view.state.doc.length) return null
  const first = view.state.doc.lineAt(target.tableFrom)
  const lineNumber = first.number + (target.row === 0 ? 0 : target.row + 1)
  if (lineNumber > view.state.doc.lines) return null
  const line = view.state.doc.line(lineNumber)
  const range = splitTableRow(line.text, true)[target.column]
  if (!range) return null
  return { from: line.from + range.from, to: line.from + Math.max(range.from, range.to) }
}

export function captureTableSelection(view) {
  const target = tableFormattingTargets.get(view)
  if (!target || target.invalid || target.element.dataset.tableEditing !== 'true') return
  const selection = window.getSelection()
  if (!selection?.anchorNode || !selection.focusNode
      || !target.element.contains(selection.anchorNode) || !target.element.contains(selection.focusNode)) return
  const offset = (node, position) => {
    const range = document.createRange()
    range.selectNodeContents(target.element)
    range.setEnd(node, position)
    return range.toString().length
  }
  target.anchor = offset(selection.anchorNode, selection.anchorOffset)
  target.head = offset(selection.focusNode, selection.focusOffset)
  const text = target.element.innerText || ''
  const positions = [target.anchor, target.head]
  escapedTableCell(text, positions)
  target.sourceAnchor = positions[0]
  target.sourceHead = positions[1]
  const state = EditorState.create({
    doc: text,
    selection: EditorSelection.single(target.anchor, target.head),
    extensions: [markdown({ extensions: obsidianHighlight })],
  })
  tableFormattingCallbacks.get(view)?.(formattingState(state))
}

export function prepareTableFormatting(view) {
  const target = tableFormattingTargets.get(view)
  if (!target || target.invalid) return null
  captureTableSelection(view)
  // Blur commits any pending typing through the table's existing save path.
  if (target.element.dataset.tableEditing === 'true') target.element.blur()
  const range = tableCellSourceRange(view, target)
  if (!range) return null
  const length = range.to - range.from
  view.dispatch({ selection: EditorSelection.single(
    range.from + Math.max(0, Math.min(target.sourceAnchor ?? target.anchor, length)),
    range.from + Math.max(0, Math.min(target.sourceHead ?? target.head, length)),
  ) })
  return target
}

export function restoreTableFormatting(view, target) {
  const range = tableCellSourceRange(view, target)
  if (!range) return
  const selection = view.state.selection.main
  const anchor = Math.max(0, Math.min(selection.anchor - range.from, range.to - range.from))
  const head = Math.max(0, Math.min(selection.head - range.from, range.to - range.from))
  const cell = view.dom.querySelector(
    `.cm-md-table-widget[data-table-from="${target.tableFrom}"] [data-table-row="${target.row}"][data-table-column="${target.column}"]`
  )
  if (!cell) return
  cell.focus({ preventScroll: true })
  const text = cell.firstChild || cell.appendChild(document.createTextNode(''))
  window.getSelection()?.setBaseAndExtent(text, anchor, text, head)
  captureTableSelection(view)
}

export const tableFormattingSelection = ViewPlugin.fromClass(class {
  constructor(view) {
    this.view = view
    this.capture = () => captureTableSelection(view)
    this.clear = event => {
      if (!event.target.closest?.('.cm-md-table-cell')) tableFormattingTargets.delete(view)
    }
    document.addEventListener('selectionchange', this.capture)
    view.dom.addEventListener('mousedown', this.clear, true)
  }
  update(update) {
    const target = tableFormattingTargets.get(this.view)
    if (target && update.docChanged
        && update.transactions.some(transaction => transaction.docChanged && !transaction.annotation(tableCellCommit))) {
      // Keep a blocked target until the user explicitly selects a live cell or
      // body position, rather than formatting CodeMirror's previous selection.
      tableFormattingTargets.set(this.view, { ...target, invalid: true })
    }
  }
  destroy() {
    document.removeEventListener('selectionchange', this.capture)
    this.view.dom.removeEventListener('mousedown', this.clear, true)
    tableFormattingTargets.delete(this.view)
    tableFormattingCallbacks.delete(this.view)
  }
})
