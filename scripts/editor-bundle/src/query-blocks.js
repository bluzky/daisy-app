import { EditorView, Decoration, ViewPlugin, WidgetType } from "@codemirror/view"
import { StateEffect, StateField } from "@codemirror/state"
import { syntaxTree, ensureSyntaxTree } from "@codemirror/language"
import { fencedCodeDetails } from "./fenced-code.js"
import { currentFindTouches, documentFind, setFind } from "./find.js"
import { activeCodeBlock, pointerPreview } from "./pointer.js"
import { registerEditorExtension } from "./extensions.js"
import { formatLocalDate } from "./dates.js"
import { taskBadgeElement, taskBadgeLabels } from "./task-metadata.js"
import { taskLineSegments } from "./task-line-segments.js"

// ```tasks and ```notes blocks show what their query matches, as in Read
// mode: the editor sends each block's text to the host
// (`onRunQueries([{ id, source, text }])`) whenever the blocks change, and
// the host answers through `setQueryResults([{ id, source, problems, rows,
// empty }])`, again whenever the workspace changes. A block with an answer
// is replaced by a widget until the caret enters it, like a Mermaid diagram;
// one without (outside a workspace, before the first answer) stays code.
// Rows open their file (`onOpenQueryResult`) and a task's checkbox checks it
// off (`onQueryTaskCheckbox`), both in the host.

const QUERY_LANGUAGES = new Set(["tasks", "notes"])

export const queryResultsChanged = StateEffect.define()

const hash = (text) => {
  let h = 5381
  for (let i = 0; i < text.length; i++) h = ((h << 5) + h + text.charCodeAt(i)) >>> 0
  return h.toString(36)
}

// Every query block in the document: `{ from, to, id, source, text }`. An
// empty block is not a query: it stays code and is never run.
export function queryBlocks(state) {
  const blocks = []
  const tree = ensureSyntaxTree(state, state.doc.length, 80) || syntaxTree(state)
  tree.iterate({
    enter(node) {
      if (node.name !== "FencedCode") return
      const details = fencedCodeDetails(state, node)
      if (QUERY_LANGUAGES.has(details.language) && details.source.trim()) {
        // Prefixed so an editor's ids never meet a Read mode page's.
        blocks.push({ from: node.from, to: node.to, source: details.language, text: details.source,
                      id: "editor:" + details.language + ":" + hash(details.source) })
      }
      return false
    },
  })
  return blocks
}

const queryResults = StateField.define({
  create: () => new Map(),
  update(value, tr) {
    for (const effect of tr.effects) if (effect.is(queryResultsChanged)) value = effect.value
    return value
  },
})

function element(tag, className, text) {
  const node = document.createElement(tag)
  if (className) node.className = className
  if (text != null) node.textContent = text
  return node
}

// A row's text as the document shows that task line: fields as badges and
// names as links that open their page.
function rowText(row, done, labels, callbacks) {
  const text = element("span", "cm-md-query-text")
  const segments = row.source ? taskLineSegments(row.source) : [{ type: "text", text: row.text }]
  const today = formatLocalDate(new Date())
  for (const segment of segments) {
    if (segment.type === "field") {
      text.append(taskBadgeElement(document, segment.key, segment.value,
        segment.key === "due" && !done && segment.value < today, labels))
    } else if (segment.type === "token") {
      const token = element("span", "cm-md-metadata-link cm-md-query-token", segment.text)
      token.setAttribute("role", "link")
      token.addEventListener("click", (event) => {
        event.preventDefault()
        event.stopPropagation()
        callbacks.onOpenLink?.({ token: segment.text })
      })
      text.append(token)
    } else {
      text.append(element("span", "cm-md-query-plain", segment.text))
    }
  }
  return text
}

class QueryResultsWidget extends WidgetType {
  constructor(result, callbacks, labels) { super(); this.result = result; this.callbacks = callbacks; this.labels = labels }
  eq(other) { return other.result === this.result }

  toDOM(view) {
    const { result, callbacks } = this
    const container = element("div", "cm-md-query")
    container.setAttribute("role", "region")
    if (result.problems.length) {
      const problems = element("ul", "cm-md-query-problems")
      for (const problem of result.problems) problems.append(element("li", null, problem))
      container.append(problems)
    }
    if (!result.rows.length) {
      container.append(element("p", "cm-md-query-empty", result.empty))
    } else {
      const list = element("ul", "cm-md-query-results cm-md-query-" + result.source)
      for (const row of result.rows) {
        const item = element("li", "cm-md-query-row")
        if (result.source === "tasks") {
          item.classList.add("cm-md-query-task")
          if (row.checked) item.classList.add("cm-md-query-done")
          const box = element("input", "cm-md-query-checkbox")
          box.type = "checkbox"
          box.checked = row.checked
          box.setAttribute("aria-label", row.text)
          box.addEventListener("mousedown", (event) => event.stopPropagation())
          box.addEventListener("change", () => {
            callbacks.onQueryTaskCheckbox?.({ path: row.path, line: row.line, checked: box.checked })
          })
          // The space the document's own task lines have after the box.
          item.append(box, document.createTextNode(" "))
        }
        const link = rowText(row, result.source === "tasks" && row.checked, this.labels, callbacks)
        link.classList.add("cm-md-query-link")
        link.setAttribute("role", "link")
        link.setAttribute("aria-label", row.text)
        link.addEventListener("mousedown", (event) => {
          event.preventDefault()
          event.stopPropagation()
        })
        link.addEventListener("click", (event) => {
          event.preventDefault()
          callbacks.onOpenQueryResult?.({ path: row.path, line: row.line })
        })
        item.append(link)
        if (row.detail) {
          const detail = element("span", "cm-md-query-detail", row.detail)
          detail.title = row.path
          item.append(detail)
        }
        list.append(item)
      }
      container.append(list)
    }

    // Anywhere else edits the query, as a click on a diagram edits its source.
    container.addEventListener("mousedown", (event) => {
      event.preventDefault()
      view.focus()
      const opening = view.state.doc.lineAt(view.posAtDOM(container))
      const anchor = opening.number < view.state.doc.lines
        ? view.state.doc.line(opening.number + 1).from
        : opening.to
      view.dispatch({ selection: { anchor }, userEvent: "select.pointer" })
    })
    return container
  }

  ignoreEvent() { return true }
}

function buildDecorations(state, callbacks, labels) {
  const results = state.field(queryResults)
  if (!results.size) return Decoration.none
  const activeFence = state.field(activeCodeBlock)
  const ranges = []
  for (const block of queryBlocks(state)) {
    const result = results.get(block.id)
    const isActive = activeFence != null && block.from <= activeFence.from && block.to >= activeFence.to
    if (!result || isActive || currentFindTouches(state, block.from, block.to)) continue
    ranges.push(Decoration.replace({ block: true, widget: new QueryResultsWidget(result, callbacks, labels) })
      .range(block.from, block.to))
  }
  return Decoration.set(ranges, true)
}

// Block widgets replace whole fences, so they come from state, as Mermaid
// previews do.
function queryDecorations(callbacks, labels) {
  return StateField.define({
    create: (state) => buildDecorations(state, callbacks, labels),
    update(value, tr) {
      if (tr.state.field(pointerPreview)) {
        if (tr.startState.field(pointerPreview)?.activateOnSelection
            && !tr.state.field(pointerPreview).activateOnSelection) return buildDecorations(tr.state, callbacks, labels)
        return value
      }
      const previousActive = tr.startState.field(activeCodeBlock)
      const nextActive = tr.state.field(activeCodeBlock)
      if (tr.docChanged || tr.startState.field(pointerPreview)
          || previousActive?.from !== nextActive?.from || previousActive?.to !== nextActive?.to
          || tr.effects.some((effect) => effect.is(queryResultsChanged) || effect.is(setFind))
          || (tr.docChanged && tr.state.field(documentFind).query)) return buildDecorations(tr.state, callbacks, labels)
      return value
    },
    provide: (field) => EditorView.decorations.from(field),
  })
}

// Tells the host which blocks the document has, whenever that changes.
function queryRequests(callbacks) {
  return ViewPlugin.fromClass(class {
    constructor(view) {
      this.requested = null
      this.send(view)
    }
    update(update) {
      if (update.docChanged) this.send(update.view)
    }
    send(view) {
      const queries = queryBlocks(view.state).map(({ id, source, text }) => ({ id, source, text }))
      const key = JSON.stringify(queries)
      if (key === this.requested) return
      this.requested = key
      callbacks.onRunQueries?.(queries)
    }
    destroy() {
      if (this.requested && this.requested !== "[]") callbacks.onRunQueries?.([])
    }
  })
}

// Results as the host sends them; anything malformed is left out.
export function readQueryResults(list) {
  const results = new Map()
  for (const result of Array.isArray(list) ? list : []) {
    if (!result || typeof result.id !== "string" || !Array.isArray(result.rows)) continue
    results.set(result.id, {
      source: result.source === "tasks" ? "tasks" : "notes",
      problems: Array.isArray(result.problems) ? result.problems.filter((p) => typeof p === "string") : [],
      empty: typeof result.empty === "string" ? result.empty : "",
      rows: result.rows.filter((row) => row && typeof row.path === "string" && Number.isInteger(row.line)
        && typeof row.text === "string").map((row) => ({
        path: row.path, line: row.line, text: row.text, checked: row.checked === true,
        detail: typeof row.detail === "string" ? row.detail : "",
        source: typeof row.source === "string" ? row.source : "",
      })),
    })
  }
  return results
}

registerEditorExtension({
  id: "query-blocks",
  // Options are the task-metadata badge labels.
  extensions: (options, host) => {
    const callbacks = host.callbacks || {}
    return [
      queryResults.init(() => host.queryResults || new Map()),
      queryDecorations(callbacks, taskBadgeLabels(options)),
      queryRequests(callbacks),
    ]
  },
})
