import { EditorSelection, EditorState, StateField } from "@codemirror/state"
import { ViewPlugin } from "@codemirror/view"
import { syntaxTree } from "@codemirror/language"
import { fencedCodeAt } from "../fenced-code.js"

// Fence lines of a rendered code block are boundaries, not text: the cursor
// never rests on them and no single keystroke merges across them. Everything
// here keeps that promise for the keyboard; the language box edits the info.

// A fence line may sit inside containers: block quote markers, indentation and
// one list marker come before the fence marker.
const PREFIX = String.raw`((?:[ \t]*>[ \t]?)*[ \t]*(?:(?:[-*+]|\d{1,9}[.)])[ \t]+)?)`
const OPENER = new RegExp(`^${PREFIX}(\`{3,}|~{3,})([^\`]*)$`)
const FENCE_LOOKING = new RegExp(`^${PREFIX}(\`{3,}|~{3,})`)

// What continuation lines of the same container start with: the quote markers
// stay, a list marker turns into the indentation under it.
const continuation = (prefix) => prefix.replace(/(?:[-*+]|\d{1,9}[.)])[ \t]+$/, (marker) => " ".repeat(marker.length))
const isBlank = (text, cont) => text.trim() === "" || (cont.trim() !== "" && text.trimEnd() === cont.trimEnd())

function inContainer(state, pos) {
  for (let node = syntaxTree(state).resolveInner(pos, 1); node; node = node.parent) {
    if (node.name === "ListItem" || node.name === "Blockquote") return true
  }
  return false
}

// The fence-opening match for `line`. Four or more spaces of plain indentation
// make an indented code block unless a list or quote contains the line.
function openerOf(state, line) {
  const opener = OPENER.exec(line.text)
  if (!opener) return null
  const prefix = opener[1]
  if (/^[ \t]*$/.test(prefix) && /\t|^ {4,}/.test(prefix) && !inContainer(state, line.from)) return null
  return opener
}

const closedFenceAt = (state, pos) => {
  const fence = fencedCodeAt(state, pos)
  return fence && fence.closed ? fence : null
}

function blockLines(state, fence) {
  const open = state.doc.lineAt(fence.from)
  const close = state.doc.lineAt(fence.to)
  const hasContent = close.number - open.number > 1
  return {
    open,
    close,
    hasContent,
    first: hasContent ? state.doc.line(open.number + 1) : null,
    last: hasContent ? state.doc.line(close.number - 1) : null,
  }
}

// The closed block whose opening or closing fence is `line`, if any.
function blockOfFenceLine(state, line) {
  const looking = FENCE_LOOKING.exec(line.text)
  if (!looking) return null
  const fence = closedFenceAt(state, line.from + looking[1].length + 1)
  if (!fence) return null
  const block = blockLines(state, fence)
  if (block.open.from === line.from) return { ...block, role: "open" }
  if (block.close.from === line.from) return { ...block, role: "close" }
  return null
}

const blockPrefix = (block) => continuation(FENCE_LOOKING.exec(block.open.text)?.[1] ?? "")
const contentStart = (line, cont) => line.from + (line.text.startsWith(cont) ? cont.length : 0)

// A fence typed inside a block only splits it when it could close that block:
// the same character, at least as long as the opening fence, and short enough
// for the block's real closing fence to close the second half.
function canCloseOuter(marker, block) {
  const opening = FENCE_LOOKING.exec(block.open.text)[2]
  const closing = FENCE_LOOKING.exec(block.close.text)?.[2]
  return marker[0] === opening[0] && marker.length >= opening.length
    && (closing == null || marker.length <= closing.length)
}

// A fence the user has just typed, before Enter has given it a partner. While
// it is pending the parser may pair it with a fence further down; the editor
// shows it as plain text and Enter inserts its own closing fence regardless.
// `insideClose` is set when it was typed inside an existing block.
export const pendingFence = StateField.define({
  create: () => null,
  update(value, tr) {
    const selection = tr.state.selection.main
    const line = tr.state.doc.lineAt(selection.head)
    if (value) {
      const from = tr.changes.mapPos(value.from, -1)
      if (selection.empty && line.from === from && openerOf(tr.state, line)) {
        return {
          from,
          insideClose: value.insideClose == null ? null : tr.changes.mapPos(value.insideClose, 1),
        }
      }
    }
    const typed = openerOf(tr.state, line)
    if (!tr.docChanged || !tr.isUserEvent("input") || !selection.empty
        || selection.head !== line.to || !typed) return null
    // A multi-line insertion (a whole block pasted or replaced) is not a fence
    // being typed, even when its last line looks like one.
    let multiline = false
    tr.changes.iterChanges((_fromA, _toA, _fromB, _toB, inserted) => {
      if (inserted.lines > 1) multiline = true
    })
    if (multiline) return null
    const before = tr.startState
    const beforeHead = before.selection.main.head
    if (openerOf(before, before.doc.lineAt(beforeHead))) return null
    let insideClose = null
    const fence = closedFenceAt(before, beforeHead)
    if (fence) {
      const block = blockLines(before, fence)
      const beforeLine = before.doc.lineAt(beforeHead)
      if (block.hasContent && beforeLine.number > block.open.number
          && beforeLine.number < block.close.number) {
        // Inside a block, only a fence that could close it is special; anything
        // else is just code.
        if (!canCloseOuter(typed[2], block)) return null
        insideClose = tr.changes.mapPos(block.close.from, 1)
      }
    }
    return { from: line.from, insideClose }
  },
})

// True while `node` (a FencedCode) is only a product of the pending fence.
export function pendingCoversFence(state, node) {
  const pending = state.field(pendingFence, false)
  if (!pending) return false
  const nodeLine = state.doc.lineAt(node.from).from
  return nodeLine <= (pending.insideClose ?? pending.from) && node.to >= pending.from
}

// Navigation never leaves the caret on a rendered fence line.
export const keepCaretOffFences = EditorState.transactionFilter.of((tr) => {
  const head = tr.newSelection.main.head
  if (tr.docChanged || !tr.selection || !tr.newSelection.main.empty) return tr
  const line = tr.newDoc.lineAt(head)
  if (!FENCE_LOOKING.test(line.text)) return tr
  const state = tr.state
  const pending = state.field(pendingFence, false)
  if (pending && pending.from === line.from) return tr
  const block = blockOfFenceLine(state, line)
  if (!block) return tr

  const movedUp = head < tr.startState.selection.main.head
  const doc = state.doc
  const cont = blockPrefix(block)
  const firstStart = block.first ? contentStart(block.first, cont) : null
  const before = block.open.number > 1 ? doc.line(block.open.number - 1).to : null
  const after = block.close.number < doc.lines ? doc.line(block.close.number + 1).from : null
  let target
  if (block.role === "open") {
    target = movedUp ? (before ?? firstStart ?? after) : (firstStart ?? after ?? before)
  } else {
    target = movedUp || after == null ? (block.last?.to ?? before) : after
  }
  if (target == null || target === head) return tr
  return [tr, { selection: EditorSelection.cursor(target), scrollIntoView: true, sequential: true }]
})

// Enter on the last, empty line of a block leaves it: that line is dropped and
// the caret lands on a blank line below the closing fence.
function leaveBlock(view, closingLine, dropFrom, dropTo) {
  const { state } = view
  const hasBlankBelow = closingLine.to < state.doc.length
    && state.doc.line(closingLine.number + 1).text.trim() === ""
  const changes = [{ from: dropFrom, to: dropTo }]
  if (!hasBlankBelow) changes.push({ from: closingLine.to, insert: "\n" })
  view.dispatch({
    changes,
    selection: { anchor: closingLine.to - (dropTo - dropFrom) + 1 },
    userEvent: "input",
    scrollIntoView: true,
  })
  return true
}

export function exitCodeBlock(view) {
  const { state } = view
  const selection = state.selection.main
  if (!selection.empty) return false
  const fence = closedFenceAt(state, selection.head)
  if (!fence) return false
  const block = blockLines(state, fence)
  const line = state.doc.lineAt(selection.head)
  if (!isBlank(line.text, blockPrefix(block))
      || line.number !== block.close.number - 1
      || line.number - 1 <= block.open.number) return false
  const previous = state.doc.line(line.number - 1)
  return leaveBlock(view, block.close, previous.to, line.to)
}

// A fence typed inside an existing block, then Enter: on the block's last
// line it leaves the block; elsewhere it splits the block in two.
function resolveTypedFence(view, line, opener, pending) {
  const { state } = view
  const closing = state.doc.lineAt(pending.insideClose)
  if (closing.number === line.number + 1) {
    const previous = state.doc.line(line.number - 1)
    return leaveBlock(view, closing, previous.to, line.to)
  }
  const [, prefix, marker, info] = opener
  const cont = continuation(prefix)
  const blank = cont.trimEnd()
  view.dispatch({
    changes: { from: line.from, to: line.to, insert: `${cont}${marker}\n${blank}\n${cont}${marker}${info}` },
    selection: { anchor: line.from + cont.length + marker.length + 1 + blank.length },
    userEvent: "input",
    scrollIntoView: true,
  })
  return true
}

// Enter on an opening fence line ("```" or "```lang") starts the block: the
// closing fence is added below and the caret moves between them.
export function openCodeFence(view) {
  const { state } = view
  const selection = state.selection.main
  if (!selection.empty) return false
  const line = state.doc.lineAt(selection.head)
  const opener = openerOf(state, line)
  if (!opener) return false

  const pending = state.field(pendingFence)
  const typed = pending && pending.from === line.from
  if (typed && pending.insideClose != null) return resolveTypedFence(view, line, opener, pending)
  if (!typed) {
    if (selection.head !== line.to) return false
    const fence = fencedCodeAt(state, line.to)
    if (!fence || fence.closed || fence.from !== line.from + opener[1].length) return false
  }
  const [, prefix, marker] = opener
  const cont = continuation(prefix)
  view.dispatch({
    changes: { from: line.to, insert: `\n${cont}\n${cont}${marker}` },
    selection: { anchor: line.to + 1 + cont.length },
    userEvent: "input",
    scrollIntoView: true,
  })
  return true
}

function removeBlock(view, block) {
  const { state } = view
  let from = block.open.from
  let to = block.close.to
  if (block.open.number > 1) from--
  else if (to < state.doc.length) to++
  view.dispatch({ changes: { from, to }, selection: { anchor: from }, userEvent: "delete", scrollIntoView: true })
  return true
}

function unwrapBlock(view, block) {
  const { state } = view
  const head = state.selection.main.head
  view.dispatch({
    changes: [
      { from: block.open.from, to: block.first.from },
      { from: block.last.to, to: block.close.to },
    ],
    selection: { anchor: head - (block.first.from - block.open.from) },
    userEvent: "delete",
    scrollIntoView: true,
  })
  return true
}

// Backspace:
//  - on the line below a block: drop that line if empty, and either way move
//    into the end of the code, never onto the fence;
//  - at the start of a block's first code line: an empty block disappears,
//    anything else is unwrapped (the code stays as plain text).
export function codeBackspace(view) {
  const { state } = view
  const selection = state.selection.main
  if (!selection.empty) return false
  const line = state.doc.lineAt(selection.head)

  if (selection.head === line.from && line.number > 1) {
    const previous = state.doc.line(line.number - 1)
    const fence = closedFenceAt(state, previous.to)
    if (fence && state.doc.lineAt(fence.to).number === previous.number) {
      const block = blockLines(state, fence)
      if (block.hasContent) {
        if (isBlank(line.text, blockPrefix(block))) {
          view.dispatch({
            changes: { from: previous.to, to: line.to },
            selection: { anchor: block.last.to },
            userEvent: "delete",
            scrollIntoView: true,
          })
        } else {
          view.dispatch({ selection: { anchor: block.last.to }, scrollIntoView: true })
        }
        return true
      }
    }
  }

  const fence = closedFenceAt(state, selection.head)
  if (!fence) return false
  const block = blockLines(state, fence)
  const cont = blockPrefix(block)
  if (!block.hasContent || selection.head !== contentStart(block.first, cont)) return false
  let blank = true
  for (let n = block.first.number; n <= block.last.number; n++) {
    if (!isBlank(state.doc.line(n).text, cont)) blank = false
  }
  return blank ? removeBlock(view, block) : unwrapBlock(view, block)
}

// Delete:
//  - at the end of a block's last code line: nothing (never into the fence);
//  - at the end of the line above a block: drop that line if empty, else nothing.
export function codeDelete(view) {
  const { state } = view
  const selection = state.selection.main
  if (!selection.empty) return false
  const line = state.doc.lineAt(selection.head)

  const fence = closedFenceAt(state, selection.head)
  if (fence) {
    const block = blockLines(state, fence)
    if (block.hasContent && selection.head === block.last.to) return true
  }

  if (selection.head === line.to && line.number < state.doc.lines) {
    const next = blockOfFenceLine(state, state.doc.line(line.number + 1))
    if (next && next.role === "open") {
      if (isBlank(line.text, blockPrefix(next))) {
        const removed = line.to + 1 - line.from
        const anchor = line.number > 1
          ? line.from - 1
          : (next.first ?? next.close).from - removed
        view.dispatch({
          changes: { from: line.from, to: line.to + 1 },
          selection: { anchor },
          userEvent: "delete",
        })
      }
      return true
    }
  }
  return false
}

// WebKit leaves the selection on the line element itself, just past a code
// line's text span, when the first character is typed into an empty code line.
// CodeMirror counts that as equivalent to "after the text" and leaves it alone,
// but the browser paints such a boundary caret at the top of the line, above
// the language header. Move it inside the text, where every later keystroke
// puts it anyway.
function settleCodeCaret(view) {
  const root = view.root
  const selection = root.getSelection ? root.getSelection() : document.getSelection()
  if (!selection || !selection.isCollapsed || !selection.anchorNode) return
  const line = selection.anchorNode
  if (line.nodeType !== 1 || !line.classList.contains("cm-line")) return
  const offset = selection.anchorOffset
  const before = line.childNodes[offset - 1]
  const after = line.childNodes[offset]
  const textSpan = (node) => node && node.nodeType === 1 && node.classList.contains("cm-md-code-scroll-text")
  const textNodes = (node, found = []) => {
    for (const child of node.childNodes) {
      if (child.nodeType === 3) found.push(child)
      else if (child.nodeType === 1) textNodes(child, found)
    }
    return found
  }
  if (textSpan(before)) {
    const text = textNodes(before).at(-1)
    if (text) selection.collapse(text, text.length)
  } else if (textSpan(after)) {
    const text = textNodes(after)[0]
    if (text) selection.collapse(text, 0)
  }
}

export const settleCodeCaretPlugin = ViewPlugin.fromClass(class {
  constructor(view) { this.view = view }
  update(update) {
    if (!update.docChanged && !update.selectionSet) return
    settleCodeCaret(update.view)
    // The browser may move the selection once more after the DOM update.
    cancelAnimationFrame(this.frame)
    this.frame = requestAnimationFrame(() => settleCodeCaret(this.view))
  }
  destroy() { cancelAnimationFrame(this.frame) }
})
