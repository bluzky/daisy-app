import { Annotation, EditorState } from "@codemirror/state"
import { syntaxTree } from "@codemirror/language"

// A second fence typed inside an existing block is a deliberate closing mark,
// so only a fence that starts its own line can be paired automatically.
const autoClosedFence = Annotation.define()

function fenceStartAt(state, pos) {
  let node = syntaxTree(state).resolve(pos, -1)
  while (node) {
    if (node.name === "FencedCode") return node.from
    node = node.parent
  }
  return null
}

export const autoCloseFence = EditorState.transactionFilter.of((tr) => {
  if (!tr.docChanged || !tr.isUserEvent("input") || tr.annotation(autoClosedFence)) {
    return tr
  }

  const selection = tr.newSelection.main
  if (!selection.empty) return tr

  const line = tr.newDoc.lineAt(selection.head)
  const offset = selection.head - line.from
  if (line.text.slice(0, offset) !== "```" || line.text.slice(offset) !== "") {
    return tr
  }

  let openedOnThisLine = false
  let openingOldPos = null
  tr.changes.iterChanges((fromA, toA, fromB, toB, inserted) => {
    if (openedOnThisLine || fromB > selection.head || toB < selection.head) return
    const oldLine = tr.startState.doc.lineAt(fromA)
    const oldPrefix = oldLine.text.slice(0, fromA - oldLine.from)
    const oldSuffix = oldLine.text.slice(toA - oldLine.from)
    const insertedText = inserted.toString()
    const completesFence = (oldPrefix === "" && insertedText === "```")
      || (oldPrefix === "``" && insertedText === "`")
    openedOnThisLine = oldSuffix === ""
      && completesFence
      && fromB <= line.from + 2
      && toB >= line.from + 3
    if (openedOnThisLine) openingOldPos = fromA
  })
  if (!openedOnThisLine) return tr

  const oldLine = tr.startState.doc.lineAt(openingOldPos)
  const existingFenceStart = fenceStartAt(tr.startState, openingOldPos)
  if (existingFenceStart != null && existingFenceStart < oldLine.from) return tr

  return [
    tr,
    {
      changes: { from: selection.head, insert: "\n\n```" },
      selection: { anchor: selection.head + 1 },
      annotations: autoClosedFence.of(true),
      sequential: true,
    },
  ]
})
