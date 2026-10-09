import { EditorView, Decoration } from "@codemirror/view"
import { StateField } from "@codemirror/state"
import { syntaxTree, ensureSyntaxTree } from "@codemirror/language"
import { joinDeco } from "./decoration-parts.js"

// ---------------------------------------------------------------------------
// Paragraph reflow
// ---------------------------------------------------------------------------
// Markdown soft breaks (hard-wrapped source lines) render as spaces in the
// preview. Mirror that: while the cursor is outside a paragraph, each
// internal newline (plus the next line's continuation indent) collapses to
// a single space so the text reflows to the full measure. Lines ending in
// a hard break (two trailing spaces or a backslash) keep their newline —
// they render as a real break in the preview too.
//
// Decorations that replace line breaks affect vertical layout, which view
// plugins are forbidden to do — these must come from a StateField.

function computeJoins(state) {
  const ranges = []
  const sel = state.selection.main
  const touches = (from, to) => sel.from <= to && sel.to >= from
  // Joins span the whole document, so make sure the tree does too —
  // otherwise paragraphs past the initial parse chunk stay unjoined
  // until the first edit.
  const tree = ensureSyntaxTree(state, state.doc.length, 80) || syntaxTree(state)
  tree.iterate({
    enter: (node) => {
      const name = node.name
      // Code content can look hard-wrapped; never descend into it.
      if (name === "FencedCode" || name === "CodeBlock" || name === "HTMLBlock") return false
      if (name !== "Paragraph") return
      if (touches(node.from, node.to)) return false
      let line = state.doc.lineAt(node.from)
      while (line.to < node.to) {
        const tail = state.doc.sliceString(Math.max(line.from, line.to - 2), line.to)
        const hardBreak = tail.endsWith("  ") || tail.endsWith("\\")
        const next = state.doc.lineAt(line.to + 1)
        if (!hardBreak) {
          const indent = next.text.length - next.text.trimStart().length
          ranges.push(joinDeco.range(line.to, next.from + indent))
        }
        line = next
      }
      return false
    },
  })
  return Decoration.set(ranges, true)
}

const paragraphReflow = StateField.define({
  create: (state) => computeJoins(state),
  update: (value, tr) => (tr.docChanged || tr.selection) ? computeJoins(tr.state) : value,
  provide: (field) => EditorView.decorations.from(field),
})
