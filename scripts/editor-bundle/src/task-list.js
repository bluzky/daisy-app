import { WidgetType } from "@codemirror/view"
import { EditorSelection } from "@codemirror/state"
import { insertNewlineContinueMarkupCommand } from "@codemirror/lang-markdown"
import { tags as t } from "@lezer/highlight"

// Completed task markers stay rendered while typing the label, including an empty item.
export class TaskCheckboxWidget extends WidgetType {
  constructor(from, checked) { super(); this.from = from; this.checked = checked }
  eq(other) { return this.from === other.from && this.checked === other.checked }
  toDOM(view) {
    const wrapper = document.createElement('span')
    wrapper.className = 'cm-md-task-marker'
    wrapper.dataset.sourceFrom = String(this.from)
    const checkbox = document.createElement('input')
    checkbox.type = 'checkbox'
    checkbox.checked = this.checked
    checkbox.setAttribute('aria-label', this.checked ? 'Mark task incomplete' : 'Mark task complete')
    checkbox.addEventListener('mousedown', event => {
      event.preventDefault()
      event.stopPropagation()
    })
    checkbox.addEventListener('change', () => {
      const keyboardFocused = document.activeElement === checkbox
      view.dispatch({ changes: { from: this.from, to: this.from + 1,
        insert: checkbox.checked ? 'x' : ' ' }, userEvent: 'input' })
      if (!keyboardFocused) view.focus()
    })
    wrapper.append(checkbox, document.createTextNode(" "))
    return wrapper
  }
  updateDOM(wrapper) {
    // Reuse the focused input when toggling; replacing it also loses Tab order.
    if (Number(wrapper.dataset.sourceFrom) !== this.from) return false
    const checkbox = wrapper.querySelector('input')
    checkbox.checked = this.checked
    checkbox.setAttribute('aria-label', this.checked ? 'Mark task incomplete' : 'Mark task complete')
    return true
  }
  ignoreEvent() { return true }
}

// CodeMirror's default second-item behavior creates a loose list. An empty
// task should instead leave the list on the second Enter, like other editors.
const continueTightTaskList = insertNewlineContinueMarkupCommand({ nonTightLists: false })
export function continueTaskList(view) {
  if (!view.state.selection.ranges.every(range => range.empty
      && /^[ \t]*(?:>[ \t]*)*[-+*][ \t]+\[[ xX]\](?:[ \t]|$)/.test(
        view.state.doc.lineAt(range.head).text))) return false
  return continueTightTaskList({
    state: view.state,
    dispatch: transaction => {
      // A blank separator prevents the next paragraph from becoming a lazy
      // continuation of the task above it in Markdown.
      const state = transaction.state
      const changes = state.changeByRange(range => {
        const line = state.doc.lineAt(range.head)
        if (range.empty && line.text === '' && line.number > 1
            && state.doc.line(line.number - 1).text.trim() !== '') {
          return { changes: { from: range.head, insert: state.lineBreak },
            range: EditorSelection.cursor(range.head + state.lineBreak.length) }
        }
        return { range }
      })
      view.dispatch([transaction, state.update(changes, { userEvent: 'input', scrollIntoView: true })])
    },
  })
}
