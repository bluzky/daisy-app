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
check("Tab nests selected list items under their preceding sibling",
  indentEvent.defaultPrevented
    && indentationEditor.getMarkdown()
      === "- Parent\n    - Alpha\n    - Beta")
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
  indentationEditor.getMarkdown() === "- Parent\n    - Alpha\n- Beta")
check("active bullet source reserves the rendered marker width",
  indentationHost.querySelector(".cm-md-bullet-source")?.textContent === "-")
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
check("repeated Tab does not impose a maximum list indentation depth",
  indentationEditor.getMarkdown() === "- Parent\n            - Alpha\n- Beta")
check("deeply indented list source keeps list geometry across the parser boundary",
  indentationHost.querySelector(".cm-md-list-depth-4.cm-md-list-item") != null
    && indentationHost.querySelector(".cm-md-list-depth-4.cm-md-codeblock") == null)
check("deeply indented list source keeps normal list-item spacing",
  indentationHost.querySelector(".cm-md-list-depth-4.cm-md-list-item-gap") != null)
for (let step = 0; step < 3; step++) {
  indentationContent?.dispatchEvent(new dom.window.KeyboardEvent("keydown", {
    key: "Tab",
    code: "Tab",
    shiftKey: true,
    bubbles: true,
    cancelable: true,
  }))
}
check("repeated Shift-Tab returns a deeply indented list item to its original depth",
  indentationEditor.getMarkdown() === "- Parent\n- Alpha\n- Beta")
indentationEditor.destroy()

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
  check(`Tab indents a first ${label} list item`,
    listEditor.getMarkdown() === `    ${source}`)
  content?.dispatchEvent(new dom.window.KeyboardEvent("keydown", {
    key: "Tab",
    code: "Tab",
    shiftKey: true,
    bubbles: true,
    cancelable: true,
  }))
  check(`Shift-Tab restores a first ${label} list item`,
    listEditor.getMarkdown() === source)
  listEditor.destroy()
}
