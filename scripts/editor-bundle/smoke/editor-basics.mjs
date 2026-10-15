// Editor smoke tests: constructing the editor, round-trips and paste.
import { dom, doc, check, paste } from "./harness.mjs"

let editor
try {
  editor = dom.window.MDEditor.create(dom.window.document.getElementById("editor"), doc, {})
  check("editor constructs without throwing", true)
} catch (error) {
  check("editor constructs without throwing (" + error + ")", false)
}

if (editor) {
  check("round-trip is byte-faithful", editor.getMarkdown() === doc)
  const text = dom.window.document.querySelector(".cm-content")?.textContent ?? ""
  check("document text renders", text.includes("Sample Markdown Cheat Sheet"))
  // Native selection: no drawSelection() layers, so WebKit paints only text
  // once the host lays .cm-content out as a flex column.
  check("documents use the native selection, not CodeMirror's layers",
    dom.window.document.querySelector(".cm-selectionLayer") == null
      && dom.window.document.querySelector(".cm-cursorLayer") == null)
  editor.exec("bold")
  check("exec('bold') inserts markers", editor.getMarkdown().startsWith("****"))
}

const pasteHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(pasteHost)
const pasteEditor = dom.window.MDEditor.create(pasteHost, "before OLD after", {})
pasteEditor.select(7, 10)
const richPaste = paste(pasteHost.querySelector(".cm-content"), {
  html: "<p><strong>New</strong></p>", text: "New", types: ["text/html", "text/plain"],
})
check("rich paste replaces selection in one Markdown transaction",
  richPaste.defaultPrevented && pasteEditor.getMarkdown() === "before **New** after")
pasteHost.querySelector(".cm-content").dispatchEvent(new dom.window.KeyboardEvent("keydown", {
  key: "z", code: "KeyZ", ctrlKey: true, bubbles: true, cancelable: true,
}))
check("rich paste supports normal undo", pasteEditor.getMarkdown() === "before OLD after")
const plainPaste = paste(pasteHost.querySelector(".cm-content"), { text: "literal text" })
check("plain-text paste stays with CodeMirror default handling",
  pasteEditor.getMarkdown() === "before literal text after")
pasteEditor.destroy()

const imagePasteHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(imagePasteHost)
const pastedImages = []
const imagePasteEditor = dom.window.MDEditor.create(imagePasteHost, "old", {
  onPasteImage: (from, to) => pastedImages.push([from, to]),
})
imagePasteEditor.select(0, 3)
const imagePaste = paste(imagePasteHost.querySelector(".cm-content"), {
  html: "<p><strong>replacement</strong></p>",
  text: "replacement",
  items: [{ type: "image/png" }],
})
check("image clipboard keeps native bridge priority",
  imagePaste.defaultPrevented && pastedImages.length === 1
    && JSON.stringify(pastedImages[0]) === JSON.stringify([0, 3])
    && imagePasteEditor.getMarkdown() === "old")
const excelPaste = paste(imagePasteHost.querySelector(".cm-content"), {
  html: "<table><tr><th>Name</th><th>Score</th></tr><tr><td>Ada</td><td>10</td></tr></table>",
  text: "Name\tScore\nAda\t10",
  types: ["text/html", "text/tab-separated-values"],
  items: [{ type: "image/png" }],
})
check("spreadsheet table wins over Excel preview image",
  excelPaste.defaultPrevented && pastedImages.length === 1
    && imagePasteEditor.getMarkdown() === "| Name | Score |\n| --- | --- |\n| Ada | 10 |")
imagePasteEditor.destroy()

const tablePasteHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(tablePasteHost)
const tablePasteEditor = dom.window.MDEditor.create(tablePasteHost,
  "| Name | Score |\n| --- | --- |\n| Ada | 10 |", {})
const tableCell = tablePasteHost.querySelector(".cm-md-table-cell")
const tablePaste = tableCell && paste(tableCell, { html: "<p><strong>New</strong></p>" })
check("table cells retain native paste handling", tablePaste != null && !tablePaste.defaultPrevented)
tablePasteEditor.destroy()
