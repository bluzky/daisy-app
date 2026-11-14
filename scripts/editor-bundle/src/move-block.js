import { EditorView } from "@codemirror/view"
import { ensureSyntaxTree, syntaxTree } from "@codemirror/language"
import { isolateHistory, undo } from "@codemirror/commands"
import { listItemExtent } from "./commands/lists.js"

// `/move` (docs/technical/move-to-file-proposal.md): the block under the caret goes to
// another file, or another section of this one. The host picks the target
// and writes it first; only then does the editor remove the block, and only
// while it still holds what was picked. The removal is one undo step of its
// own, so ⌘Z puts the block back here and nowhere else. The host's Undo
// button reverses both files: `undoMove` runs that same undo, but only while
// nothing has changed since the move.

// Per editor: moves waiting for their target, and finished moves the Undo
// button can still reverse, both by id.
const moves = new WeakMap()
let nextMoveId = 0

const movesOf = (view) => {
  let entry = moves.get(view)
  if (!entry) {
    entry = { pending: new Map(), done: new Map() }
    moves.set(view, entry)
  }
  return entry
}

const HEADING = /^(?:ATXHeading|SetextHeading)(\d)$/
const blank = (doc, number) => number >= 1 && number <= doc.lines && !doc.line(number).text.trim()

// The block `/move` takes from the line at `pos`: a list item with its
// children, a heading with its whole section (up to the next heading of the
// same or a higher level), or a paragraph. `first` and `last` are line
// numbers; `text` is what goes to the target. Null on a blank line, in a
// quote or callout, and in anything else.
export function moveBlockAt(state, pos) {
  const line = state.doc.lineAt(pos)
  if (!line.text.trim()) return null
  const tree = ensureSyntaxTree(state, state.doc.length, 200) ?? syntaxTree(state)
  const start = line.from + /^[ \t]*/.exec(line.text)[0].length
  // The outermost block: the frontmatter support wraps the Markdown
  // `Document` in another.
  let top = null
  for (let node = tree.resolveInner(start, 1); node && node.name !== "Document"; node = node.parent) {
    if (node.name === "Blockquote") return null
    top = node
  }
  if (!top) return null
  if (top.name === "BulletList" || top.name === "OrderedList") {
    const item = listItemExtent(state, line.number)
    return item && { kind: "listItem", ...item }
  }
  const lineOf = (offset) => state.doc.lineAt(offset).number
  const heading = HEADING.exec(top.name)
  if (heading) {
    const level = Number(heading[1])
    let end = top
    for (let next = top.nextSibling; next; next = next.nextSibling) {
      const other = HEADING.exec(next.name)
      if (other && Number(other[1]) <= level) break
      end = next
    }
    return sectionOf(state, lineOf(top.from), lineOf(end.to))
  }
  if (top.name === "Paragraph") return sectionOf(state, lineOf(top.from), lineOf(top.to), "paragraph")
  return null
}

function sectionOf(state, first, last, kind = "section") {
  const lines = []
  for (let number = first; number <= last; number++) lines.push(state.doc.line(number).text)
  return { kind, first, last, text: lines.join("\n") }
}

// The text taken out of this document: the block's lines with one line
// break, and a blank line next to it when it stood between two (or opened
// the document), so no double gap is left behind.
function removalRange(doc, first, last) {
  if (last < doc.lines) {
    const gapBefore = first === 1 || blank(doc, first - 1)
    const after = gapBefore && blank(doc, last + 1) && last + 2 <= doc.lines ? last + 2 : last + 1
    return { from: doc.line(first).from, to: doc.line(after).from }
  }
  if (first > 1) {
    const before = blank(doc, first - 1) && first > 2 ? first - 2 : first - 1
    return { from: doc.line(before).to, to: doc.line(last).to }
  }
  return { from: 0, to: doc.length }
}

// Called by the slash command once the typed `/move` is gone. Hands the
// block to the host, or does nothing when the line has none.
export function startMove(view, pos, callbacks) {
  const block = moveBlockAt(view.state, pos)
  if (!block || typeof callbacks.onPickMoveTarget !== "function") return false
  const id = ++nextMoveId
  const range = removalRange(view.state.doc, block.first, block.last)
  movesOf(view).pending.set(id, { ...range, original: view.state.doc.sliceString(range.from, range.to) })
  callbacks.onPickMoveTarget({ id, kind: block.kind, text: block.text, firstLine: block.first, lastLine: block.last })
  return true
}

const isolated = (spec) => ({ ...spec, annotations: isolateHistory.of("full"), scrollIntoView: true })

// Once the target holds the block: removes it here as one undo step.
// False when it changed since it was picked, so it stays.
export function completeMove(view, id) {
  const { pending, done } = movesOf(view)
  const move = pending.get(id)
  pending.delete(id)
  if (!move || view.state.doc.sliceString(move.from, move.to) !== move.original) return false
  view.dispatch(isolated({ changes: { from: move.from, to: move.to }, userEvent: "delete.move" }))
  done.set(id, view.state.doc)
  return true
}

// The document as `completeMove` would leave it, for a move within it:
// `{ expected, removed }`, or null when the block changed.
export function removalPreview(view, id) {
  const move = movesOf(view).pending.get(id)
  const doc = view.state.doc
  if (!move || doc.sliceString(move.from, move.to) !== move.original) return null
  return { expected: doc.toString(), removed: doc.sliceString(0, move.from) + doc.sliceString(move.to) }
}

// Replaces the document with `next` as one change spanning what differs,
// one undo step. False when it is no longer `expected`. A host write into
// a target open in this editor goes this way too.
export function replaceIfUnchanged(view, expected, next, userEvent = "input.host") {
  const current = view.state.doc.toString()
  if (current !== expected || typeof next !== "string") return false
  let from = 0
  while (from < current.length && from < next.length && current[from] === next[from]) from++
  let end = 0
  while (end < current.length - from && end < next.length - from
         && current[current.length - 1 - end] === next[next.length - 1 - end]) end++
  view.dispatch(isolated({
    changes: { from, to: current.length - end, insert: next.slice(from, next.length - end) },
    userEvent,
  }))
  return true
}

// A move within this document: the host has worked out the whole new text
// from `expected` (see `removalPreview`). False when the document is no
// longer `expected`.
export function applyMove(view, id, expected, next) {
  const { pending, done } = movesOf(view)
  pending.delete(id)
  if (!replaceIfUnchanged(view, expected, next, "input.move")) return false
  done.set(id, view.state.doc)
  return true
}

// The Undo button: the move's own undo step, only while the document is
// exactly as the move left it. False otherwise, and nothing changes.
export function undoMove(view, id) {
  const { done } = movesOf(view)
  const after = done.get(id)
  done.delete(id)
  if (!after || view.state.doc !== after) return false
  undo(view)
  return view.state.doc !== after
}

// A move the host no longer offers to undo, or one it gave up on.
export function forgetMove(view, id) {
  const { pending, done } = movesOf(view)
  pending.delete(id)
  done.delete(id)
}

// Tells the host when a finished move can no longer be undone with the
// button, because the document changed after it.
export const moveTracking = (callbacks) => EditorView.updateListener.of((update) => {
  if (!update.docChanged) return
  const entry = moves.get(update.view)
  if (!entry) return
  for (const [id, after] of entry.done) {
    if (update.state.doc === after) continue
    entry.done.delete(id)
    if (typeof callbacks?.onMoveStale === "function") callbacks.onMoveStale(id)
  }
})
