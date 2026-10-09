import { EditorView, keymap, ViewPlugin } from "@codemirror/view"
import { EditorSelection, StateEffect, StateField } from "@codemirror/state"
import { syntaxTree } from "@codemirror/language"
import { tags as t } from "@lezer/highlight"
import { registerEditorExtension } from "./extensions.js"

// Slash commands: typing `/` at the start of a line or after a space opens a
// menu of blocks; picking one converts that line. Labels come from the host
// (`options["cmd.<id>"]`, `options["group.<id>"]`) so they follow the app
// language, with English as the fallback.
const SLASH_GROUPS = [
  { id: "text", label: "Text" },
  { id: "lists", label: "Lists" },
  { id: "blocks", label: "Blocks" },
]

// An existing block marker on the converted line is replaced, not stacked.
const SLASH_BLOCK_PREFIX = /^(?:#{1,6}[ \t]+|>[ \t]?(?:\[![A-Za-z]+\][ \t]*)?|[-*+][ \t]+(?:\[[ xX]\][ \t]+)?|\d{1,9}[.)][ \t]+)/

function slashLine(prefix, raw) {
  const text = prefix + raw.replace(SLASH_BLOCK_PREFIX, "")
  return { lines: [text], caret: { line: 0, ch: text.length } }
}

function slashFence(open, close, raw, fallback) {
  const body = raw ? [raw] : fallback
  return { lines: [open, ...body, close], caret: { line: body.length, ch: body[body.length - 1].length } }
}

function slashCallout(kind, raw) {
  const text = "> " + raw.replace(SLASH_BLOCK_PREFIX, "")
  return { lines: [`> [!${kind}]`, text], caret: { line: 1, ch: text.length } }
}

// Line icons for the menu rows, drawn on a 20x20 grid in the text color.
const SLASH_ICON_TEXT = (value) =>
  `<text x="10" y="14.2" text-anchor="middle" font-size="11.5" font-weight="700" fill="currentColor" stroke="none" font-family="-apple-system, system-ui, sans-serif">${value}</text>`
const SLASH_ICONS = {
  h1: SLASH_ICON_TEXT("H1"),
  h2: SLASH_ICON_TEXT("H2"),
  h3: SLASH_ICON_TEXT("H3"),
  quote: '<path d="M5 4.5v11M9 6.5h6.5M9 10h6.5M9 13.5h4"/>',
  divider: '<path d="M3.5 10h13"/>',
  bullet: '<path d="M8.5 6h8M8.5 10h8M8.5 14h8"/><circle cx="4.7" cy="6" r=".9" fill="currentColor" stroke="none"/><circle cx="4.7" cy="10" r=".9" fill="currentColor" stroke="none"/><circle cx="4.7" cy="14" r=".9" fill="currentColor" stroke="none"/>',
  ordered: '<path d="M9 6h7.5M9 10h7.5M9 14h7.5"/><text x="3" y="7.6" font-size="5.6" font-weight="700" fill="currentColor" stroke="none" font-family="-apple-system, system-ui, sans-serif">1</text><text x="3" y="11.6" font-size="5.6" font-weight="700" fill="currentColor" stroke="none" font-family="-apple-system, system-ui, sans-serif">2</text><text x="3" y="15.6" font-size="5.6" font-weight="700" fill="currentColor" stroke="none" font-family="-apple-system, system-ui, sans-serif">3</text>',
  task: '<rect x="3.5" y="4" width="5" height="5" rx="1.2"/><path d="M4.8 6.6l1.1 1.1 1.8-2.1M11.5 6.5h5M11.5 14h5"/><rect x="3.5" y="11" width="5" height="5" rx="1.2"/>',
  code: '<path d="M7.5 6.5L4 10l3.5 3.5M12.5 6.5L16 10l-3.5 3.5"/>',
  table: '<rect x="3.5" y="4.5" width="13" height="11" rx="2"/><path d="M3.5 9h13M9 9v6.5"/>',
  image: '<rect x="3.5" y="4.5" width="13" height="11" rx="2"/><circle cx="7.6" cy="8.6" r="1.3"/><path d="M4 14.2l4-3.4 3 2.4 2.2-2 3.3 3"/>',
  mermaid: '<rect x="3" y="3.5" width="6" height="4" rx="1"/><rect x="11" y="12.5" width="6" height="4" rx="1"/><path d="M6 7.5v3a2 2 0 002 2h3"/>',
  math: '<path d="M14.5 5h-9l4 5-4 5h9"/>',
  note: '<circle cx="10" cy="10" r="6.5"/><path d="M10 9.3v4M10 6.8v.1"/>',
  tip: '<path d="M7.8 13.6h4.4M8.3 16h3.4M10 3.5a4.5 4.5 0 00-2.5 8.2v1.9h5v-1.9A4.5 4.5 0 0010 3.5z"/>',
  important: '<circle cx="10" cy="10" r="6.5"/><path d="M10 6.6v4.2M10 13.2v.1"/>',
  warning: '<path d="M10 3.8L17 16H3z"/><path d="M10 8.6v3.2M10 13.8v.1"/>',
  caution: '<path d="M7 3.5h6l3.5 3.5v6L13 16.5H7L3.5 13V7z"/><path d="M10 7v3.5M10 12.8v.1"/>',
  templates: '<path d="M6 3.5h5.5L15 7v8.5a1 1 0 01-1 1H6a1 1 0 01-1-1v-11a1 1 0 011-1z"/><path d="M11.5 3.5V7H15M7.5 10.5h5M7.5 13.5h5"/>',
}

// A command with `host` has no template: it asks the host to do something the
// page cannot (here, open a file picker) and the host inserts the result at
// the position the `/query` was removed from. It is hidden when the page has
// no matching callback.
const SLASH_HOST_ACTIONS = {
  pickImage: {
    available: (callbacks) => typeof callbacks.onPickImage === "function",
    run: (callbacks, position) => callbacks.onPickImage(position, position),
  },
}

// `convert(raw)` receives the rest of the line and returns the replacement
// lines plus where the caret goes (`select` extends it over that many chars).
const SLASH_COMMANDS = [
  { id: "h1", group: "text", label: "Heading 1", aliases: ["h1", "heading", "title"],
    convert: (raw) => slashLine("# ", raw) },
  { id: "h2", group: "text", label: "Heading 2", aliases: ["h2", "heading", "subtitle"],
    convert: (raw) => slashLine("## ", raw) },
  { id: "h3", group: "text", label: "Heading 3", aliases: ["h3", "heading"],
    convert: (raw) => slashLine("### ", raw) },
  { id: "quote", group: "text", label: "Block Quote", aliases: ["quote", "blockquote"],
    convert: (raw) => slashLine("> ", raw) },
  { id: "divider", group: "text", label: "Divider", aliases: ["divider", "hr", "rule", "line", "separator"],
    // A blank line keeps `text\n---` from becoming a setext heading.
    convert: (raw) => raw
      ? { lines: [raw, "", "---", ""], caret: { line: 3, ch: 0 } }
      : { lines: ["---", ""], caret: { line: 1, ch: 0 } } },
  { id: "bullet", group: "lists", label: "Bulleted List", aliases: ["bullet", "list", "ul", "unordered"],
    convert: (raw) => slashLine("- ", raw) },
  { id: "ordered", group: "lists", label: "Numbered List", aliases: ["number", "ordered", "list", "ol"],
    convert: (raw) => slashLine("1. ", raw) },
  { id: "task", group: "lists", label: "Checklist", aliases: ["task", "todo", "checkbox", "check", "list"],
    convert: (raw) => slashLine("- [ ] ", raw) },
  { id: "code", group: "blocks", label: "Code Block", aliases: ["code", "fence", "snippet"],
    convert: (raw) => slashFence("```", "```", raw, [""]) },
  { id: "table", group: "blocks", label: "Table", aliases: ["table", "grid"],
    convert: (raw) => {
      const lead = raw ? [raw, ""] : []
      return {
        lines: [...lead, "| Column 1 | Column 2 |", "| --- | --- |", "|  |  |"],
        caret: { line: lead.length, ch: 2, select: 8 },
      }
    } },
  { id: "image", group: "blocks", label: "Image", aliases: ["image", "picture", "photo", "img"],
    host: "pickImage" },
  { id: "mermaid", group: "blocks", label: "Mermaid diagram", aliases: ["mermaid", "diagram", "chart", "flowchart"],
    convert: (raw) => slashFence("```mermaid", "```", raw, ["graph TD", "    A --> B"]) },
  { id: "math", group: "blocks", label: "Math Block", aliases: ["math", "equation", "latex", "katex"],
    convert: (raw) => slashFence("$$", "$$", raw, [""]) },
  { id: "note", group: "blocks", label: "Note", aliases: ["note", "callout", "alert", "admonition"],
    convert: (raw) => slashCallout("NOTE", raw) },
  { id: "tip", group: "blocks", label: "Tip", aliases: ["tip", "callout", "alert", "admonition"],
    convert: (raw) => slashCallout("TIP", raw) },
  { id: "important", group: "blocks", label: "Important", aliases: ["important", "callout", "alert", "admonition"],
    convert: (raw) => slashCallout("IMPORTANT", raw) },
  { id: "warning", group: "blocks", label: "Warning", aliases: ["warning", "callout", "alert", "admonition"],
    convert: (raw) => slashCallout("WARNING", raw) },
  { id: "caution", group: "blocks", label: "Caution", aliases: ["caution", "danger", "callout", "alert", "admonition"],
    convert: (raw) => slashCallout("CAUTION", raw) },
]

// Templates come from the host's template file (`setSlashTemplates`). They sit
// behind one "Templates" row, a second menu level that searches template names
// only; the top level never lists them. `body` is inserted verbatim, with the
// caret at its first `{{cursor}}` marker, or at its end when there is none.
export const slashTemplatesChanged = StateEffect.define()

const SLASH_TEMPLATES_ENTRY = {
  id: "templates", group: "blocks", label: "Templates", aliases: [], submenu: "templates",
}

// Variables in a template body are filled in when it is picked, so the date is
// the moment of insertion. `\{{` writes a literal `{{`; an unknown name stays
// as typed so a typo is visible. `{{cursor}}` marks where the caret lands.
const SLASH_VARIABLE = /\\\{\{|\{\{\s*([A-Za-z]+)\s*\}\}/g

function slashExpandTemplate(body, now, locale) {
  const pad = (value) => String(value).padStart(2, "0")
  const date = () => `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`
  const time = () => `${pad(now.getHours())}:${pad(now.getMinutes())}`
  const weekday = () => {
    try { return new Intl.DateTimeFormat(locale || undefined, { weekday: "long" }).format(now) }
    catch (_) { return new Intl.DateTimeFormat("en", { weekday: "long" }).format(now) }
  }
  const values = { date, time, datetime: () => `${date()} ${time()}`, weekday }
  let cursor = -1
  let text = ""
  let last = 0
  for (const match of body.matchAll(SLASH_VARIABLE)) {
    text += body.slice(last, match.index)
    last = match.index + match[0].length
    const name = match[1] && match[1].toLowerCase()
    if (!match[1]) text += "{{"
    else if (name === "cursor") { if (cursor < 0) cursor = text.length }
    else if (values[name]) text += values[name]()
    else text += match[0]
  }
  text += body.slice(last)
  return { text, cursor: cursor < 0 ? text.length : cursor }
}

function slashTemplateCommands(templates, context) {
  return templates.map((template, index) => ({
    id: `tpl:${index}`,
    group: "templates",
    label: template.name,
    template: true,
    names: [template.name.toLowerCase()],
    convert: (raw) => {
      const lead = raw ? [raw, ""] : []
      const { text, cursor } = slashExpandTemplate(template.body, context.now(), context.locale)
      const body = text.split("\n")
      const before = text.slice(0, cursor).split("\n")
      return {
        lines: [...lead, ...body],
        caret: { line: lead.length + before.length - 1, ch: before[before.length - 1].length },
      }
    },
  }))
}

// `/` opens the menu at the start of a line or after a space or tab, so it
// also works at the end of a line of text. A `/` glued to a word (`and/or`,
// `1/2`, a path) never does, nor does one inside code, frontmatter, HTML,
// tables, links or URLs, where it is literal text.
const SLASH_TRIGGER = /(^|[ \t])\/([\w-]*)$/
const SLASH_BLOCKED = /^(?:Frontmatter|FencedCode|CodeBlock|HTMLBlock|CommentBlock|Table|InlineCode|URL|Autolink|Link|Image)/

function slashTrigger(state) {
  const selection = state.selection.main
  if (!selection.empty) return null
  const line = state.doc.lineAt(selection.head)
  const match = SLASH_TRIGGER.exec(state.doc.sliceString(line.from, selection.head))
  if (!match) return null
  for (let node = syntaxTree(state).resolveInner(selection.head, -1); node; node = node.parent) {
    if (SLASH_BLOCKED.test(node.name)) return null
  }
  return {
    from: selection.head - match[2].length - 1,
    to: selection.head,
    indent: /^[ \t]*/.exec(line.text)[0],
    query: match[2],
    lineFrom: line.from,
  }
}

function slashMatches(commands, query) {
  if (!query) return commands
  const needle = query.toLowerCase()
  const scored = []
  commands.forEach((command, order) => {
    let score = 0
    for (const name of command.names) {
      if (name === needle) score = Math.max(score, 3)
      else if (name.startsWith(needle)) score = Math.max(score, 2)
      else if (name.split(/[\s-]+/).some((word) => word.startsWith(needle))) score = Math.max(score, 1)
    }
    if (score) scored.push({ command, score, order })
  })
  return scored.sort((a, b) => b.score - a.score || a.order - b.order).map((entry) => entry.command)
}

function applySlashCommand(view, trigger, command, host) {
  if (command.host) {
    // Drop the typed `/query`, keep the rest of the line, then hand over.
    view.dispatch({
      changes: { from: trigger.from, to: trigger.to, insert: "" },
      selection: EditorSelection.cursor(trigger.from),
      userEvent: "slash.apply",
    })
    SLASH_HOST_ACTIONS[command.host].run(host.callbacks, trigger.from)
    return
  }
  const line = view.state.doc.lineAt(trigger.from)
  // Text on both sides of the typed `/query` becomes the block's content.
  const before = view.state.doc.sliceString(line.from, trigger.from).trim()
  const after = view.state.doc.sliceString(trigger.to, line.to).trim()
  const raw = [before, after].filter(Boolean).join(" ")
  const { lines, caret } = command.convert(raw)
  // A template's blank lines stay empty rather than carrying the indent.
  const indented = lines.map((text) => (command.template && !text ? text : trigger.indent + text))
  let position = line.from
  for (let i = 0; i < caret.line; i++) position += indented[i].length + 1
  // Blank template lines carry no indent, so measure the line as inserted.
  position += indented[caret.line].length - lines[caret.line].length + caret.ch
  view.dispatch({
    changes: { from: line.from, to: line.to, insert: indented.join("\n") },
    selection: caret.select
      ? EditorSelection.range(position, position + caret.select)
      : EditorSelection.cursor(position),
    userEvent: "slash.apply",
    scrollIntoView: true,
  })
}

function slashExtensions(options, host) {
  const commands = SLASH_COMMANDS.filter(
    (command) => !command.host || SLASH_HOST_ACTIONS[command.host].available(host.callbacks)
  ).map((command) => {
    const label = options[`cmd.${command.id}`] || command.label
    return {
      ...command,
      label,
      // The English name and aliases stay searchable in any language.
      names: [label.toLowerCase(), command.label.toLowerCase(), ...command.aliases],
    }
  })
  const groupLabel = (id) => options[`group.${id}`] || SLASH_GROUPS.find((group) => group.id === id).label
  const templatesLabel = options["cmd.templates"] || SLASH_TEMPLATES_ENTRY.label
  const templateContext = {
    now: () => (host.callbacks.slashClock ? host.callbacks.slashClock() : new Date()),
    locale: options.locale,
  }

  // What each level lists. The top level has one Templates row (searchable as
  // "templates") and never the templates themselves.
  const levelCommands = (level) => {
    const templates = host.slashTemplates || []
    if (level === "templates") return slashTemplateCommands(templates, templateContext)
    if (!templates.length) return commands
    const label = templatesLabel
    return [...commands, {
      ...SLASH_TEMPLATES_ENTRY,
      label,
      names: [label.toLowerCase(), SLASH_TEMPLATES_ENTRY.label.toLowerCase(), "template"],
    }]
  }

  const move = StateEffect.define()
  const pick = StateEffect.define()
  const dismiss = StateEffect.define()
  const enter = StateEffect.define()
  const back = StateEffect.define()

  const field = StateField.define({
    create: () => null,
    update(value, tr) {
      const trigger = slashTrigger(tr.state)
      if (!trigger) return null
      // Open only from typing or deleting; a loaded document never pops it up.
      if (!value && !(tr.docChanged && (tr.isUserEvent("input") || tr.isUserEvent("delete")))) return null
      const sameLine = value && tr.changes.mapPos(value.lineFrom, -1) === trigger.lineFrom
      let level = sameLine ? value.level : "root"
      let navigated = false
      for (const effect of tr.effects) {
        if (effect.is(enter)) { level = "templates"; navigated = true }
        else if (effect.is(back)) { level = "root"; navigated = true }
      }
      // Templates edited away while their list is open: fall back to the root.
      if (level === "templates" && !(host.slashTemplates || []).length) level = "root"
      const items = slashMatches(levelCommands(level), trigger.query)
      if (!items.length) return null
      const sameList = sameLine && !navigated && value.level === level && value.query === trigger.query
      let index = sameList ? Math.min(value.index, items.length - 1) : 0
      let dismissed = !!(sameLine && value.dismissed)
      for (const effect of tr.effects) {
        if (effect.is(move)) index = (index + effect.value + items.length) % items.length
        else if (effect.is(pick)) index = Math.max(0, Math.min(effect.value, items.length - 1))
        else if (effect.is(dismiss)) dismissed = true
      }
      return { ...trigger, items, index, dismissed, level }
    },
  })

  const active = (view) => {
    if (view.composing) return null
    const state = view.state.field(field, false)
    return state && !state.dismissed ? state : null
  }
  // Opening the list clears the typed query (the `/` stays), so what is typed
  // next searches template names rather than the word that got here.
  const openTemplates = (view, state) => {
    view.dispatch({
      changes: state.query ? { from: state.from + 1, to: state.to, insert: "" } : undefined,
      selection: EditorSelection.cursor(state.from + 1),
      effects: enter.of(null),
    })
  }
  // A submenu row opens its list; anything else is applied to the line.
  const choose = (view, state, command) => {
    if (command.submenu) openTemplates(view, state)
    else applySlashCommand(view, state, command, host)
  }
  const accept = (view) => {
    const state = active(view)
    if (!state) return false
    choose(view, state, state.items[state.index])
    return true
  }
  const into = (view) => {
    const state = active(view)
    if (!state || !state.items[state.index].submenu) return false
    openTemplates(view, state)
    return true
  }
  // Left always leaves the list; Backspace only once nothing is left to delete.
  const out = (onlyWhenEmpty) => (view) => {
    const state = active(view)
    if (!state || state.level !== "templates" || (onlyWhenEmpty && state.query)) return false
    view.dispatch({ effects: back.of(null) })
    return true
  }
  const step = (delta) => (view) => {
    if (!active(view)) return false
    view.dispatch({ effects: move.of(delta) })
    return true
  }

  const menu = ViewPlugin.fromClass(class {
    constructor(view) {
      this.view = view
      this.key = null
      const doc = view.dom.ownerDocument
      this.dom = doc.createElement("div")
      this.dom.className = "cm-md-slash-menu"
      this.dom.setAttribute("role", "listbox")
      this.dom.hidden = true
      // Keep focus in the editor: a click must never blur it.
      this.dom.addEventListener("mousedown", (event) => {
        event.preventDefault()
        const row = event.target.closest && event.target.closest("[data-slash-index]")
        const state = active(this.view)
        if (!state) return
        if (event.target.closest && event.target.closest("[data-slash-back]")) {
          this.view.dispatch({ effects: back.of(null) })
        } else if (row) {
          choose(this.view, state, state.items[Number(row.dataset.slashIndex)])
        }
      })
      this.dom.addEventListener("mousemove", (event) => {
        const row = event.target.closest && event.target.closest("[data-slash-index]")
        const state = active(this.view)
        const index = row ? Number(row.dataset.slashIndex) : -1
        if (state && index >= 0 && index !== state.index) this.view.dispatch({ effects: pick.of(index) })
      })
      doc.body.appendChild(this.dom)
      this.sync()
    }

    update() { this.sync() }

    sync() {
      const state = active(this.view)
      if (!state) {
        this.dom.hidden = true
        this.key = null
        return
      }
      const key = `${state.level}|${state.query}|${state.items.map((item) => item.id).join(",")}`
      if (this.key !== key || this.dom.hidden) this.rebuild(state)
      this.key = key
      let selected = null
      for (const row of this.dom.querySelectorAll("[data-slash-index]")) {
        const isSelected = Number(row.dataset.slashIndex) === state.index
        row.classList.toggle("cm-md-slash-selected", isSelected)
        row.setAttribute("aria-selected", String(isSelected))
        if (isSelected) selected = row
      }
      this.dom.hidden = false
      if (selected) {
        if (selected.offsetTop < this.dom.scrollTop) this.dom.scrollTop = selected.offsetTop
        else if (selected.offsetTop + selected.offsetHeight > this.dom.scrollTop + this.dom.clientHeight) {
          this.dom.scrollTop = selected.offsetTop + selected.offsetHeight - this.dom.clientHeight
        }
      }
      this.view.requestMeasure({
        key: this,
        read: (view) => {
          try { return view.coordsAtPos(state.to) } catch (_) { return null }
        },
        write: (coords) => this.place(coords),
      })
    }

    rebuild(state) {
      const doc = this.dom.ownerDocument
      const make = (tag, className, text) => {
        const element = doc.createElement(tag)
        element.className = className
        if (text !== undefined) element.textContent = text
        return element
      }
      this.dom.textContent = ""
      if (state.level === "templates") {
        const header = make("div", "cm-md-slash-back")
        header.dataset.slashBack = ""
        header.appendChild(make("span", "cm-md-slash-chevron", "‹"))
        header.appendChild(make("span", "cm-md-slash-label", templatesLabel))
        this.dom.appendChild(header)
      }
      let group = null
      state.items.forEach((command, index) => {
        if (!state.query && state.level === "root" && command.group !== group) {
          group = command.group
          this.dom.appendChild(make("div", "cm-md-slash-group", groupLabel(group)))
        }
        const row = make("div", "cm-md-slash-item")
        row.setAttribute("role", "option")
        row.dataset.slashIndex = String(index)
        const icon = make("span", "cm-md-slash-icon")
        icon.innerHTML = `<svg viewBox="0 0 20 20" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${SLASH_ICONS[command.id] || (command.template ? SLASH_ICONS.templates : "")}</svg>`
        row.appendChild(icon)
        row.appendChild(make("span", "cm-md-slash-label", command.label))
        if (command.submenu) row.appendChild(make("span", "cm-md-slash-chevron", "›"))
        this.dom.appendChild(row)
      })
      this.dom.scrollTop = 0
    }

    place(coords) {
      if (!coords || this.dom.hidden) return
      const win = this.dom.ownerDocument.defaultView
      const width = this.dom.offsetWidth
      const height = this.dom.offsetHeight
      const below = win.innerHeight - coords.bottom
      const flip = height > below - 8 && coords.top > below
      const top = flip ? Math.max(8, coords.top - height - 4) : coords.bottom + 4
      const left = Math.max(8, Math.min(coords.left, win.innerWidth - width - 8))
      this.dom.style.top = `${top}px`
      this.dom.style.left = `${left}px`
    }

    destroy() { this.dom.remove() }
  })

  return [
    field,
    menu,
    keymap.of([
      { key: "ArrowDown", run: step(1) },
      { key: "ArrowUp", run: step(-1) },
      { key: "ArrowRight", run: into },
      { key: "ArrowLeft", run: out(false) },
      { key: "Backspace", run: out(true) },
      { key: "Enter", run: accept },
      { key: "Tab", run: accept },
      { key: "Escape", run: (view) => {
        if (!active(view)) return false
        view.dispatch({ effects: dismiss.of(null) })
        return true
      } },
    ]),
    EditorView.domEventHandlers({
      blur(_event, view) {
        if (active(view)) view.dispatch({ effects: dismiss.of(null) })
      },
    }),
  ]
}

registerEditorExtension({ id: "slash-commands", precedence: "highest", extensions: slashExtensions })
