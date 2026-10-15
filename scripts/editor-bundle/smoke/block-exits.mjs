// Editor smoke tests: leaving tables and code blocks with the keyboard.
import { dom, check, enterIn, pressKey, keyHost } from "./harness.mjs"

// Block exits: table at EOF, whole-table delete, double Enter in code fence.
const tableDoc = "intro\n\n| A | B |\n| --- | --- |\n| 1 | 2 |"
let host = keyHost()
let keyEditor = dom.window.MDEditor.create(host, tableDoc, {})
keyEditor.select(tableDoc.length)
pressKey(host, "Enter")
check("Enter after a table at EOF opens a line below", keyEditor.getMarkdown() === tableDoc + "\n")
keyEditor.destroy()

host = keyHost()
keyEditor = dom.window.MDEditor.create(host, tableDoc, {})
keyEditor.select(tableDoc.length)
pressKey(host, "Backspace")
check("Backspace at the end of a table deletes the whole table", keyEditor.getMarkdown() === "intro\n")
keyEditor.destroy()

host = keyHost()
keyEditor = dom.window.MDEditor.create(host, "| A |\n| --- |\n| 1 |\n\nafter", {})
keyEditor.select(0)
pressKey(host, "Delete")
check("Delete at the start of a table deletes the whole table", keyEditor.getMarkdown() === "\nafter")
keyEditor.destroy()

const fenceDoc = "```js\nlet a = 1\n\n```"
host = keyHost()
keyEditor = dom.window.MDEditor.create(host, fenceDoc, {})
keyEditor.select(fenceDoc.indexOf("\n\n```") + 1)
pressKey(host, "Enter")
check("Enter on the empty last code line exits the block",
  keyEditor.getMarkdown() === "```js\nlet a = 1\n```\n")
keyEditor.destroy()

host = keyHost()
keyEditor = dom.window.MDEditor.create(host, "```js\nlet a = 1\n```", {})
keyEditor.select("```js\nlet a = 1".length)
pressKey(host, "Enter")
check("first Enter at the end of code stays in the block",
  keyEditor.getMarkdown() === "```js\nlet a = 1\n\n```")
pressKey(host, "Enter")
check("second Enter exits the block and opens a line below",
  keyEditor.getMarkdown() === "```js\nlet a = 1\n```\n")
keyEditor.destroy()

// ArrowDown/ArrowUp past the last/first table row leave the table.
const exitDoc = "| A | B |\n| --- | --- |\n| 1 | 2 |"
host = keyHost()
keyEditor = dom.window.MDEditor.create(host, exitDoc, {})
const exitCell = (row) => host.querySelector(`[data-table-row="${row}"][data-table-column="0"]`)
const exitArrow = (cell, key) => {
  Object.defineProperty(cell, "innerText", { value: cell.textContent, configurable: true })
  const text = cell.firstChild
  dom.window.getSelection().setBaseAndExtent(text, 0, text, 0)
  const event = new dom.window.KeyboardEvent("keydown", { key, bubbles: true, cancelable: true })
  cell.dispatchEvent(event)
  return event
}
const downEvent = exitArrow(exitCell(1), "ArrowDown")
check("ArrowDown in the last row of a table at EOF opens a line below",
  downEvent.defaultPrevented && keyEditor.getMarkdown() === exitDoc + "\n")
keyEditor.destroy()
host = keyHost()
keyEditor = dom.window.MDEditor.create(host, exitDoc, {})
check("ArrowUp in the header row of a table at the top opens a line above",
  exitArrow(exitCell(0), "ArrowUp").defaultPrevented && keyEditor.getMarkdown() === "\n" + exitDoc)
keyEditor.destroy()

host = keyHost()
keyEditor = dom.window.MDEditor.create(host, "intro\n", {})
keyEditor.select(keyEditor.getMarkdown().length)
for (const character of "```python") keyEditor.insert(character)
enterIn(host)
keyEditor.insert("x = 1")
check("```lang then Enter opens a block with that language",
  keyEditor.getMarkdown() === "intro\n```python\nx = 1\n```")
keyEditor.destroy()
