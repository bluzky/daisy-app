// Editor smoke tests: list editing as specified in docs/list-editing-proposal.md.
// Sources mark the caret with `|`, or a selection with `«` and `»`.
import { dom, check } from "./harness.mjs"

const open = (source) => {
  let anchor = source.indexOf("«"), head, text
  if (anchor >= 0) {
    text = source.replace("«", "")
    head = text.indexOf("»")
    text = text.replace("»", "")
  } else {
    anchor = head = source.indexOf("|")
    text = source.replace("|", "")
  }
  const host = dom.window.document.createElement("div")
  dom.window.document.body.appendChild(host)
  const editor = dom.window.MDEditor.create(host, text, {})
  const content = host.querySelector(".cm-content")
  content.focus()
  editor.select(anchor, head)
  const press = (key, { shiftKey = false, ctrlKey = false } = {}) => content.dispatchEvent(
    new dom.window.KeyboardEvent("keydown", { key, shiftKey, ctrlKey, bubbles: true, cancelable: true }))
  const caret = () => {
    const markdown = editor.getMarkdown()
    const { from, to } = editor.getLinkSelection()
    return from === to ? markdown.slice(0, from) + "|" + markdown.slice(from)
      : markdown.slice(0, from) + "«" + markdown.slice(from, to) + "»" + markdown.slice(to)
  }
  return { host, editor, press, caret, close: () => { editor.destroy(); host.remove() } }
}

const keyCase = (label, source, keys, expected) => {
  const { press, caret, close } = open(source)
  for (const key of keys) {
    if (key === "S-Enter") press("Enter", { shiftKey: true })
    else if (key === "S-Tab") press("Tab", { shiftKey: true })
    else if (key === "Undo") press("z", { ctrlKey: true })
    else press(key)
  }
  const got = caret()
  check(label + (got === expected ? "" : ` (got ${JSON.stringify(got)})`), got === expected)
  close()
}

// 2. Enter
keyCase("Enter splits an item and continues its marker", "- fo|o", ["Enter"], "- fo\n- |o")
keyCase("Enter after a done task starts an unchecked task", "- [x] done|", ["Enter"], "- [x] done\n- [ ] |")
keyCase("Enter after a numbered task continues number and box", "1. [x] done|", ["Enter"], "1. [x] done\n2. [ ] |")
keyCase("Enter renumbers the following items", "1. a|\n2. b\n3. c", ["Enter"], "1. a\n2. |\n3. b\n4. c")
keyCase("Enter keeps a non-1 start and the ) delimiter", "3) a|", ["Enter"], "3) a\n4) |")
keyCase("Enter keeps the bullet character", "* a|", ["Enter"], "* a\n* |")
keyCase("Enter on an empty item exits the list after a blank line", "- a\n- |", ["Enter"], "- a\n\n|")
keyCase("Enter on an empty item exits a task list the same way", "- [ ] a\n- [ ] |", ["Enter"], "- [ ] a\n\n|")
keyCase("Enter on an empty item inside a quote stays in the quote", "> - a\n> - |", ["Enter"], "> - a\n>\n> |")
keyCase("Enter on an empty nested item outdents it", "- a\n  - |", ["Enter"], "- a\n- |")
keyCase("an outdented item joins the parent's numbered list", "1. a\n   - |", ["Enter"], "1. a\n2. |")
keyCase("Enter at the start of an item inserts an empty item above", "1. |foo\n2. bar", ["Enter"], "1. \n2. |foo\n3. bar")
keyCase("Enter keeps a loose list loose", "- a\n\n- b|", ["Enter"], "- a\n\n- b\n\n- |")
keyCase("Enter leaves a `1. 1. 1.` list's numbering alone", "1. a|\n1. b", ["Enter"], "1. a\n1. |\n1. b")
keyCase("exiting mid-list continues the numbering below", "1. a\n2. |\n3. b", ["Enter"], "1. a\n\n|\n2. b")
keyCase("Enter in a fenced code block adds a plain line", "```\n- a|\n```", ["Enter"], "```\n- a\n|\n```")

for (const [label, source, typed, expected] of [
  ["text typed under a list starts a paragraph", "- a\n", "x", "- a\n\nx"],
  ["text typed under a numbered list starts a paragraph", "1. a\n2. b\n", "Hi", "1. a\n2. b\n\nHi"],
  ["a marker typed under a list continues it", "- a\n", "- b", "- a\n- b"],
  ["indented text under a list stays a continuation", "- a\n", "  more", "- a\n  more"],
  ["text after a blank line gets no second blank line", "- a\n\n", "x", "- a\n\nx"],
  ["text under a paragraph is left alone", "Para\n", "x", "Para\nx"],
]) {
  const { editor, close } = open(source + "|")
  for (const character of typed) editor.insert(character)
  check(label, editor.getMarkdown() === expected)
  close()
}

// 8. Multi-line items
keyCase("Shift-Enter adds a continuation line at the text column", "1. a|", ["S-Enter"], "1. a\n   |")
keyCase("Enter on a blank continuation line makes it the next item", "- a|", ["S-Enter", "Enter"], "- a\n- |")
keyCase("Enter on a continuation line starts a sibling item", "- a\n  co|nt", ["Enter"], "- a\n  co\n- |nt")

// 4. Backspace and Delete
keyCase("Backspace after a marker joins the text to the item above", "- a\n- |b", ["Backspace"], "- a\n  |b")
keyCase("Backspace after the first item's marker leaves a paragraph", "- |b", ["Backspace"], "|b")
keyCase("Backspace after a nested marker outdents the item", "- a\n  - |b", ["Backspace"], "- a\n- |b")
keyCase("Backspace on an empty task removes box and marker", "- a\n- [ ] |", ["Backspace"], "- a\n|")
keyCase("Backspace renumbers the items after a removed marker", "1. a\n2. |b\n3. c", ["Backspace"], "1. a\n   |b\n2. c")
keyCase("deleting a selection across items does not renumber", "1. fo«o\n2. ba»r\n3. c", ["Backspace"], "1. fo|r\n3. c")

// 3. Tab / Shift-Tab
keyCase("Tab nests a numbered item and restarts its numbering", "1. a\n2. b|\n3. c", ["Tab"], "1. a\n   1. b|\n2. c")
keyCase("Tab indents to a wide marker's text column", "10. a\n11. b|", ["Tab"], "10. a\n    1. b|")
keyCase("Tab moves children and continuation lines along", "- a\n- b|\n  - c\n  cont", ["Tab"], "- a\n  - b|\n    - c\n    cont")
keyCase("Tab joins the previous sibling's sublist", "1. a\n   1. x\n2. b|", ["Tab"], "1. a\n   1. x\n   2. b|")
keyCase("Shift-Tab adopts the parent list's marker", "1. a\n   - b|\n2. c", ["S-Tab"], "1. a\n2. b|\n3. c")
keyCase("Shift-Tab takes later siblings along as children", "- P\n  - T1\n  - T|2\n  - U", ["S-Tab"], "- P\n  - T1\n- T|2\n  - U")
keyCase("Tab and Shift-Tab are single undo steps", "- a\n- b|", ["Tab", "Undo"], "- a\n- b|")
keyCase("Undo after Enter also restores the numbering", "1. a|\n2. b", ["Enter", "Undo"], "1. a|\n2. b")

// 5. Converting lists
const convertCase = (label, source, run, expected) => {
  const { editor, close } = open(source)
  run(editor)
  check(label + (editor.getMarkdown() === expected ? "" : ` (got ${JSON.stringify(editor.getMarkdown())})`),
    editor.getMarkdown() === expected)
  close()
}
convertCase("the bullet toggle converts plain lines", "«a\nb»", (e) => e.exec("bulletList"), "- a\n- b")
convertCase("the bullet toggle removes bullets when all lines have them", "«- a\n- b»", (e) => e.exec("bulletList"), "a\nb")
convertCase("a mixed selection becomes the target style", "«- a\nb»", (e) => e.exec("bulletList"), "- a\n- b")
convertCase("numbering is per nesting level, and nesting survives", "«- a\n  - b\n- c»",
  (e) => e.exec("orderedList"), "1. a\n   1. b\n2. c")
convertCase("a converted line continues the list above", "1. a\n2. b\n«c»", (e) => e.exec("orderedList"), "1. a\n2. b\n3. c")
convertCase("converting to tasks keeps numbers", "«1. a\n2. b»", (e) => e.exec("taskList"), "1. [ ] a\n2. [ ] b")
convertCase("converting to tasks keeps the bullet character", "«* a»", (e) => e.exec("taskList"), "* [ ] a")
convertCase("tasks to bullets drops the box, numbers to bullets the number", "«1. [x] a»",
  (e) => e.setListStyle("bullet"), "- a")
convertCase("conversion keeps a blockquote prefix", "«> a\n> b»", (e) => e.exec("bulletList"), "> - a\n> - b")
convertCase("conversion skips code", "«a\n```\ncode\n```»", (e) => e.exec("bulletList"), "- a\n```\ncode\n```")
{
  const { editor, close } = open("«- [ ] a\n1. b»")
  check("getListStyle reports a mixed selection", editor.getListStyle() === "mixed")
  close()
}

// 1.1 / 7. Numbered and empty tasks, checkbox undo
{
  const { host, close } = open("1. [ ] Numbered\n- [ ]\n\nText|")
  check("a numbered task renders its number and a checkbox",
    host.querySelector(".cm-md-ordered") != null && host.querySelector(".cm-md-task-inline input") != null)
  check("an empty task box renders as a checkbox",
    host.querySelectorAll(".cm-md-task-marker input").length === 2)
  close()
}
{
  const { host, editor, press, close } = open("- [ ] Task\n\nText|")
  const box = host.querySelector(".cm-md-task-marker input")
  box.checked = true
  box.dispatchEvent(new dom.window.Event("change", { bubbles: true }))
  editor.select(editor.getMarkdown().length)
  editor.insert("!")
  press("z", { ctrlKey: true })
  check("undo after a checkbox click undoes the typing, not the click",
    editor.getMarkdown() === "- [x] Task\n\nText")
  press("z", { ctrlKey: true })
  check("the checkbox click is its own undo step", editor.getMarkdown() === "- [ ] Task\n\nText")
  close()
}

// 9.3 The caret never rests in front of a rendered list marker.
{
  const source = "Title\n- one\n  - [ ] task\n1. num"
  const { editor, press, caret, close } = open("|" + source)
  for (const [label, position, expected] of [
    ["a click before a bullet lands after it", source.indexOf("- one"), "Title\n- |one\n  - [ ] task\n1. num"],
    ["a click before a task box lands after it", source.indexOf("  - [ ]"), "Title\n- one\n  - [ ] |task\n1. num"],
    ["a click before a number lands after it", source.indexOf("1. num"), "Title\n- one\n  - [ ] task\n1. |num"],
  ]) {
    editor.select(position)
    check(label, caret() === expected)
  }
  editor.select(source.indexOf("one"))
  press("ArrowLeft")
  check("Left from the start of item text moves to the line above", caret() === "Title|\n- one\n  - [ ] task\n1. num")
  close()
}
{
  const { editor, press, caret, close } = open("Title\n- one tw|o")
  press("Home")
  check("a line-start move from item text stops after the marker", caret() === "Title\n- |one two")
  press("Home")
  check("a second line-start move stays after the marker", caret() === "Title\n- |one two")
  press("ArrowLeft", { shiftKey: true })
  check("Shift-Left from the item text start extends to the line above", caret() === "Title«\n- »one two")
  close()
}
