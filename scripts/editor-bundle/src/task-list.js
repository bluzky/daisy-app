import { WidgetType } from "@codemirror/view"
import { isolateHistory } from "@codemirror/commands"

// Completed task markers stay rendered while typing the label, including an empty item.
export class TaskCheckboxWidget extends WidgetType {
  // `inline` places the box at the start of the text, after a numbered
  // marker, instead of hanging it in the marker box.
  constructor(from, checked, inline = false) { super(); this.from = from; this.checked = checked; this.inline = inline }
  eq(other) { return this.from === other.from && this.checked === other.checked && this.inline === other.inline }
  toDOM(view) {
    const wrapper = document.createElement('span')
    wrapper.className = this.inline ? 'cm-md-task-marker cm-md-task-inline' : 'cm-md-task-marker'
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
      // Its own undo step: typing right after a click never merges into it.
      view.dispatch({ changes: { from: this.from, to: this.from + 1,
        insert: checkbox.checked ? 'x' : ' ' }, userEvent: 'input.task',
        annotations: isolateHistory.of('full') })
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

// Cmd+Enter on a list item steps it through list item -> open task -> done
// task -> list item. Each selected list line steps from its own state; lines
// that are not list items are left alone, and a selection with none of them
// falls through to the default Cmd+Enter.
const LIST_ITEM_MARKER = /^([ \t]*(?:>[ \t]?)*(?:[-+*]|\d{1,9}[.)])[ \t]+)(\[[ xX]\][ \t]?)?/
export function cycleListItemState(view) {
  const { state } = view
  const changes = []
  let last = -1
  for (const range of state.selection.ranges) {
    const fromLine = state.doc.lineAt(range.from).number
    const toLine = state.doc.lineAt(range.to).number
    for (let number = Math.max(fromLine, last + 1); number <= toLine; number++) {
      const line = state.doc.line(number)
      const match = LIST_ITEM_MARKER.exec(line.text)
      if (!match) continue
      const from = line.from + match[1].length
      const task = match[2]
      if (!task) changes.push({ from, insert: '[ ] ' })
      else if (task[1] === ' ') changes.push({ from: from + 1, to: from + 2, insert: 'x' })
      else changes.push({ from, to: from + task.length, insert: '' })
    }
    last = toLine
  }
  if (!changes.length) return false
  view.dispatch({ changes, userEvent: 'input.list.cycle', scrollIntoView: true,
    annotations: isolateHistory.of('full') })
  return true
}
