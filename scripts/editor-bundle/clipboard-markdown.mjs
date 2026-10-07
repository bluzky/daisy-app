// Safe, DOMParser-only clipboard conversion. This module never inserts source
// HTML: it reads text nodes and emits a small Markdown subset.

const MAX_INPUT_LENGTH = 1_000_000
const MAX_OUTPUT_LENGTH = 1_000_000
const MAX_NODES = 10_000
const BLOCKED_TAGS = new Set([
  "script", "style", "noscript", "template", "form", "input", "button",
  "select", "textarea", "option", "iframe", "frame", "object", "embed",
  "svg", "math", "canvas", "video", "audio", "source", "picture",
])

function escapeText(value) {
  return String(value || "")
    .replace(/\\/g, "\\\\")
    .replace(/[\[\]]/g, "\\$&")
    .replace(/([*~])/g, "\\$1")
    // Intraword underscores (snake_case) are never emphasis in CommonMark.
    .replace(/(?<![\p{L}\p{N}])_|_(?![\p{L}\p{N}])/gu, "\\_")
}

function escapeLinkDestination(value) {
  return value.replace(/[\\()\s]/g, (character) =>
    character === "(" || character === ")"
      ? `%${character.charCodeAt(0).toString(16).toUpperCase()}`
      : encodeURIComponent(character))
}

// Converted HTML is already escaped by escapeText; raw text (TSV) is not.
function escapeTableCell(value, escapeBackslashes = false) {
  return (escapeBackslashes ? value.replace(/\\/g, "\\\\") : value)
    .replace(/\|/g, "\\|")
    .replace(/[\u0000\r\n]+/g, "\n")
    .split("\n")
    .map(line => line.replace(/[ \t]+/g, " ").trim())
    .filter(Boolean)
    .join("<br>")
}

function normalizeMarkdown(value) {
  return value
    .replace(/\r\n?/g, "\n")
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .replace(/^\n+|\n+$/g, "")
}

function wrapInline(marker, value) {
  const source = value || ""
  const leading = source.match(/^\s*/)[0]
  const trailing = source.match(/\s*$/)[0]
  const middle = source.slice(leading.length, source.length - trailing.length)
  return middle ? `${leading}${marker}${middle}${marker}${trailing}` : source
}

function codeSpan(value) {
  const source = String(value || "").replace(/\s+/g, " ")
  const longestFence = Math.max(0, ...(source.match(/`+/g) || []).map(run => run.length))
  const fence = "`".repeat(longestFence + 1)
  const padded = source.startsWith("`") || source.endsWith("`") ? ` ${source} ` : source
  return `${fence}${padded}${fence}`
}

function fencedCode(value) {
  const source = String(value || "").replace(/\r\n?/g, "\n").replace(/^\n+|\n+$/g, "")
  const longestFence = Math.max(0, ...(source.match(/`+/g) || []).map(run => run.length))
  const fence = "`".repeat(Math.max(3, longestFence + 1))
  return `\n\n${fence}\n${source}\n${fence}\n\n`
}

function safeHref(value) {
  if (!value || /[\r\n]/.test(value)) return null
  try {
    const url = new URL(value, "https://clipboard.invalid")
    return ["http:", "https:", "mailto:"].includes(url.protocol) ? value : null
  } catch (_) {
    return null
  }
}

function directChildren(element, names) {
  return Array.from(element.children).filter(child => names.includes(child.tagName.toLowerCase()))
}

function listMarkdown(element, ordered) {
  const start = Number.parseInt(element.getAttribute("start"), 10) || 1
  const items = directChildren(element, ["li"])
  if (!items.length) return ""
  return `\n\n${items.map((item, index) => {
    const nested = directChildren(item, ["ul", "ol"])
    const content = normalizeMarkdown(Array.from(item.childNodes)
      .filter(child => child.nodeType !== 1 || !["ul", "ol"].includes(child.tagName.toLowerCase()))
      .map(node => markdownForNode(node)).join(""))
    const marker = ordered ? `${start + index}. ` : "- "
    const childLists = nested.map(child => normalizeMarkdown(listMarkdown(child, child.tagName.toLowerCase() === "ol")))
      .filter(Boolean)
      .map(child => child.split("\n").map(line => `    ${line}`).join("\n"))
    return marker + content + (childLists.length ? `\n${childLists.join("\n")}` : "")
  }).join("\n")}\n\n`
}

function markdownForNode(node) {
  if (node.nodeType === 3) return escapeText(node.nodeValue).replace(/\s+/g, " ")
  if (node.nodeType !== 1) return ""
  const tag = node.tagName.toLowerCase()
  if (BLOCKED_TAGS.has(tag)) return ""
  const children = () => Array.from(node.childNodes).map(markdownForNode).join("")
  const inline = () => children()
  const block = (value) => `\n\n${normalizeMarkdown(value)}\n\n`

  if (/^h[1-6]$/.test(tag)) return block(`${"#".repeat(Number(tag[1]))} ${normalizeMarkdown(inline())}`)
  if (tag === "p" || tag === "div" || tag === "section" || tag === "article" || tag === "header" || tag === "footer") return block(inline())
  if (tag === "br") return "\u0000"
  if (tag === "strong" || tag === "b") return wrapInline("**", inline())
  if (tag === "em" || tag === "i") return wrapInline("*", inline())
  if (tag === "s" || tag === "strike" || tag === "del") return wrapInline("~~", inline())
  if (tag === "code") return codeSpan(node.textContent)
  if (tag === "pre") return fencedCode(node.textContent)
  if (tag === "a") {
    const label = inline() || escapeText(node.textContent)
    const href = safeHref(node.getAttribute("href"))
    return href && label ? `[${label}](${escapeLinkDestination(href)})` : label
  }
  if (tag === "img") {
    const alt = escapeText(node.getAttribute("alt") || "")
    const src = node.getAttribute("src")
    // Only absolute http(s) images are portable; anything else keeps its alt text.
    return src && /^https?:\/\//i.test(src.trim()) && safeHref(src.trim())
      ? `![${alt}](${escapeLinkDestination(src.trim())})`
      : alt
  }
  if (tag === "blockquote") {
    const value = normalizeMarkdown(inline())
    return value ? `\n\n${value.split("\n").map(line => `> ${line}`).join("\n")}\n\n` : ""
  }
  if (tag === "ul") return listMarkdown(node, false)
  if (tag === "ol") return listMarkdown(node, true)
  if (tag === "hr") return "\n\n---\n\n"
  if (tag === "table") return tableMarkdown(node) || ""
  return inline()
}

function tableMarkdown(table) {
  const rows = Array.from(table.querySelectorAll("tr"))
    .filter(row => row.closest("table") === table)
    .map(row => directChildren(row, ["th", "td"])
      .map(cell => escapeTableCell(markdownForNode(cell))))
    .filter(row => row.length)
  if (!rows.length) return null
  const columns = Math.max(...rows.map(row => row.length))
  for (const row of rows) while (row.length < columns) row.push("")
  const render = cells => `| ${cells.join(" | ")} |`
  return [render(rows[0]), render(Array(columns).fill("---")), ...rows.slice(1).map(render)].join("\n")
}

function convertHTML(html, DOMParserClass) {
  if (!html || html.length > MAX_INPUT_LENGTH || typeof DOMParserClass !== "function") return null
  let document
  try {
    document = new DOMParserClass().parseFromString(html, "text/html")
  } catch (_) {
    return null
  }
  const body = document?.body
  if (!body || body.querySelectorAll("*").length > MAX_NODES) return null
  // Tables are self-contained clipboard payloads. Prefer them over surrounding
  // app markup and over text/tab-separated-values representations.
  const table = body.querySelector("table")
  const markdown = table ? tableMarkdown(table) : normalizeMarkdown(
    Array.from(body.childNodes).map(markdownForNode).join(""))
  const resolved = markdown?.replace(/\u0000/g, "  \n")
  return resolved && resolved.length <= MAX_OUTPUT_LENGTH ? resolved : null
}

function tsvMarkdown(text, explicit) {
  if (!text || text.length > MAX_INPUT_LENGTH) return null
  const rows = text.replace(/\r\n?/g, "\n").replace(/\n$/, "").split("\n")
  const tabbedRows = rows.filter(row => row.includes("\t"))
  if (!explicit && tabbedRows.length < 2) return null
  if (!explicit && tabbedRows.length !== rows.length) return null
  const cells = rows.map(row => row.split("\t").map(cell => escapeTableCell(cell, true)))
  if (!cells.length || (!explicit && !cells.every(row => row.length > 1))) return null
  const columns = Math.max(...cells.map(row => row.length))
  for (const row of cells) while (row.length < columns) row.push("")
  const render = row => `| ${row.join(" | ")} |`
  return [render(cells[0]), render(Array(columns).fill("---")), ...cells.slice(1).map(render)].join("\n")
}

/**
 * Return Markdown only when rich HTML or safe tabular data deserves handling.
 * Returning null intentionally leaves CodeMirror's plain-text paste untouched.
 */
export function convertClipboardToMarkdown({ html = "", text = "", types = [] } = {}, options = {}) {
  const DOMParserClass = options.DOMParser || globalThis.DOMParser
  const fromHTML = convertHTML(String(html || ""), DOMParserClass)
  if (fromHTML) return fromHTML
  const explicitTSV = Array.from(types || []).some(type =>
    /^text\/tab-separated-values(?:;|$)/.test(String(type).toLowerCase()))
  return tsvMarkdown(String(text || ""), explicitTSV)
}
