import { PRIORITY_KEY, PRIORITY_VALUES, TASK_DATE_KEYS, isTaskDate } from "./task-fields.js"
import { METADATA_MARKERS, TOKEN_CHARACTER, TOKEN_START, isMetadataValue } from "./metadata-names.js"

// A task line as written after its checkbox, split the way the document
// shows it: text, task fields (badges) and `#`/`@`/`+` names (links). Fields
// and names start at the line start or after whitespace, as the extractor
// reads them. Read mode's query script mirrors these rules
// (`MarkdownHTML.queryBlocksScript`).
const FIELD = new RegExp(
  String.raw`^(?:(${TASK_DATE_KEYS.join("|")}):(\d{4}-\d{2}-\d{2})|${PRIORITY_KEY}:(${PRIORITY_VALUES.join("|")}))(?=$|[\s,;.!?])`,
  "u",
)

export function taskLineSegments(source) {
  const segments = []
  let text = ""
  const flush = () => { if (text) segments.push({ type: "text", text }); text = "" }
  const characters = Array.from(source)
  for (let index = 0; index < characters.length;) {
    const atBoundary = index === 0 || /\s/u.test(characters[index - 1])
    const rest = characters.slice(index).join("")
    const field = atBoundary ? FIELD.exec(rest) : null
    if (field && (!field[2] || isTaskDate(field[2]))) {
      flush()
      segments.push({ type: "field", text: field[0], key: field[1] || PRIORITY_KEY, value: field[2] || field[3] })
      index += Array.from(field[0]).length
      continue
    }
    const marker = characters[index]
    if (atBoundary && METADATA_MARKERS[marker] && TOKEN_START.test(characters[index + 1] || "")) {
      let end = index + 1
      while (end < characters.length && TOKEN_CHARACTER.test(characters[end])) end++
      const value = characters.slice(index + 1, end).join("")
      if (isMetadataValue(value)) {
        flush()
        segments.push({ type: "token", text: marker + value })
        index = end
        continue
      }
    }
    text += characters[index]
    index++
  }
  flush()
  return segments
}
