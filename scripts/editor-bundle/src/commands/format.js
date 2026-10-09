import { EditorSelection } from "@codemirror/state"
import { syntaxTree } from "@codemirror/language"
import { tags as t } from "@lezer/highlight"
import { parseTableSource } from "../table/model.js"

// ---------------------------------------------------------------------------
// Bold / italic toggles
// ---------------------------------------------------------------------------

export function toggleInlineMark(marker) {
  return (view) => {
    const changes = view.state.changeByRange((range) => {
      let { from, to } = range
      // CommonMark rejects emphasis that opens or closes against
      // whitespace ("** bold **"), so keep it outside the markers.
      while (from < to && /\s/.test(view.state.sliceDoc(from, from + 1))) from++
      while (to > from && /\s/.test(view.state.sliceDoc(to - 1, to))) to--
      const len = marker.length
      const before = view.state.sliceDoc(Math.max(0, from - len), from)
      const after = view.state.sliceDoc(to, to + len)
      if (before === marker && after === marker) {
        return {
          changes: [
            { from: from - len, to: from, insert: "" },
            { from: to, to: to + len, insert: "" },
          ],
          range: EditorSelection.range(from - len, to - len),
        }
      }
      const selected = view.state.sliceDoc(from, to)
      if (selected.startsWith(marker) && selected.endsWith(marker) && selected.length >= len * 2) {
        return {
          changes: { from, to, insert: selected.slice(len, selected.length - len) },
          range: EditorSelection.range(from, to - len * 2),
        }
      }
      return {
        changes: { from, to, insert: marker + selected + marker },
        range: EditorSelection.range(from + len, to + len),
      }
    })
    view.dispatch(changes, { scrollIntoView: true, userEvent: "input" })
    return true
  }
}

// ---------------------------------------------------------------------------
// Block-level toggles (headings, quotes, lists) and link insertion —
// backing for the host app's formatting bar.
// ---------------------------------------------------------------------------

function eachSelectedLine(state, fn) {
  const sel = state.selection.main
  const start = state.doc.lineAt(sel.from).number
  const end = state.doc.lineAt(sel.to).number
  const lines = []
  for (let n = start; n <= end; n++) lines.push(state.doc.line(n))
  return fn(lines)
}

export function toggleBlockPrefix(prefix, pattern) {
  return (view) => {
    const changes = eachSelectedLine(view.state, (lines) => {
      const all = lines.every((line) => pattern.test(line.text))
      return lines.map((line) => {
        if (all) {
          const m = line.text.match(pattern)
          return { from: line.from, to: line.from + m[0].length, insert: "" }
        }
        return pattern.test(line.text) ? null : { from: line.from, insert: prefix }
      }).filter(Boolean)
    })
    if (changes.length) dispatchBlockChanges(view, changes)
    return true
  }
}

// Dispatch line-prefix edits while keeping the cursor after any inserted
// prefix (the default mapping leaves it before, stranding the caret behind
// the new list marker).
export function dispatchBlockChanges(view, changes) {
  const changeSet = view.state.changes(changes)
  const sel = view.state.selection.main
  view.dispatch({
    changes,
    selection: EditorSelection.range(
      changeSet.mapPos(sel.anchor, 1),
      changeSet.mapPos(sel.head, 1)
    ),
    userEvent: "input",
  })
}

export function orderedList(view) {
  const pattern = /^\d+\.\s/
  const changes = eachSelectedLine(view.state, (lines) => {
    const all = lines.every((line) => pattern.test(line.text))
    let i = 1
    return lines.map((line) => {
      if (all) {
        const m = line.text.match(pattern)
        return { from: line.from, to: line.from + m[0].length, insert: "" }
      }
      return pattern.test(line.text) ? null : { from: line.from, insert: `${i++}. ` }
    }).filter(Boolean)
  })
  if (changes.length) dispatchBlockChanges(view, changes)
  return true
}

function selectedListLines(state) {
  const selection = state.selection.main
  const start = state.doc.lineAt(selection.from).number
  const end = state.doc.lineAt(selection.empty ? selection.to : selection.to - 1).number
  return Array.from({ length: end - start + 1 }, (_, index) => state.doc.line(start + index))
}

export function listPrefix(text) {
  const match = /^([ \t]*(?:>[ \t]*)*)(?:([-+*]|\d+[.)])([ \t]+)(\[[ xX]\][ \t]+)?)?/.exec(text)
  return {
    prefix: match[0], indent: match[1],
    style: !match[2] ? 'none' : match[4] ? 'task' : /^\d/.test(match[2]) ? 'ordered' : 'bullet',
  }
}

export function enclosingNode(state, position, names) {
  for (let node = syntaxTree(state).resolve(position, 1); node; node = node.parent) {
    if (names.includes(node.name)) return node
  }
  return null
}

export function editableListLines(state) {
  return selectedListLines(state).filter(line =>
    !/^[ \t>]*$/.test(line.text)
    && !enclosingNode(state, line.from + line.text.search(/\S/), ['FencedCode', 'CodeBlock']))
}

export function applyListStyle(view, style) {
  if (!['none', 'bullet', 'ordered', 'task'].includes(style)) return false
  const changes = editableListLines(view.state).map((line, index) => {
    const current = listPrefix(line.text)
    if (current.style === style) return null
    const marker = style === 'none' ? '' : style === 'bullet' ? '- ' : style === 'task' ? '- [ ] ' : `${index + 1}. `
    return { from: line.from, to: line.from + current.prefix.length, insert: current.indent + marker }
  }).filter(Boolean)
  if (changes.length) dispatchBlockChanges(view, changes)
  view.focus()
  return true
}

export function setHeading(level) {
  return (view) => {
    const changes = eachSelectedLine(view.state, (lines) => lines.map((line) => {
      const m = line.text.match(/^(#{1,6})\s+/)
      const current = m ? m[1].length : 0
      const insert = current === level || level === 0 ? "" : "#".repeat(level) + " "
      return { from: line.from, to: line.from + (m ? m[0].length : 0), insert }
    }))
    view.dispatch({ changes, userEvent: "input" })
    return true
  }
}

export function stylingContext(state) {
  const styles = { InlineCode: 'code', FencedCode: 'fenced', CodeBlock: 'plain', Blockquote: 'quote', Table: 'table' }
  for (let node = syntaxTree(state).resolve(state.selection.main.head, state.selection.main.empty ? 1 : -1); node; node = node.parent) {
    if (styles[node.name]) return { style: styles[node.name], node }
  }
  return { style: 'none', node: null }
}

export function applyBlockStyle(view, style, language = '') {
  if (!['none', 'quote', 'code', 'plain', 'fenced', 'table'].includes(style)) return false
  const state = view.state, selection = state.selection.main
  const context = stylingContext(state)
  const containsSelection = context.node && selection.from >= context.node.from && selection.to <= context.node.to
  if (style === 'code' && (!containsSelection || context.style === 'code')) {
    if (context.style !== 'code') toggleInlineMark('`')(view)
    view.focus()
    return true
  }
  if (style === 'table') {
    const fence = enclosingNode(state, selection.to, ['FencedCode'])
    const end = fence ? fence.to : state.doc.lineAt(selection.to).to
    const close = fence && fence.lastChild?.name !== 'CodeMark'
      ? '\n' + state.sliceDoc(fence.firstChild.from, fence.firstChild.to) : ''
    const insert = close + '\n\n| Column 1 | Column 2 |\n| --- | --- |\n|  |  |\n'
    view.dispatch({ changes: { from: end, insert }, selection: { anchor: end + insert.length }, userEvent: 'input' })
    view.focus()
    return true
  }
  if (style === context.style && containsSelection && style !== 'fenced') return true
  if (style === 'quote' && !containsSelection) {
    const changes = selectedListLines(state).filter(line =>
      !enclosingNode(state, line.from + Math.max(0, line.text.search(/\S/)), ['Blockquote']))
      .map(line => ({ from: line.from, insert: '> ' }))
    if (changes.length) dispatchBlockChanges(view, changes)
    view.focus()
    return true
  }
  const lines = selectedListLines(state)
  let from = lines[0].from, to = lines[lines.length - 1].to
  let source = state.sliceDoc(from, to)
  const node = context.node
  if (node && selection.from >= node.from && selection.to <= node.to
      && (context.style !== 'code' || style === 'none')) {
    from = context.style === 'code' ? node.from : state.doc.lineAt(node.from).from
    to = node.to
    source = state.sliceDoc(from, to)
    if (context.style === 'fenced') {
      const opening = state.doc.lineAt(node.from)
      const last = state.doc.lineAt(node.to)
      const closed = node.lastChild?.name === 'CodeMark'
      source = state.sliceDoc(Math.min(opening.to + 1, node.to), closed ? last.from : node.to).replace(/\n$/, '')
    } else if (context.style === 'plain') source = source.replace(/^(?: {4}|\t)/gm, '')
    else if (context.style === 'quote') source = source.replace(/^ {0,3}> ?/gm, '')
    else if (context.style === 'code') source = state.sliceDoc(node.firstChild.to, node.lastChild.from)
    else if (context.style === 'table') {
      const model = parseTableSource(source)
      if (model) source = model.rows.map(row => row.join('\t')).join('\n')
    }
  }
  let insert = source, caretOffset = 0
  if (style === 'code') {
    source = source.replace(/\n/g, ' ')
    const fence = '`'.repeat(Math.max(1, ...(source.match(/`+/g) || []).map(run => run.length + 1)))
    const pad = /^`|`$/.test(source) || (/^ .* $/.test(source) && /\S/.test(source)) ? ' ' : ''
    insert = fence + pad + source + pad + fence
    caretOffset = fence.length + pad.length
  }
  if (style === 'quote') { insert = source.split('\n').map(line => '> ' + line).join('\n'); caretOffset = 2 }
  if (style === 'plain') { insert = source.split('\n').map(line => '    ' + line).join('\n'); caretOffset = 4 }
  if (style === 'fenced') {
    const runs = source.match(/`+/g) || []
    const fence = '`'.repeat(Math.max(3, ...runs.map(run => run.length + 1)))
    const info = String(language).replace(/[^\w+-]/g, '')
    const opening = fence + info + '\n'
    insert = opening + source + '\n' + fence
    caretOffset = opening.length
  }
  if (style === 'plain' && from > 0 && state.doc.lineAt(from - 1).text.trim()) {
    insert = '\n' + insert
    caretOffset++
  }
  view.dispatch({ changes: { from, to, insert }, selection: { anchor: from + caretOffset }, userEvent: 'input' })
  view.focus()
  return true
}

export function insertLink(view) {
  const range = view.state.selection.main
  const text = view.state.sliceDoc(range.from, range.to) || "text"
  const insert = `[${text}](url)`
  const urlStart = range.from + text.length + 3
  view.dispatch({
    changes: { from: range.from, to: range.to, insert },
    selection: EditorSelection.range(urlStart, urlStart + 3),
    userEvent: "input",
    scrollIntoView: true,
  })
  return true
}
