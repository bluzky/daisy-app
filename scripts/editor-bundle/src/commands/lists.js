import { EditorSelection, Prec } from "@codemirror/state"
import { EditorView } from "@codemirror/view"
import { ensureSyntaxTree, syntaxTree } from "@codemirror/language"
import { markdownLanguage } from "@codemirror/lang-markdown"
import { isolateHistory } from "@codemirror/commands"

// List editing: Enter, Shift-Enter, Backspace, Tab / Shift-Tab and list-style
// conversion, as specified in docs/list-editing-proposal.md.
//
// Each command reads the list around the selection into a line model, edits
// the model, renumbers the ordered lists the edit touched, and writes back
// only the lines that changed, in one transaction (one undo step). The model
// is line-based on purpose: renumbering has to see the result of the edit,
// which the syntax tree has not parsed yet. The tree is used only to find
// where a list starts and ends, and to keep code, HTML and front matter out.

const QUOTE_PREFIX = /^(?:[ \t]{0,3}>[ \t]?)*/
const ITEM_LINE = /^([ \t]*)([-+*]|\d{1,9}[.)])([ \t]+|$)(\[[ xX]\](?:[ \t]+|$))?/
const THEMATIC_BREAK = /^[ \t]*([-*_])(?:[ \t]*\1){2,}[ \t]*$/
const FENCE_OPEN = /^[ \t]*(`{3,}|~{3,})/
const OPAQUE_BLOCKS = new Set(["FencedCode", "CodeBlock", "HTMLBlock", "CommentBlock"])

const columns = (text) => {
  let column = 0
  for (const character of text) column = character === "\t" ? column + 4 - (column % 4) : column + 1
  return column
}

// ---------------------------------------------------------------------------
// Line model
// ---------------------------------------------------------------------------

const isBullet = (marker) => /^[-+*]$/.test(marker)
const listType = (line) => isBullet(line.marker) ? line.marker : "ordered" + line.marker.slice(-1)

function setItemFields(line, indentStr, marker, sep, box, content) {
  Object.assign(line, { base: "item", kind: "item", indentStr, marker, sep, box, content })
  line.indent = columns(indentStr)
  // Five or more spaces after the marker start indented code; the item's
  // text column is then one past the marker (CommonMark).
  const gap = sep.length === 0 || columns(sep) > 4 ? 1 : columns(sep)
  line.contentCol = line.indent + marker.length + gap
}

function parseLine(text, number) {
  const quote = QUOTE_PREFIX.exec(text)[0]
  const body = text.slice(quote.length)
  const line = { n: number, quote, body, base: body.trim() ? "text" : "blank", indent: columns(/^[ \t]*/.exec(body)[0]) }
  if (line.base === "blank") return line
  const match = ITEM_LINE.exec(body)
  if (match && !THEMATIC_BREAK.test(body)) {
    setItemFields(line, match[1], match[2], match[3], match[4] || "", body.slice(match[0].length))
  }
  return line
}

const itemBody = (line) => line.indentStr + line.marker + line.sep + line.box + line.content
const render = (line) => line.quote + (line.base === "item" ? itemBody(line) : line.body)
const blankLine = (quote) => ({ n: null, quote: quote.replace(/[ \t]+$/, ""), body: "", base: "blank", indent: 0 })
// Offset of the item text within the rendered line.
const prefixLength = (line) => line.quote.length + line.indentStr.length
  + line.marker.length + line.sep.length + line.box.length
// The shortest prefix that still reads as the marker: one space after the
// marker and the box. The rendered marker can leave the caret here when the
// source has extra spaces.
const minimalPrefix = (line) => line.quote.length + line.indentStr.length + line.marker.length
  + Math.min(line.sep.length, 1) + (line.box ? Math.min(line.box.length, 4) : 0)

function newItem(like, content) {
  const line = { n: null, quote: like.quote, touched: true }
  setItemFields(line, like.indentStr, like.marker, like.sep || " ", like.box ? "[ ] " : "", content)
  return line
}

function toText(line, body) {
  for (const key of ["indentStr", "marker", "sep", "box", "content", "contentCol", "parent", "group"]) delete line[key]
  line.base = line.kind = body.trim() ? "text" : "blank"
  line.body = body
  line.indent = columns(/^[ \t]*/.exec(body)[0])
}

function setIndent(line, column) {
  if (line.kind === "item") {
    setItemFields(line, " ".repeat(column), line.marker, line.sep, line.box, line.content)
  } else {
    line.body = " ".repeat(column) + line.body.replace(/^[ \t]*/, "")
    line.indent = column
  }
}

// Shift a line's indentation by `delta` columns, clamping at the margin.
function shiftLine(line, delta) {
  if (!delta || line.kind === "blank") return
  if (line.kind === "code" && delta > 0) {
    line.body = " ".repeat(delta) + line.body
    return
  }
  if (line.kind === "code") {
    let removed = 0, index = 0
    while (index < line.body.length && removed < -delta && /[ \t]/.test(line.body[index])) {
      removed = line.body[index] === "\t" ? removed + 4 - (removed % 4) : removed + 1
      index++
    }
    line.body = line.body.slice(index)
    return
  }
  setIndent(line, Math.max(0, line.indent + delta))
}

// Derive item nesting, sibling groups and item extents from indentation,
// approximating CommonMark: a line belongs to the deepest open item whose text
// column it reaches; paragraph text may continue lazily; a paragraph at an
// item's level ends that item's sublist.
function analyze(lines) {
  const root = { kids: { group: null } }
  const groups = []
  const stack = []
  let fence = null, paragraph = false
  for (let index = 0; index < lines.length; index++) {
    const line = lines[index]
    line.index = index
    line.owner = null
    line.kind = line.base
    if (fence) {
      line.kind = "code"
      line.owner = fence.owner
      const close = /^[ \t]*(`{3,}|~{3,})[ \t]*$/.exec(line.body)
      if (close && close[1][0] === fence.marker[0] && close[1].length >= fence.marker.length) fence = null
      continue
    }
    if (line.kind === "blank") {
      line.owner = stack[stack.length - 1] ?? null
      paragraph = false
      continue
    }
    // An empty item cannot interrupt a paragraph, and a top-level line indented
    // four columns is code: both stay text.
    if (line.kind === "item" && ((paragraph && !stack.length && !line.content.trim() && !line.box)
        || (!stack.length && line.indent >= 4))) {
      line.kind = "text"
    }
    if (line.kind === "item") {
      while (stack.length && line.indent < stack[stack.length - 1].contentCol) stack.pop()
      const parent = stack[stack.length - 1] ?? null
      const holder = (parent ?? root).kids
      const type = listType(line)
      let group = holder.group
      if (!group || !group.open || group.type !== type) {
        group = { type, items: [], parent, open: true }
        holder.group = group
        groups.push(group)
      }
      group.items.push(line)
      Object.assign(line, { parent, group, owner: parent, end: index, kids: { group: null } })
      stack.push(line)
      paragraph = line.content.trim() !== ""
      continue
    }
    const lazy = paragraph && stack.length > 0 && line.indent < stack[stack.length - 1].contentCol
    if (!lazy) {
      while (stack.length && line.indent < stack[stack.length - 1].contentCol) stack.pop()
      const holder = (stack[stack.length - 1] ?? root).kids
      if (holder.group) holder.group.open = false
    }
    line.owner = stack[stack.length - 1] ?? null
    const open = FENCE_OPEN.exec(line.body)
    if (open) {
      line.kind = "code"
      fence = { owner: line.owner, marker: open[1] }
      paragraph = false
    } else {
      paragraph = true
    }
  }
  for (const line of lines) {
    if (line.kind === "blank") continue
    for (let item = line.kind === "item" ? line.parent : line.owner; item; item = item.parent) {
      item.end = Math.max(item.end, line.index)
    }
  }
  for (const group of groups) {
    group.loose = group.items.some((item, i) => {
      const next = group.items[i + 1]
      if (!next) return false
      for (let index = item.end + 1; index < next.index; index++) if (lines[index].kind === "blank") return true
      return false
    })
  }
  return groups
}

const subtree = (lines, item) => lines.slice(item.index + 1, item.end + 1)

// Move an item's line to `indent`, optionally with a new marker; its
// continuation lines and children follow its text column.
function moveItem(lines, item, indent, marker = item.marker) {
  const before = item.contentCol
  const children = subtree(lines, item)
  setItemFields(item, " ".repeat(indent), marker, item.sep || " ", item.box, item.content)
  const delta = item.contentCol - before
  for (const line of children) shiftLine(line, delta)
  item.touched = true
}

// The marker an item takes when it joins `group`'s list.
const markerFor = (group, item) => !group ? item.marker
  : group.type.startsWith("ordered") ? "1" + group.type.slice(-1) : group.type

// ---------------------------------------------------------------------------
// Ordered numbering
// ---------------------------------------------------------------------------

// Record each item's pre-edit numbering, so renumbering can follow a list's
// own style: sequential lists are renumbered, `1. 1. 1.` lists copy their
// number, and any other numbering is left alone.
function snapshot(groups) {
  for (const group of groups) {
    const ordered = !isBullet(group.type)
    const numbers = group.items.map((item) => ordered ? parseInt(item.marker, 10) : 0)
    const mode = !ordered ? "bullet"
      : numbers.length > 1 && numbers.every((number) => number === numbers[0]) ? "same"
      : numbers.every((number, i) => i === 0 || number === numbers[i - 1] + 1) ? "sequential"
      : "keep"
    const old = { items: group.items.slice(), start: numbers[0], mode, dirty: false }
    group.items.forEach((item, i) => { item.old = { group: old, index: i, number: numbers[i] } })
  }
}

function setNumber(lines, item, number, delimiter) {
  const marker = String(number) + delimiter
  if (marker !== item.marker) moveItem(lines, item, item.indent, marker)
}

function renumber(lines, groups) {
  for (const line of lines) {
    if (line.old && (line.touched || line.kind !== "item")) line.old.group.dirty = true
  }
  for (const group of groups) {
    if (isBullet(group.type)) continue
    const items = group.items
    if (!items.some((item) => item.touched || item.old?.group.dirty)) continue
    const delimiter = group.type.slice(-1)
    const anchor = items.find((item) => !item.touched && item.old)
    const mode = anchor ? anchor.old.group.mode : "sequential"
    if (mode === "same") {
      for (const item of items) if (item.touched) setNumber(lines, item, anchor.old.number, delimiter)
      continue
    }
    if (mode === "keep") {
      let previous = 0
      for (const item of items) {
        if (item.touched || !item.old) setNumber(lines, item, previous + 1, delimiter)
        previous = parseInt(item.marker, 10)
      }
      continue
    }
    const first = items[0]
    let next = 1
    if (!first.touched && first.old) {
      // A list split by an edit continues its numbering after the split.
      const before = first.old.group.items.slice(0, first.old.index).reverse()
        .find((item) => item.kind === "item" && !item.touched && item.parent === group.parent
          && item.index < first.index)
      next = before ? parseInt(before.marker, 10) + 1 : first.old.group.start
    }
    for (const item of items) setNumber(lines, item, next++, delimiter)
  }
}

// ---------------------------------------------------------------------------
// Reading and writing a block
// ---------------------------------------------------------------------------

const treeOf = (state, upto) => ensureSyntaxTree(state, upto, 100) ?? syntaxTree(state)

// The outermost list containing the line, within its blockquote, or null;
// "code" when the line is inside code, HTML or other opaque content.
function enclosingList(state, lineNumber) {
  const line = state.doc.line(lineNumber)
  const quote = QUOTE_PREFIX.exec(line.text)[0].length
  const offset = quote + (/^[ \t]*/.exec(line.text.slice(quote))[0].length)
  const pos = Math.min(line.from + offset, line.to)
  if (!markdownLanguage.isActiveAt(state, pos, 1) && !markdownLanguage.isActiveAt(state, pos, -1)) return "code"
  let outer = null
  for (let node = treeOf(state, line.to).resolveInner(pos, 1); node; node = node.parent) {
    if (OPAQUE_BLOCKS.has(node.name)) return "code"
    if (node.name === "Blockquote") break
    if (node.name === "BulletList" || node.name === "OrderedList") outer = node
  }
  if (!outer) return null
  return { first: state.doc.lineAt(outer.from).number, last: state.doc.lineAt(outer.to).number }
}

function readBlock(state, first, last) {
  const lines = []
  for (let n = first; n <= last; n++) lines.push(parseLine(state.doc.line(n).text, n))
  const groups = analyze(lines)
  snapshot(groups)
  return { first, lines }
}

// Renumber, then turn the edited model into changes against the document.
// Returns the changes and a function from (line, offset) to a position in the
// new document.
function writeBlock(state, block) {
  renumber(block.lines, analyze(block.lines))
  const { doc, lineBreak } = state
  const changes = []
  let pending = [], previousEnd = null
  for (const line of block.lines) {
    const text = render(line)
    if (line.n == null) {
      if (previousEnd == null) pending.push(text)
      else changes.push({ from: previousEnd, insert: lineBreak + text })
      continue
    }
    const old = doc.line(line.n)
    if (pending.length) {
      changes.push({ from: old.from, insert: pending.join(lineBreak) + lineBreak })
      pending = []
    }
    if (text !== old.text) {
      let start = 0, end = 0
      const shorter = Math.min(text.length, old.text.length)
      while (start < shorter && text[start] === old.text[start]) start++
      while (end < shorter - start && text[text.length - 1 - end] === old.text[old.text.length - 1 - end]) end++
      changes.push({ from: old.from + start, to: old.to - end, insert: text.slice(start, text.length - end) })
    }
    previousEnd = old.to
  }
  const startPos = doc.line(block.first).from
  const position = (target, offset) => {
    let pos = startPos
    for (const line of block.lines) {
      if (line === target) return pos + offset
      pos += render(line).length + lineBreak.length
    }
    return pos
  }
  return { changes, position }
}

// Run `edit` for each cursor on its own list block. Cursors that share a
// block, or a cursor outside a list, leave the key to the default command.
function perCursor(edit, userEvent) {
  return (view) => {
    const { state } = view
    const results = []
    for (const range of state.selection.ranges) {
      const result = edit(state, range)
      if (!result) return false
      results.push(result)
    }
    const spans = results.map((result) => result.span).sort((a, b) => a[0] - b[0])
    for (let i = 1; i < spans.length; i++) if (spans[i][0] <= spans[i - 1][1]) return false
    const changes = state.changes(results.flatMap((result) => result.changes))
    const ranges = results.map((result) => {
      // Earlier blocks' edits shift this block's caret by their net length.
      let shift = 0
      for (const other of results) {
        if (other !== result && other.span[0] < result.span[0]) shift += other.delta
      }
      return EditorSelection.cursor(result.caret + shift)
    })
    view.dispatch({
      changes,
      selection: EditorSelection.create(ranges, state.selection.mainIndex),
      scrollIntoView: true,
      userEvent,
    })
    return true
  }
}

function cursorResult(state, block, line, offset) {
  const { changes, position } = writeBlock(state, block)
  const delta = state.changes(changes).newLength - state.doc.length
  return {
    changes,
    caret: position(line, offset),
    delta,
    span: [block.first, block.first + block.lines.filter((l) => l.n != null).length - 1],
  }
}

// The block and model line at a cursor, or null outside a list.
function cursorContext(state, pos) {
  const lineNumber = state.doc.lineAt(pos).number
  let list = enclosingList(state, lineNumber)
  // The parser ends a list at its last text, so a blank continuation line
  // just below it (Shift-Enter's) is read with the list above.
  if (!list && lineNumber > 1 && !state.doc.line(lineNumber).text.trim()) {
    list = enclosingList(state, lineNumber - 1)
    if (list && list !== "code" && list.last === lineNumber - 1) list = { first: list.first, last: lineNumber }
    else list = null
  }
  if (!list || list === "code") return null
  const block = readBlock(state, list.first, list.last)
  const line = block.lines[lineNumber - list.first]
  if (line.kind === "code") return null
  return { block, line, offset: pos - state.doc.line(lineNumber).from }
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

function outdent(lines, item) {
  const parent = item.parent
  moveItem(lines, item, parent.indent, markerFor(parent.group, item))
}

// Enter: split the item, continue the list, exit or outdent an empty item,
// and start a new sibling from a continuation line (spec section 2, 8.3).
function enter(state, range) {
  if (!range.empty) return null
  const context = cursorContext(state, range.head)
  if (!context) return null
  const { block, line, offset } = context
  const { lines } = block
  const insertAt = (index, ...added) => lines.splice(index, 0, ...added)

  if (line.kind === "item") {
    if (offset < line.quote.length + line.indentStr.length) return null
    const prefix = prefixLength(line)
    const at = Math.max(offset, prefix)
    const text = render(line)
    const empty = !line.content.trim() && line.end === line.index
    if (empty && line.parent) {
      outdent(lines, line)
      return cursorResult(state, block, line, prefixLength(line))
    }
    if (empty) {
      // Leave the list: the line becomes an empty paragraph, after a blank
      // separator so the paragraph does not continue the list lazily.
      toText(line, "")
      const previous = lines[line.index - 1]
      if (previous && previous.kind !== "blank") {
        const caretLine = { ...blankLine(""), quote: line.quote }
        line.quote = line.quote.replace(/[ \t]+$/, "")
        insertAt(line.index + 1, caretLine)
        return cursorResult(state, block, caretLine, caretLine.quote.length)
      }
      return cursorResult(state, block, line, line.quote.length)
    }
    if (at === prefix) {
      // At the start of the text: an empty item goes in above.
      const above = newItem(line, "")
      above.touched = false
      above.old = line.old
      line.old = null
      line.touched = true
      insertAt(line.index, above)
      return cursorResult(state, block, line, prefixLength(line))
    }
    line.content = text.slice(prefix, at).replace(/[ \t]+$/, "")
    const next = newItem(line, text.slice(at))
    const added = [next]
    if (line.group.loose) added.unshift(blankLine(line.quote))
    insertAt(line.index + 1, ...added)
    return cursorResult(state, block, next, prefixLength(next))
  }

  const owner = line.owner
  if (!owner || offset < line.quote.length) return null
  if (line.kind === "blank") {
    // A blank continuation line, as Shift-Enter leaves it, becomes the item.
    if (!line.body || line.indent < owner.contentCol) return null
    const item = newItem(owner, "")
    item.n = line.n
    lines[line.index] = item
    return cursorResult(state, block, item, prefixLength(item))
  }
  const text = render(line)
  const before = text.slice(line.quote.length, offset).replace(/[ \t]+$/, "")
  const after = text.slice(offset).replace(/^[ \t]+/, "")
  if (!before.trim()) {
    const item = newItem(owner, after)
    item.n = line.n
    lines[line.index] = item
    return cursorResult(state, block, item, prefixLength(item))
  }
  line.body = before
  const item = newItem(owner, after)
  insertAt(line.index + 1, item)
  return cursorResult(state, block, item, prefixLength(item))
}

// Shift-Enter: a continuation line at the item's text column (spec 8.2).
function continuation(state, range) {
  if (!range.empty) return null
  const context = cursorContext(state, range.head)
  if (!context) return null
  const { block, line, offset } = context
  const owner = line.kind === "item" ? line : line.owner
  if (!owner || (line.kind !== "item" && line.kind !== "text")) return null
  const text = render(line)
  const start = line.kind === "item" ? prefixLength(line) : line.quote.length
  if (offset < start) return null
  const after = text.slice(offset)
  if (line.kind === "item") line.content = text.slice(start, offset)
  else line.body = text.slice(line.quote.length, offset)
  const added = { n: null, quote: line.quote, base: after.trim() ? "text" : "blank",
    indent: owner.contentCol, body: " ".repeat(owner.contentCol) + after }
  block.lines.splice(line.index + 1, 0, added)
  return cursorResult(state, block, added, line.quote.length + owner.contentCol)
}

// Backspace right after a marker: outdent a nested item; otherwise remove
// the marker (and task box), so the text joins the item above (spec 4.1, 4.2).
function backspace(state, range) {
  if (!range.empty) return null
  const context = cursorContext(state, range.head)
  if (!context) return null
  const { block, line, offset } = context
  if (line.kind !== "item") return null
  if (offset < minimalPrefix(line) || offset > prefixLength(line)) return null
  const { lines } = block
  if (line.parent) {
    outdent(lines, line)
    return cursorResult(state, block, line, prefixLength(line))
  }
  if (!line.content.trim()) {
    toText(line, "")
    return cursorResult(state, block, line, line.quote.length)
  }
  const siblings = line.group.items
  const previous = siblings[siblings.indexOf(line) - 1]
  const indent = previous ? previous.contentCol : 0
  toText(line, " ".repeat(indent) + line.content)
  return cursorResult(state, block, line, line.quote.length + indent)
}

// ---------------------------------------------------------------------------
// Selection-wide edits: Tab, Shift-Tab and list-style conversion
// ---------------------------------------------------------------------------

function selectedLineNumbers(state) {
  const numbers = new Set()
  for (const range of state.selection.ranges) {
    const first = state.doc.lineAt(range.from).number
    let last = state.doc.lineAt(range.to).number
    // A selection ending at the start of a line does not include that line.
    if (!range.empty && last > first && state.doc.line(last).from === range.to) last--
    for (let n = first; n <= last; n++) numbers.add(n)
  }
  return [...numbers].sort((a, b) => a - b)
}

// One block covering the selected lines and every list they touch, plus the
// lists right before and after, whose numbering a conversion can continue.
function selectionBlock(state, numbers) {
  let first = numbers[0], last = numbers[numbers.length - 1]
  const extend = (n) => {
    if (n < 1 || n > state.doc.lines) return
    const list = enclosingList(state, n)
    if (list && list !== "code") {
      first = Math.min(first, list.first)
      last = Math.max(last, list.last)
    }
  }
  extend(first - 1)
  extend(last + 1)
  for (const n of numbers) extend(n)
  return readBlock(state, first, last)
}

function dispatchSelectionEdit(view, block) {
  const { state } = view
  const { changes } = writeBlock(state, block)
  const changeSet = state.changes(changes)
  if (!changeSet.empty) {
    view.dispatch({
      changes: changeSet,
      selection: state.selection.map(changeSet, 1),
      scrollIntoView: true,
      userEvent: "input.list",
      annotations: isolateHistory.of("full"),
    })
  }
  return true
}

// Items touched by the selection, outermost first: a selected child moves
// with its parent rather than on its own.
function selectedItems(state) {
  const numbers = selectedLineNumbers(state)
  if (numbers.some((n) => enclosingList(state, n) === "code")) return null
  const block = selectionBlock(state, numbers)
  const touched = new Set()
  for (const n of numbers) {
    const line = block.lines[n - block.first]
    const item = line.kind === "item" ? line : line.owner
    if (item) touched.add(item)
  }
  const top = [...touched].filter((item) => {
    for (let parent = item.parent; parent; parent = parent.parent) if (touched.has(parent)) return false
    return true
  }).sort((a, b) => a.index - b.index)
  return top.length ? { block, items: top } : null
}

// Tab: nest each selected item under its previous sibling, at that sibling's
// text column or its existing sublist (spec 3.1–3.4).
export function indentListItems(view) {
  const selection = selectedItems(view.state)
  if (!selection) return false
  const { block, items } = selection
  const moving = new Set(items)
  for (const item of items) {
    const siblings = item.group.items
    let position = siblings.indexOf(item)
    // The parent is the sibling before the run of selected siblings.
    while (position > 0 && moving.has(siblings[position - 1])) position--
    const parent = siblings[position - 1]
    if (!parent) continue
    const sublist = parent.kids.group?.open && parent.kids.group.items.at(-1).end === parent.end
      ? parent.kids.group : null
    const indent = sublist ? sublist.items[0].indent : parent.contentCol
    moveItem(block.lines, item, indent, sublist ? markerFor(sublist, item) : item.marker)
  }
  return dispatchSelectionEdit(view, block)
}

// Shift-Tab: make each selected nested item a sibling of its parent; a
// top-level item stays where it is (spec 3.1, 3.2, 3.5).
export function outdentListItems(view) {
  const selection = selectedItems(view.state)
  if (!selection) return false
  for (const item of selection.items) if (item.parent) outdent(selection.block.lines, item)
  return dispatchSelectionEdit(view, selection.block)
}

// The list item on line `lineNumber`, for `/move`: its first and last line,
// children and continuation lines included, and its text moved to the
// margin with everything under it shifted the same way. A line that
// continues an item belongs to that item. Null outside a list, in code and
// in a quote.
export function listItemExtent(state, lineNumber) {
  const list = enclosingList(state, lineNumber)
  if (!list || list === "code") return null
  const { first, lines } = readBlock(state, list.first, list.last)
  const line = lines[lineNumber - first]
  const item = line.kind === "item" ? line : line.owner
  if (!item || item.quote) return null
  const own = lines.slice(item.index, item.end + 1)
  const delta = -item.indent
  for (const each of own) shiftLine(each, delta)
  return { first: first + item.index, last: first + item.end, text: own.map(render).join("\n") }
}

export const LIST_STYLES = ["none", "bullet", "ordered", "task"]

export function lineListStyle(line) {
  if (line.kind !== "item") return "none"
  if (line.box) return "task"
  return isBullet(line.marker) ? "bullet" : "ordered"
}

function convertibleLines(state) {
  const numbers = selectedLineNumbers(state).filter((n) => enclosingList(state, n) !== "code")
  if (!numbers.length) return null
  const block = selectionBlock(state, numbers)
  const lines = numbers.map((n) => block.lines[n - block.first])
    .filter((line) => line.kind === "item" || line.kind === "text")
  return lines.length ? { block, lines } : null
}

// Switch the selected lines to a list style. Only the marker and task box
// change; item text and indentation stay (spec section 5).
export function setListStyle(view, style) {
  if (!LIST_STYLES.includes(style)) return false
  const selection = convertibleLines(view.state)
  if (!selection) return true
  for (const line of selection.lines) {
    const current = lineListStyle(line)
    if (current === style) continue
    if (style === "none") {
      toText(line, line.indentStr + line.content)
      continue
    }
    if (line.kind !== "item") {
      const indent = /^[ \t]*/.exec(line.body)[0]
      setItemFields(line, indent, style === "ordered" ? "1." : "-", " ", "", line.body.slice(indent.length))
    }
    line.box = style === "task" ? line.box || "[ ] " : ""
    const marker = style === "bullet" && !isBullet(line.marker) ? "-"
      : style === "ordered" && isBullet(line.marker) ? "1." : line.marker
    // A wider or narrower marker carries the item's children along, so the
    // nesting stays as it was.
    moveItem(selection.block.lines, line, line.indent, marker)
  }
  return dispatchSelectionEdit(view, selection.block)
}

// The list style shared by the selected lines: a style, "none" or "mixed".
export function selectedListStyle(state) {
  const selection = convertibleLines(state)
  if (!selection) return "none"
  const styles = selection.lines.map(lineListStyle)
  return styles.every((style) => style === styles[0]) ? styles[0] : "mixed"
}

// Menu and shortcut toggles: a selection already in `style` goes back to
// plain paragraphs; anything else becomes `style` (spec 5.2).
export const toggleListStyle = (style) => (view) =>
  setListStyle(view, selectedListStyle(view.state) === style ? "none" : style)

export const continueList = perCursor(enter, "input")
export const insertListContinuation = perCursor(continuation, "input")
export const deleteListMarker = perCursor(backspace, "delete.backward")

// Text typed at the left margin of an empty line right below a list starts a
// paragraph, as it looks on screen (spec 2.7). Markdown would otherwise read
// it as a lazy continuation of the last item, so a blank line goes in first.
// Indentation and marker characters keep the line in the list: continuation
// lines are indented (Shift-Enter), and `-`, `*`, `+` or a digit can begin a
// new item.
export const paragraphAfterList = Prec.high(EditorView.inputHandler.of((view, from, to, text) => {
  const { state } = view
  if (from !== to || !text || /^[ \t\-*+0-9]/.test(text) || state.selection.ranges.length > 1) return false
  const line = state.doc.lineAt(from)
  if (line.length || line.number === 1) return false
  const above = state.doc.line(line.number - 1)
  if (!above.text.trim()) return false
  const list = enclosingList(state, above.number)
  if (!list || list === "code" || list.last !== above.number) return false
  const insert = state.lineBreak + text
  view.dispatch({
    changes: { from, insert },
    selection: { anchor: from + insert.length },
    scrollIntoView: true,
    userEvent: "input.type",
  })
  return true
}))
