// Editor smoke tests: the slash commands that set `p:`, `due:` and
// `scheduled:` on checkbox task lines.
import { readFileSync } from "node:fs"
import { dom, check } from "./harness.mjs"

const extractor = Function(`${readFileSync(new URL(
  "../../../daisy/Vendor/WorkspaceMetadata/workspace-metadata.min.js", import.meta.url), "utf8")}; return WorkspaceMetadataExtractor`)()
const firstTask = (markdown) => extractor.extractMetadata(markdown).tasks[0]

// Fixed clock: Sunday 4 October 2026, 14:05 local time.
const sunday = () => new Date(2026, 9, 4, 14, 5)

const menu = () => Array.from(dom.window.document.querySelectorAll(".cm-md-slash-menu")).at(-1)
const visible = () => menu() != null && !menu().hidden
const labels = () => visible()
  ? Array.from(menu().querySelectorAll(".cm-md-slash-item .cm-md-slash-label")).map((el) => el.textContent)
  : []
const details = () => Array.from(menu().querySelectorAll(".cm-md-slash-item"))
  .map((row) => row.querySelector(".cm-md-slash-detail")?.textContent ?? null)
const backLabel = () => (visible() && menu().querySelector("[data-slash-back] .cm-md-slash-label")?.textContent) || null
const selectedDay = () => menu().querySelector("[data-slash-date].cm-md-slash-selected")?.dataset.slashDate ?? null
const footer = () => menu().querySelector(".cm-md-slash-calendar-footer")?.textContent ?? null
const key = (host, name, extra = {}) => host.querySelector(".cm-content").dispatchEvent(
  new dom.window.KeyboardEvent("keydown", { key: name, bubbles: true, cancelable: true, ...extra }))
const mousedown = (element) => element.dispatchEvent(
  new dom.window.MouseEvent("mousedown", { bubbles: true, cancelable: true }))
const FIELD_LABELS = ["Priority: High", "Priority: Medium", "Priority: Low", "Priority: None", "Due Date", "Schedule"]

// An editor holding `source` with `/query` typed at its end (or at `at`).
const typed = (source, query, { at = source.length, clock = sunday, ...extra } = {}) => {
  const host = dom.window.document.createElement("div")
  dom.window.document.body.appendChild(host)
  const editor = dom.window.MDEditor.create(host, source, {
    extensionState: { "slash-commands": true }, slashClock: clock, ...extra,
  })
  editor.insertTextAt("/" + query, at, at)
  return { host, editor }
}
const pick = (host, label) => {
  const index = labels().indexOf(label)
  if (index < 0) return false
  for (let i = 0; i < index; i++) key(host, "ArrowDown")
  key(host, "Enter")
  return true
}

// --- Availability ----------------------------------------------------------

{
  const { editor } = typed("- [ ] Buy milk ", "")
  check("field commands are offered on a task line", FIELD_LABELS.every((label) => labels().includes(label)))
  check("field commands come after every existing command", labels().slice(-6).join() === FIELD_LABELS.join())
  check("Due Date and Schedule rows have no chevron",
    Array.from(menu().querySelectorAll(".cm-md-slash-item"))
      .filter((row) => ["Due Date", "Schedule"].includes(row.querySelector(".cm-md-slash-label").textContent))
      .every((row) => !row.querySelector(".cm-md-slash-chevron")))
  check("field commands sit under a Task group",
    Array.from(menu().querySelectorAll(".cm-md-slash-group")).at(-1).textContent === "Task")
  editor.destroy()
}

for (const [name, source] of [
  ["plain text", "Buy milk "],
  ["a bullet without a checkbox", "- Buy milk "],
  ["a heading", "# Buy milk "],
  ["the line after a task", "- [ ] Buy milk\n\n"],
]) {
  const { editor } = typed(source, "")
  check(`field commands are hidden on ${name}`, visible() && !FIELD_LABELS.some((label) => labels().includes(label)))
  editor.destroy()
}

for (const [name, source] of [
  ["a done task", "- [x] Buy milk "],
  ["a numbered task", "1. [ ] Buy milk "],
  ["a nested task", "- parent\n  - [ ] Buy milk "],
  ["a task in a quote", "> - [ ] Buy milk "],
]) {
  const { editor } = typed(source, "")
  check(`field commands are offered on ${name}`, labels().includes("Due Date"))
  editor.destroy()
}

{
  const { editor } = typed("- [ ] Buy milk ", "pri")
  check("/pri lists every priority in order",
    labels().join() === "Priority: High,Priority: Medium,Priority: Low,Priority: None")
  check("priority flags are tinted high, medium, low and None is not",
    Array.from(menu().querySelectorAll(".cm-md-slash-item .cm-md-slash-icon svg"))
      .map((svg) => svg.getAttribute("class") || "").join() === "cm-md-slash-tint-high,cm-md-slash-tint-medium,cm-md-slash-tint-low,")
  editor.destroy()
}

{
  const { editor } = typed("- [ ] Buy milk ", "high")
  check("/high finds Priority: High", labels()[0] === "Priority: High")
  editor.destroy()
}

{
  const { editor } = typed("- [ ] Buy milk ", "deadline")
  check("/deadline finds Due Date", labels()[0] === "Due Date")
  editor.destroy()
}

// Existing top results do not move on a task line.
{
  const top = (source, query) => {
    const { editor } = typed(source, query, { onPickImage() {}, onPickLink() {} })
    const first = labels()[0]
    editor.destroy()
    return first
  }
  const moved = ["", "a", "b", "c", "d", "h", "i", "l", "m", "n", "p", "s", "t", "h1", "heading", "quote",
    "list", "li", "todo", "task", "code", "table", "image", "link", "math", "note", "today", "now", "date",
    "divider", "check"].filter((query) => top("x ", query) !== top("- [ ] x ", query))
  check("field commands do not displace existing top results", moved.length === 0)
}

// --- Priority --------------------------------------------------------------

{
  const { host, editor } = typed("- [ ] Buy milk ", "high")
  key(host, "Enter")
  check("a priority is added at the start of the task text",
    editor.getMarkdown() === "- [ ] p:high Buy milk" && !visible())
  check("the caret stays where the command was typed", editor.getLinkSelection().from === 21)
  check("an added priority round-trips through the extractor", firstTask(editor.getMarkdown()).priority === "high")
  editor.destroy()
}

{
  const { host, editor } = typed("- [ ] ", "low")
  key(host, "Enter")
  check("a priority on an empty task keeps a single space", editor.getMarkdown() === "- [ ] p:low")
  editor.destroy()
}

{
  const { host, editor } = typed("- [ ] Buy milk", "low", { at: 10 })
  key(host, "Enter")
  check("a priority typed mid-line is still added at the start",
    editor.getMarkdown() === "- [ ] p:low Buy milk" && editor.getLinkSelection().from === 16)
  editor.destroy()
}

{
  const { host, editor } = typed("- [ ] Buy milk due:2026-10-04 ", "high")
  key(host, "Enter")
  check("dates stay at the end while a priority leads",
    editor.getMarkdown() === "- [ ] p:high Buy milk due:2026-10-04")
  editor.destroy()
}

{
  const { host, editor } = typed("- [ ] Buy p:low milk", "medium", { at: 6 })
  key(host, "Enter")
  check("a priority typed mid-line replaces the existing one in place",
    editor.getMarkdown() === "- [ ] Buy p:medium milk")
  check("a replaced priority round-trips", firstTask(editor.getMarkdown()).priority === "medium")
  editor.destroy()
}

{
  const { host, editor } = typed("- [ ] Buy p:urgent ", "high")
  key(host, "Enter")
  check("a malformed priority is replaced by a valid one", editor.getMarkdown() === "- [ ] Buy p:high")
  editor.destroy()
}

{
  const { host, editor } = typed("- [ ] p:high Buy milk ", "none")
  key(host, "Enter")
  check("Priority: None removes the field and its space", editor.getMarkdown() === "- [ ] Buy milk")
  check("a removed priority reads back as unset", firstTask(editor.getMarkdown()).priority === null)
  editor.destroy()
}

{
  const { host, editor } = typed("- [ ] Buy milk ", "none")
  key(host, "Enter")
  check("Priority: None without a priority only removes the command", editor.getMarkdown() === "- [ ] Buy milk")
  editor.destroy()
}

{
  const { host, editor } = typed("- [ ] Buy p:low p:high ", "medium")
  key(host, "Enter")
  check("with duplicate priorities a command asks which one to change",
    editor.getMarkdown() === "- [ ] Buy p:low p:high /medium"
      && backLabel() === "Priority: Medium" && labels().join() === "p:low,p:high")
  check("duplicate rows say which occurrence they are", details().join() === "1/2,2/2")
  key(host, "ArrowDown")
  key(host, "Enter")
  check("only the chosen duplicate changes", editor.getMarkdown() === "- [ ] Buy p:low p:medium")
  editor.destroy()
}

{
  const { host, editor } = typed("- [ ] Buy p:low p:high ", "none")
  key(host, "Enter")
  key(host, "Enter")
  check("Priority: None removes only the chosen duplicate", editor.getMarkdown() === "- [ ] Buy p:high")
  editor.destroy()
}

{
  const { host, editor } = typed("- [ ] Buy `p:low` ", "high")
  key(host, "Enter")
  check("a field inside inline code is not an occurrence",
    editor.getMarkdown() === "- [ ] p:high Buy `p:low`")
  editor.destroy()
}

// --- Dates -----------------------------------------------------------------

const title = () => menu().querySelector(".cm-md-slash-calendar-title")?.textContent ?? null
const calendarOpen = () => visible() && menu().querySelector(".cm-md-slash-calendar-grid") != null

{
  const { host, editor } = typed("- [ ] Buy milk ", "due")
  key(host, "Enter")
  check("Due Date opens the date picker straight away without editing the line",
    calendarOpen() && editor.getMarkdown() === "- [ ] Buy milk /due")
  check("the picker has no back row but keeps month buttons",
    !menu().querySelector("[data-slash-back]") && menu().querySelectorAll("[data-slash-month]").length === 2)
  check("the picker does not scroll", menu().classList.contains("cm-md-slash-calendar-menu"))
  check("the picker starts on today", selectedDay() === "2026-10-04" && title() === "October 2026")
  check("the picker shows what it will write", footer() === "Sunday, October 4, 2026")
  check("the picker marks today", menu().querySelector(".cm-md-slash-day-today")?.dataset.slashDate === "2026-10-04")
  key(host, "Enter")
  check("Enter writes today and removes the command",
    editor.getMarkdown() === "- [ ] Buy milk due:2026-10-04" && !visible())
  check("a written due date round-trips", firstTask(editor.getMarkdown()).due === "2026-10-04")
  editor.destroy()
}

{
  const { host, editor } = typed("- [ ] Plan trip ", "schedule")
  key(host, "Enter")
  check("Schedule opens the same picker", calendarOpen())
  key(host, "ArrowRight")
  key(host, "Enter")
  check("Schedule writes scheduled:", editor.getMarkdown() === "- [ ] Plan trip scheduled:2026-10-05")
  check("a written scheduled date round-trips", firstTask(editor.getMarkdown()).scheduled === "2026-10-05")
  editor.destroy()
}

{
  const { host, editor } = typed("- [ ] Buy milk ", "due")
  key(host, "Enter")
  key(host, "ArrowRight")
  check("ArrowRight moves one day", selectedDay() === "2026-10-05")
  key(host, "ArrowDown")
  check("ArrowDown moves one week", selectedDay() === "2026-10-12")
  key(host, "ArrowLeft")
  check("ArrowLeft moves back one day", selectedDay() === "2026-10-11")
  key(host, "ArrowUp")
  check("ArrowUp moves back one week", selectedDay() === "2026-10-04")
  key(host, "PageDown")
  check("PageDown moves one month", selectedDay() === "2026-11-04" && title() === "November 2026")
  check("the footer follows the selection", footer() === "Wednesday, November 4, 2026")
  key(host, "Tab")
  check("Tab accepts like Enter", editor.getMarkdown() === "- [ ] Buy milk due:2026-11-04" && !visible())
  editor.destroy()
}

for (const [name, clock, keys, expected] of [
  ["a week ahead crosses the year", () => new Date(2026, 11, 28, 9), ["ArrowDown"], "2027-01-04"],
  ["a day ahead reaches a leap day", () => new Date(2028, 1, 28, 23, 59), ["ArrowRight"], "2028-02-29"],
  ["today uses the local date late at night", () => new Date(2026, 9, 4, 23, 59), [], "2026-10-04"],
]) {
  const { host, editor } = typed("- [ ] x ", "due", { clock })
  key(host, "Enter")
  for (const name of keys) key(host, name)
  key(host, "Enter")
  check(name, editor.getMarkdown() === `- [ ] x due:${expected}`)
  editor.destroy()
}

{
  const { host, editor } = typed("- [ ] Buy due:2026-01-31 milk ", "due")
  key(host, "Enter")
  check("the picker opens on the task's existing date", selectedDay() === "2026-01-31")
  key(host, "PageDown")
  check("month steps clamp to the month's last day", selectedDay() === "2026-02-28")
  key(host, "PageUp")
  key(host, "PageUp")
  check("PageUp moves back across the year", selectedDay() === "2025-12-28")
  key(host, "Enter")
  check("a picked date replaces the existing one in place", editor.getMarkdown() === "- [ ] Buy due:2025-12-28 milk")
  editor.destroy()
}

{
  const { host, editor } = typed("- [ ] Buy milk ", "due")
  key(host, "Enter")
  mousedown(menu().querySelector("[data-slash-month='1']"))
  check("the next-month button moves the picker", selectedDay() === "2026-11-04")
  mousedown(menu().querySelector("[data-slash-month='-1']"))
  check("the previous-month button moves it back", selectedDay() === "2026-10-04")
  mousedown(menu().querySelector("[data-slash-date='2026-10-20']"))
  check("clicking a day writes it", editor.getMarkdown() === "- [ ] Buy milk due:2026-10-20")
  editor.destroy()
}

{
  const { host, editor } = typed("- [ ] Buy milk ", "due")
  key(host, "Enter")
  key(host, "ArrowRight")
  editor.insertTextAt("xxx", 19, 19)
  check("typing is ignored while the picker is open",
    editor.getMarkdown() === "- [ ] Buy milk /due" && calendarOpen() && selectedDay() === "2026-10-05")
  editor.insertTextAt("", 15, 19)
  check("deleting is ignored while the picker is open", editor.getMarkdown() === "- [ ] Buy milk /due" && calendarOpen())
  key(host, "Enter")
  check("the picker still accepts after ignored typing", editor.getMarkdown() === "- [ ] Buy milk due:2026-10-05")
  editor.destroy()
}

{
  const { host, editor } = typed("- [ ] Buy due:tomorrow ", "due")
  key(host, "Enter")
  check("a malformed date opens the picker on today", selectedDay() === "2026-10-04")
  key(host, "Enter")
  check("a malformed date is replaced by a valid one", editor.getMarkdown() === "- [ ] Buy due:2026-10-04")
  editor.destroy()
}

{
  const { host, editor } = typed("- [ ] Buy scheduled:2026-03-03 ", "due")
  key(host, "Enter")
  key(host, "Enter")
  check("a due date leaves scheduled: alone",
    editor.getMarkdown() === "- [ ] Buy scheduled:2026-03-03 due:2026-10-04")
  check("both dates round-trip", (() => {
    const task = firstTask(editor.getMarkdown())
    return task.due === "2026-10-04" && task.scheduled === "2026-03-03"
  })())
  editor.destroy()
}

// --- Clear -----------------------------------------------------------------

{
  const { editor } = typed("- [ ] Buy milk ", "clear")
  check("Clear rows are hidden when the task has no dates",
    !labels().includes("Clear Due Date") && !labels().includes("Clear Schedule"))
  editor.destroy()
}

{
  const { host, editor } = typed("- [ ] Buy due:2026-01-01 milk ", "due")
  check("Clear Due Date is offered under Due Date when the task has a due date",
    labels().slice(0, 2).join() === "Due Date,Clear Due Date" && !labels().includes("Clear Schedule"))
  pick(host, "Clear Due Date")
  check("Clear Due Date removes the date and its space", editor.getMarkdown() === "- [ ] Buy milk")
  check("a cleared date reads back as unset", firstTask(editor.getMarkdown()).due === null)
  editor.destroy()
}

{
  const { host, editor } = typed("- [ ] Buy scheduled:2026-01-01 ", "clear")
  check("Clear Schedule is offered when the task is scheduled", labels().includes("Clear Schedule"))
  pick(host, "Clear Schedule")
  check("Clear Schedule removes scheduled:", editor.getMarkdown() === "- [ ] Buy")
  editor.destroy()
}

// --- Duplicates ------------------------------------------------------------

{
  const { host, editor } = typed("- [ ] a due:2026-01-01 due:2026-02-02 ", "due")
  key(host, "Enter")
  check("with duplicate dates Due Date asks which one to change",
    labels().join() === "due:2026-01-01,due:2026-02-02" && editor.getMarkdown().endsWith("/due"))
  key(host, "ArrowDown")
  key(host, "Enter")
  check("the chosen duplicate opens its picker on its date",
    calendarOpen() && selectedDay() === "2026-02-02")
  key(host, "ArrowRight")
  key(host, "Enter")
  check("only the chosen duplicate date changes",
    editor.getMarkdown() === "- [ ] a due:2026-01-01 due:2026-02-03")
  editor.destroy()
}

{
  const { host, editor } = typed("- [ ] a due:2026-01-01 due:2026-02-02 ", "due")
  key(host, "Enter")
  key(host, "Enter")
  key(host, "Backspace")
  check("Back from a duplicate's picker returns to the duplicate list",
    labels().join() === "due:2026-01-01,due:2026-02-02")
  editor.destroy()
}

{
  const { host, editor } = typed("- [ ] a due:2026-01-01 due:2026-02-02 ", "due")
  pick(host, "Clear Due Date")
  check("with duplicate dates Clear Due Date asks which one",
    backLabel() === "Clear Due Date" && labels().join() === "due:2026-01-01,due:2026-02-02")
  key(host, "Enter")
  check("Clear Due Date removes only the chosen duplicate", editor.getMarkdown() === "- [ ] a due:2026-02-02")
  editor.destroy()
}

// --- Cancel and navigation -------------------------------------------------

{
  const { host, editor } = typed("- [ ] Buy milk ", "due")
  key(host, "Enter")
  key(host, "ArrowRight")
  key(host, "Escape")
  check("Escape in the picker leaves the text as typed",
    !visible() && editor.getMarkdown() === "- [ ] Buy milk /due")
  editor.destroy()
}

{
  const { host, editor } = typed("- [ ] Buy milk ", "due")
  key(host, "Enter")
  key(host, "Backspace")
  check("Backspace in the picker goes back without deleting",
    backLabel() === null && labels()[0] === "Due Date" && editor.getMarkdown() === "- [ ] Buy milk /due")
  editor.destroy()
}

{
  const { host, editor } = typed("- [ ] Buy milk ", "due")
  key(host, "Enter")
  editor.replaceMarkdown("- Buy milk /due")
  check("a line that stops being a task closes its picker", !visible())
  key(host, "Enter")
  check("and no field is written to it", !editor.getMarkdown().includes("due:"))
  editor.destroy()
}

{
  const { host, editor } = typed("- [ ] Buy milk ", "due", { extensionOptions: { "slash-commands": { locale: "fr" } } })
  key(host, "Enter")
  check("the picker follows the app language", title() === "octobre 2026")
  check("the picker starts the week on the locale's first day",
    menu().querySelector(".cm-md-slash-weekday").getAttribute("aria-label") === "lundi")
  editor.destroy()
}

// --- Undo, localization, task lifecycle -------------------------------------

{
  const { host, editor } = typed("- [ ] Buy milk ", "due")
  key(host, "Enter")
  key(host, "Enter")
  key(host, "z", { ctrlKey: true, code: "KeyZ" })
  check("one undo restores the typed command", editor.getMarkdown() === "- [ ] Buy milk /due")
  key(host, "y", { ctrlKey: true, code: "KeyY" })
  check("redo reapplies the field", editor.getMarkdown() === "- [ ] Buy milk due:2026-10-04")
  editor.destroy()
}

{
  const { host, editor } = typed("- [ ] Buy milk ", "", {
    extensionOptions: { "slash-commands": { "cmd.due": "截止日期", "group.task": "任务", "label.nextMonth": "下个月" } },
  })
  check("field labels come from the host", labels().includes("截止日期")
    && Array.from(menu().querySelectorAll(".cm-md-slash-group")).at(-1).textContent === "任务")
  editor.insertTextAt("due", 16, 16)
  check("English names stay searchable under host field labels", labels()[0] === "截止日期")
  key(host, "Enter")
  check("month buttons use host labels",
    menu().querySelector("[data-slash-month='1']").getAttribute("aria-label") === "下个月")
  editor.destroy()
}

{
  const host = dom.window.document.createElement("div")
  dom.window.document.body.appendChild(host)
  const editor = dom.window.MDEditor.create(host, "- [ ] Buy milk due:2026-10-04 p:high", {})
  editor.select(36, 36)
  key(host, "Enter", { ctrlKey: true })
  check("completing a task keeps its fields", editor.getMarkdown() === "- [x] Buy milk due:2026-10-04 p:high")
  key(host, "Enter")
  check("the next task does not copy dates or priority",
    editor.getMarkdown() === "- [x] Buy milk due:2026-10-04 p:high\n- [ ] ")
  editor.destroy()
}
