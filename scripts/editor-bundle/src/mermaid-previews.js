import { EditorView, Decoration } from "@codemirror/view"
import { StateField } from "@codemirror/state"
import { syntaxTree, ensureSyntaxTree } from "@codemirror/language"
import { fencedCodeDetails } from "./fenced-code.js"
import { currentFindTouches, documentFind, setFind } from "./find.js"
import { activeCodeBlock, pointerPreview } from "./pointer.js"
import { MermaidWidget } from "./widgets/mermaid.js"

function buildMermaidPreviews(state) {
  const ranges = []
  const activeFence = state.field(activeCodeBlock)
  const tree = ensureSyntaxTree(state, state.doc.length, 80) || syntaxTree(state)
  tree.iterate({
    enter(node) {
      if (node.name !== "FencedCode") return
      const details = fencedCodeDetails(state, node)
      const isActive = activeFence != null
        && node.from <= activeFence.from && node.to >= activeFence.to
      if (details.language === "mermaid" && !isActive && !currentFindTouches(state, node.from, node.to)) {
        ranges.push(Decoration.replace({
          block: true,
          widget: new MermaidWidget(details.source),
        }).range(node.from, node.to))
        return false
      }
    },
  })
  return Decoration.set(ranges, true)
}

// Mermaid previews replace entire fenced ranges, so they must be provided
// directly from editor state rather than from a view plugin.
export const mermaidPreviews = StateField.define({
  create: (state) => buildMermaidPreviews(state),
  update: (value, tr) => {
    if (tr.state.field(pointerPreview)) {
      if (tr.startState.field(pointerPreview)?.activateOnSelection
          && !tr.state.field(pointerPreview).activateOnSelection) return buildMermaidPreviews(tr.state)
      return value
    }
    if (tr.startState.field(pointerPreview)) return buildMermaidPreviews(tr.state)
    const previousActive = tr.startState.field(activeCodeBlock)
    const nextActive = tr.state.field(activeCodeBlock)
    const activeChanged = previousActive?.from !== nextActive?.from
      || previousActive?.to !== nextActive?.to

    let fenceSyntaxChanged = false
    if (tr.docChanged) {
      tr.changes.iterChanges((fromA, toA, _fromB, _toB, inserted) => {
        if (fenceSyntaxChanged) return
        const removed = tr.startState.doc.sliceString(fromA, toA)
        const changedSource = removed + inserted.toString()
        fenceSyntaxChanged = /[`~]|mermaid/i.test(changedSource)
      })
    }

    if (activeChanged || fenceSyntaxChanged || tr.effects.some((effect) => effect.is(setFind))
        || (tr.docChanged && tr.state.field(documentFind).query)) return buildMermaidPreviews(tr.state)
    if (tr.docChanged) return value.map(tr.changes)
    return value
  },
  provide: (field) => EditorView.decorations.from(field),
})
