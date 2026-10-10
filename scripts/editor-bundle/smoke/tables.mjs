// Editor smoke tests: table cell navigation, grips, drag, copy, undo and grid paste.
import { dom, check, paste } from "./harness.mjs"

// A short cell's editable box is shorter than its <td> when a sibling cell
// wraps; the <td>'s empty space must still activate that cell.
const tableGapHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(tableGapHost)
const tableGapEditor = dom.window.MDEditor.create(tableGapHost,
  "| A   | B   |\n| --- | --- |\n| 1   | 2   |\n| 3   | 4   |", {})
const gapCell = tableGapHost.querySelector('[data-table-row="1"][data-table-column="0"]')
const gapContainer = gapCell?.parentElement
let gapFocused = false
if (gapCell) gapCell.focus = () => { gapFocused = true }
const gapDown = gapContainer && new dom.window.MouseEvent("mousedown",
  { bubbles: true, cancelable: true, button: 0 })
gapContainer?.dispatchEvent(gapDown)
check("clicking a table cell's empty space focuses that cell", gapFocused && gapDown.defaultPrevented)
const gapTarget = tableGapHost.querySelector('[data-table-row="2"][data-table-column="1"]')?.parentElement
gapTarget?.dispatchEvent(new dom.window.MouseEvent("mousemove", { bubbles: true, cancelable: true }))
check("dragging over another cell's empty space selects a cell range",
  tableGapHost.querySelector(".cm-md-table-widget")?.classList.contains("is-table-range-selected"))
dom.window.document.dispatchEvent(new dom.window.MouseEvent("mouseup", { bubbles: true }))

// Left/Right at a cell's edge hop to the neighbouring cell.
const arrowCells = [...tableGapHost.querySelectorAll(".cm-md-table-cell")]
const arrowAt = (row, column) => arrowCells.find((cell) =>
  cell.dataset.tableRow === String(row) && cell.dataset.tableColumn === String(column))
const focusedCells = []
for (const cell of arrowCells) {
  const value = cell.textContent
  Object.defineProperty(cell, "innerText", { value, configurable: true })
  cell.focus = () => focusedCells.push(`${cell.dataset.tableRow},${cell.dataset.tableColumn}`)
}
const arrow = (cell, key, offset) => {
  const text = cell.firstChild
  dom.window.getSelection().setBaseAndExtent(text, offset, text, offset)
  const event = new dom.window.KeyboardEvent("keydown", { key, bubbles: true, cancelable: true })
  cell.dispatchEvent(event)
  return event
}
const rightAtEnd = arrow(arrowAt(1, 0), "ArrowRight", 1)
check("ArrowRight at the end of a cell moves to the next cell",
  rightAtEnd.defaultPrevented && focusedCells.at(-1) === "1,1")
const leftAtStart = arrow(arrowAt(1, 1), "ArrowLeft", 0)
check("ArrowLeft at the start of a cell moves to the previous cell",
  leftAtStart.defaultPrevented && focusedCells.at(-1) === "1,0")
const rightWrap = arrow(arrowAt(1, 1), "ArrowRight", 1)
check("ArrowRight at the end of a row wraps to the next row",
  rightWrap.defaultPrevented && focusedCells.at(-1) === "2,0")
const leftWrap = arrow(arrowAt(2, 0), "ArrowLeft", 0)
check("ArrowLeft at the start of a row wraps to the previous row",
  leftWrap.defaultPrevented && focusedCells.at(-1) === "1,1")
const focusedBefore = focusedCells.length
const leftMid = arrow(arrowAt(2, 1), "ArrowLeft", 1)
check("ArrowLeft mid-text keeps native caret movement",
  !leftMid.defaultPrevented && focusedCells.length === focusedBefore)
const down = arrow(arrowAt(1, 1), "ArrowDown", 1)
check("ArrowDown on a single-line cell moves to the cell below",
  down.defaultPrevented && focusedCells.at(-1) === "2,1")
const up = arrow(arrowAt(2, 0), "ArrowUp", 1)
check("ArrowUp on a single-line cell moves to the cell above",
  up.defaultPrevented && focusedCells.at(-1) === "1,0")
// Fake a three-line cell: lines are 18px tall inside 8px padding.
const wrapped = arrowAt(1, 0)
wrapped.style.paddingTop = "8px"
wrapped.style.paddingBottom = "8px"
wrapped.getBoundingClientRect = () => ({ top: 0, bottom: 70, left: 0, right: 100, width: 100, height: 70 })
const realRects = dom.window.Range.prototype.getClientRects
const caretOnLine = (line) => {
  dom.window.Range.prototype.getClientRects = () => [{
    top: 8 + line * 18, bottom: 26 + line * 18, height: 18, left: 0, right: 0, width: 0,
  }]
}
caretOnLine(1)
check("ArrowUp from a wrapped cell's middle line stays inside the cell",
  !arrow(wrapped, "ArrowUp", 1).defaultPrevented)
check("ArrowDown from a wrapped cell's middle line stays inside the cell",
  !arrow(wrapped, "ArrowDown", 1).defaultPrevented)
caretOnLine(0)
const wrappedUp = arrow(wrapped, "ArrowUp", 1)
check("ArrowUp from a wrapped cell's top line moves to the cell above",
  wrappedUp.defaultPrevented && focusedCells.at(-1) === "0,0")
caretOnLine(2)
const wrappedDown = arrow(wrapped, "ArrowDown", 1)
check("ArrowDown from a wrapped cell's bottom line moves to the cell below",
  wrappedDown.defaultPrevented && focusedCells.at(-1) === "2,0")
dom.window.Range.prototype.getClientRects = realRects
// Shift+arrow stays inside the cell instead of selecting the empty space.
const shiftArrow = (cell, key, anchor, focus = anchor) => {
  const text = cell.firstChild
  dom.window.getSelection().setBaseAndExtent(text, anchor, text, focus)
  const event = new dom.window.KeyboardEvent("keydown",
    { key, shiftKey: true, bubbles: true, cancelable: true })
  cell.dispatchEvent(event)
  return event
}
check("Shift+ArrowRight at the end of a cell does not extend past it",
  shiftArrow(arrowAt(1, 0), "ArrowRight", 0, 1).defaultPrevented)
check("Shift+ArrowLeft at the start of a cell does not extend past it",
  shiftArrow(arrowAt(1, 0), "ArrowLeft", 1, 0).defaultPrevented)
check("Shift+ArrowRight inside a cell keeps native selection",
  !shiftArrow(arrowAt(1, 0), "ArrowRight", 0, 0).defaultPrevented)
const shiftUp = shiftArrow(arrowAt(1, 0), "ArrowUp", 1, 1)
check("Shift+ArrowUp on the top line selects to the cell start",
  shiftUp.defaultPrevented && dom.window.getSelection().focusOffset === 0
    && dom.window.getSelection().anchorOffset === 1)
const shiftDown = shiftArrow(arrowAt(1, 0), "ArrowDown", 0, 0)
check("Shift+ArrowDown on the bottom line selects to the cell end",
  shiftDown.defaultPrevented && dom.window.getSelection().focusOffset === 1)
const leftHeader = arrow(arrowAt(0, 0), "ArrowLeft", 0)
check("ArrowLeft in the first cell of the table does nothing",
  !leftHeader.defaultPrevented)
tableGapEditor.destroy()

// Hover "+" controls insert a row or column at the nearest boundary.
const addHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(addHost)
const addEditor = dom.window.MDEditor.create(addHost,
  "| A   | B   |\n| --- | --- |\n| 1   | 2   |\n| 3   | 4   |", {})
const addRoot = addHost.querySelector(".cm-md-table-widget")
const rect = (left, top, width, height) => ({
  left, top, width, height, right: left + width, bottom: top + height,
})
// 2 columns x 3 rows at (100, 50); each cell 100 x 40.
addRoot.getBoundingClientRect = () => rect(100, 50, 200, 120)
addRoot.querySelector(".cm-md-table-scroll").getBoundingClientRect = () => rect(100, 50, 200, 120)
addRoot.querySelector("table").getBoundingClientRect = () => rect(100, 50, 200, 120)
const addRows = [...addRoot.querySelectorAll("tr")]
addRows.forEach((tr, index) => {
  tr.getBoundingClientRect = () => rect(100, 50 + index * 40, 200, 40)
  ;[...tr.cells].forEach((cell, column) => {
    cell.getBoundingClientRect = () => rect(100 + column * 100, 50 + index * 40, 100, 40)
  })
})
const hover = (clientX, clientY) => addRoot.dispatchEvent(new dom.window.MouseEvent(
  "mousemove", { bubbles: true, clientX, clientY, buttons: 0 }))
const addRowButton = addRoot.querySelector(".cm-md-table-add-row")
const addColumnButton = addRoot.querySelector(".cm-md-table-add-column")
hover(105, 92)
check("hovering the left edge near a row boundary shows the add-row control",
  !addRowButton.hidden && addRowButton.style.top === "40px" && addColumnButton.hidden)
hover(200, 300)
check("moving away hides the add controls", addRowButton.hidden && addColumnButton.hidden)
hover(205, 55)
check("hovering the top edge near a column boundary shows the add-column control",
  !addColumnButton.hidden && addColumnButton.style.left === "100px" && addRowButton.hidden)
const markdownLines = () => addEditor.getMarkdown().split("\n").length
hover(105, 92)
const linesBefore = markdownLines()
addRowButton.click()
check("clicking add-row inserts a row at that boundary",
  markdownLines() === linesBefore + 1)
// Edge grips select the hovered cell's row or column.
const gripRow = addRoot.querySelector(".cm-md-table-grip-row")
const gripColumn = addRoot.querySelector(".cm-md-table-grip-column")
const hoverCell = (row, column) => addRows[row].cells[column]
  .querySelector(".cm-md-table-cell").dispatchEvent(new dom.window.MouseEvent(
    "mousemove", { bubbles: true, clientX: 150, clientY: 70, buttons: 0 }))
hoverCell(2, 1)
check("hovering a body cell shows the row and column grips",
  !gripRow.hidden && !gripColumn.hidden && gripRow.style.left === "0px"
    && gripColumn.style.top === "0px")
hoverCell(0, 0)
check("the header row has no row grip", gripRow.hidden && !gripColumn.hidden)
hoverCell(2, 1)
gripRow.click()
check("clicking the row grip selects that row",
  addRoot.classList.contains("is-table-row-selected")
    && addRoot.querySelectorAll(".is-table-part-selected").length === 2)
gripColumn.click()
check("clicking the column grip selects that column",
  addRoot.classList.contains("is-table-column-selected")
    && addRoot.querySelectorAll(".is-table-part-selected").length === addRows.length)
addEditor.destroy()

// Shift-clicking a grip selects a range, and Delete removes all of it.
const rangeHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(rangeHost)
const rangeEditor = dom.window.MDEditor.create(rangeHost,
  "| A | B | C |\n| --- | --- | --- |\n| 1 | 2 | 3 |\n| 4 | 5 | 6 |\n| 7 | 8 | 9 |", {})
const rangeRoot = rangeHost.querySelector(".cm-md-table-widget")
const rangeCell = (row, column) => rangeRoot
  .querySelector(`[data-table-row="${row}"][data-table-column="${column}"]`)
const rangeHover = (row, column) => rangeCell(row, column).dispatchEvent(
  new dom.window.MouseEvent("mousemove", { bubbles: true, buttons: 0, clientX: 500, clientY: 500 }))
const gripClick = (grip, shiftKey) => grip.dispatchEvent(
  new dom.window.MouseEvent("click", { bubbles: true, shiftKey }))
const rangeKey = (key) => rangeRoot.dispatchEvent(
  new dom.window.KeyboardEvent("keydown", { key, bubbles: true }))
rangeHover(1, 0)
gripClick(rangeRoot.querySelector(".cm-md-table-grip-row"), false)
rangeHover(2, 0)
gripClick(rangeRoot.querySelector(".cm-md-table-grip-row"), true)
check("shift-clicking the row grip extends the selection to a row range",
  rangeRoot.classList.contains("is-table-row-selected")
    && rangeRoot.querySelectorAll(".is-table-part-selected").length === 6)
rangeHost.dispatchEvent(new dom.window.MouseEvent("mousedown", { bubbles: true }))
check("clicking elsewhere clears a row selection",
  !rangeRoot.classList.contains("is-table-row-selected")
    && rangeRoot.querySelectorAll(".is-table-part-selected").length === 0)
rangeHover(1, 0)
gripClick(rangeRoot.querySelector(".cm-md-table-grip-row"), false)
rangeHover(2, 0)
gripClick(rangeRoot.querySelector(".cm-md-table-grip-row"), true)
rangeKey("Delete")
check("Delete removes every row in the selected range",
  rangeEditor.getMarkdown().split("\n").length === 3)
rangeEditor.destroy()
const columnHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(columnHost)
const columnEditor = dom.window.MDEditor.create(columnHost,
  "| A | B | C |\n| --- | --- | --- |\n| 1 | 2 | 3 |", {})
const columnRoot = columnHost.querySelector(".cm-md-table-widget")
const columnGripEl = columnRoot.querySelector(".cm-md-table-grip-column")
const columnHover = (column) => columnRoot
  .querySelector(`[data-table-row="1"][data-table-column="${column}"]`)
  .dispatchEvent(new dom.window.MouseEvent("mousemove", { bubbles: true, buttons: 0, clientX: 500, clientY: 500 }))
columnHover(0)
columnGripEl.dispatchEvent(new dom.window.MouseEvent("click", { bubbles: true }))
columnHover(1)
columnGripEl.dispatchEvent(new dom.window.MouseEvent("click", { bubbles: true, shiftKey: true }))
check("shift-clicking the column grip selects a column range",
  columnRoot.querySelectorAll(".is-table-part-selected").length === 4)
columnRoot.dispatchEvent(new dom.window.KeyboardEvent("keydown", { key: "Delete", bubbles: true }))
check("Delete removes every column in the selected range",
  columnEditor.getMarkdown().split("\n")[0].replace(/\s/g, "") === "|C|")
columnEditor.destroy()

// Dragging a grip moves its row/column to the boundary under the pointer.
const dragHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(dragHost)
const dragEditor = dom.window.MDEditor.create(dragHost,
  "| A | B | C |\n| --- | --- | --- |\n| 1 | 2 | 3 |\n| 4 | 5 | 6 |\n| 7 | 8 | 9 |", {})
const dragRoot = dragHost.querySelector(".cm-md-table-widget")
;[...dragRoot.querySelectorAll("tr")].forEach((tr, index) => {
  tr.getBoundingClientRect = () => ({ left: 0, right: 300, top: index * 40, bottom: index * 40 + 40, width: 300, height: 40 })
  ;[...tr.cells].forEach((cell, column) => {
    cell.getBoundingClientRect = () => ({ left: column * 100, right: column * 100 + 100, top: index * 40, bottom: index * 40 + 40, width: 100, height: 40 })
  })
})
const dragMouse = (type, target, clientX, clientY) => target.dispatchEvent(
  new dom.window.MouseEvent(type, { bubbles: true, button: 0, buttons: type === "mouseup" ? 0 : 1, clientX, clientY }))
const dragCell = (row, column) => dragRoot
  .querySelector(`[data-table-row="${row}"][data-table-column="${column}"]`)
dragCell(1, 0).dispatchEvent(new dom.window.MouseEvent("mousemove", { bubbles: true, buttons: 0, clientX: 500, clientY: 500 }))
const dragRowGrip = dragRoot.querySelector(".cm-md-table-grip-row")
dragMouse("mousedown", dragRowGrip, 0, 60)
dragMouse("mousemove", dom.window.document, 0, 150)
dragMouse("mouseup", dom.window.document, 0, 150)
check("dragging a row grip moves the row below the last row",
  dragEditor.getMarkdown().split("\n").slice(2).map((line) => line.replace(/\s/g, "")).join() === "|4|5|6|,|7|8|9|,|1|2|3|")
dragEditor.destroy()
const dragColumnHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(dragColumnHost)
const dragColumnEditor = dom.window.MDEditor.create(dragColumnHost,
  "| A | B | C |\n| --- | --- | --- |\n| 1 | 2 | 3 |", {})
const dragColumnRoot = dragColumnHost.querySelector(".cm-md-table-widget")
;[...dragColumnRoot.querySelectorAll("tr")].forEach((tr, index) => {
  tr.getBoundingClientRect = () => ({ left: 0, right: 300, top: index * 40, bottom: index * 40 + 40, width: 300, height: 40 })
  ;[...tr.cells].forEach((cell, column) => {
    cell.getBoundingClientRect = () => ({ left: column * 100, right: column * 100 + 100, top: index * 40, bottom: index * 40 + 40, width: 100, height: 40 })
  })
})
dragColumnRoot.querySelector(".cm-md-table-scroll").getBoundingClientRect = () => ({
  left: 0, right: 300, top: 0, bottom: 80, width: 300, height: 80,
})
dragColumnRoot.querySelector('[data-table-row="1"][data-table-column="0"]')
  .dispatchEvent(new dom.window.MouseEvent("mousemove", { bubbles: true, buttons: 0, clientX: 500, clientY: 500 }))
dragMouse("mousedown", dragColumnRoot.querySelector(".cm-md-table-grip-column"), 50, 0)
dragMouse("mousemove", dom.window.document, 250, 0)
dragMouse("mouseup", dom.window.document, 250, 0)
check("dragging a column grip moves the column to the end",
  dragColumnEditor.getMarkdown().split("\n")[0].replace(/\s/g, "") === "|B|C|A|"
    && dragColumnEditor.getMarkdown().split("\n")[2].replace(/\s/g, "") === "|2|3|1|")
dragColumnEditor.destroy()

// Cmd-C on a selected cell range copies it as a Markdown table.
const copyHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(copyHost)
const copyEditor = dom.window.MDEditor.create(copyHost,
  "| A | B | C |\n| --- | --- | --- |\n| 1 | 2 | 3 |\n| 4 | 5 | 6 |\n| 7 | 8 | 9 |", {})
const copyRoot = copyHost.querySelector(".cm-md-table-widget")
const copyCell = (row, column) => copyRoot
  .querySelector(`[data-table-row="${row}"][data-table-column="${column}"]`)
const dragSelect = (from, to) => {
  copyCell(...from).dispatchEvent(new dom.window.MouseEvent("mousedown",
    { bubbles: true, button: 0, buttons: 1, clientX: 1, clientY: 1 }))
  copyCell(...to).dispatchEvent(new dom.window.MouseEvent("mousemove",
    { bubbles: true, buttons: 1, clientX: 50, clientY: 50 }))
  copyCell(...to).dispatchEvent(new dom.window.MouseEvent("mouseup", { bubbles: true, button: 0 }))
}
const copySelection = () => {
  const data = {}
  const event = new dom.window.Event("copy", { bubbles: true, cancelable: true })
  event.clipboardData = { setData: (type, value) => { data[type] = value } }
  copyRoot.dispatchEvent(event)
  return { data, prevented: event.defaultPrevented }
}
dragSelect([2, 1], [3, 2])
const copied = copySelection()
check("copying a cell range writes a Markdown table with the selected columns' header",
  copied.prevented && copied.data["text/plain"]?.split("\n").map((l) => l.replace(/\s/g, "")).join()
    === "|B|C|,|---|---|,|5|6|,|8|9|")
copyEditor.destroy()

// Cmd-Z in an unedited cell undoes the document, and a table edit made while
// the selection sat elsewhere parks it on the table so Undo doesn't jump away.
const undoHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(undoHost)
const undoSource = "para\n\n| A | B |\n| --- | --- |\n| 1 | 2 |"
const undoEditor = dom.window.MDEditor.create(undoHost, undoSource, {})
const undoCell = () => undoHost.querySelector('[data-table-row="1"][data-table-column="0"]')
undoCell().dispatchEvent(new dom.window.FocusEvent("focus"))
undoCell().innerText = "changed"
undoCell().dispatchEvent(new dom.window.FocusEvent("blur"))
await new Promise((resolve) => setTimeout(resolve, 30))
check("a committed cell edit changes the Markdown", undoEditor.getMarkdown().includes("changed"))
undoCell().dispatchEvent(new dom.window.FocusEvent("focus"))
undoCell().innerText = "changed" // jsdom has no innerText; mirror the rendered text
const undoKey = new dom.window.KeyboardEvent("keydown",
  { key: "z", metaKey: true, bubbles: true, cancelable: true })
undoCell().dispatchEvent(undoKey)
await new Promise((resolve) => setTimeout(resolve, 30))
check("Cmd-Z in an unedited cell undoes the document change",
  undoKey.defaultPrevented && undoEditor.getMarkdown() === undoSource)
undoEditor.destroy()

// Pasting a grid (Excel/Sheets tab-separated text) fills cells and grows the table.
const gridPasteHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(gridPasteHost)
const gridPasteEditor = dom.window.MDEditor.create(gridPasteHost,
  "| A | B |\n| --- | --- |\n| 1 | 2 |", {})
const gridPasteCell = gridPasteHost.querySelector('[data-table-row="1"][data-table-column="1"]')
gridPasteCell.dispatchEvent(new dom.window.FocusEvent("focus"))
const gridPasteEvent = new dom.window.Event("paste", { bubbles: true, cancelable: true })
gridPasteEvent.clipboardData = { getData: (type) => type === "text/plain" ? 'x\ty\n"z\nq"\tw\n' : "" }
gridPasteCell.dispatchEvent(gridPasteEvent)
await new Promise((resolve) => setTimeout(resolve, 30))
check("pasting a 2x2 grid expands the table to fit (a quoted newline becomes a space)",
  gridPasteEvent.defaultPrevented
    && gridPasteEditor.getMarkdown().split("\n").map((l) => l.replace(/\s/g, "")).join()
      === "|A|B||,|---|---|---|,|1|x|y|,||zq|w|")
gridPasteEditor.destroy()
