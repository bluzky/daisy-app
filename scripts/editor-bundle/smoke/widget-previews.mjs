// Widget previews in the editor (docs/features/editor-widget-previews.md).
// The real widget script runs in WebKit (EditorWidgetPreviewTests.swift);
// here a stub `window.MdWidgets` stands in for it, so these checks cover the
// editor's rules: when a widget is drawn, when its source shows, clicks,
// find, tables, copy and decks.
import { dom, check, pressKey } from "./harness.mjs"

const document = dom.window.document
dom.window.MdWidgets = {
  block(language, source) {
    if (!["stat", "chart", "progress"].includes(language) || /color: purple/.test(source)) return null
    const node = document.createElement("div")
    node.className = `stub-widget stub-${language}`
    node.dataset.source = source
    const link = /^link: (.*)$/m.exec(source)
    if (link) {
      const anchor = document.createElement("a")
      anchor.href = link[1]
      anchor.textContent = "link"
      node.append(anchor)
    }
    return node
  },
  inline(text) {
    const match = /^\{\{\s*([a-z][a-z0-9-]*):([\s\S]*)\}\}$/.exec(text)
    if (!match || !["sparkline", "badge", "progress", "shape"].includes(match[1])) return null
    if (match[1] === "sparkline" && match[2].split(",").length < 2) return null
    const node = document.createElement("span")
    node.className = `stub-inline stub-${match[1]}`
    node.dataset.text = text
    return node
  },
  animate: (node) => node,
}

const mount = (markdown) => {
  const host = document.createElement("div")
  document.body.appendChild(host)
  const editor = dom.window.MDEditor.create(host, markdown, {})
  const view = host.querySelector(".cm-content").cmTile.view
  return { host, editor, view }
}
const mousedown = (target) => target.dispatchEvent(new dom.window.MouseEvent("mousedown",
  { bubbles: true, cancelable: true, button: 0, detail: 1 }))
const settle = () => new Promise((resolve) => setTimeout(resolve, 10))

const stat = "```stat\nlabel: Revenue\nvalue: 12,400\n```"

// AC-1.1
{
  const { host, editor } = mount(`intro\n\n${stat}\n\nafter`)
  const preview = host.querySelector(".cm-md-widget-preview")
  check("AC-1.1 a valid stat block is drawn in place of its fence",
    preview?.querySelector(".stub-stat")?.dataset.source === "label: Revenue\nvalue: 12,400"
      && !host.querySelector(".cm-content").textContent.includes("label: Revenue"))
  editor.destroy()
}

// AC-1.2
{
  const chart = "```chart\ntype: bar\n| Month | Sales |\n| --- | --- |\n| Jan | 10 |\n```"
  const markdown = `intro\n\n${chart}\n\nafter`
  const { host, editor, view } = mount(markdown)
  check("AC-1.2 a chart block is drawn while the caret is outside it",
    host.querySelector(".stub-chart") != null)
  const value = markdown.indexOf("| 10 |") + 2
  editor.select(value)
  check("AC-1.2 moving the caret into the chart shows its source and no chart",
    host.querySelector(".cm-md-widget-preview") == null
      && host.querySelector(".cm-content").textContent.includes("| Jan | 10 |"))
  view.dispatch({ changes: { from: value, to: value + 2, insert: "42" } })
  editor.select(view.state.doc.length)
  check("AC-1.2 leaving the chart draws it from the new source",
    host.querySelector(".stub-chart")?.dataset.source.includes("| Jan | 42 |"))
  editor.destroy()
}

// A value changed while the caret is outside (undo, reload) redraws it.
{
  const { host, editor, view } = mount(`intro\n\n${stat}\n\nafter`)
  const at = view.state.doc.toString().indexOf("12,400")
  view.dispatch({ changes: { from: at, to: at + 6, insert: "99" } })
  check("an edit outside the caret redraws the widget from the new source",
    host.querySelector(".stub-stat")?.dataset.source === "label: Revenue\nvalue: 99")
  editor.destroy()
}

// BR-1: a caret that reaches a block without a pointer still shows its source.
{
  const markdown = `intro\n\n${stat}\n\nafter`
  const { host, editor, view } = mount(markdown)
  view.dispatch({ selection: { anchor: markdown.indexOf("12,400") }, userEvent: "select" })
  check("AC-1.2 a keyboard selection moving into a block shows its source",
    host.querySelector(".cm-md-widget-preview") == null)
  view.dispatch({ selection: { anchor: markdown.length }, userEvent: "select" })
  check("AC-1.2 a keyboard selection leaving the block draws it again",
    host.querySelector(".cm-md-widget-preview .stub-stat") != null)
  editor.destroy()
}

// BR-1: Backspace below a block reveals the source before it deletes any of it.
for (const [where, markdown] of [
  ["on the line below", `intro\n\n${stat}\nafter`],
  ["on an empty line below", `intro\n\n${stat}\n`],
]) {
  const { host, editor, view } = mount(markdown)
  view.dispatch({ selection: { anchor: markdown.indexOf("12,400\n```") + "12,400\n```\n".length },
    userEvent: "select" })
  pressKey(host, "Backspace")
  check(`BR-1 Backspace ${where} of a block shows its source with the values intact`,
    host.querySelector(".cm-md-widget-preview") == null
      && view.state.doc.toString().includes("value: 12,400"))
  editor.destroy()
}

// BR-1: a block right after another fence, entered at its first position.
{
  const markdown = `\`\`\`js\nlet a = 1\n\`\`\`\n${stat}\n\nafter`
  const { host, editor, view } = mount(markdown)
  // Arrowing past the first fence's closing line lands on the block's start.
  view.focus()
  view.dispatch({ selection: { anchor: markdown.indexOf("\n```\n") }, userEvent: "select" })
  pressKey(host, "ArrowRight")
  check("BR-1 a caret on a block's first position shows its source",
    view.state.selection.main.head === markdown.indexOf("```stat")
      && host.querySelector(".cm-md-widget-preview") == null)
  editor.destroy()
}

// An edit elsewhere doesn't open a leading block under the untouched caret.
{
  const { host, editor, view } = mount(`${stat}\n\nafter`)
  view.dispatch({ changes: { from: view.state.doc.length, insert: "!" } })
  check("an edit elsewhere keeps a leading block drawn",
    host.querySelector(".cm-md-widget-preview") != null)
  editor.destroy()
}

// BR-1: a selection with either end inside a block shows its source; one that
// reaches past both ends leaves it drawn.
{
  const markdown = `intro\n\n${stat}\n\nmiddle\n\n\`\`\`progress\nvalue: 3\n\`\`\`\n\nafter`
  const { host, editor, view } = mount(markdown)
  const select = (anchor, head) => view.dispatch({ selection: { anchor, head }, userEvent: "select" })
  const drawn = () => [".stub-stat", ".stub-progress"].map((name) => host.querySelector(name) != null)
  const inStat = markdown.indexOf("12,400")
  const inProgress = markdown.indexOf("value: 3")
  select(markdown.indexOf("middle"), inStat)
  check("BR-1 a selection reaching into a block from outside shows its source",
    drawn().join() === "false,true")
  select(inStat, markdown.length)
  check("BR-1 a selection starting inside a block shows its source",
    drawn().join() === "false,true")
  select(inStat, inProgress)
  check("BR-1 a selection ending in two blocks shows both sources", drawn().join() === "false,false")
  select(0, markdown.length)
  check("BR-1 a selection past both ends of the blocks leaves them drawn", drawn().join() === "true,true")
  editor.destroy()
}

// A table cell's escaped pipe reaches the widget script unescaped, as in Read mode.
{
  const { host, editor } = mount('| Item |\n| --- |\n| `{{badge: "a\\|b"}}` |\n')
  check("an escaped pipe in a cell's shortcode is unescaped",
    host.querySelector(".cm-md-table-cell .stub-badge")?.dataset.text === '{{badge: "a|b"}}')
  editor.destroy()
}

// AC-1.3
{
  const { host, editor } = mount("intro\n\n```progress\nvalue: 3\ncolor: purple\n```\n\nafter")
  check("AC-1.3 an invalid progress block stays a code block",
    host.querySelector(".cm-md-widget-preview") == null
      && host.querySelector(".cm-content").textContent.includes("color: purple"))
  editor.destroy()
}

const linkedStat = "intro\n\n```stat\nlabel: Docs\nvalue: 3\nlink: https://example.com\n```\n\nafter"

// A stat's link is never followed in the editor.
{
  const { host, editor } = mount(linkedStat)
  const click = new dom.window.MouseEvent("click", { bubbles: true, cancelable: true })
  host.querySelector(".stub-stat a").dispatchEvent(click)
  check("clicking a stat's link in the editor doesn't follow it", click.defaultPrevented)
  editor.destroy()
}

// AC-1.4
for (const [where, start] of [["above", 0], ["below", linkedStat.length]]) {
  const { host, editor, view } = mount(linkedStat)
  editor.select(start)
  mousedown(host.querySelector(".cm-md-widget-preview"))
  document.dispatchEvent(new dom.window.MouseEvent("mouseup", { bubbles: true }))
  await settle()
  check(`AC-1.4 clicking a stat with the caret ${where} puts the caret on its first source line`,
    view.state.selection.main.head === linkedStat.indexOf("label: Docs")
      && host.querySelector(".cm-md-widget-preview") == null)
  editor.destroy()
}

// AC-1.5
{
  const markdown = "intro\n\n```chart\ntype: bar\n| Month | Revenue |\n| --- | --- |\n| Jan | 10 |\n```\n\nafter"
  const { host, editor } = mount(markdown)
  editor.find("Revenue")
  check("AC-1.5 the current find match in a chart shows its source, highlighted",
    host.querySelector(".cm-md-widget-preview") == null
      && host.querySelector(".cm-find-current")?.textContent === "Revenue")
  editor.find("")
  editor.destroy()
}

const badge = '`{{badge: "In review" color=warning}}`'

// AC-2.1
{
  const markdown = `Status ${badge} today`
  const { host, editor } = mount(markdown)
  check("AC-2.1 a valid badge is drawn inline with the caret elsewhere",
    host.querySelector(".cm-md-widget-inline .stub-badge")?.dataset.text === '{{badge: "In review" color=warning}}'
      && !host.querySelector(".cm-content").textContent.includes("{{badge"))
  editor.focus()
  editor.select(markdown.indexOf("{{") + 3)
  check("AC-2.1 the caret on the code span shows the shortcode's source",
    host.querySelector(".cm-md-widget-inline") == null
      && host.querySelector(".cm-content").textContent.includes("{{badge"))
  editor.select(0)
  check("AC-2.1 the caret leaving the code span draws the badge again",
    host.querySelector(".cm-md-widget-inline .stub-badge") != null)
  editor.destroy()
}

// AC-2.2
{
  const { host, editor } = mount("Trend `{{sparkline: 3}}` here")
  check("AC-2.2 a sparkline with one number stays inline code",
    host.querySelector(".cm-md-widget-inline") == null
      && host.querySelector(".cm-md-inline-code")?.textContent === "{{sparkline: 3}}")
  editor.destroy()
}

// AC-2.3
{
  const markdown = `Status ${badge} today`
  const { host, editor, view } = mount(markdown)
  mousedown(host.querySelector(".cm-md-widget-inline"))
  await settle()
  check("AC-2.3 clicking a badge puts the caret inside its code span and shows its source",
    view.state.selection.main.head === markdown.indexOf("{{")
      && host.querySelector(".cm-md-widget-inline") == null)
  editor.destroy()
}

// AC-2.4
{
  const markdown = "| Item | Trend |\n| --- | --- |\n| Sales | `{{sparkline: 3,5,2,8}}` |\n"
  const { host, editor } = mount(markdown)
  const cell = host.querySelector('.cm-md-table-cell[data-table-row="1"][data-table-column="1"]')
  check("AC-2.4 a sparkline in a table cell is drawn while no cell is edited",
    cell?.querySelector(".cm-md-widget-inline .stub-sparkline") != null
      && cell.querySelector(".cm-md-widget-inline").contentEditable === "false")
  // JSDOM has no contenteditable focus; send the event the table listens for.
  cell?.dispatchEvent(new dom.window.FocusEvent("focus"))
  check("AC-2.4 editing the cell shows the shortcode's source",
    cell?.textContent === "`{{sparkline: 3,5,2,8}}`" && cell.querySelector(".cm-md-widget-inline") == null)
  editor.destroy()
}

// AC-2.5
{
  const markdown = `Status ${badge} today`
  const { host, editor } = mount(markdown)
  editor.focus()
  editor.select(0, markdown.length)
  const data = {}
  const event = new dom.window.Event("copy", { bubbles: true, cancelable: true })
  event.clipboardData = { setData: (type, value) => { data[type] = value }, clearData() {} }
  host.querySelector(".cm-content").dispatchEvent(event)
  check("AC-2.5 copying a line with a drawn badge copies its Markdown source",
    data["text/plain"] === markdown)
  editor.destroy()
}

// AC-3.1
{
  const { host, editor } = mount(`---\nslides: true\n---\n\n${stat}\n\nText ${badge}\n`)
  check("AC-3.1 a deck draws widget blocks and shortcodes as any file does",
    host.querySelector(".cm-md-widget-preview .stub-stat") != null
      && host.querySelector(".cm-md-widget-inline .stub-badge") != null)
  editor.destroy()
}

// Read mode doesn't draw shortcodes in footnote definitions (Q-8).
{
  const { host, editor } = mount(`Body[^1] and ${badge}\n\n[^1]: Note ${badge}\n    more ${badge}\n`)
  check("shortcodes in a footnote definition stay code, as in Read mode",
    host.querySelectorAll(".cm-md-widget-inline").length === 1
      && host.querySelectorAll(".cm-md-inline-code").length === 2)
  editor.destroy()
}

// Mermaid keeps working on the shared fence preview.
{
  const { host, editor } = mount(`intro\n\n\`\`\`mermaid\nflowchart LR\n  A --> B\n\`\`\`\n\n${stat}`)
  check("Mermaid and widget previews draw side by side",
    host.querySelector(".cm-md-mermaid-preview") != null && host.querySelector(".stub-stat") != null)
  editor.destroy()
}

// Without the widget script (headless hosts), widgets stay as code.
delete dom.window.MdWidgets
{
  const { host, editor } = mount(`intro\n\n${stat}\n\nStatus ${badge}`)
  check("without the widget script, widget blocks and shortcodes stay code",
    host.querySelector(".cm-md-widget-preview") == null && host.querySelector(".cm-md-widget-inline") == null)
  editor.destroy()
}
