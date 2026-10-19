// Read-only workspace metadata scanner shared by editor consumers. `source` is
// original token spelling (including its marker); `key` uses NFKC plus
// en-US lowercase, making lookups stable while retaining what user typed.
const TOKEN_START = /[\p{L}\p{N}_-]/u
const TOKEN_CHARACTER = /[\p{L}\p{N}_\-/]/u
const LETTER = /\p{L}/u
const TASK_MARKER = /^[ \t]*(?:>[ \t]*)*(?:[-+*]|\d{1,9}[.)])[ \t]+\[[ xX]\](?:[ \t]+(.*))?$/
const TASK_FIELD = /(?:^|[\s,;])(?:(due|scheduled):(\d{4}-\d{2}-\d{2})|p:(high|medium|low))(?=$|[\s,;.,!?])/giu
const BLOCK_HTML_TAGS = new Set([
  "address", "article", "aside", "blockquote", "details", "div", "figure", "footer",
  "header", "main", "nav", "ol", "pre", "section", "script", "style", "table", "ul",
])

const normalizedKey = (value) => value.normalize("NFKC").toLocaleLowerCase("en-US")
const isTokenCharacter = (character) => TOKEN_CHARACTER.test(character)

function validDate(value) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false
  const [year, month, day] = value.split("-").map(Number)
  const date = new Date(Date.UTC(year, month - 1, day))
  return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day
}

function blank(match) { return " ".repeat(match.length) }

function searchableText(line) {
  // Links, URLs, emails, and inline code have their own syntax. Do not turn
  // fragments inside them into workspace metadata.
  return line
    .replace(/!?\[[^\]\n]*\]\([^\)\n]*\)/gu, blank)
    .replace(/`+[^`\n]*`+/gu, blank)
    .replace(/<https?:\/\/[^>\s]+>/giu, blank)
    .replace(/\b(?:https?|ftp):\/\/[^\s<]+/giu, blank)
    .replace(/\bwww\.[^\s<]+/giu, blank)
    .replace(/[\p{L}\p{N}._+-]+@[\p{L}\p{N}.-]+\.[\p{L}]{2,}/giu, blank)
}

function openingFence(line) {
  const match = /^[ \t]*(`{3,}|~{3,})/.exec(line)
  return match ? { marker: match[1][0], length: match[1].length } : null
}

function closesFence(line, fence) {
  const trimmed = line.trimStart()
  let length = 0
  while (trimmed[length] === fence.marker) length++
  return length >= fence.length && trimmed.slice(length).trim() === ""
}

function openingHTMLBlock(line) {
  const trimmed = line.trimStart()
  if (trimmed.startsWith("<!--")) return "!--"
  const match = /^<([A-Za-z][A-Za-z0-9-]*)\b[^>]*>/u.exec(trimmed)
  return match && BLOCK_HTML_TAGS.has(match[1].toLowerCase()) ? match[1].toLowerCase() : null
}

function closesHTMLBlock(line, tag) {
  return tag === "!--" ? line.includes("-->") : new RegExp(`</${tag}\\s*>`, "i").test(line)
}

function collectTokens(line, lineNumber, result) {
  const characters = Array.from(searchableText(line))
  for (let index = 0; index < characters.length; index++) {
    const marker = characters[index]
    if (marker !== "#" && marker !== "@" && marker !== "+") continue
    const previous = index === 0 ? "" : characters[index - 1]
    const first = characters[index + 1] ?? ""
    if (isTokenCharacter(previous) || !TOKEN_START.test(first)) continue

    let end = index + 1
    while (end < characters.length && isTokenCharacter(characters[end])) end++
    const value = characters.slice(index + 1, end).join("")
    if (!value.includes("/") ? true : value.split("/").every(Boolean)) {
      if (LETTER.test(value)) {
        const token = { source: characters.slice(index, end).join(""), key: normalizedKey(value), line: lineNumber }
        if (marker === "#") result.tags.push(token)
        else if (marker === "@") result.contexts.push(token)
        else result.projects.push(token)
      }
    }
    index = end - 1
  }
}

function taskMetadata(line, lineNumber) {
  const match = TASK_MARKER.exec(line)
  if (!match) return null
  const task = { line: lineNumber, due: null, scheduled: null, priority: null }
  const text = searchableText(match[1] ?? "")
  for (const field of text.matchAll(TASK_FIELD)) {
    if (field[1] === "due" && validDate(field[2])) task.due ??= field[2]
    else if (field[1] === "scheduled" && validDate(field[2])) task.scheduled ??= field[2]
    else if (field[3]) task.priority ??= field[3].toLowerCase()
  }
  return task
}

export function extractWorkspaceMetadata(markdown) {
  const result = { tags: [], contexts: [], projects: [], tasks: [] }
  const lines = String(markdown ?? "").replace(/^\uFEFF/, "").split(/\r\n|\n|\r/)
  let frontmatter = null
  let fence = null
  let htmlBlock = null

  for (const [offset, line] of lines.entries()) {
    const lineNumber = offset + 1
    if (offset === 0 && (line.trim() === "---" || line.trim() === "+++")) {
      frontmatter = line.trim()
      continue
    }
    if (frontmatter) {
      if ((frontmatter === "---" && (line.trim() === "---" || line.trim() === "..."))
          || (frontmatter === "+++" && line.trim() === "+++")) frontmatter = null
      continue
    }
    if (fence) {
      if (closesFence(line, fence)) fence = null
      continue
    }
    if (htmlBlock) {
      if (closesHTMLBlock(line, htmlBlock)) htmlBlock = null
      continue
    }
    if (line.includes("|") || (/^(?: {4}|\t)/.test(line) && !TASK_MARKER.test(line))) continue
    const openedFence = openingFence(line)
    if (openedFence) {
      fence = openedFence
      continue
    }
    const htmlTag = openingHTMLBlock(line)
    if (htmlTag || line.trimStart().startsWith("<")) {
      if (htmlTag && !closesHTMLBlock(line, htmlTag)) htmlBlock = htmlTag
      continue
    }

    collectTokens(line, lineNumber, result)
    const task = taskMetadata(line, lineNumber)
    if (task) result.tasks.push(task)
  }
  return result
}
