import { EditorView, Decoration } from "@codemirror/view"
import { StateEffect, StateField } from "@codemirror/state"

// Search the source buffer, including lines outside CodeMirror's mounted DOM.
// Decorations keep highlights visible while the native toolbar owns focus.
export const setFind = StateEffect.define()
function findState(doc, query, beginsWith, index = 0) {
  const matches = []
  if (query) {
    const pattern = new RegExp(query.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "giu")
    const text = doc.toString()
    for (const match of text.matchAll(pattern)) {
      const from = match.index
      if (!beginsWith || from === 0 || !/[A-Za-z0-9_]/.test(text[from - 1])) {
        matches.push({ from, to: from + match[0].length })
      }
    }
  }
  index = matches.length ? Math.min(Math.max(index, 0), matches.length - 1) : -1
  const decorations = Decoration.set(matches.map((match, i) =>
    Decoration.mark({ class: i === index ? "cm-find-match cm-find-current" : "cm-find-match" })
      .range(match.from, match.to)))
  return { query, beginsWith, matches, index, decorations }
}
export const documentFind = StateField.define({
  create: (state) => findState(state.doc, "", false),
  update(value, tr) {
    for (const effect of tr.effects) {
      if (effect.is(setFind)) {
        const { query, beginsWith, index } = effect.value
        return findState(tr.state.doc, query, beginsWith, index)
      }
    }
    return tr.docChanged
      ? findState(tr.state.doc, value.query, value.beginsWith, value.index)
      : value
  },
  provide: (field) => EditorView.decorations.from(field, (value) => value.decorations),
})
export function currentFindTouches(state, from, to) {
  const search = state.field(documentFind)
  const match = search.matches[search.index]
  return !!match && match.from < to && match.to > from
}
export const findTheme = EditorView.baseTheme({
  ".cm-find-match": { backgroundColor: "#ffe58a", color: "#201800", borderRadius: "2px" },
  ".cm-find-current": { backgroundColor: "#ffad33", outline: "1px solid #9b5700" },
})
