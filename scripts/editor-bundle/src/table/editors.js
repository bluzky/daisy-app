import { EditorView, Decoration } from "@codemirror/view"
import { StateField } from "@codemirror/state"
import { syntaxTree, ensureSyntaxTree } from "@codemirror/language"
import { currentFindTouches, setFind } from "../find.js"
import { parseTableSource } from "./model.js"
import { TableEditorWidget } from "./widget.js"

function buildTableEditors(state) {
  const ranges = []
  const tree = ensureSyntaxTree(state, state.doc.length, 80) || syntaxTree(state)
  tree.iterate({
    enter(node) {
      if (node.name !== "Table") return
      if (currentFindTouches(state, node.from, node.to)) return false
      const source = state.doc.sliceString(node.from, node.to)
      if (!parseTableSource(source)) return
      ranges.push(Decoration.replace({
        block: true,
        widget: new TableEditorWidget(source, node.from),
      }).range(node.from, node.to))
      return false
    },
  })
  return Decoration.set(ranges, true)
}

export const tableEditors = StateField.define({
  create: buildTableEditors,
  update: (value, transaction) => transaction.docChanged || transaction.effects.some((effect) => effect.is(setFind))
    ? buildTableEditors(transaction.state)
    : value,
  provide: (field) => EditorView.decorations.from(field),
})
