import { GFM, parser } from "@lezer/markdown"

// This module deliberately has no CodeMirror view/state or DOM dependency. It
// is bundled once for native callers and is also imported by editor API code.
const markdownParser = parser.configure(GFM)
const TOKEN_START = /[\p{L}\p{N}_-]/u
const TOKEN_CHARACTER = /[\p{L}\p{N}_\-/]/u
const LETTER = /\p{L}/u
const WHITESPACE = /\s/u
const TASK_FIELD = /(?:^|[\s,;])(?:(due|scheduled):(\d{4}-\d{2}-\d{2})|p:(high|medium|low))(?=$|[\s,;.,!?])/gu
const BLOCKED_NODES = new Set([
  "Autolink", "CodeBlock", "FencedCode", "HTMLBlock", "Image", "InlineCode", "Link", "Table", "URL",
])

const normalizedKey = (value) => value.normalize("NFKC").toLocaleLowerCase("en-US")
const isTokenCharacter = (character) => TOKEN_CHARACTER.test(character)

function validDate(value) {
  const [year, month, day] = value.split("-").map(Number)
  const date = new Date(Date.UTC(year, month - 1, day))
  return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day
}

function characterAt(source, offset) {
  const codePoint = source.codePointAt(offset)
  return codePoint == null ? "" : String.fromCodePoint(codePoint)
}

function nextOffset(source, offset) {
  return offset + characterAt(source, offset).length
}

function lineAt(source, offset) {
  let line = 1
  for (let index = 0; index < offset; index++) {
    if (source[index] === "\n") line++
    else if (source[index] === "\r" && source[index + 1] !== "\n") line++
  }
  return line
}

function lineEnd(source, offset) {
  let index = offset
  while (index < source.length && source[index] !== "\r" && source[index] !== "\n") index++
  return index
}

// Markdown parser intentionally has no frontmatter extension. Frontmatter is
// a document-level syntax context, so exclude it before collecting tokens.
function frontmatterRange(source) {
  const firstEnd = lineEnd(source, 0)
  const first = source.slice(0, firstEnd).replace(/^\uFEFF/, "").trim()
  if (first !== "---" && first !== "+++") return null
  let index = firstEnd
  if (source[index] === "\r" && source[index + 1] === "\n") index += 2
  else if (source[index] === "\r" || source[index] === "\n") index++
  while (index <= source.length) {
    const end = lineEnd(source, index)
    const line = source.slice(index, end).trim()
    if ((first === "---" && (line === "---" || line === "...")) || (first === "+++" && line === "+++")) {
      return { from: 0, to: end }
    }
    if (end === source.length) break
    index = end + (source[end] === "\r" && source[end + 1] === "\n" ? 2 : 1)
  }
  return { from: 0, to: source.length }
}

function syntaxContexts(source) {
  const blocked = []
  const tasks = []
  markdownParser.parse(source).iterate({
    enter(node) {
      if (BLOCKED_NODES.has(node.name)) blocked.push({ from: node.from, to: node.to })
      if (node.name === "Task") tasks.push(node.from)
    },
  })
  const frontmatter = frontmatterRange(source)
  if (frontmatter) blocked.push(frontmatter)
  blocked.sort((left, right) => left.from - right.from || right.to - left.to)
  const merged = []
  for (const range of blocked) {
    const previous = merged.at(-1)
    if (previous && range.from <= previous.to) previous.to = Math.max(previous.to, range.to)
    else merged.push({ ...range })
  }
  return { blocked: merged, tasks: [...new Set(tasks)] }
}

function isBlocked(offset, ranges) {
  let low = 0, high = ranges.length - 1
  while (low <= high) {
    const middle = (low + high) >> 1
    const range = ranges[middle]
    if (offset < range.from) high = middle - 1
    else if (offset >= range.to) low = middle + 1
    else return true
  }
  return false
}

function collectTokens(source, ranges, result) {
  for (let offset = 0; offset < source.length;) {
    const marker = characterAt(source, offset)
    if (marker !== "#" && marker !== "@" && marker !== "+") {
      offset = nextOffset(source, offset)
      continue
    }
    const previous = offset === 0 ? "" : characterAt(source, offset - 1)
    const valueStart = nextOffset(source, offset)
    const first = characterAt(source, valueStart)
    if (isBlocked(offset, ranges) || (previous && !WHITESPACE.test(previous)) || !TOKEN_START.test(first)) {
      offset = valueStart
      continue
    }

    let end = valueStart
    while (end < source.length) {
      const character = characterAt(source, end)
      if (isBlocked(end, ranges) || !isTokenCharacter(character)) break
      end = nextOffset(source, end)
    }
    const value = source.slice(valueStart, end)
    if ((!value.includes("/") || value.split("/").every(Boolean)) && LETTER.test(value)) {
      const token = { source: source.slice(offset, end), key: normalizedKey(value), line: lineAt(source, offset) }
      if (marker === "#") result.tags.push(token)
      else if (marker === "@") result.contexts.push(token)
      else result.projects.push(token)
    }
    offset = end
  }
}

function taskMetadata(source, taskOffset, ranges) {
  const line = lineAt(source, taskOffset)
  const end = lineEnd(source, taskOffset)
  const text = source.slice(taskOffset, end)
  const task = { line, due: null, scheduled: null, priority: null }
  for (const field of text.matchAll(TASK_FIELD)) {
    if (isBlocked(taskOffset + field.index, ranges)) continue
    if (field[1] === "due" && validDate(field[2])) task.due ??= field[2]
    else if (field[1] === "scheduled" && validDate(field[2])) task.scheduled ??= field[2]
    else if (field[3]) task.priority ??= field[3]
  }
  return task
}

/// Extracts workspace metadata from Markdown without mutating `markdown`.
/// Token spelling stays in `source`; `key` is NFKC-normalized lowercase.
export function extractMetadata(markdown) {
  const source = String(markdown ?? "")
  const result = { tags: [], contexts: [], projects: [], tasks: [] }
  const { blocked, tasks } = syntaxContexts(source)
  collectTokens(source, blocked, result)
  for (const offset of tasks) {
    if (!isBlocked(offset, blocked)) result.tasks.push(taskMetadata(source, offset, blocked))
  }
  return result
}
