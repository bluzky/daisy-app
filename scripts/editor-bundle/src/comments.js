import { Decoration, ViewPlugin, WidgetType, EditorView } from "@codemirror/view"
import { EditorSelection } from "@codemirror/state"
import { syntaxTree } from "@codemirror/language"
import { registerEditorExtension } from "./extensions.js"
import { hide } from "./decoration-parts.js"

// Reader comments in CriticMarkup: `{==text==}{>>comment<<}`, or a bare
// `{>>comment<<}`. Like bold and italic, a comment hides its markup until the
// caret is on its line, and then look as they do in Read mode: the commented
// text highlighted with its notes in a popover on hover, or a small bubble for
// a comment on a spot. With the caret on the line the whole source shows,
// dimmed, to edit (`MarkdownComments` in Swift owns the rules; keep the two in
// step: notes are one line, an anchor stops at a blank line, code is not
// scanned).

const syntaxMark = Decoration.mark({ class: "cm-comment-syntax" })
const anchorMark = Decoration.mark({ class: "cm-comment-anchor" })
const noteMark = Decoration.mark({ class: "cm-comment-note" })

// An anchor ends at the first `==}` (which must be followed by a note) and
// never crosses a blank line. A note is one line and ends at the first `<<}`;
// it may be empty. Whether a
// comment counts is decided on its notes' text, as Swift does: an empty or
// white-space-only note is no comment (see `noteTexts`).
const COMMENT = /(?:\{==((?:(?!\n[ \t]*\n|==\})[^])+?)==\}(?=\{>>))?((?:\{>>(?:(?!<<\})[^\n])*<<\})+)/g
const NOTE = /\{>>((?:(?!<<\})[^\n])*)<<\}/g
const CODE_NODES = new Set([
  "FencedCode", "CodeBlock", "InlineCode", "CodeText", "Comment", "CommentBlock",
])

// The notes that have text. A comment with none is plain text, as in Read mode.
function noteTexts(match) {
  return Array.from(match[2].matchAll(NOTE), (note) => note[1].trim()).filter(Boolean)
}

function inCode(tree, position) {
  for (let node = tree.resolveInner(position, 1); node; node = node.parent) {
    if (CODE_NODES.has(node.name)) return true
  }
  return false
}

// A comment with replies lists its notes, each behind a bullet, so they read as
// separate; a single note is shown as it is. `data-list` switches the hanging
// indent on (see `commentPopoverCSS` in Swift).
function popoverText(notes) {
  return notes.length > 1 ? notes.map((note) => `\u2022 ${note}`).join("\n") : notes[0]
}

// The bubble standing in for a comment on a spot. Its note shows on hover (CSS
// reads it from `data-comment`, as Read mode does); a click puts the caret
// there, which brings the source back to edit.
class CommentBubble extends WidgetType {
  constructor(notes) {
    super()
    this.notes = notes
  }
  eq(other) {
    return other.notes.length === this.notes.length
      && other.notes.every((note, index) => note === this.notes[index])
  }
  toDOM(view) {
    const bubble = document.createElement("span")
    bubble.className = "cm-comment-point"
    bubble.setAttribute("data-comment", popoverText(this.notes))
    if (this.notes.length > 1) bubble.setAttribute("data-list", "")
    bubble.setAttribute("role", "img")
    bubble.setAttribute("aria-label", this.notes.join(". "))
    bubble.addEventListener("mousedown", (event) => {
      event.preventDefault()
      view.dispatch({ selection: { anchor: view.posAtDOM(bubble) }, scrollIntoView: true })
      view.focus()
    })
    return bubble
  }
  ignoreEvent() { return true }
}

// Whether the caret, or any selected range, touches a line the comment is on.
function touched(state, from, to) {
  const start = state.doc.lineAt(from).from
  const end = state.doc.lineAt(to).to
  return state.selection.ranges.some((range) => range.from <= end && range.to >= start)
}

// What to scan for the visible ranges: each grown to its whole paragraph, since
// an anchor can start above the viewport and stops only at a blank line. Ranges
// that now touch are merged so nothing is scanned twice.
function scanRanges(doc, visibleRanges) {
  const grown = visibleRanges.map(({ from, to }) => {
    let first = doc.lineAt(from)
    for (let steps = 0; first.number > 1 && steps < 200; steps++) {
      const previous = doc.line(first.number - 1)
      if (!previous.text.trim()) break
      first = previous
    }
    let last = doc.lineAt(to)
    for (let steps = 0; last.number < doc.lines && steps < 200; steps++) {
      const next = doc.line(last.number + 1)
      if (!next.text.trim()) break
      last = next
    }
    return { from: first.from, to: last.to }
  })
  const merged = []
  for (const range of grown.sort((a, b) => a.from - b.from)) {
    const previous = merged[merged.length - 1]
    if (previous && range.from <= previous.to) previous.to = Math.max(previous.to, range.to)
    else merged.push({ ...range })
  }
  return merged.filter((range) => range.to > range.from)
}

function buildComments(view) {
  const { state } = view
  const tree = syntaxTree(state)
  const { doc } = state
  const found = []
  const hidden = []
  for (const { from, to } of scanRanges(doc, view.visibleRanges)) {
    const text = doc.sliceString(from, to)
    COMMENT.lastIndex = 0
    for (let match = COMMENT.exec(text); match; match = COMMENT.exec(text)) {
      const start = from + match.index
      if ((match.index > 0 && text[match.index - 1] === "\\") || inCode(tree, start)) continue
      const notes = noteTexts(match)
      if (!notes.length) continue
      const end = start + match[0].length
      const raw = touched(state, start, end)
      let position = start
      if (match[1] !== undefined) {
        const anchorEnd = start + 3 + match[1].length
        if (raw) {
          found.push(syntaxMark.range(start, start + 3))
          found.push(anchorMark.range(start + 3, anchorEnd))
          found.push(syntaxMark.range(anchorEnd, anchorEnd + 3))
        } else {
          // As in Read mode: the text carries its notes, and the markup around
          // it, with the notes themselves, is hidden.
          const anchor = Decoration.mark({
            class: "cm-comment-anchor",
            attributes: notes.length > 1
              ? { "data-comment": popoverText(notes), "data-list": "" }
              : { "data-comment": popoverText(notes) },
          })
          found.push(hide.range(start, start + 3), anchor.range(start + 3, anchorEnd), hide.range(anchorEnd, end))
          hidden.push(hide.range(start, start + 3), hide.range(anchorEnd, end))
        }
        position = anchorEnd + 3
      } else if (!raw) {
        const bubble = Decoration.replace({ widget: new CommentBubble(notes) })
        found.push(bubble.range(start, end))
        hidden.push(bubble.range(start, end))
      }
      if (raw) {
        for (const note of match[2].matchAll(NOTE)) {
          const length = note[0].length
          found.push(syntaxMark.range(position, position + 3))
          // An empty note has no text to tint, and CodeMirror rejects empty marks.
          if (length > 6) found.push(noteMark.range(position + 3, position + length - 3))
          found.push(syntaxMark.range(position + length - 3, position + length))
          position += length
        }
      }
    }
  }
  return { all: Decoration.set(found, true), hidden: Decoration.set(hidden, true) }
}

const commentsPlugin = ViewPlugin.fromClass(class {
  constructor(view) { Object.assign(this, buildComments(view)) }
  update(update) {
    if (update.docChanged || update.viewportChanged || update.selectionSet
        || syntaxTree(update.startState) !== syntaxTree(update.state)) {
      Object.assign(this, buildComments(update.view))
    }
  }
}, {
  decorations: (plugin) => plugin.all,
  // The caret skips what is hidden, as it skips a bold mark's asterisks.
  provide: (plugin) => EditorView.atomicRanges.of((view) => view.plugin(plugin)?.hidden ?? Decoration.none),
})

// Insert ▸ Comment. A selection becomes the commented text and the caret lands
// in the empty note; with no selection a bare note goes in at the caret. With
// the caret already in a comment, a reply is added after its last note, so a
// second press answers instead of nesting.
export function insertComment(view) {
  const { state } = view
  const tree = syntaxTree(state)
  const changes = state.changeByRange((range) => {
    // Code is not scanned for comments, so markup put there would do nothing.
    if (inCode(tree, range.head) || inCode(tree, range.from)
        || (range.to > range.from && inCode(tree, range.to - 1))) {
      return { range }
    }
    const line = state.doc.lineAt(range.head)
    const text = line.text
    COMMENT.lastIndex = 0
    for (let match = COMMENT.exec(text); match; match = COMMENT.exec(text)) {
      const start = line.from + match.index
      const end = start + match[0].length
      if (range.head >= start && range.head <= end) {
        // Already in a note that has no text yet: nothing more to add.
        if (!noteTexts(match).length) return { range }
        return {
          changes: { from: end, insert: "{>><<}" },
          range: EditorSelection.cursor(end + 3),
        }
      }
    }
    let { from, to } = range
    while (from < to && /\s/.test(state.sliceDoc(from, from + 1))) from++
    while (to > from && /\s/.test(state.sliceDoc(to - 1, to))) to--
    const selected = state.sliceDoc(from, to)
    if (!selected || /\n[ \t]*\n/.test(selected)) {
      return {
        changes: { from: range.to, insert: "{>><<}" },
        range: EditorSelection.cursor(range.to + 3),
      }
    }
    return {
      changes: { from, to, insert: `{==${selected}==}{>><<}` },
      range: EditorSelection.cursor(from + 3 + selected.length + 3 + 3),
    }
  })
  if (changes.changes.empty) return
  view.dispatch(state.update(changes, { scrollIntoView: true, userEvent: "input" }))
}

registerEditorExtension({ id: "comments", extensions: () => [commentsPlugin] })
