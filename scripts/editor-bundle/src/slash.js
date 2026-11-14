import { EditorSelection, StateEffect } from "@codemirror/state"
import { syntaxTree } from "@codemirror/language"
import { registerEditorExtension } from "./extensions.js"
import { completionExtensions } from "./completion.js"
import { formatLocalDate, parseLocalDate } from "./dates.js"
import { PRIORITY_KEY, TASK_DATE_KEYS, isTaskDate } from "./task-fields.js"
import { taskFieldChange, taskLine } from "./task-field-commands.js"

// Slash commands: typing `/` at the start of a line or after a space opens a
// menu of blocks; picking one converts that line. Labels come from the host
// (`options["cmd.<id>"]`, `options["group.<id>"]`) so they follow the app
// language, with English as the fallback.
const SLASH_GROUPS = [
  { id: "text", label: "Text" },
  { id: "lists", label: "Lists" },
  { id: "blocks", label: "Blocks" },
  { id: "insert", label: "Insert" },
  { id: "task", label: "Task" },
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
  link: '<path d="M8.6 11.4a3 3 0 004.3 0l2.4-2.4a3 3 0 00-4.3-4.3l-1 1"/><path d="M11.4 8.6a3 3 0 00-4.3 0l-2.4 2.4a3 3 0 004.3 4.3l1-1"/>',
  mermaid: '<rect x="3" y="3.5" width="6" height="4" rx="1"/><rect x="11" y="12.5" width="6" height="4" rx="1"/><path d="M6 7.5v3a2 2 0 002 2h3"/>',
  math: '<path d="M14.5 5h-9l4 5-4 5h9"/>',
  note: '<circle cx="10" cy="10" r="6.5"/><path d="M10 9.3v4M10 6.8v.1"/>',
  tip: '<path d="M7.8 13.6h4.4M8.3 16h3.4M10 3.5a4.5 4.5 0 00-2.5 8.2v1.9h5v-1.9A4.5 4.5 0 0010 3.5z"/>',
  important: '<circle cx="10" cy="10" r="6.5"/><path d="M10 6.6v4.2M10 13.2v.1"/>',
  warning: '<path d="M10 3.8L17 16H3z"/><path d="M10 8.6v3.2M10 13.8v.1"/>',
  caution: '<path d="M7 3.5h6l3.5 3.5v6L13 16.5H7L3.5 13V7z"/><path d="M10 7v3.5M10 12.8v.1"/>',
  today: '<rect x="3.5" y="4.5" width="13" height="12" rx="2"/><path d="M3.5 8.5h13M7 3v3M13 3v3"/>',
  now: '<circle cx="10" cy="10" r="6.5"/><path d="M10 6.5V10l2.5 1.5"/>',
  priority: '<path d="M5.5 16.5v-13M5.5 4h9l-2 3.25 2 3.25h-9"/>',
  due: '<rect x="3.5" y="4.5" width="13" height="12" rx="2"/><path d="M3.5 8.5h13M7 3v3M13 3v3M10 10.5v2.6M10 14.9v.1"/>',
  schedule: '<rect x="3.5" y="4.5" width="13" height="12" rx="2"/><path d="M3.5 8.5h13M7 3v3M13 3v3M7.5 12.5l1.8 1.8 3.4-3.6"/>',
  clear: '<path d="M6 6l8 8M14 6l-8 8"/>',
  field: '<path d="M4 10.5V4.5a1 1 0 011-1h6l5.5 5.5-7 7L4 10.5z"/><circle cx="7.5" cy="7" r="1"/>',
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
  pickLink: {
    available: (callbacks) => typeof callbacks.onPickLink === "function",
    run: (callbacks, position) => callbacks.onPickLink(position, position),
  },
}

// A command with `insert(now)` converts nothing: its text replaces the typed
// `/query` where it stands, so it also works in the middle of a sentence.
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
  { id: "link", group: "blocks", label: "Link to File", aliases: ["link", "file", "page", "ref", "reference"],
    host: "pickLink" },
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
  { id: "today", group: "insert", label: "Today", aliases: ["today", "date"],
    insert: (now) => slashDate(now) },
  { id: "now", group: "insert", label: "Now", aliases: ["now", "time", "datetime", "date"],
    insert: (now) => `${slashDate(now)} ${slashTime(now)}` },
]

// Task fields, offered only on a checkbox task's marker line and listed after
// everything else, so they never push an existing command down. Each priority
// is its own top-level row; Due Date and Schedule open a date picker straight
// away, and their Clear rows appear only when the task has that date.
const TASK_FIELD_COMMANDS = [
  { id: "priority-high", group: "task", label: "Priority: High", aliases: ["priority", "high"],
    icon: "priority", tint: "high", field: PRIORITY_KEY, value: "high" },
  { id: "priority-medium", group: "task", label: "Priority: Medium", aliases: ["priority", "medium"],
    icon: "priority", tint: "medium", field: PRIORITY_KEY, value: "medium" },
  { id: "priority-low", group: "task", label: "Priority: Low", aliases: ["priority", "low"],
    icon: "priority", tint: "low", field: PRIORITY_KEY, value: "low" },
  { id: "priority-none", group: "task", label: "Priority: None", aliases: ["priority", "none"],
    icon: "clear", field: PRIORITY_KEY, value: null },
  { id: "due", group: "task", label: "Due Date", aliases: ["due", "deadline", "date"],
    icon: "due", dateField: "due" },
  { id: "schedule", group: "task", label: "Schedule", aliases: ["schedule", "scheduled", "plan", "date"],
    icon: "schedule", dateField: "scheduled" },
  { id: "due-clear", group: "task", label: "Clear Due Date", aliases: ["due", "deadline", "clear", "remove"],
    icon: "clear", clearField: "due" },
  { id: "schedule-clear", group: "task", label: "Clear Schedule", aliases: ["schedule", "scheduled", "clear", "remove"],
    icon: "clear", clearField: "scheduled" },
]

// Field submenus are named by path: `due/calendar` (the date picker),
// `due/1/calendar` (the picker for the second `due:` on the line), `due` and
// `due/clear` (which `due:` to change or clear when there are several), and
// `p/high` (which `p:` to set when there are several).
function taskFieldLevel(level) {
  const parts = level.split("/")
  if (parts[0] === PRIORITY_KEY) {
    return parts.length === 2 ? { key: PRIORITY_KEY, value: parts[1] === "none" ? null : parts[1], occurrence: null } : null
  }
  if (!TASK_DATE_KEYS.includes(parts[0])) return null
  if (parts.length === 1) return { key: parts[0], occurrence: null, pick: true }
  if (parts.length === 2 && parts[1] === "clear") return { key: parts[0], occurrence: null, pick: true, clear: true }
  if (parts.length === 2 && parts[1] === "calendar") return { key: parts[0], occurrence: null, calendar: true }
  if (parts.length === 3 && /^\d+$/.test(parts[1]) && parts[2] === "calendar") {
    return { key: parts[0], occurrence: Number(parts[1]), calendar: true }
  }
  return null
}

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

const slashPad = (value) => String(value).padStart(2, "0")
const slashDate = (now) => `${now.getFullYear()}-${slashPad(now.getMonth() + 1)}-${slashPad(now.getDate())}`
const slashTime = (now) => `${slashPad(now.getHours())}:${slashPad(now.getMinutes())}`

function slashExpandTemplate(body, now, locale) {
  const date = () => slashDate(now)
  const time = () => slashTime(now)
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

// How a query matches one name: whole name, start of the name, or start of a
// later word. A label outranks an alias at the same kind of match, so `/li`
// puts "Link to File" above the `list` and `line` aliases. Within a kind, the
// name the query covers more of wins, so `/table` prefers "Table" over a
// longer name that merely starts the same way.
const SLASH_MATCH_EXACT = 3
const SLASH_MATCH_PREFIX = 2
const SLASH_MATCH_WORD = 1

function slashNameScore(name, needle, isLabel) {
  let kind = 0
  if (name === needle) kind = SLASH_MATCH_EXACT
  else if (name.startsWith(needle)) kind = SLASH_MATCH_PREFIX
  else if (name.split(/[\s-]+/).some((word) => word.startsWith(needle))) kind = SLASH_MATCH_WORD
  if (!kind) return 0
  return kind * 4 + (isLabel ? 2 : 0) + needle.length / name.length
}

function slashMatches(commands, query) {
  if (!query) return commands
  const needle = query.toLowerCase()
  const scored = []
  commands.forEach((command, order) => {
    const labels = command.labelNames || [command.label.toLowerCase()]
    let score = 0
    for (const name of command.names) {
      score = Math.max(score, slashNameScore(name, needle, labels.includes(name)))
    }
    if (score) scored.push({ command, score, order })
  })
  return scored.sort((a, b) => b.score - a.score || a.order - b.order).map((entry) => entry.command)
}

function applySlashCommand(view, trigger, command, host, clock) {
  if (command.insert) {
    const text = command.insert(clock())
    view.dispatch({
      changes: { from: trigger.from, to: trigger.to, insert: text },
      selection: EditorSelection.cursor(trigger.from + text.length),
      userEvent: "slash.apply",
      scrollIntoView: true,
    })
    return
  }
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
  // The English name and aliases stay searchable in any language.
  const localize = (command) => {
    const label = options[`cmd.${command.id}`] || command.label
    const labelNames = [label.toLowerCase(), command.label.toLowerCase()]
    return { ...command, label, labelNames, names: [...labelNames, ...(command.aliases || [])] }
  }
  const commands = SLASH_COMMANDS.filter(
    (command) => !command.host || SLASH_HOST_ACTIONS[command.host].available(host.callbacks)
  ).map(localize)
  // Field commands match on their aliases (and a translated label), not the
  // English label, so they rank below every existing label match: `/p` and
  // `/s` keep their results, and `/pri` lists the priorities in order.
  const fieldCommands = TASK_FIELD_COMMANDS.map((command) => {
    const localized = localize(command)
    const translated = localized.label !== command.label ? [localized.label.toLowerCase()] : []
    return { ...localized, labelNames: translated, names: [...translated, ...command.aliases] }
  })
  const groupLabel = (id) => options[`group.${id}`] || SLASH_GROUPS.find((group) => group.id === id).label
  const templatesLabel = options["cmd.templates"] || SLASH_TEMPLATES_ENTRY.label
  const clock = () => (host.callbacks.slashClock ? host.callbacks.slashClock() : new Date())
  const templateContext = { now: clock, locale: options.locale }
  const longDate = (value) => {
    const format = { weekday: "long", year: "numeric", month: "long", day: "numeric" }
    try { return new Intl.DateTimeFormat(options.locale || undefined, format).format(parseLocalDate(value)) }
    catch (_) { return new Intl.DateTimeFormat("en", format).format(parseLocalDate(value)) }
  }
  const commandLabel = (id) => fieldCommands.find((command) => command.id === id).label
  const dateLabel = (key, clear) => commandLabel(`${key === "due" ? "due" : "schedule"}${clear ? "-clear" : ""}`)

  // Which field occurrence a field submenu edits: the one it names, else the
  // only one on the line, else none (the value is added).
  const fieldTarget = (field, session) => {
    const found = session.task.occurrences[field.key]
    return field.occurrence != null ? found[field.occurrence] : found.length === 1 ? found[0] : null
  }

  // The top-level rows for a task line. With duplicate fields a command opens
  // a list of them to choose from instead of picking one silently.
  const fieldRoot = (session) => fieldCommands.flatMap((command) => {
    const key = command.dateField || command.clearField || PRIORITY_KEY
    const several = session.task.occurrences[key].length > 1
    if (command.dateField) {
      return [{ ...command, submenu: several ? key : `${key}/calendar`, keepQuery: true, chevron: false }]
    }
    if (command.clearField) {
      if (!session.task.occurrences[key].length) return []
      return [several
        ? { ...command, submenu: `${key}/clear`, keepQuery: true }
        : { ...command, field: key, value: null }]
    }
    return [several ? { ...command, submenu: `${PRIORITY_KEY}/${command.value || "none"}`, keepQuery: true } : command]
  })

  // Lists of duplicate occurrences, one row each.
  const fieldItems = (level, session) => {
    const field = taskFieldLevel(level)
    const found = session.task.occurrences[field.key]
    return found.map((occurrence, index) => ({
      id: `occurrence-${index}`,
      label: occurrence.text,
      detail: `${index + 1}/${found.length}`,
      icon: "field",
      names: [occurrence.text.toLowerCase()],
      ...(field.pick && !field.clear
        ? { submenu: `${field.key}/${index}/calendar`, keepQuery: true, chevron: false }
        : { field: field.key, value: field.clear ? null : field.value, occurrence: index }),
    }))
  }

  // What each level lists. The top level has one Templates row (searchable as
  // "templates") and never the templates themselves.
  const levelCommands = (level, session) => {
    const templates = host.slashTemplates || []
    if (level === "templates") return slashTemplateCommands(templates, templateContext)
    if (level !== "root") return fieldItems(level, session)
    const label = templatesLabel
    return [
      ...commands,
      ...(templates.length ? [{
        ...SLASH_TEMPLATES_ENTRY,
        label,
        labelNames: [label.toLowerCase(), SLASH_TEMPLATES_ENTRY.label.toLowerCase()],
        names: [label.toLowerCase(), SLASH_TEMPLATES_ENTRY.label.toLowerCase(), "template"],
      }] : []),
      ...(session.task ? fieldRoot(session) : []),
    ]
  }

  const hasLevel = (level, session) => {
    // Templates edited away while their list is open: fall back to the root.
    if (level === "templates") return (host.slashTemplates || []).length > 0
    const field = taskFieldLevel(level)
    if (!field || !session.task) return false
    const found = session.task.occurrences[field.key]
    if (field.key === PRIORITY_KEY || field.pick) return found.length > 1
    if (field.occurrence != null) return field.occurrence < found.length
    return found.length <= 1
  }

  return completionExtensions({
    classPrefix: "slash",
    trigger: (state) => {
      const trigger = slashTrigger(state)
      return trigger && { ...trigger, task: taskLine(state, state.doc.lineAt(trigger.from)) }
    },
    items: (level, query, session) => slashMatches(levelCommands(level, session), query),
    hasLevel,
    // A duplicate's picker goes back to the list of duplicates.
    parent: (level) => {
      const field = taskFieldLevel(level)
      return field && field.calendar && field.occurrence != null ? field.key : "root"
    },
    apply: (view, session, command) => {
      if (!command.field) return applySlashCommand(view, session, command, host, clock)
      const spec = taskFieldChange(view.state, session, command.field, command.value, command.occurrence)
      if (spec) view.dispatch(spec)
    },
    calendar: (level, session) => {
      const field = taskFieldLevel(level)
      if (!field || !field.calendar || !session.task) return null
      const today = formatLocalDate(clock())
      const target = fieldTarget(field, session)
      return {
        initial: target && isTaskDate(target.value) ? target.value : today,
        today,
        locale: options.locale,
        describe: longDate,
      }
    },
    applyDate: (view, session, date) => {
      const field = taskFieldLevel(session.level)
      const spec = field && taskFieldChange(view.state, session, field.key, date, field.occurrence)
      if (spec) view.dispatch(spec)
    },
    // `tint` colors a priority's flag (see `.cm-md-slash-tint-*` in the host CSS).
    icon: (command) => `<svg${command.tint ? ` class="cm-md-slash-tint-${command.tint}"` : ""} viewBox="0 0 20 20" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${SLASH_ICONS[command.icon || command.id] || (command.template ? SLASH_ICONS.templates : "")}</svg>`,
    detail: (command) => command.detail,
    // Group headers only on the unfiltered top level.
    group: (command, session) => (!session.query && session.level === "root" ? command.group : null),
    groupLabel,
    levelLabel: (level, session) => {
      if (level === "templates") return templatesLabel
      const field = taskFieldLevel(level)
      if (field.key === PRIORITY_KEY) return commandLabel(`priority-${field.value || "none"}`)
      if (field.occurrence != null) return session.task.occurrences[field.key][field.occurrence].text
      return dateLabel(field.key, field.clear)
    },
    text: (key, fallback) => options[`label.${key}`] || fallback,
  })
}

registerEditorExtension({ id: "slash-commands", precedence: "highest", extensions: slashExtensions })
