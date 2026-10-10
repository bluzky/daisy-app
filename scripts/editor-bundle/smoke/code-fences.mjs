// Editor smoke tests: typed fences, caret protection and guarded deletes.
import { dom, doc, check, pressKey, keyHost } from "./harness.mjs"

// Code fence boundaries: typed fences, caret never on a fence, guarded deletes.
const fenceCase = (doc, at) => {
  const h = keyHost()
  const ed = dom.window.MDEditor.create(h, doc, {})
  ed.select(at)
  const view = h.querySelector(".cm-content").cmTile.view
  return { ed, h, view, key: (k) => pressKey(h, k), type: (t) => { for (const c of t) ed.insert(c) },
    caret: () => { const head = view.state.selection.main.head; const l = view.state.doc.lineAt(head); return `${l.number}:${head - l.from}` },
    md: () => ed.getMarkdown() }
}
const fenceBlock = "intro\n```js\nlet a = 1\n```\n\nafter"
let fc = fenceCase("intro\n\n```py\nx = 1\n```\n", 6)
fc.type("```js")
check("a fence typed above an existing block renders as plain text until Enter",
  fc.h.querySelector(".cm-md-codeblock") == null && fc.h.querySelector(".cm-md-code-language") == null)
fc.key("Enter")
check("Enter gives a fence typed above an existing block its own closing fence",
  fc.md() === "intro\n```js\n\n```\n```py\nx = 1\n```\n")
fc.ed.destroy()
fc = fenceCase("intro\n", 6)
fc.type("```js"); fc.ed.select(fc.view.state.doc.length - 1)
fc.key("Enter")
check("Enter mid-language on a typed fence keeps the whole info string",
  fc.md() === "intro\n```js\n\n```")
fc.ed.destroy()
fc = fenceCase(fenceBlock, 21)
fc.key("Enter"); fc.type("```"); fc.key("Enter")
check("a fence typed on the last code line leaves the block",
  fc.md() === fenceBlock && fc.caret() === "5:0")
fc.ed.destroy()
fc = fenceCase("intro\n```js\na\nb\nc\n```\nafter", 13)
fc.key("Enter"); fc.type("```py"); fc.key("Enter")
check("a fence typed mid-block splits it into two blocks",
  fc.md() === "intro\n```js\na\n```\n\n```py\nb\nc\n```\nafter" && fc.caret() === "5:0")
fc.ed.destroy()
fc = fenceCase("intro\n```js\n  let a = 1\n```\nz", 23)
fc.key("Enter"); fc.key("Enter")
check("Enter twice after indented code leaves the block",
  fc.md() === "intro\n```js\n  let a = 1\n```\n\nz")
fc.ed.destroy()

fc = fenceCase(fenceBlock, 5); fc.ed.select(6)
check("moving onto the opening fence lands on the first code line", fc.caret() === "3:0")
fc.ed.select(26); fc.ed.select(24)
check("moving up onto the closing fence lands at the end of the code", fc.caret() === "3:9")
fc.ed.select(21); fc.ed.select(22)
check("moving down onto the closing fence lands below the block", fc.caret() === "5:0")
fc.ed.destroy()

fc = fenceCase("intro\n```js\n\n```\n\nafter", 12); fc.key("Backspace")
check("Backspace in an empty block deletes the block",
  fc.md() === "intro\n\nafter" && fc.caret() === "1:5")
fc.ed.destroy()
fc = fenceCase(fenceBlock, 12); fc.key("Backspace")
check("Backspace at the start of the code unwraps the block",
  fc.md() === "intro\nlet a = 1\n\nafter" && fc.caret() === "2:0")
fc.ed.destroy()
fc = fenceCase(fenceBlock, 21); fc.key("Delete")
check("Delete at the end of the code does not touch the closing fence", fc.md() === fenceBlock)
fc.ed.destroy()
fc = fenceCase(fenceBlock, 26); fc.key("Backspace")
check("Backspace on the empty line below a block drops it and enters the code",
  fc.md() === "intro\n```js\nlet a = 1\n```\nafter" && fc.caret() === "3:9")
fc.ed.destroy()
fc = fenceCase("intro\n```js\nx\n```\nafter", 17); fc.key("Backspace")
check("Backspace at a text line below a block only moves into the code",
  fc.md() === "intro\n```js\nx\n```\nafter" && fc.caret() === "3:1")
fc.ed.destroy()
fc = fenceCase("intro\n\n```js\nx\n```", 6); fc.key("Delete")
check("Delete on the empty line above a block drops that line",
  fc.md() === "intro\n```js\nx\n```" && fc.caret() === "1:5")
fc.ed.destroy()
fc = fenceCase("intro\n```js\nx\n```", 5); fc.key("Delete")
check("Delete at the end of a text line above a block does nothing",
  fc.md() === "intro\n```js\nx\n```")
fc.ed.destroy()

// An indented code block reveals its indent on every line together.
const indentCodeDoc = "intro\n\n    {\n        a: 1,\n        b: 2\n    }\n\nafter"
for (const [at, label] of [[0, "away from"], [22, "inside"]]) {
  fc = fenceCase(indentCodeDoc, at)
  const lines = [...fc.h.querySelectorAll(".cm-md-codeblock")].map((l) => l.textContent.match(/^ */)[0].length)
  check(`indented code lines keep matching indents with the caret ${label} the block`,
    new Set([lines[0], lines[3]]).size === 1 && lines[1] === lines[2] && lines[1] === lines[0] + 4)
  fc.ed.destroy()
}

fc = fenceCase("", 0)
fc.ed.insertTextAt("```text\nlong code\n```", 0, 0)
check("a whole block inserted at once renders as a block, not a pending fence",
  fc.h.querySelector(".cm-md-code-toggle-wrap") != null)
fc.ed.destroy()

// Rich clipboard content pasted into a code block goes in as plain text; the
// Markdown conversion would wrap a <pre> in fences that split the block.
{
  const code = "%% Styling\n    classDef a fill:#FFE4B5\n    \n    class B a"
  fc = fenceCase("a\n```\n\n```\nz", 6)
  const paste = new dom.window.Event("paste", { bubbles: true, cancelable: true })
  const data = { "text/plain": code, "text/html": `<pre>${code}</pre>` }
  paste.clipboardData = { types: Object.keys(data), items: [], getData: (type) => data[type] ?? "" }
  fc.h.querySelector(".cm-content").dispatchEvent(paste)
  check("rich text pasted into a code block stays inside the block",
    fc.md() === `a\n\`\`\`\n${code}\n\`\`\`\nz`)
  fc.ed.destroy()
}

// The first character typed into an empty code line must leave the DOM caret
// inside the text, not on the line element after it.
fc = fenceCase("intro\n```js\n\n```\n", 12)
fc.ed.insert("s")
{
  const line = [...fc.h.querySelectorAll(".cm-md-codeblock")][0]
  dom.window.getSelection().collapse(line, line.childNodes.length)
  fc.ed.select(fc.view.state.selection.main.head)
  const anchor = dom.window.getSelection().anchorNode
  check("the caret after the first typed character settles inside the code text",
    anchor?.nodeType === 3 && anchor.textContent === "s")
}
fc.ed.destroy()

// A typed fence only splits a block when it could close that block.
fc = fenceCase("````js\na\nb\n````\n", 8)
fc.key("Enter"); fc.type("~~~"); fc.key("Enter")
check("a typed fence of another character inside a block stays plain code",
  fc.md().startsWith("````js\na\n~~~\n") && fc.md().endsWith("b\n````\n") && !fc.md().includes("~~~\n\n~~~"))
fc.ed.destroy()
fc = fenceCase("````js\na\nb\n````\n", 8)
fc.key("Enter"); fc.type("```"); fc.key("Enter")
check("a typed fence shorter than the outer fence stays plain code",
  fc.md().startsWith("````js\na\n```\n") && fc.md().endsWith("b\n````\n") && !fc.md().includes("```\n\n```"))
fc.ed.destroy()
fc = fenceCase("````js\na\n````\n", 8)
fc.key("Enter"); fc.type("~~~"); fc.key("Enter")
check("an incompatible typed fence on the last code line does not exit the block",
  fc.md().startsWith("````js\na\n~~~\n") && fc.md().endsWith("````\n"))
fc.ed.destroy()

// Fences inside block quotes and lists keep their container prefix.
fc = fenceCase("> intro\n> ", 10)
fc.type("```js"); fc.key("Enter")
check("a fence typed in a block quote is paired inside the quote",
  fc.md() === "> intro\n> ```js\n> \n> ```" && fc.caret() === "3:2")
fc.ed.destroy()
fc = fenceCase("> ```js\n> a\n> ```\n", 8)
fc.ed.select(4)
check("the caret skips the opening fence of a quoted block", fc.caret() === "2:2")
fc.ed.destroy()
fc = fenceCase("> ```js\n> a\n> \n> ```\nx", 12)
fc.key("Enter")
check("Enter on the empty last line of a quoted block leaves the block",
  fc.md() === "> ```js\n> a\n> ```\n\nx")
fc.ed.destroy()
fc = fenceCase("> ```js\n> a\n> ```", 10)
fc.key("Backspace")
check("Backspace at the start of quoted code unwraps the block",
  fc.md() === "> a")
fc.ed.destroy()
