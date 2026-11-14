// Editor smoke tests: list indentation, Tab behaviour and bracket auto-closing.
import { dom, check } from "./harness.mjs"

const indentationHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(indentationHost)
const indentationEditor = dom.window.MDEditor.create(
  indentationHost, "- Parent\n- Alpha\n- Beta", {})
const indentationContent = indentationHost.querySelector(".cm-content")
indentationEditor.select(9, 23)
const indentEvent = new dom.window.KeyboardEvent("keydown", {
  key: "Tab",
  code: "Tab",
  bubbles: true,
  cancelable: true,
})
indentationContent?.dispatchEvent(indentEvent)
check("Tab nests selected list items at their preceding sibling's text column",
  indentEvent.defaultPrevented
    && indentationEditor.getMarkdown()
      === "- Parent\n  - Alpha\n  - Beta")
const outdentEvent = new dom.window.KeyboardEvent("keydown", {
  key: "Tab",
  code: "Tab",
  shiftKey: true,
  bubbles: true,
  cancelable: true,
})
indentationContent?.dispatchEvent(outdentEvent)
check("Shift-Tab outdents every selected nested list item",
  outdentEvent.defaultPrevented
    && indentationEditor.getMarkdown() === "- Parent\n- Alpha\n- Beta")
indentationEditor.select(11)
indentationContent?.focus()
indentationContent?.dispatchEvent(new dom.window.KeyboardEvent("keydown", {
  key: "Tab",
  code: "Tab",
  bubbles: true,
  cancelable: true,
}))
check("Tab nests the current list item when there is no selection",
  indentationEditor.getMarkdown() === "- Parent\n  - Alpha\n- Beta")
check("the caret's list line keeps its rendered bullet",
  indentationHost.querySelectorAll(".cm-md-bullet").length === 3)
check("nested list layout uses semantic depth instead of source-space width",
  indentationHost.querySelector(".cm-md-list-depth-2") != null)
check("nested list source indentation does not occupy rendered layout",
  !indentationHost.querySelector(".cm-md-list-depth-2")?.textContent.startsWith(" "))
indentationContent?.dispatchEvent(new dom.window.KeyboardEvent("keydown", {
  key: "Tab",
  code: "Tab",
  bubbles: true,
  cancelable: true,
}))
indentationContent?.dispatchEvent(new dom.window.KeyboardEvent("keydown", {
  key: "Tab",
  code: "Tab",
  bubbles: true,
  cancelable: true,
}))
check("Tab on an item without a previous sibling leaves it in place",
  indentationEditor.getMarkdown() === "- Parent\n  - Alpha\n- Beta")
indentationEditor.destroy()

// Authored source can still nest deeper than the parser reads as a list.
const deepHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(deepHost)
const deepEditor = dom.window.MDEditor.create(
  deepHost, "- Parent\n            - Alpha\n- Beta", {})
const deepContent = deepHost.querySelector(".cm-content")
deepContent?.focus()
deepEditor.select(23)
check("deeply indented list source keeps list geometry across the parser boundary",
  deepHost.querySelector(".cm-md-list-depth-4.cm-md-list-item") != null
    && deepHost.querySelector(".cm-md-list-depth-4.cm-md-codeblock") == null)
check("deeply indented list source keeps normal list-item spacing",
  deepHost.querySelector(".cm-md-list-depth-4.cm-md-list-item-gap") != null)
for (let step = 0; step < 3; step++) {
  deepContent?.dispatchEvent(new dom.window.KeyboardEvent("keydown", {
    key: "Tab",
    code: "Tab",
    shiftKey: true,
    bubbles: true,
    cancelable: true,
  }))
}
check("repeated Shift-Tab returns a deeply indented list item to its original depth",
  deepEditor.getMarkdown() === "- Parent\n- Alpha\n- Beta")
deepEditor.destroy()

const bracketCases = [
  ["paragraph", "Hello", 5, "(", ")", "Hello()", "Hello(x)"],
  ["ATX heading", "# Heading", 9, "[", "]", "# Heading[]", "# Heading[x]"],
  ["Setext heading", "Heading\n=======", 7, "{", "}", "Heading{}\n=======", "Heading{x}\n======="],
  ["fenced code block", "```js\ncall\n```", 10, "(", ")", "```js\ncall()\n```", "```js\ncall(x)\n```"],
]
for (const [label, source, cursorPos, openBracket, closeBracket, expectedText, expectedAtCursor] of bracketCases) {
  const bracketHost = dom.window.document.createElement("div")
  dom.window.document.body.appendChild(bracketHost)
  const bracketEditor = dom.window.MDEditor.create(bracketHost, source, {})
  bracketEditor.select(cursorPos)
  bracketEditor.insert(openBracket)
  check(`typing ${openBracket} in ${label} auto-closes with ${closeBracket}`,
    bracketEditor.getMarkdown() === expectedText)
  bracketEditor.insert("x")
  check(`cursor lands between ${openBracket}${closeBracket} in ${label}`,
    bracketEditor.getMarkdown() === expectedAtCursor)
  bracketEditor.destroy()
}

const inlineTabHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(inlineTabHost)
const inlineTabEditor = dom.window.MDEditor.create(
  inlineTabHost, "Plain paragraph", {})
const inlineTabContent = inlineTabHost.querySelector(".cm-content")
inlineTabEditor.select(5)
const inlineTabEvent = new dom.window.KeyboardEvent("keydown", {
  key: "Tab",
  code: "Tab",
  bubbles: true,
  cancelable: true,
})
inlineTabContent?.dispatchEvent(inlineTabEvent)
check("Tab inserts a tab inside ordinary text",
  inlineTabEvent.defaultPrevented
    && inlineTabEditor.getMarkdown() === "Plain\t paragraph")
inlineTabEditor.select(0)
inlineTabContent?.dispatchEvent(new dom.window.KeyboardEvent("keydown", {
  key: "Tab",
  code: "Tab",
  bubbles: true,
  cancelable: true,
}))
check("Tab at a paragraph's leading edge preserves its Markdown block type",
  inlineTabEditor.getMarkdown() === "Plain\t paragraph")
inlineTabEditor.destroy()

const fencedTabHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(fencedTabHost)
const fencedTabEditor = dom.window.MDEditor.create(
  fencedTabHost, "intro\n```c\nint main() {\nreturn 0;\n}\n```", {})
const fencedTabContent = fencedTabHost.querySelector(".cm-content")
fencedTabEditor.select(fencedTabEditor.getMarkdown().indexOf("return"))
const fencedTabEvent = new dom.window.KeyboardEvent("keydown", {
  key: "Tab",
  code: "Tab",
  bubbles: true,
  cancelable: true,
})
fencedTabContent?.dispatchEvent(fencedTabEvent)
check("Tab indents from the leading edge of fenced code content",
  fencedTabEvent.defaultPrevented
    && fencedTabEditor.getMarkdown().includes("\n\treturn 0;"))
fencedTabEditor.destroy()

const topLevelBlockCases = [
  ["ATX heading", "# Heading"],
  ["Setext heading", "Heading\n======="],
  ["paragraph", "Plain paragraph"],
  ["blockquote", "> Quote"],
  ["fenced code", "```swift\nlet value = 1\n```"],
  ["indented code", "    let value = 1", "let value = 1"],
  ["table", "| A | B |\n| - | - |\n| 1 | 2 |"],
  ["horizontal rule", "---"],
  ["link paragraph", "[OpenAI](https://openai.com)"],
  ["YAML frontmatter", "---\ntitle: Example\n---"],
]
for (const [label, source, expectedAfterShiftTab = source] of topLevelBlockCases) {
  const host = dom.window.document.createElement("div")
  dom.window.document.body.appendChild(host)
  const blockEditor = dom.window.MDEditor.create(host, source, {})
  const content = host.querySelector(".cm-content")
  blockEditor.select(0, source.length)
  const tabEvent = new dom.window.KeyboardEvent("keydown", {
    key: "Tab",
    code: "Tab",
    bubbles: true,
    cancelable: true,
  })
  content?.dispatchEvent(tabEvent)
  check(`Tab preserves top-level ${label} Markdown`,
    tabEvent.defaultPrevented && blockEditor.getMarkdown() === source)
  const shiftTabEvent = new dom.window.KeyboardEvent("keydown", {
    key: "Tab",
    code: "Tab",
    shiftKey: true,
    bubbles: true,
    cancelable: true,
  })
  content?.dispatchEvent(shiftTabEvent)
  check(`Shift-Tab handles ${label} Markdown safely`,
    shiftTabEvent.defaultPrevented
      && blockEditor.getMarkdown() === expectedAfterShiftTab)
  blockEditor.destroy()
}

for (const [label, source] of [
  ["unordered", "- Item"],
  ["ordered", "1. Item"],
  ["task", "- [ ] Item"],
]) {
  const host = dom.window.document.createElement("div")
  dom.window.document.body.appendChild(host)
  const listEditor = dom.window.MDEditor.create(host, source, {})
  const content = host.querySelector(".cm-content")
  listEditor.select(0, source.length)
  content?.dispatchEvent(new dom.window.KeyboardEvent("keydown", {
    key: "Tab",
    code: "Tab",
    bubbles: true,
    cancelable: true,
  }))
  check(`Tab leaves a first ${label} list item in place`,
    listEditor.getMarkdown() === source)
  content?.dispatchEvent(new dom.window.KeyboardEvent("keydown", {
    key: "Tab",
    code: "Tab",
    shiftKey: true,
    bubbles: true,
    cancelable: true,
  }))
  check(`Shift-Tab leaves a top-level ${label} list item in place`,
    listEditor.getMarkdown() === source)
  listEditor.destroy()
}

// Blank lines between list items collapse like the preview. While the caret is
// in the item below, only the blank directly above it stays open (so typing a
// new item does not jump), and the caret's own blank line is never collapsed.
const blankHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(blankHost)
const blankEditor = dom.window.MDEditor.create(blankHost, "- One\n\n\n- Two", {})
blankHost.querySelector(".cm-content").focus()
blankEditor.select(7)
const blankLines = [...blankHost.querySelectorAll(".cm-line")]
check("caret's blank line between list items stays visible",
  !blankLines[2].classList.contains("cm-md-block-separator"))
check("earlier blank lines between list items stay collapsed",
  blankLines[1].classList.contains("cm-md-block-separator"))
blankEditor.select(11)
const itemBlankLines = [...blankHost.querySelectorAll(".cm-line")]
check("the blank directly above the active item stays open",
  !itemBlankLines[2].classList.contains("cm-md-block-separator"))
check("earlier blanks above the active item stay collapsed",
  itemBlankLines[1].classList.contains("cm-md-block-separator"))
blankEditor.select(0)
check("blank lines between list items collapse when the caret is elsewhere",
  [...blankHost.querySelectorAll(".cm-md-block-separator")].length === 2)

// Backspace on an empty list item: first press removes the marker, second
// removes the line break.
const emptyItemHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(emptyItemHost)
const emptyItemEditor = dom.window.MDEditor.create(emptyItemHost, "- One\n- ", {})
emptyItemHost.querySelector(".cm-content").focus()
emptyItemEditor.select(8)
const backspace = () => emptyItemHost.querySelector(".cm-content").dispatchEvent(
  new dom.window.KeyboardEvent("keydown", { key: "Backspace", bubbles: true, cancelable: true }))
backspace()
check("first Backspace removes the empty list marker",
  emptyItemEditor.getMarkdown() === "- One\n")
backspace()
check("second Backspace removes the line break",
  emptyItemEditor.getMarkdown() === "- One")

// Cmd-Down / Cmd-Up are handled by the editor (caret to the document edge,
// then scroll to the real edge) rather than falling through to the default.
const edgeHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(edgeHost)
const edgeEditor = dom.window.MDEditor.create(edgeHost, "one\n\ntwo\n\nthree", {})
edgeHost.querySelector(".cm-content").focus()
edgeEditor.select(5)
const edgeKey = (key) => {
  const event = new dom.window.KeyboardEvent("keydown", { key, ctrlKey: true, bubbles: true, cancelable: true })
  edgeHost.querySelector(".cm-content").dispatchEvent(event)
  return event.defaultPrevented
}
check("Cmd-Down is handled by the editor", edgeKey("ArrowDown"))
check("Cmd-Up is handled by the editor", edgeKey("ArrowUp"))

// Cmd+Enter steps a list item through list item -> task -> done task.
const cycleEditor = (source) => {
  const host = dom.window.document.createElement("div")
  dom.window.document.body.appendChild(host)
  const editor = dom.window.MDEditor.create(host, source, {})
  const press = () => {
    const event = new dom.window.KeyboardEvent("keydown", { key: "Enter", ctrlKey: true, bubbles: true, cancelable: true })
    host.querySelector(".cm-content").dispatchEvent(event)
    return event.defaultPrevented
  }
  return { editor, press }
}
{
  const { editor, press } = cycleEditor("- Buy milk")
  editor.select(5, 5)
  press()
  check("Cmd+Enter turns a list item into a task", editor.getMarkdown() === "- [ ] Buy milk")
  press()
  check("Cmd+Enter checks an open task", editor.getMarkdown() === "- [x] Buy milk")
  press()
  check("Cmd+Enter turns a done task back into a list item", editor.getMarkdown() === "- Buy milk")
  check("Cmd+Enter keeps the caret in the item text", editor.getLinkSelection().from === 5)
}
{
  const { editor, press } = cycleEditor("1. One\n  * [X] Two\n> - Three\nplain")
  editor.select(0, 25)
  press()
  check("Cmd+Enter steps each selected item from its own state",
    editor.getMarkdown() === "1. [ ] One\n  * Two\n> - [ ] Three\nplain")
}
{
  const { editor, press } = cycleEditor("plain text")
  editor.select(5, 5)
  press()
  check("Cmd+Enter outside a list leaves the line's text alone", !editor.getMarkdown().startsWith("- "))
}

// Line start (Home; Cmd-Left on macOS) stops after a rendered list marker, so
// typed text lands in the item instead of in front of its source marker.
for (const [label, source, textStart] of [
  ["a task", "- [ ] Buy milk", 6],
  ["a nested task", "  - [x] Done", 8],
  ["a bullet", "- Buy milk", 2],
  ["a numbered item", "12. Buy milk", 4],
]) {
  const host = dom.window.document.createElement("div")
  dom.window.document.body.appendChild(host)
  const editor = dom.window.MDEditor.create(host, source, {})
  const content = host.querySelector(".cm-content")
  content.focus()
  editor.select(source.length)
  const home = (shiftKey = false) => content.dispatchEvent(new dom.window.KeyboardEvent("keydown", {
    key: "Home", code: "Home", shiftKey, bubbles: true, cancelable: true,
  }))
  home()
  check(`Home on ${label} stops after the rendered marker`,
    editor.getLinkSelection().from === textStart)
  home()
  check(`Home again on ${label} stays after the marker`,
    editor.getLinkSelection().from === textStart)
  editor.insert("X")
  check(`typing after Home on ${label} goes into the item text`,
    editor.getMarkdown() === source.slice(0, textStart) + "X" + source.slice(textStart))
  editor.select(editor.getMarkdown().length)
  home(true)
  const selection = editor.getLinkSelection()
  check(`Shift-Home on ${label} selects only the item text`,
    selection.from === textStart && selection.to === editor.getMarkdown().length)
  editor.destroy()
}
{
  const host = dom.window.document.createElement("div")
  dom.window.document.body.appendChild(host)
  const editor = dom.window.MDEditor.create(host, "- Parent\n- Alpha", {})
  host.querySelector(".cm-content").focus()
  editor.select(12)
  check("the caret's list line keeps the rendered bullet instead of raw source",
    host.querySelectorAll(".cm-md-bullet").length === 2)
  editor.destroy()
}

// A marker renders only once the space after it is typed.
for (const [label, typed, rendered] of [
  ["a bullet", "-", ".cm-md-bullet"],
  ["a numbered item", "1.", ".cm-md-ordered"],
  ["a task", "- [ ]", ".cm-md-task-marker"],
]) {
  const host = dom.window.document.createElement("div")
  dom.window.document.body.appendChild(host)
  const editor = dom.window.MDEditor.create(host, "Intro\n\n", {})
  host.querySelector(".cm-content").focus()
  editor.select(7)
  for (const character of typed) editor.insert(character)
  check(`typing ${label} marker leaves it as source`,
    host.querySelector(rendered) == null && editor.getMarkdown() === "Intro\n\n" + typed)
  editor.insert(" ")
  check(`the space after ${label} marker renders it`, host.querySelector(rendered) != null)
  editor.select(0)
  editor.destroy()
}
{
  const host = dom.window.document.createElement("div")
  dom.window.document.body.appendChild(host)
  const editor = dom.window.MDEditor.create(host, "-\n\nText", {})
  host.querySelector(".cm-content").focus()
  editor.select(editor.getMarkdown().length)
  check("a bare marker the caret is not on still renders",
    host.querySelector(".cm-md-bullet") != null)
  editor.destroy()
}
