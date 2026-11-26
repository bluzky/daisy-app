import { EditorView, Decoration } from "@codemirror/view"
import { StateField } from "@codemirror/state"
import { syntaxTree, ensureSyntaxTree } from "@codemirror/language"
import { fencedCodeDetails } from "./fenced-code.js"
import { currentFindTouches, documentFind, setFind } from "./find.js"
import { activeCodeBlock, pointerPreview } from "./pointer.js"

// ---------------------------------------------------------------------------
// Fence previews
//
// A fence in one of `languages` is replaced by a block widget while the caret
// is outside it and the current find match isn't in it. `widget(details)`
// returns the widget, or null to leave the fence as code. Shared by Mermaid
// diagrams and the widget blocks (`stat`, `chart`, `progress`).
//
// `triggerPattern`, when given, limits rebuilding on edits to changes whose
// text matches it; other edits only move the old decorations. Without it,
// every edit rebuilds, which a widget whose result depends on the fence's
// whole source needs: an undo or a reload can change a value while the caret
// is outside the block. `revealedBySelection(selection, from, to)`, when
// given, also leaves a fence as source for a non-empty selection it returns
// true for. `onBuild` runs before each rebuild (for caches).
// ---------------------------------------------------------------------------

export function fencePreviewField({
  languages, triggerPattern = null, widget, revealedBySelection = null, onBuild = null,
}) {
  const accepted = new Set(languages)
  const build = (state) => {
    onBuild?.()
    const ranges = []
    const activeFence = state.field(activeCodeBlock)
    const tree = ensureSyntaxTree(state, state.doc.length, 80) || syntaxTree(state)
    tree.iterate({
      enter(node) {
        if (node.name !== "FencedCode") return
        const details = fencedCodeDetails(state, node)
        if (!accepted.has(details.language)) return
        const isActive = activeFence != null
          && node.from <= activeFence.from && node.to >= activeFence.to
        if (isActive || currentFindTouches(state, node.from, node.to)
            || revealedBySelection?.(state.selection.main, node.from, node.to)) return false
        const preview = widget(details)
        if (preview) {
          ranges.push(Decoration.replace({ block: true, widget: preview }).range(node.from, node.to))
        }
        return false
      },
    })
    return Decoration.set(ranges, true)
  }

  // Previews replace entire fenced ranges, so they must be provided directly
  // from editor state rather than from a view plugin.
  return StateField.define({
    create: (state) => build(state),
    update: (value, tr) => {
      if (tr.state.field(pointerPreview)) {
        if (tr.startState.field(pointerPreview)?.activateOnSelection
            && !tr.state.field(pointerPreview).activateOnSelection) return build(tr.state)
        return value
      }
      if (tr.startState.field(pointerPreview)) return build(tr.state)
      const previousActive = tr.startState.field(activeCodeBlock)
      const nextActive = tr.state.field(activeCodeBlock)
      const activeChanged = previousActive?.from !== nextActive?.from
        || previousActive?.to !== nextActive?.to

      let sourceChanged = false
      if (tr.docChanged) {
        if (!triggerPattern) {
          sourceChanged = true
        } else {
          tr.changes.iterChanges((fromA, toA, _fromB, _toB, inserted) => {
            if (sourceChanged) return
            const removed = tr.startState.doc.sliceString(fromA, toA)
            sourceChanged = triggerPattern.test(removed + inserted.toString())
          })
        }
      }

      // A caret moving on its own is covered by the active fence.
      const rangeChanged = revealedBySelection != null && tr.selection != null
        && !(tr.startState.selection.main.empty && tr.state.selection.main.empty)

      if (activeChanged || sourceChanged || rangeChanged
          || tr.effects.some((effect) => effect.is(setFind))
          || (tr.docChanged && tr.state.field(documentFind).query)) return build(tr.state)
      if (tr.docChanged) return value.map(tr.changes)
      return value
    },
    provide: (field) => EditorView.decorations.from(field),
  })
}
