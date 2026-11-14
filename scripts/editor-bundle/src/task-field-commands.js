import { syntaxTree } from "@codemirror/language"
import { isolateHistory } from "@codemirror/commands"
import { PRIORITY_KEY, TASK_DATE_KEYS, isTaskFieldValue } from "./task-fields.js"

// Slash commands that set `p:`, `due:` and `scheduled:` on a checkbox task's
// marker line. Every command goes through `taskFieldChange`, which inserts the
// field when it is absent, replaces the one occurrence it is pointed at, or
// removes it, and drops the typed `/query` in the same transaction.

export const TASK_FIELD_KEYS = [PRIORITY_KEY, ...TASK_DATE_KEYS]

// Any `key:` occurrence counts, valid or not, so a malformed value can be
// replaced by a valid one; trailing sentence punctuation is not part of it.
const FIELD_OCCURRENCE = new RegExp(String.raw`(^|[ \t])(${TASK_FIELD_KEYS.join("|")}):(\S*)`, "g")
const FIELD_BLOCKED = /^(?:InlineCode|URL|Autolink|Link|Image|HTMLTag|Comment)/
const isSpace = (character) => character === " " || character === "\t"

// The task on `line`, or null when the line is not a checkbox task's marker
// line. `contentStart` is the line offset just past `[ ]` and its space;
// `occurrences[key]` lists that field's `{ from, to, text }` in line offsets.
export function taskLine(state, line) {
  let marker = null
  syntaxTree(state).iterate({
    from: line.from,
    to: line.to,
    enter(node) {
      if (marker) return false
      if (node.name === "TaskMarker" && node.from >= line.from && node.to <= line.to) marker = node.node
    },
  })
  if (!marker) return null
  let contentStart = marker.to - line.from
  if (isSpace(line.text[contentStart])) contentStart++
  const occurrences = Object.fromEntries(TASK_FIELD_KEYS.map((key) => [key, []]))
  FIELD_OCCURRENCE.lastIndex = 0
  for (const match of line.text.matchAll(FIELD_OCCURRENCE)) {
    const from = match.index + match[1].length
    if (from < contentStart) continue
    const value = match[3].replace(/[,;.!?]+$/, "")
    const to = from + match[2].length + 1 + value.length
    let blocked = false
    for (let node = syntaxTree(state).resolveInner(line.from + from, 1); node; node = node.parent) {
      if (FIELD_BLOCKED.test(node.name)) { blocked = true; break }
    }
    if (!blocked) occurrences[match[2]].push({ from, to, text: line.text.slice(from, to), value })
  }
  return { contentStart, occurrences }
}

// The edited marker line and caret, all in line offsets. `cut` is the typed
// `/query`; `target` the occurrence to change (null adds one); `token` the
// field text to write (null removes `target`). A new field goes at the end of
// the task text, or at its start when `leading` (priority).
function editLine(text, cut, contentStart, target, token, leading) {
  let line = text.slice(0, cut.from) + text.slice(cut.to)
  let caret = cut.from
  let field = target && {
    from: target.from >= cut.to ? target.from - (cut.to - cut.from) : target.from,
    to: target.to >= cut.to ? target.to - (cut.to - cut.from) : target.to,
  }
  // Removing `/query` from `a /query b` or `a /query` leaves a space too many.
  if (caret > contentStart && isSpace(line[caret - 1]) && (caret === line.length || isSpace(line[caret]))) {
    line = line.slice(0, caret - 1) + line.slice(caret)
    if (field && field.from >= caret) { field.from--; field.to-- }
    caret--
  }
  const splice = (from, to, insert) => {
    line = line.slice(0, from) + insert + line.slice(to)
    if (caret >= to) caret += insert.length - (to - from)
    else if (caret > from) caret = from
  }
  if (field && token) splice(field.from, field.to, token)
  else if (field) {
    // Take one neighbouring space with it, never the one after `[ ]`.
    if (isSpace(line[field.to])) splice(field.from, field.to + 1, "")
    else if (field.from > contentStart && isSpace(line[field.from - 1])) splice(field.from - 1, field.to, "")
    else splice(field.from, field.to, "")
  } else if (token && leading) {
    const start = Math.min(contentStart, line.length)
    const rest = line.slice(start)
    splice(start, start, rest && !isSpace(rest[0]) ? `${token} ` : token)
  } else if (token) {
    const end = Math.max(line.replace(/[ \t]+$/, "").length, Math.min(contentStart, line.length))
    splice(end, end, (end > 0 && !isSpace(line[end - 1]) ? " " : "") + token)
  }
  return { line, caret }
}

// The transaction spec for setting `key` to `value` (null removes it) on the
// task under `session`, or null when the line is no longer a task, the value
// does not validate, or the target occurrence is ambiguous or gone.
// `occurrence` picks which duplicate to change; it may be omitted when the
// field appears at most once.
export function taskFieldChange(state, session, key, value, occurrence) {
  if (!TASK_FIELD_KEYS.includes(key)) return null
  if (value != null && !isTaskFieldValue(key, value)) return null
  const line = state.doc.lineAt(session.from)
  const task = taskLine(state, line)
  if (!task) return null
  const found = task.occurrences[key]
  if (occurrence == null && found.length > 1) return null
  const target = occurrence == null ? found[0] || null : found[occurrence]
  if (occurrence != null && !target) return null
  const cut = { from: session.from - line.from, to: session.to - line.from }
  const { line: text, caret } = editLine(line.text, cut, task.contentStart, target,
    value == null ? null : `${key}:${value}`, key === PRIORITY_KEY)
  // Change only what differs so marks and widgets elsewhere on the line stay.
  let start = 0
  while (start < text.length && start < line.text.length && text[start] === line.text[start]) start++
  let end = 0
  while (end < text.length - start && end < line.text.length - start
    && text[text.length - 1 - end] === line.text[line.text.length - 1 - end]) end++
  return {
    changes: { from: line.from + start, to: line.to - end, insert: text.slice(start, text.length - end) },
    selection: { anchor: line.from + caret },
    userEvent: "slash.apply",
    // Its own undo step: undo restores the typed `/query`, not the line before it.
    annotations: isolateHistory.of("full"),
    scrollIntoView: true,
  }
}
