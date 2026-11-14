import { insertTab } from "@codemirror/commands"
import { fencedCodeAt } from "../fenced-code.js"

// Tab outside a list (lists.js handles list items first). Markdown assigns
// semantic meaning to four leading spaces: headings, paragraphs, tables,
// fences, and other top-level blocks become code blocks. So within ordinary
// text Tab behaves like a text editor and inserts a tab at the caret, but at
// a line's leading margin it does nothing. Inside fenced code it indents.
export function indentMarkdownListItems(view) {
  const selection = view.state.selection.main
  const firstLine = view.state.doc.lineAt(selection.from)

  if (selection.empty) {
    const fence = fencedCodeAt(view.state, selection.head)
    if (fence) {
      const openingLine = view.state.doc.lineAt(fence.from)
      const closingLine = view.state.doc.lineAt(fence.to)
      if (firstLine.number > openingLine.number
          && (!fence.closed || firstLine.number < closingLine.number)) {
        return insertTab(view)
      }
    }
    const offset = selection.head - firstLine.from
    const leadingWhitespace = firstLine.text.match(/^[ \t]*/)?.[0].length || 0
    if (offset > leadingWhitespace) return insertTab(view)
  }
  return true
}
