import { Prec } from "@codemirror/state"
import { keymap } from "@codemirror/view"
import { registerEditorExtension } from "./extensions.js"
import { fencePreviewField } from "./fence-previews.js"
import { WIDGET_LANGUAGES, fencedCodeAt } from "./fenced-code.js"
import { WidgetBlockWidget, blockValidity, isWidgetBlock } from "./widgets/widget.js"

// Widget blocks (```stat, ```chart, ```progress) are drawn in place of their
// fence while the caret is outside it, like a Mermaid diagram. A block the
// widget script can't read stays code, as it does in Read mode.
//
// No trigger pattern: a widget depends on every line of its source, so any
// edit rebuilds (the validity cache keeps that cheap).
export const widgetPreviews = fencePreviewField({
  languages: WIDGET_LANGUAGES,
  widget: (details) => isWidgetBlock(details)
    ? new WidgetBlockWidget(details.explicitLanguage, details.source)
    : null,
  // Either end of a selection inside a block shows its source, so that an
  // edit never changes hidden text. One reaching past both ends leaves it
  // drawn.
  revealedBySelection: ({ anchor, head }, from, to) =>
    [anchor, head].some((pos) => pos > from && pos < to),
  onBuild: () => blockValidity.begin(),
})

// CodeMirror's vertical motion steps over a block widget, so ArrowUp and
// ArrowDown would never reach a drawn block's source. When a move would step
// over one, the caret goes to its nearest source line instead.
const enterWidgetBlock = (forward) => (view) => {
  const selection = view.state.selection.main
  if (!selection.empty) return false
  const { head } = view.moveVertically(selection, forward)
  let block = null
  // The block nearest the caret in the move's direction: ranges arrive in
  // document order, so that is the first one going down and the last going up.
  view.state.field(widgetPreviews).between(
    Math.min(selection.head, head), Math.max(selection.head, head), (from, to) => {
      if (forward) {
        if (!block && from > selection.head) block = { from, to }
      } else if (to < selection.head) {
        block = { from, to }
      }
    })
  if (!block) return false
  const { doc } = view.state
  const opening = doc.lineAt(block.from).number
  const last = doc.lineAt(block.to)
  // An unclosed fence's last line is source, not a closing marker.
  const { closed } = fencedCodeAt(view.state, block.to)
  const lastSourceLine = closed ? last.number - 1 : last.number
  const line = forward ? Math.min(opening + 1, last.number) : Math.max(lastSourceLine, opening)
  view.dispatch({
    selection: { anchor: doc.line(line).from }, userEvent: "select", scrollIntoView: true,
  })
  return true
}

registerEditorExtension({
  id: "widgets",
  extensions: () => [
    widgetPreviews,
    Prec.high(keymap.of([
      { key: "ArrowDown", run: enterWidgetBlock(true) },
      { key: "ArrowUp", run: enterWidgetBlock(false) },
    ])),
  ],
})
