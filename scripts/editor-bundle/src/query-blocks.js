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
// the host answers through `setQueryResults([{ id, source, problems, view,
// columns, groups, empty }])`, again whenever the workspace changes. The
// host has already grouped the rows and filled a table's cells; this only
// draws them. A block with an answer
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

// A cell's or a group label's values, drawn by kind (see `QueryBlockResult`
// in WorkspaceQueryBlocks.swift).
function valuesElement(kind, values, done, labels, callbacks) {
  const node = element("span", "cm-md-query-values" + (kind === "none" ? " cm-md-query-none" : ""))
  const today = formatLocalDate(new Date())
  values.forEach((value, index) => {
    if (index) node.append(document.createTextNode(kind === "value" ? ", " : " "))
    if (kind === "due" || kind === "scheduled" || kind === "p") {
      const text = kind === "p" ? value.text.toLowerCase() : value.text
      if (kind === "p" ? labels[text] : /^\d{4}-\d{2}-\d{2}$/.test(text)) {
        node.append(taskBadgeElement(document, kind, text, kind === "due" && !done && text < today, labels))
        return
      }
    }
    if (kind === "names") {
      const token = element("span", "cm-md-metadata-link cm-md-query-token", value.text)
      token.setAttribute("role", "link")
      token.addEventListener("click", (event) => {
        event.preventDefault()
        event.stopPropagation()
        callbacks.onOpenLink?.({ token: value.text })
      })
      node.append(token)
    } else if (value.path) {
      const link = element("span", "cm-md-query-link cm-md-query-plain", value.text)
      link.setAttribute("role", "link")
      stopPointer(link)
      link.addEventListener("click", (event) => {
        event.preventDefault()
        callbacks.onOpenQueryResult?.({ path: value.path, line: 1 })
      })
      node.append(link)
    } else {
      node.append(element("span", null, value.text))
    }
  })
  return node
}

// Clicks on a control act on it, not on the query underneath.
function stopPointer(node) {
  node.addEventListener("mousedown", (event) => {
    event.preventDefault()
    event.stopPropagation()
  })
}

class QueryResultsWidget extends WidgetType {
  constructor(result, callbacks, labels) { super(); this.result = result; this.callbacks = callbacks; this.labels = labels }
  eq(other) { return other.result === this.result }

  checkbox(row) {
    const box = element("input", "cm-md-query-checkbox")
    box.type = "checkbox"
    box.checked = row.checked
    box.setAttribute("aria-label", row.text)
    box.addEventListener("mousedown", (event) => event.stopPropagation())
    box.addEventListener("change", () => {
      this.callbacks.onQueryTaskCheckbox?.({ path: row.path, line: row.line, checked: box.checked })
    })
    return box
  }

  // The row's text, opening its line; in a table, without the fields its
  // own columns show.
  rowLink(row, withSource) {
    const { result, callbacks } = this
    const link = rowText(withSource ? row : { ...row, source: "" }, result.source === "tasks" && row.checked,
      this.labels, callbacks)
    link.classList.add("cm-md-query-link")
    link.setAttribute("role", "link")
    link.setAttribute("aria-label", row.text)
    stopPointer(link)
    link.addEventListener("click", (event) => {
      event.preventDefault()
      callbacks.onOpenQueryResult?.({ path: row.path, line: row.line })
    })
    return link
  }

  list(rows) {
    const { result } = this
    const list = element("ul", "cm-md-query-results cm-md-query-" + result.source)
    for (const row of rows) {
      const item = element("li", "cm-md-query-row")
      if (result.source === "tasks") {
        item.classList.add("cm-md-query-task")
        if (row.checked) item.classList.add("cm-md-query-done")
        // The space the document's own task lines have after the box.
        item.append(this.checkbox(row), document.createTextNode(" "))
      }
      item.append(this.rowLink(row, true))
      if (row.detail) {
        const detail = element("span", "cm-md-query-detail", row.detail)
        detail.title = row.path
        item.append(detail)
      }
      list.append(item)
    }
    return list
  }

  table(rows) {
    const { result } = this
    const scroll = element("div", "cm-md-query-table-scroll")
    const table = element("table", "cm-md-query-table cm-md-query-" + result.source)
    const head = element("thead")
    const header = element("tr")
    for (const column of result.columns) {
      const cell = element("th", "cm-md-query-cell-" + column.kind, column.kind === "done" ? "" : column.label)
      cell.scope = "col"
      if (column.kind === "done") cell.setAttribute("aria-label", column.label)
      header.append(cell)
    }
    head.append(header)
    const body = element("tbody")
    for (const row of rows) {
      const line = element("tr", "cm-md-query-row" + (row.checked ? " cm-md-query-done" : ""))
      result.columns.forEach((column, index) => {
        const cell = element("td", "cm-md-query-cell-" + column.kind)
        if (column.kind === "done") cell.append(this.checkbox(row))
        else if (column.kind === "text") cell.append(this.rowLink(row, false))
        else cell.append(valuesElement(column.kind, row.cells[index] || [], row.checked, this.labels, this.callbacks))
        line.append(cell)
      })
      body.append(line)
    }
    table.append(head, body)
    scroll.append(table)
    return scroll
  }

  toDOM(view) {
    const { result } = this
    const container = element("div", "cm-md-query")
    container.setAttribute("role", "region")
    if (result.problems.length) {
      const problems = element("ul", "cm-md-query-problems")
      for (const problem of result.problems) problems.append(element("li", null, problem))
      container.append(problems)
    }
    if (!result.groups.some((group) => group.rows.length)) {
      container.append(element("p", "cm-md-query-empty", result.empty))
    } else {
      for (const group of result.groups) {
        const rows = result.view === "table" ? this.table(group.rows) : this.list(group.rows)
        if (!group.label) {
          container.append(rows)
          continue
        }
        // Not an h1–h6: the document's outline reads those.
        const section = element("section", "cm-md-query-group")
        const header = element("div", "cm-md-query-group-header")
        header.setAttribute("role", "heading")
        header.setAttribute("aria-level", "4")
        header.append(valuesElement(group.kind, [group.label], false, this.labels, this.callbacks),
          element("span", "cm-md-query-group-count", String(group.rows.length)))
        section.append(header, rows)
        container.append(section)
      }
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

const KINDS = new Set(["done", "text", "due", "scheduled", "p", "names", "value", "none"])
const readValue = (value) => value && typeof value.text === "string"
  ? { text: value.text, path: typeof value.path === "string" ? value.path : null }
  : null
const readValues = (values) => Array.isArray(values) ? values.map(readValue).filter(Boolean) : []

// Results as the host sends them; anything malformed is left out.
export function readQueryResults(list) {
  const results = new Map()
  for (const result of Array.isArray(list) ? list : []) {
    if (!result || typeof result.id !== "string" || !Array.isArray(result.groups)) continue
    const columns = (Array.isArray(result.columns) ? result.columns : [])
      .filter((column) => column && KINDS.has(column.kind) && typeof column.label === "string")
      .map((column) => ({ kind: column.kind, label: column.label }))
    const readRow = (row) => ({
      path: row.path, line: row.line, text: row.text, checked: row.checked === true,
      detail: typeof row.detail === "string" ? row.detail : "",
      source: typeof row.source === "string" ? row.source : "",
      cells: columns.map((_, index) => readValues(Array.isArray(row.cells) ? row.cells[index] : null)),
    })
    results.set(result.id, {
      source: result.source === "tasks" ? "tasks" : "notes",
      problems: Array.isArray(result.problems) ? result.problems.filter((p) => typeof p === "string") : [],
      empty: typeof result.empty === "string" ? result.empty : "",
      view: result.view === "table" && columns.length ? "table" : "list",
      columns,
      groups: result.groups.filter((group) => group && Array.isArray(group.rows)).map((group) => ({
        label: readValue(group.label),
        kind: KINDS.has(group.kind) ? group.kind : "value",
        rows: group.rows.filter((row) => row && typeof row.path === "string" && Number.isInteger(row.line)
          && typeof row.text === "string").map(readRow),
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
