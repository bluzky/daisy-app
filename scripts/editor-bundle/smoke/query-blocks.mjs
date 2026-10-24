// Editor smoke tests: ```tasks and ```notes blocks render their results as
// a widget, as Read mode does, and send their queries, clicks and check-offs
// to the host.
import { dom, check } from "./harness.mjs"

const source = "# Plan\n\n```tasks\n+daisy -is:done\n```\n\nAfter\n"
const create = (text = source, extra = {}) => {
  const host = dom.window.document.createElement("div")
  dom.window.document.body.appendChild(host)
  const sent = { queries: [], opened: [], toggled: [] }
  const editor = dom.window.MDEditor.create(host, text, {
    onRunQueries: (queries) => sent.queries.push(queries),
    onOpenQueryResult: (row) => sent.opened.push(row),
    onQueryTaskCheckbox: (row) => sent.toggled.push(row),
    ...extra,
  })
  return { host, editor, sent }
}
const result = (id, rows = [{ path: "a.md", line: 3, text: "Ship it", checked: false, detail: "a" }]) => ({
  id, source: "tasks", problems: ["“wrd” is not a term."], empty: "No matching tasks", rows,
})

{
  const { host, editor, sent } = create()
  const queries = sent.queries.at(-1) || []
  check("the editor sends its query blocks", queries.length === 1 && queries[0].source === "tasks"
    && queries[0].text.trim() === "+daisy -is:done" && queries[0].id.startsWith("editor:tasks:"))
  check("without results the block stays code", !host.querySelector(".cm-md-query")
    && host.textContent.includes("+daisy -is:done"))

  editor.setQueryResults([result(queries[0].id)])
  const widget = host.querySelector(".cm-md-query")
  check("results replace the block", !!widget && !host.textContent.includes("+daisy -is:done")
    && widget.querySelector(".cm-md-query-link")?.textContent === "Ship it"
    && widget.querySelector(".cm-md-query-problems")?.textContent.includes("wrd"))

  widget.querySelector(".cm-md-query-link").dispatchEvent(new dom.window.MouseEvent("click", { bubbles: true, cancelable: true }))
  check("a row opens its file in the host", JSON.stringify(sent.opened) === JSON.stringify([{ path: "a.md", line: 3 }]))

  const box = widget.querySelector(".cm-md-query-checkbox")
  box.checked = true
  box.dispatchEvent(new dom.window.Event("change", { bubbles: true }))
  check("a checkbox checks the task off in the host, not in this document",
    JSON.stringify(sent.toggled) === JSON.stringify([{ path: "a.md", line: 3, checked: true }])
    && editor.getMarkdown() === source)

  editor.setQueryResults(null)
  check("clearing the results shows the code again", !host.querySelector(".cm-md-query"))
  editor.destroy()
}

{
  const { host, editor, sent } = create()
  const id = sent.queries.at(-1)[0].id
  editor.setQueryResults([result(id, [])])
  check("no rows shows the empty note", host.querySelector(".cm-md-query-empty")?.textContent === "No matching tasks")
  editor.select(source.indexOf("+daisy") + 1)
  check("the caret in the query shows its source", !host.querySelector(".cm-md-query")
    && host.textContent.includes("+daisy -is:done"))
  editor.select(source.indexOf("After"))
  check("leaving the query shows the results again", !!host.querySelector(".cm-md-query"))
  const before = sent.queries.length
  editor.destroy()
  check("closing the editor withdraws its queries", sent.queries.length > before
    && JSON.stringify(sent.queries.at(-1)) === "[]")
}

{
  const { host, editor, sent } = create(source, { extensionState: { "query-blocks": false } })
  check("the module off sends nothing", sent.queries.length === 0)
  editor.setQueryResults([result("editor:tasks:x")])
  check("the module off shows the code", !host.querySelector(".cm-md-query"))
  editor.destroy()
}

{
  const { host, editor, sent } = create(source, { onOpenLink: (link) => sent.opened.push(link) })
  const id = sent.queries.at(-1)[0].id
  editor.setQueryResults([{ id, source: "tasks", problems: [], empty: "", rows: [{
    path: "a.md", line: 3, text: "Water plants @Daniel", checked: false, detail: "a",
    source: "p:medium Water plants due:2026-10-24 @Daniel email@x.com C#",
  }] }])
  const row = host.querySelector(".cm-md-query-row")
  check("a task row shows its fields as badges", Array.from(row.querySelectorAll(".mdp-task-badge"),
    (badge) => badge.className).join("|") === "mdp-task-badge mdp-task-badge-priority mdp-task-badge-medium|mdp-task-badge mdp-task-badge-due"
    && !row.textContent.includes("due:"))
  const tokens = Array.from(row.querySelectorAll(".cm-md-query-token"), (token) => token.textContent)
  check("a task row shows its names as links", tokens.join() === "@Daniel")
  row.querySelector(".cm-md-query-token").dispatchEvent(new dom.window.MouseEvent("click", { bubbles: true, cancelable: true }))
  check("a name opens its page, not the row", JSON.stringify(sent.opened) === JSON.stringify([{ token: "@Daniel" }]))
  editor.destroy()
}

{
  const text = "```notes\nstatus:active\n```\n\n```files\nstatus:active\n```\n"
  const { host, editor, sent } = create(text)
  const queries = sent.queries.at(-1)
  check("only tasks and notes blocks are queries", queries.length === 1 && queries[0].source === "notes")
  editor.setQueryResults([{ id: queries[0].id, source: "notes", problems: [], empty: "",
    rows: [{ path: "p.md", line: 1, text: "Plan", checked: false, detail: "projects" }] }])
  const list = host.querySelector(".cm-md-query-results")
  check("notes render as an unordered list without checkboxes", list?.classList.contains("cm-md-query-notes")
    && !list.querySelector("input") && list.querySelector(".cm-md-query-link")?.textContent === "Plan")
  editor.destroy()
}

{
  const { host, editor, sent } = create("```tasks\n\n```\n\n```notes\n   \n```\n\n```tasks\n```\n")
  check("empty query blocks are never sent", JSON.stringify(sent.queries.at(-1) ?? []) === "[]")
  check("empty query blocks stay code", !host.querySelector(".cm-md-query"))
  editor.destroy()
}
