// Editor smoke tests: slash menu, templates and template variables.
import { dom, check } from "./harness.mjs"

// --- Slash commands --------------------------------------------------------
// Menus live on <body>; the newest one belongs to the editor just created.
const slashMenu = () => Array.from(dom.window.document.querySelectorAll(".cm-md-slash-menu")).at(-1)
const slashVisible = () => slashMenu() != null && !slashMenu().hidden
const slashLabels = () => Array.from(slashMenu().querySelectorAll(".cm-md-slash-label")).map((el) => el.textContent)
const slashKey = (host, key) => host.querySelector(".cm-content").dispatchEvent(
  new dom.window.KeyboardEvent("keydown", { key, bubbles: true, cancelable: true }))
const slashEditor = (source, extra = {}) => {
  const host = dom.window.document.createElement("div")
  dom.window.document.body.appendChild(host)
  const editor = dom.window.MDEditor.create(host, source, { extensionState: { "slash-commands": true }, ...extra })
  return { host, editor }
}

{
  const { host, editor } = slashEditor("")
  check("slash menu stays closed for a loaded document", !slashVisible())
  editor.insertTextAt("/", 0, 0)
  check("typing / on an empty line opens the menu", slashVisible())
  check("menu lists grouped commands", slashLabels().includes("Heading 1") && slashLabels().includes("Table"))
  check("every menu row has a line icon",
    Array.from(slashMenu().querySelectorAll(".cm-md-slash-item"))
      .every((row) => row.querySelector(".cm-md-slash-icon svg path, .cm-md-slash-icon svg text") != null))
  editor.insertTextAt("h2", 1, 1)
  check("typing filters the menu", slashLabels()[0] === "Heading 2")
  slashKey(host, "Enter")
  check("Enter converts the line to the chosen block", editor.getMarkdown() === "## ")
  check("menu closes after applying", !slashVisible())
  editor.exec("h0")
}

{
  const { host, editor } = slashEditor("")
  editor.insertTextAt("/", 0, 0)
  slashKey(host, "ArrowDown")
  slashKey(host, "Enter")
  check("ArrowDown moves the selection before Enter", editor.getMarkdown() === "## ")
}

{
  const { host, editor } = slashEditor("")
  editor.insertTextAt("/", 0, 0)
  slashKey(host, "Escape")
  check("Escape dismisses the menu without touching the text",
    !slashVisible() && editor.getMarkdown() === "/")
  editor.insertTextAt("t", 1, 1)
  check("a dismissed menu stays closed while the same line is edited", !slashVisible())
}

{
  const { editor } = slashEditor("see ")
  editor.insertTextAt("/", 4, 4)
  check("a slash after a space at the end of text opens the menu", slashVisible())
}

{
  const { editor } = slashEditor("see")
  editor.insertTextAt("/", 3, 3)
  check("a slash glued to a word does not open the menu", !slashVisible())
}

{
  const { editor } = slashEditor("1")
  editor.insertTextAt("/", 1, 1)
  check("a slash inside a fraction or path does not open the menu", !slashVisible())
}

{
  const { host, editor } = slashEditor("Buy milk ")
  editor.insertTextAt("/task", 9, 9)
  slashKey(host, "Enter")
  check("a command typed after text converts the whole line", editor.getMarkdown() === "- [ ] Buy milk")
}

{
  const { host, editor } = slashEditor("Buy milk later")
  editor.insertTextAt("/h2", 9, 9)
  slashKey(host, "Enter")
  check("text on both sides of the slash joins into the block",
    editor.getMarkdown() === "## Buy milk later")
}

{
  const { host, editor } = slashEditor("- item ")
  editor.insertTextAt("/h1", 7, 7)
  slashKey(host, "Enter")
  check("an existing marker is replaced when converting from line end", editor.getMarkdown() === "# item")
}

{
  const { editor } = slashEditor("`code  here`")
  editor.insertTextAt("/", 6, 6)
  check("a slash inside inline code stays literal", !slashVisible())
}

{
  const { editor } = slashEditor("  ")
  editor.insertTextAt("/", 2, 2)
  check("a slash after whitespace opens the menu", slashVisible())
}

{
  // Four spaces make an indented code block, where `/` is literal.
  const { editor } = slashEditor("    ")
  editor.insertTextAt("/", 4, 4)
  check("a slash in an indented code block stays literal", !slashVisible())
}

// --- Slash templates --------------------------------------------------------
const slashTemplates = [
  { name: "Meeting notes", body: "### Attendees\n\n- \n\n### Notes" },
  { name: "Daily standup", body: "- Yesterday\n- Today" },
]
const slashHasBack = () => slashMenu().querySelector("[data-slash-back]") != null

{
  const { host, editor } = slashEditor("")
  editor.insertTextAt("/", 0, 0)
  check("no Templates row without templates", !slashLabels().includes("Templates"))
  editor.setSlashTemplates(slashTemplates)
  check("a Templates row appears once templates are set", slashLabels().at(-1) === "Templates")
  check("the Templates row has an icon and a chevron",
    slashMenu().querySelector(".cm-md-slash-item:last-child .cm-md-slash-icon svg path") != null
    && slashMenu().querySelector(".cm-md-slash-item:last-child .cm-md-slash-chevron") != null)
  editor.setSlashTemplates([])
  check("clearing templates removes the row again", !slashLabels().includes("Templates"))
  editor.setSlashTemplates(slashTemplates)

  for (let i = 0; i < slashLabels().length - 1; i++) slashKey(host, "ArrowDown")
  slashKey(host, "Enter")
  check("Enter on Templates lists the templates instead of inserting",
    slashVisible() && slashHasBack() && editor.getMarkdown() === "/"
    && JSON.stringify(slashLabels()) === JSON.stringify(["Templates", "Meeting notes", "Daily standup"]))
  slashKey(host, "ArrowDown")
  slashKey(host, "Enter")
  check("Enter on a template inserts its body verbatim",
    editor.getMarkdown() === "- Yesterday\n- Today" && !slashVisible())
}

{
  const { host, editor } = slashEditor("")
  editor.setSlashTemplates(slashTemplates)
  editor.insertTextAt("/", 0, 0)
  for (let i = 0; i < slashLabels().length - 1; i++) slashKey(host, "ArrowDown")
  slashKey(host, "ArrowRight")
  check("ArrowRight opens the Templates list", slashHasBack())
  slashKey(host, "ArrowLeft")
  check("ArrowLeft goes back to the top level", !slashHasBack() && slashLabels().includes("Heading 1"))
}

{
  const { host, editor } = slashEditor("")
  editor.setSlashTemplates(slashTemplates)
  editor.insertTextAt("/", 0, 0)
  for (let i = 0; i < slashLabels().length - 1; i++) slashKey(host, "ArrowDown")
  slashKey(host, "Enter")
  slashKey(host, "Backspace")
  check("Backspace on an empty query goes back and keeps the slash",
    !slashHasBack() && slashVisible() && editor.getMarkdown() === "/")
  slashKey(host, "ArrowRight")
  check("ArrowRight does nothing on the first, normal row", !slashHasBack())
  for (let i = 0; i < slashLabels().length - 1; i++) slashKey(host, "ArrowDown")
  slashKey(host, "Enter")
  slashKey(host, "Escape")
  check("Escape closes the whole menu from the Templates list", !slashVisible() && editor.getMarkdown() === "/")
}

{
  const { host, editor } = slashEditor("")
  editor.setSlashTemplates(slashTemplates)
  editor.insertTextAt("/", 0, 0)
  for (let i = 0; i < slashLabels().length - 1; i++) slashKey(host, "ArrowDown")
  slashKey(host, "Enter")
  editor.insertTextAt("stand", 1, 1)
  check("typing in the Templates list filters templates only",
    JSON.stringify(slashLabels()) === JSON.stringify(["Templates", "Daily standup"]))
  editor.insertTextAt("x", 6, 6)
  check("a query with no match closes the menu", !slashVisible())
}

{
  const { host, editor } = slashEditor("")
  editor.setSlashTemplates(slashTemplates)
  editor.insertTextAt("/meet", 0, 0)
  check("the top level never lists templates, even on a name match", !slashVisible())
  editor.exec("h0")
}

{
  const { host, editor } = slashEditor("")
  editor.setSlashTemplates(slashTemplates)
  editor.insertTextAt("/templ", 0, 0)
  check("searching \"templ\" finds only the Templates row", JSON.stringify(slashLabels()) === JSON.stringify(["Templates"]))
  slashKey(host, "Enter")
  check("Enter opens the list and clears the typed query but keeps the slash",
    slashHasBack() && editor.getMarkdown() === "/"
    && JSON.stringify(slashLabels()) === JSON.stringify(["Templates", "Meeting notes", "Daily standup"]))
  editor.insertTextAt("meet", 1, 1)
  check("then typing searches template names only",
    JSON.stringify(slashLabels()) === JSON.stringify(["Templates", "Meeting notes"]))
  slashKey(host, "Enter")
  check("picking the match inserts it",
    editor.getMarkdown() === "### Attendees\n\n- \n\n### Notes" && !slashVisible())
}

{
  // The list searches names, not bodies or the words that opened it.
  const { host, editor } = slashEditor("")
  editor.setSlashTemplates(slashTemplates)
  editor.insertTextAt("/templates", 0, 0)
  slashKey(host, "Enter")
  editor.insertTextAt("yesterday", 1, 1)
  check("template bodies are not searched", !slashVisible())
}

{
  const { host, editor } = slashEditor("Agenda ")
  editor.setSlashTemplates(slashTemplates)
  editor.insertTextAt("/templates", 7, 7)
  slashKey(host, "Enter")
  check("opening the list from the end of text keeps the text", editor.getMarkdown() === "Agenda /")
  editor.insertTextAt("daily", 8, 8)
  slashKey(host, "Enter")
  check("text on the line stays above an inserted template",
    editor.getMarkdown() === "Agenda\n\n- Yesterday\n- Today")
}

{
  const { host, editor } = slashEditor("  ")
  editor.setSlashTemplates([{ name: "Two", body: "a\n\nb" }])
  editor.insertTextAt("/templates", 2, 2)
  slashKey(host, "Enter")
  slashKey(host, "Enter")
  check("a template keeps the line's indent but not on blank lines", editor.getMarkdown() === "  a\n\n  b")
}

// Template variables, with a fixed clock: Sunday 4 October 2026, 14:05.
const slashVariableClock = () => new Date(2026, 9, 4, 14, 5)
const slashInsertTemplate = (body, { source = "", locale = "en" } = {}) => {
  const { host, editor } = slashEditor(source, {
    slashClock: slashVariableClock,
    extensionOptions: { "slash-commands": { locale } },
  })
  editor.setSlashTemplates([{ name: "T", body }])
  editor.insertTextAt("/templates", source.length, source.length)
  slashKey(host, "Enter")
  slashKey(host, "Enter")
  return editor
}

{
  check("{{date}} inserts the ISO date", slashInsertTemplate("# {{date}}").getMarkdown() === "# 2026-10-04")
  check("{{time}} inserts the 24-hour time", slashInsertTemplate("at {{time}}").getMarkdown() === "at 14:05")
  check("{{datetime}} inserts date and time", slashInsertTemplate("{{datetime}}").getMarkdown() === "2026-10-04 14:05")
  check("{{weekday}} inserts the day name", slashInsertTemplate("{{weekday}}").getMarkdown() === "Sunday")
  check("{{weekday}} follows the app language", slashInsertTemplate("{{weekday}}", { locale: "fr" }).getMarkdown() === "dimanche")
  check("variable names ignore case and inner spaces", slashInsertTemplate("{{ DATE }}").getMarkdown() === "2026-10-04")
  check("a variable can repeat", slashInsertTemplate("{{date}} / {{date}}").getMarkdown() === "2026-10-04 / 2026-10-04")
  check("an unknown variable stays as typed", slashInsertTemplate("{{nope}} {{date}}").getMarkdown() === "{{nope}} 2026-10-04")
  check("a backslash writes a literal {{", slashInsertTemplate("\\{{date}} {{date}}").getMarkdown() === "{{date}} 2026-10-04")
  check("variables expand inside code fences too", slashInsertTemplate("```\n{{date}}\n```").getMarkdown() === "```\n2026-10-04\n```")
}

{
  const editor = slashInsertTemplate("# {{date}}\n\nNotes: {{cursor}}\nmore")
  check("{{cursor}} is removed from the text", editor.getMarkdown() === "# 2026-10-04\n\nNotes: \nmore")
  check("{{cursor}} puts the caret where it was", editor.getLinkSelection().from === 21)
}

{
  const editor = slashInsertTemplate("a {{cursor}} b {{cursor}} c")
  check("only the first {{cursor}} counts and the rest are dropped",
    editor.getMarkdown() === "a  b  c" && editor.getLinkSelection().from === 2)
}

{
  const editor = slashInsertTemplate("one\ntwo")
  check("without {{cursor}} the caret lands at the end", editor.getLinkSelection().from === 7)
}

{
  const { host, editor } = slashEditor("")
  editor.setSlashTemplates(slashTemplates)
  editor.insertTextAt("/", 0, 0)
  for (let i = 0; i < slashLabels().length - 1; i++) slashKey(host, "ArrowDown")
  slashKey(host, "Enter")
  editor.setSlashTemplates([])
  check("emptying the templates in the list falls back to the top level",
    slashVisible() && !slashHasBack() && slashLabels().includes("Heading 1"))
}

{
  const { editor } = slashEditor("```\n\n```")
  editor.insertTextAt("/", 4, 4)
  check("a slash inside a code fence stays literal", !slashVisible())
}

{
  const { editor } = slashEditor("---\ntitle: x\n---\n\n")
  editor.insertTextAt("/", 6, 6)
  check("a slash inside frontmatter stays literal", !slashVisible())
}

{
  const { editor } = slashEditor("")
  editor.insertTextAt("/zzzz", 0, 0)
  check("a query with no match closes the menu and keeps the text",
    !slashVisible() && editor.getMarkdown() === "/zzzz")
}

{
  const { host, editor } = slashEditor("")
  editor.insertTextAt("/table", 0, 0)
  slashKey(host, "Enter")
  check("table command inserts a table skeleton",
    editor.getMarkdown() === "| Column 1 | Column 2 |\n| --- | --- |\n|  |  |")
}

{
  const { host, editor } = slashEditor("")
  editor.insertTextAt("/mermaid", 0, 0)
  slashKey(host, "Enter")
  check("mermaid command inserts a fenced diagram",
    editor.getMarkdown() === "```mermaid\ngraph TD\n    A --> B\n```")
}

{
  const { host, editor } = slashEditor("")
  editor.insertTextAt("/warning", 0, 0)
  slashKey(host, "Enter")
  check("callout command inserts an alert blockquote",
    editor.getMarkdown() === "> [!WARNING]\n> ")
}

{
  const { host, editor } = slashEditor("")
  editor.insertTextAt("/code", 0, 0)
  slashKey(host, "Enter")
  check("code command inserts an empty fence", editor.getMarkdown() === "```\n\n```")
}

{
  // Conversion: text already on the line moves into the new block.
  const { host, editor } = slashEditor("Buy milk")
  editor.insertTextAt("/task", 0, 0)
  editor.select(5)
  slashKey(host, "Enter")
  check("conversion keeps the rest of the line as content", editor.getMarkdown() === "- [ ] Buy milk")
}

{
  const { host, editor } = slashEditor("## Old title")
  editor.insertTextAt("/h1", 0, 0)
  editor.select(3)
  slashKey(host, "Enter")
  check("conversion replaces an existing block marker", editor.getMarkdown() === "# Old title")
}

{
  const { host, editor } = slashEditor("  ")
  editor.insertTextAt("/quote", 2, 2)
  slashKey(host, "Enter")
  check("indentation is preserved when converting", editor.getMarkdown() === "  > ")
}

{
  const { host, editor } = slashEditor("")
  editor.insertTextAt("/", 0, 0)
  slashMenu().querySelector("[data-slash-index='1']").dispatchEvent(
    new dom.window.MouseEvent("mousedown", { bubbles: true, cancelable: true }))
  check("clicking a row applies that command", editor.getMarkdown() === "## ")
}

{
  const { editor } = slashEditor("", { extensionOptions: { "slash-commands": { "cmd.h1": "标题 1", "group.text": "文本" } } })
  editor.insertTextAt("/", 0, 0)
  check("host labels replace the English ones", slashLabels().includes("标题 1"))
  editor.insertTextAt("heading", 1, 1)
  check("English names stay searchable under host labels", slashLabels().includes("标题 1"))
}

{
  const { editor } = slashEditor("")
  editor.insertTextAt("/", 0, 0)
  check("image command is hidden when the page cannot pick files", !slashLabels().includes("Image"))
}

{
  const picks = []
  const { host, editor } = slashEditor("Photo ", { onPickImage: (from, to) => picks.push([from, to]) })
  editor.insertTextAt("/image", 6, 6)
  check("image command is offered when the page can pick files", slashLabels()[0] === "Image")
  slashKey(host, "Enter")
  check("image command removes the typed query and keeps the line", editor.getMarkdown() === "Photo ")
  check("image command asks the host to pick at the query position",
    picks.length === 1 && picks[0][0] === 6 && picks[0][1] === 6)
  check("image command closes the menu", !slashVisible())
}

{
  const { editor } = slashEditor("")
  editor.setExtensionState({ "slash-commands": false })
  editor.insertTextAt("/", 0, 0)
  check("disabling the module stops the menu", !slashVisible())
  editor.setExtensionState({ "slash-commands": true })
  editor.insertTextAt("h", 1, 1)
  check("re-enabling the module restores the menu", slashVisible())
}

{
  const before = dom.window.document.querySelectorAll(".cm-md-slash-menu").length
  const { editor } = slashEditor("")
  check("each editor owns one menu element",
    dom.window.document.querySelectorAll(".cm-md-slash-menu").length === before + 1)
  editor.destroy()
  check("destroying the editor removes its menu",
    dom.window.document.querySelectorAll(".cm-md-slash-menu").length === before)
}
