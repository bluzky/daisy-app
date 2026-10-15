// Editor smoke tests: rendered table widget interactions.
import { dom, check } from "./harness.mjs"

const tableHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(tableHost)
const tableEditor = dom.window.MDEditor.create(
  tableHost,
  "| Name | Status |\n| --- | --- |\n| Ada | Active |",
  {},
)
check("Markdown table renders as an editable grid",
  tableHost.querySelectorAll(".cm-md-table-cell").length === 4
    && tableHost.querySelector(".cm-md-table-grid") != null)
check("visual table hides pipe-delimited source",
  !tableHost.querySelector(".cm-content")?.textContent.includes("| Name |"))
const lastTableCell = tableHost.querySelector(
  '[data-table-row="1"][data-table-column="1"]'
)
lastTableCell?.focus()
if (lastTableCell) lastTableCell.innerText = "Reviewing"
lastTableCell?.dispatchEvent(new dom.window.KeyboardEvent("keydown", {
  key: "Tab",
  bubbles: true,
  cancelable: true,
}))
await new Promise((resolve) => setTimeout(resolve, 30))
check("Tab saves the cell and appends a row from the final cell",
  tableEditor.getMarkdown().includes("Reviewing")
    && tableEditor.getMarkdown().split("\n").length === 4)
tableEditor.destroy()

const obsidianTableHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(obsidianTableHost)
const obsidianTableEditor = dom.window.MDEditor.create(
  obsidianTableHost,
  "| Name |  | Status |\n| --- | --- | --- |\n| Ada | x | Active |",
  {},
)
check("table structure controls are hover grips, not a toolbar or context menu",
  obsidianTableHost.querySelector(".cm-md-table-toolbar") == null
    && obsidianTableHost.querySelector(".cm-md-table-edge-action") == null)
let contextMenuRequested = false
dom.window.__mdRequestTableContextMenu = () => { contextMenuRequested = true }
const contextCell = obsidianTableHost.querySelector(
  '[data-table-row="1"][data-table-column="0"]'
)
contextCell?.dispatchEvent(new dom.window.MouseEvent("contextmenu", {
  bubbles: true,
  cancelable: true,
}))
check("right-click in a cell no longer requests a table context menu",
  !contextMenuRequested)
const insertedHeader = obsidianTableHost.querySelector(
  '[data-table-row="0"][data-table-column="1"]'
)
check("an empty header cell has a visible placeholder without changing Markdown",
  insertedHeader?.dataset.placeholder === "Column 2"
    && insertedHeader?.textContent === "")
const hoverTableCell = (row, column) => obsidianTableHost
  .querySelector(`[data-table-row="${row}"][data-table-column="${column}"]`)
  .dispatchEvent(new dom.window.MouseEvent("mousemove", {
    bubbles: true, buttons: 0, clientX: 500, clientY: 500,
  }))
hoverTableCell(1, 1)
obsidianTableHost.querySelector(".cm-md-table-grip-column").click()
let selectedWidget = obsidianTableHost.querySelector(".cm-md-table-widget")
check("the column grip highlights the complete column",
  selectedWidget?.querySelectorAll(".is-table-part-selected").length === 2)
selectedWidget?.dispatchEvent(new dom.window.KeyboardEvent("keydown", {
  key: "Delete",
  bubbles: true,
  cancelable: true,
}))
await new Promise((resolve) => setTimeout(resolve, 30))
check("Delete removes the selected column",
  /\|\s*Name\s*\|\s*Status\s*\|/.test(
    obsidianTableEditor.getMarkdown().split("\n")[0]
  ))
hoverTableCell(1, 0)
obsidianTableHost.querySelector(".cm-md-table-grip-row").click()
selectedWidget = obsidianTableHost.querySelector(".cm-md-table-widget")
check("the row grip highlights the complete row",
  selectedWidget?.querySelectorAll(".is-table-part-selected").length === 2)
selectedWidget?.dispatchEvent(new dom.window.KeyboardEvent("keydown", {
  key: "Backspace",
  bubbles: true,
  cancelable: true,
}))
await new Promise((resolve) => setTimeout(resolve, 30))
check("Backspace removes the selected row",
  obsidianTableEditor.getMarkdown().split("\n").length === 2)
obsidianTableEditor.destroy()

const dragTableHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(dragTableHost)
const dragTableEditor = dom.window.MDEditor.create(
  dragTableHost,
  "| Name | Status |\n| --- | --- |\n| Ada | Active |\n| Grace | Active |",
  {},
)
const dragStartCell = dragTableHost.querySelector(
  '[data-table-row="1"][data-table-column="0"]'
)
const dragEndCell = dragTableHost.querySelector(
  '[data-table-row="2"][data-table-column="1"]'
)
const nativeRange = dom.window.document.createRange()
if (dragStartCell && dragEndCell) {
  nativeRange.setStart(dragStartCell, 0)
  nativeRange.setEnd(dragEndCell, dragEndCell.childNodes.length)
  dom.window.getSelection()?.removeAllRanges()
  dom.window.getSelection()?.addRange(nativeRange)
}
dragStartCell?.dispatchEvent(new dom.window.MouseEvent("mousedown", {
  button: 0,
  buttons: 1,
  bubbles: true,
  cancelable: true,
}))
const originalElementFromPoint = dom.window.document.elementFromPoint
dom.window.document.elementFromPoint = () => dragEndCell
dragStartCell?.dispatchEvent(new dom.window.MouseEvent("mousemove", {
  button: 0,
  buttons: 1,
  clientX: 500,
  clientY: 300,
  bubbles: true,
  cancelable: true,
}))
dragStartCell?.dispatchEvent(new dom.window.MouseEvent("mouseup", {
  button: 0,
  buttons: 0,
  bubbles: true,
  cancelable: true,
}))
dom.window.document.elementFromPoint = originalElementFromPoint
const dragSelectedWidget = dragTableHost.querySelector(".cm-md-table-widget")
dragEndCell?.dispatchEvent(new dom.window.MouseEvent("click", {
  bubbles: true,
  cancelable: true,
}))
const selectedTopLeft = dragTableHost.querySelector(
  '[data-table-row="1"][data-table-column="0"]'
)
const selectedBottomRight = dragTableHost.querySelector(
  '[data-table-row="2"][data-table-column="1"]'
)
check("dragging across rows and columns selects the anchor-to-head rectangle",
  dragSelectedWidget?.querySelectorAll(".is-table-part-selected").length === 4
    && selectedTopLeft?.classList.contains("is-table-part-selected")
    && selectedBottomRight?.classList.contains("is-table-part-selected"))
check("cell-range selection persists after pointer release without native text selection",
  dragSelectedWidget?.classList.contains("is-table-range-selected")
    && dom.window.getSelection()?.rangeCount === 0)
dragSelectedWidget?.dispatchEvent(new dom.window.KeyboardEvent("keydown", {
  key: "Escape",
  bubbles: true,
  cancelable: true,
}))
check("Escape clears a dragged cell range",
  dragSelectedWidget?.querySelectorAll(".is-table-part-selected").length === 0)
const nativeCellClickAllowed = dragStartCell?.dispatchEvent(new dom.window.MouseEvent("mousedown", {
  button: 0,
  buttons: 1,
  clientX: 100,
  clientY: 100,
  bubbles: true,
  cancelable: true,
}))
dragStartCell?.dispatchEvent(new dom.window.MouseEvent("mouseup", {
  button: 0,
  buttons: 0,
  clientX: 100,
  clientY: 100,
  bubbles: true,
  cancelable: true,
}))
dragStartCell?.dispatchEvent(new dom.window.MouseEvent("click", {
  bubbles: true,
  cancelable: true,
}))
check("an ordinary cell click allows native caret placement and selection",
  nativeCellClickAllowed === true)
const dragHeaderCell = dragTableHost.querySelector(
  '[data-table-row="0"][data-table-column="1"]'
)
const dragBodyCell = dragTableHost.querySelector(
  '[data-table-row="2"][data-table-column="0"]'
)
dragHeaderCell?.dispatchEvent(new dom.window.MouseEvent("mousedown", {
  button: 0,
  buttons: 1,
  bubbles: true,
  cancelable: true,
}))
dom.window.document.elementFromPoint = () => dragBodyCell
dragHeaderCell?.dispatchEvent(new dom.window.MouseEvent("mousemove", {
  button: 0,
  buttons: 1,
  clientX: 100,
  clientY: 300,
  bubbles: true,
  cancelable: true,
}))
dragHeaderCell?.dispatchEvent(new dom.window.MouseEvent("mouseup", {
  button: 0,
  buttons: 0,
  bubbles: true,
  cancelable: true,
}))
dom.window.document.elementFromPoint = originalElementFromPoint
dragBodyCell?.dispatchEvent(new dom.window.MouseEvent("click", {
  bubbles: true,
  cancelable: true,
}))
check("dragging from a header into the body selects both directions",
  dragSelectedWidget?.querySelectorAll(".is-table-part-selected").length === 6
    && dragSelectedWidget?.getAttribute("aria-label") === "Selected 3 rows by 2 columns.")
dragTableEditor.destroy()

const dragDelete = async (markdown, start, end) => {
  const host = dom.window.document.createElement("div")
  dom.window.document.body.appendChild(host)
  const editor = dom.window.MDEditor.create(host, markdown, {})
  const cellAt = ([row, column]) => host.querySelector(
    `[data-table-row="${row}"][data-table-column="${column}"]`
  )
  const from = cellAt(start)
  const to = cellAt(end)
  from.dispatchEvent(new dom.window.MouseEvent("mousedown", {
    button: 0, buttons: 1, bubbles: true, cancelable: true,
  }))
  const original = dom.window.document.elementFromPoint
  dom.window.document.elementFromPoint = () => to
  from.dispatchEvent(new dom.window.MouseEvent("mousemove", {
    button: 0, buttons: 1, clientX: 500, clientY: 300, bubbles: true, cancelable: true,
  }))
  from.dispatchEvent(new dom.window.MouseEvent("mouseup", {
    button: 0, buttons: 0, bubbles: true, cancelable: true,
  }))
  dom.window.document.elementFromPoint = original
  host.querySelector(".cm-md-table-widget").dispatchEvent(new dom.window.KeyboardEvent("keydown", {
    key: "Backspace", bubbles: true, cancelable: true,
  }))
  await new Promise((resolve) => setTimeout(resolve, 30))
  const result = editor.getMarkdown()
  editor.destroy()
  return result
}
const shiftHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(shiftHost)
const shiftEditor = dom.window.MDEditor.create(
  shiftHost,
  "| A | B | C |\n| --- | --- | --- |\n| a1 | b1 | c1 |\n| a2 | b2 | c2 |",
  {},
)
const shiftCell = (row, column) => shiftHost.querySelector(
  `[data-table-row="${row}"][data-table-column="${column}"]`
)
shiftCell(1, 0).dispatchEvent(new dom.window.MouseEvent("mousedown", {
  button: 0, buttons: 1, bubbles: true, cancelable: true,
}))
shiftCell(1, 0).dispatchEvent(new dom.window.MouseEvent("mouseup", {
  button: 0, buttons: 0, bubbles: true, cancelable: true,
}))
// jsdom does not focus contenteditable cells on its own.
shiftCell(1, 0).dispatchEvent(new dom.window.FocusEvent("focus"))
shiftCell(2, 1).dispatchEvent(new dom.window.MouseEvent("mousedown", {
  button: 0, buttons: 1, shiftKey: true, bubbles: true, cancelable: true,
}))
check("click a cell then shift-click another selects the range between them",
  shiftHost.querySelectorAll(".is-table-part-selected").length === 4
    && shiftHost.querySelector(".cm-md-table-widget").classList.contains("is-table-range-selected"))
shiftCell(2, 2).dispatchEvent(new dom.window.MouseEvent("mousedown", {
  button: 0, buttons: 1, shiftKey: true, bubbles: true, cancelable: true,
}))
check("shift-clicking again keeps the original anchor",
  shiftHost.querySelectorAll(".is-table-part-selected").length === 6)
shiftEditor.destroy()
const threeColumns = "| A | B | C |\n| --- | --- | --- |\n| a1 | b1 | c1 |\n| a2 | b2 | c2 |"
const partialResult = await dragDelete(threeColumns, [1, 0], [2, 1])
check("Backspace on a partial cell range clears the cells and keeps the structure",
  !/a2|b2|a1|b1/.test(partialResult) && /c1/.test(partialResult) && /c2/.test(partialResult)
    && partialResult.split("\n").length === 4)
const fullRowResult = await dragDelete(threeColumns, [1, 0], [1, 2])
check("Backspace on a range spanning every column deletes those rows",
  !/a1|b1|c1/.test(fullRowResult) && /a2/.test(fullRowResult)
    && fullRowResult.split("\n").length === 3)
const headerRowResult = await dragDelete(threeColumns, [0, 0], [1, 2])
check("a full-width range including the header promotes the next row to header",
  /\|\s*a2\s*\|/.test(headerRowResult.split("\n")[0])
    && headerRowResult.split("\n").length === 2)
