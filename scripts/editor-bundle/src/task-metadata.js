import { Decoration, ViewPlugin, WidgetType } from "@codemirror/view"
import { syntaxTree } from "@codemirror/language"
import { registerEditorExtension } from "./extensions.js"
import { formatLocalDate, parseLocalDate } from "./dates.js"
import { documentFind, currentFindTouches } from "./find.js"
import { pointerPreview } from "./pointer.js"
import { TASK_FIELD_KEYS, taskLine } from "./task-field-commands.js"
import { isTaskFieldValue } from "./task-fields.js"

// Task metadata badges: on a checkbox task's marker line, each valid `due:`,
// `scheduled:` and `p:` reads as a badge, like the rest of live preview. The
// caret (or the current find match) on a field shows its source for editing.
// Read mode draws the same `.mdp-task-badge` markup (see
// `MarkdownHTML.taskMetadataScript`); the stylesheet is shared.

const FIELD_HINT = /(?:due|scheduled|p):/
const ICONS = {
  due: '<circle cx="10" cy="10" r="6.5"/><path d="M10 6.5V10l2.5 1.5"/>',
  scheduled: '<rect x="3.5" y="4.5" width="13" height="12" rx="2"/><path d="M3.5 8.5h13M7 3v3M13 3v3"/>',
}

// English fallbacks; the host passes localized ones as module options.
const DEFAULT_LABELS = {
  due: "Due", scheduled: "Scheduled", overdue: "Overdue", priority: "Priority",
  high: "High", medium: "Medium", low: "Low",
}

function formatDate(locale, date, options) {
  try { return new Intl.DateTimeFormat(locale || undefined, options).format(date) }
  catch (_) { return new Intl.DateTimeFormat("en", options).format(date) }
}

// English fallbacks merged with the host's labels.
export const taskBadgeLabels = (options) => ({ ...DEFAULT_LABELS, ...options })

// One `.mdp-task-badge`: `key` is `due`, `scheduled` or `p`. Also drawn by
// query block results (`query-blocks.js`).
export function taskBadgeElement(document, key, value, overdue, labels) {
  const element = document.createElement("span")
  element.className = `mdp-task-badge mdp-task-badge-${key === "p" ? "priority" : key}`
  element.setAttribute("role", "img")
  if (key === "p") {
    const text = labels[value]
    element.classList.add(`mdp-task-badge-${value}`)
    element.textContent = text.toLocaleUpperCase(labels.locale || undefined)
    element.setAttribute("aria-label", `${labels.priority}: ${text}`)
    return element
  }
  const date = parseLocalDate(value)
  if (overdue) element.classList.add("mdp-task-badge-overdue")
  element.innerHTML = `<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICONS[key]}</svg>`
  element.appendChild(document.createTextNode(`${value} ${formatDate(labels.locale, date, { weekday: "short" })}`))
  element.setAttribute("aria-label", `${labels[key]}: ${formatDate(labels.locale, date, { dateStyle: "full" })}`
    + (overdue ? `, ${labels.overdue}` : ""))
  return element
}

class TaskBadgeWidget extends WidgetType {
  constructor(key, value, overdue, labels) {
    super()
    this.key = key
    this.value = value
    this.overdue = overdue
    this.labels = labels
  }

  eq(other) {
    return other.key === this.key && other.value === this.value && other.overdue === this.overdue
  }

  toDOM(view) {
    return taskBadgeElement(view.dom.ownerDocument, this.key, this.value, this.overdue, this.labels)
  }

  // Let clicks through so the caret lands on the field and reveals it.
  ignoreEvent() { return false }
}

function badges(view, labels, clock) {
  const { state } = view
  const pointer = state.field(pointerPreview, false)
  const selection = pointer?.selection ?? state.selection.main
  const focused = pointer ? pointer.focused : view.hasFocus
  const caret = focused && selection.empty ? selection.head : null
  const today = formatLocalDate(clock())
  const ranges = []
  let lastLine = 0
  for (const { from, to } of view.visibleRanges) {
    for (let position = from; position <= to;) {
      const line = state.doc.lineAt(position)
      position = line.to + 1
      if (line.number <= lastLine) continue
      lastLine = line.number
      if (!FIELD_HINT.test(line.text)) continue
      const task = taskLine(state, line)
      if (!task) continue
      const done = /\[[xX]\]/.test(line.text.slice(0, task.contentStart))
      for (const key of TASK_FIELD_KEYS) {
        for (const occurrence of task.occurrences[key]) {
          if (!isTaskFieldValue(key, occurrence.value)) continue
          const fieldFrom = line.from + occurrence.from
          const fieldTo = line.from + occurrence.to
          if (caret != null && caret >= fieldFrom && caret <= fieldTo) continue
          if (currentFindTouches(state, fieldFrom, fieldTo)) continue
          const overdue = key === "due" && !done && occurrence.value < today
          ranges.push(Decoration.replace({ widget: new TaskBadgeWidget(key, occurrence.value, overdue, labels) })
            .range(fieldFrom, fieldTo))
        }
      }
    }
  }
  return Decoration.set(ranges, true)
}

function taskMetadataExtensions(options, host) {
  const labels = taskBadgeLabels(options)
  const clock = () => (host.callbacks && host.callbacks.slashClock ? host.callbacks.slashClock() : new Date())
  const plugin = ViewPlugin.fromClass(class {
    constructor(view) { this.decorations = badges(view, labels, clock) }
    update(update) {
      if (update.docChanged || update.selectionSet || update.viewportChanged || update.focusChanged
          || update.startState.field(pointerPreview, false) !== update.state.field(pointerPreview, false)
          || syntaxTree(update.startState) !== syntaxTree(update.state)
          || update.startState.field(documentFind, false) !== update.state.field(documentFind, false)) {
        this.decorations = badges(update.view, labels, clock)
      }
    }
  }, { decorations: (plugin) => plugin.decorations })
  return [plugin]
}

registerEditorExtension({ id: "task-metadata", extensions: taskMetadataExtensions })
