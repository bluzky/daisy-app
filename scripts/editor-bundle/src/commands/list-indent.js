import { insertTab } from "@codemirror/commands"
import { tags as t } from "@lezer/highlight"
import { dispatchBlockChanges } from "./format.js"
import { markdownListMarker } from "../decoration-parts.js"
import { fencedCodeAt } from "../fenced-code.js"

// Markdown assigns semantic meaning to four leading spaces: headings,
// paragraphs, tables, fences, and other top-level blocks become code blocks.
// List items are different: keep each Tab as authored, including repeated
// indentation, rather than imposing a maximum nesting depth in the editor.
export function indentMarkdownListItems(view) {
  const selection = view.state.selection.main
  const firstLine = view.state.doc.lineAt(selection.from)
  let lastLine = view.state.doc.lineAt(selection.to)
  if (!selection.empty
      && selection.to === lastLine.from
      && lastLine.number > firstLine.number) {
    lastLine = view.state.doc.line(lastLine.number - 1)
  }

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
  }

  const firstMatch = firstLine.text.match(markdownListMarker)
  if (!firstMatch) {
    // Within ordinary text, behave like a text editor and insert a tab at the
    // caret. Guard the leading source margin:
    // indenting a top-level Markdown block there would reinterpret it as an
    // indented code block.
    if (selection.empty) {
      const offset = selection.head - firstLine.from
      const leadingWhitespace = firstLine.text.match(/^[ \t]*/)?.[0].length || 0
      if (offset > leadingWhitespace) return insertTab(view)
    }
    return true
  }
  const changes = []
  for (let number = firstLine.number; number <= lastLine.number; number++) {
    changes.push({ from: view.state.doc.line(number).from, insert: "    " })
  }
  dispatchBlockChanges(view, changes)
  return true
}
