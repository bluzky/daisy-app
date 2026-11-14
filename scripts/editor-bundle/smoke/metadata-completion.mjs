// Editor smoke tests: `#`, `@` and `+` suggestions from the document and from
// the host's workspace snapshot.
import { dom, check } from "./harness.mjs"

const menu = () => Array.from(dom.window.document.querySelectorAll(".cm-md-metadata-menu")).at(-1)
const visible = () => menu() != null && !menu().hidden
const labels = () => visible()
  ? Array.from(menu().querySelectorAll(".cm-md-metadata-item .cm-md-metadata-label")).map((el) => el.textContent)
  : []
const key = (host, name, extra = {}) => host.querySelector(".cm-content").dispatchEvent(
  new dom.window.KeyboardEvent("keydown", { key: name, bubbles: true, cancelable: true, ...extra }))

// An editor holding `source`, with `text` typed at `at` (default: the end).
const typed = (source, text, { at = source.length, ...extra } = {}) => {
  const host = dom.window.document.createElement("div")
  dom.window.document.body.appendChild(host)
  const editor = dom.window.MDEditor.create(host, source, extra)
  if (text) editor.insertTextAt(text, at, at)
  else editor.select(at, at)
  return { host, editor }
}
const type = (editor, text) => {
  const at = editor.getLinkSelection().from
  editor.insertTextAt(text, at, at)
}

// --- Triggers --------------------------------------------------------------

{
  const { editor } = typed("Plan #review #release #roadmap #review\n\n", "Next #re")
  check("# lists the document's tags, most used first", labels().join() === "#review,#release")
  check("rows show no use count", menu().querySelector(".cm-md-metadata-detail") == null)
  check("rows are listbox options with a selected state",
    menu().getAttribute("role") === "listbox"
    && menu().querySelector(".cm-md-metadata-item").getAttribute("role") === "option"
    && menu().querySelector(".cm-md-metadata-item").getAttribute("aria-selected") === "true")
  editor.destroy()
}

{
  const { editor } = typed("Call @alex @Alex @anna and +daisy +docs\n\n", "Ask @a")
  check("@ lists contexts only", labels().join() === "@alex,@anna")
  editor.destroy()
}

{
  const { editor } = typed("Call @alex and +daisy +docs\n\n", "Ship +d")
  check("+ lists projects only", labels().join() === "+daisy,+docs")
  editor.destroy()
}

{
  const { editor } = typed("#Review #review #REVIEW #Review\n\n", "#rev")
  check("the most used spelling is shown", labels()[0] === "#Review")
  editor.destroy()
}

{
  const { editor } = typed("#café\n\n", "#café")
  check("names match across Unicode normalization", labels().join() === "#café")
  editor.destroy()
}

for (const [name, source, text] of [
  ["a heading marker", "#review\n\n", "#"],
  ["a heading", "#review\n\n", "# "],
  ["a second heading level", "#review\n\n", "##"],
  ["a list marker", "+daisy\n\n", "+"],
  ["a list item", "+daisy\n\n", "+ "],
  ["an email address", "@example\n\n", "name@ex"],
  ["C#", "#review\n\n", "C#"],
  ["a URL fragment", "#review\n\n", "see https://example.com/#re"],
  ["inline code", "#review\n\n", "`#re"],
  ["a fenced code block", "#review\n\n```\n", "#re"],
  ["link text", "#review\n\n", "[#re"],
  ["frontmatter", "---\ntitle: x\n", "#re"],
  ["a table", "#review\n\n| a | b |\n| --- | --- |\n| ", "#re"],
  ["an HTML block", "#review\n\n<div>\n", "#re"],
  ["a name starting with a slash", "#review\n\n", "#/"],
]) {
  const { editor } = typed(source, text)
  check(`no suggestions in ${name}`, !visible())
  editor.destroy()
}

{
  const { editor } = typed("#review\n\n", "#r")
  check("# opens at the start of a line once a name is typed", labels()[0] === "#review")
  editor.destroy()
}

{
  const { editor } = typed("#review\n\n", "Note #")
  check("# after a space lists every tag", labels().join() === "#review")
  editor.destroy()
}

{
  const { editor } = typed("#review\n\n- [ ] ", "#")
  check("# opens after a list marker", labels().join() === "#review")
  editor.destroy()
}

{
  const host = dom.window.document.createElement("div")
  dom.window.document.body.appendChild(host)
  const editor = dom.window.MDEditor.create(host, "#review\n\nText #re", {})
  editor.select(17, 17)
  check("loading or moving the caret opens nothing", !visible())
  editor.destroy()
}

// --- Ranking ---------------------------------------------------------------

{
  const source = "#daisy/frontend #frontend-x #front #frontier #frontier #zfront\n\n"
  const { editor } = typed(source, "#front")
  check("exact, then prefix by use, then hierarchy segment",
    labels().join() === "#front,#frontier,#frontend-x,#daisy/frontend")
  editor.destroy()
}

{
  const { editor } = typed("#beta #alpha #gamma\n\n", "x #")
  check("equal use falls back to the name", labels().join() === "#alpha,#beta,#gamma")
  editor.destroy()
}

{
  const { editor } = typed("#review\n\n", "#new-idea")
  check("an unknown name lists nothing and keeps the text", !visible()
    && editor.getMarkdown() === "#review\n\n#new-idea")
  editor.destroy()
}

{
  const { editor } = typed("#review\n\n", "#review")
  check("a known name lists itself once", labels().join() === "#review")
  editor.destroy()
}

{
  const { editor } = typed("#review\n\n", "#123")
  check("a name without a letter lists nothing", !visible()
    && editor.getMarkdown() === "#review\n\n#123")
  editor.destroy()
}

{
  const { editor } = typed("#review\n\nText ", "#a/")
  check("an empty hierarchy segment is not offered", !visible())
  editor.destroy()
}

{
  const { editor } = typed("Text ", "#rev")
  check("the token being typed does not suggest itself", !visible())
  editor.destroy()
}

// --- Accepting -------------------------------------------------------------

{
  const { host, editor } = typed("#review\n\n", "Read #re")
  key(host, "Enter")
  check("Enter inserts the name", editor.getMarkdown() === "#review\n\nRead #review" && !visible())
  check("the caret ends after the name", editor.getLinkSelection().from === 21)
  key(host, "z", { ctrlKey: true, code: "KeyZ" })
  check("one undo restores the typed text", editor.getMarkdown() === "#review\n\nRead #re")
  key(host, "y", { ctrlKey: true, code: "KeyY" })
  check("redo reapplies the name", editor.getMarkdown() === "#review\n\nRead #review")
  editor.destroy()
}

{
  const { host, editor } = typed("#review #release\n\n", "Read #rel")
  key(host, "Tab")
  check("Tab accepts", editor.getMarkdown() === "#review #release\n\nRead #release")
  editor.destroy()
}

{
  const { host, editor } = typed("#review #release\n\nRead #rxyz, ok", "", { at: 0 })
  editor.insertTextAt("e", 25, 25)
  check("a token with text after the caret opens on what precedes the caret",
    labels().join() === "#release,#review")
  key(host, "Enter")
  check("the whole token is replaced and the punctuation kept",
    editor.getMarkdown() === "#review #release\n\nRead #release, ok")
  editor.destroy()
}

{
  const { host, editor } = typed("#review #release\n\n", "Read #re")
  key(host, "ArrowDown")
  key(host, "Enter")
  check("arrow keys move the selection", editor.getMarkdown() === "#review #release\n\nRead #review")
  editor.destroy()
}

{
  const { editor } = typed("#review #release\n\n", "Read #re")
  const row = Array.from(menu().querySelectorAll(".cm-md-metadata-item"))[1]
  const event = new dom.window.MouseEvent("mousedown", { bubbles: true, cancelable: true })
  row.dispatchEvent(event)
  check("a click inserts that row", editor.getMarkdown() === "#review #release\n\nRead #review")
  check("a click does not move focus out of the editor", event.defaultPrevented)
  editor.destroy()
}

// --- Dismissing ------------------------------------------------------------

{
  const { host, editor } = typed("#review\n\n", "Read #re")
  key(host, "Escape")
  check("Escape closes without changing the text", !visible() && editor.getMarkdown() === "#review\n\nRead #re")
  type(editor, "v")
  check("a dismissed token stays closed", !visible())
  type(editor, " #r")
  check("a new token opens again", labels().includes("#review"))
  editor.destroy()
}

{
  const { editor } = typed("#review\n\n", "Read #re")
  type(editor, " ")
  check("space closes and keeps the text", !visible() && editor.getMarkdown() === "#review\n\nRead #re ")
  editor.destroy()
}

{
  const { editor } = typed("#review\n\n", "Read #re")
  editor.select(15, 17)
  check("a selection closes the menu", !visible())
  editor.destroy()
}

{
  const { host, editor } = typed("#review\n\n", "Read #re")
  host.querySelector(".cm-content").dispatchEvent(new dom.window.CompositionEvent("compositionstart", { bubbles: true }))
  type(editor, "v")
  check("IME composition hides the menu", !visible())
  key(host, "Enter")
  check("Enter during composition does not accept", !editor.getMarkdown().includes("Read #review"))
  host.querySelector(".cm-content").dispatchEvent(new dom.window.CompositionEvent("compositionend", { bubbles: true }))
  editor.destroy()
}

{
  // An IME that composes every letter, such as Vietnamese Telex.
  const { editor, host } = typed("#review\n\n", "Read #")
  const content = host.querySelector(".cm-content")
  content.dispatchEvent(new dom.window.CompositionEvent("compositionstart", { bubbles: true }))
  type(editor, "re")
  content.dispatchEvent(new dom.window.CompositionEvent("compositionend", { bubbles: true }))
  await new Promise((resolve) => setTimeout(resolve, 5))
  check("the menu shows once composition ends", labels()[0] === "#review")
  key(host, "Enter")
  check("Enter accepts after composition ends", editor.getMarkdown() === "#review\n\nRead #review")
  editor.destroy()
}

{
  const { editor } = typed("#review\n\n", "Read #rev")
  editor.replaceMarkdown("Replaced #rev")
  check("a session the host replaced is gone", !visible())
  editor.destroy()
}

{
  const { editor } = typed("#new-idea\n\n", "Read #new")
  editor.setExtensionState({ "metadata-completion": false })
  check("switching the module off closes the menu", !visible())
  type(editor, "x")
  check("the module off opens nothing", !visible())
  editor.destroy()
}

// --- Workspace snapshot ------------------------------------------------------

{
  const { editor } = typed("Text\n\n", "", {})
  check("a snapshot is taken", editor.setWorkspaceCandidates({
    version: 2,
    tags: [{ name: "release", count: 9 }, { name: "Review", count: 1 }, { name: "#bad" }, { name: "123" }, { name: "a//b" }],
    contexts: [{ name: "alex", count: 3 }],
    projects: [{ name: "daisy" }],
  }) === true)
  type(editor, "#re")
  check("snapshot names are suggested by use", labels().join() === "#release,#Review")
  type(editor, " @")
  check("snapshot contexts are suggested", labels().join() === "@alex")
  type(editor, " +")
  check("snapshot projects are suggested", labels().join() === "+daisy")
  editor.setWorkspaceCandidates({ version: 2, projects: [{ name: "daisy" }, { name: "dune" }] })
  check("a snapshot refreshes an open menu", labels().join() === "+daisy,+dune")
  check("an older snapshot is ignored", editor.setWorkspaceCandidates({ version: 1, projects: [{ name: "old" }] }) === false)
  type(editor, "o")
  check("the ignored snapshot changes nothing", !visible())
  check("a malformed snapshot is ignored", editor.setWorkspaceCandidates({ tags: [] }) === false
    && editor.setWorkspaceCandidates(null) === false && editor.setWorkspaceCandidates({ version: -1 }) === false)
  check("a newer snapshot is taken", editor.setWorkspaceCandidates({ version: 3, projects: [{ name: "orbit" }] }) === true)
  type(editor, "r")
  check("a snapshot reaches a token being typed", labels().join() === "+orbit")
  editor.destroy()
}

{
  const { editor } = typed("#Release #Release\n\n", "")
  editor.setWorkspaceCandidates({ version: 1, tags: [{ name: "release", count: 1 }, { name: "review", count: 1 }] })
  type(editor, "#re")
  check("the document's spelling and count win for its own names", labels().join() === "#Release,#review")
  editor.destroy()
}

{
  const { editor } = typed("Text\n\n", "")
  editor.setWorkspaceCandidates({ version: 1, tags: [{ name: "review", count: 2 }] })
  editor.setExtensionState({ "metadata-completion": false })
  editor.setExtensionState({ "metadata-completion": true })
  type(editor, "#re")
  check("a snapshot survives switching the module off and on", labels()[0] === "#review")
  editor.destroy()
}

// --- Task lifecycle -----------------------------------------------------------

{
  const host = dom.window.document.createElement("div")
  dom.window.document.body.appendChild(host)
  const editor = dom.window.MDEditor.create(host, "- [ ] Call @alex about +daisy #review", {})
  editor.select(37, 37)
  key(host, "Enter")
  check("the next task does not copy contexts, projects or tags",
    editor.getMarkdown() === "- [ ] Call @alex about +daisy #review\n- [ ] ")
  editor.destroy()
}

// --- Slash menu still works beside it ------------------------------------------

{
  const { editor } = typed("#review\n\n", "Read /h1")
  const slash = Array.from(dom.window.document.querySelectorAll(".cm-md-slash-menu")).at(-1)
  check("the slash menu still opens", slash && !slash.hidden && !visible())
  editor.destroy()
}
