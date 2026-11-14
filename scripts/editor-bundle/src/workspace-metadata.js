import { GFM, parser } from "@lezer/markdown";
import {
  PRIORITY_KEY,
  PRIORITY_VALUES,
  TASK_DATE_KEYS,
  isTaskDate,
} from "./task-fields.js";

// This module deliberately has no CodeMirror view/state or DOM dependency. It
// is bundled once for native callers and is also imported by editor API code.
const markdownParser = parser.configure(GFM);
const TOKEN_START = /[\p{L}\p{N}_-]/u;
// Combining marks (`\p{M}`) continue a token so decomposed accents and
// scripts such as Devanagari or Thai keep their whole names.
const TOKEN_CHARACTER = /[\p{L}\p{M}\p{N}_\-/]/u;
const LETTER = /\p{L}/u;
const WHITESPACE = /\s/u;
// Fields start at the line start or after whitespace, like `#`/`@`/`+`
// tokens. The leading group captures that boundary so `fieldStart` can point
// at the key itself.
const TASK_FIELD = new RegExp(
  String.raw`(^|\s)(?:(${TASK_DATE_KEYS.join("|")}):(\d{4}-\d{2}-\d{2})|${PRIORITY_KEY}:(${PRIORITY_VALUES.join("|")}))(?=$|[\s,;.!?])`,
  "gu",
);
const BLOCKED_NODES = new Set([
  "Autolink",
  "CodeBlock",
  "FencedCode",
  "HTMLBlock",
  "HTMLTag",
  "Image",
  "InlineCode",
  "Link",
  "Table",
  "URL",
]);

// Lookup keys: NFKC, then lowercase. Source spelling is kept separately.
const normalizedKey = (value) =>
  value.normalize("NFKC").toLocaleLowerCase("en-US");
const isTokenCharacter = (character) => TOKEN_CHARACTER.test(character);

function characterAt(source, offset) {
  const codePoint = source.codePointAt(offset);
  return codePoint == null ? "" : String.fromCodePoint(codePoint);
}

function nextOffset(source, offset) {
  return offset + characterAt(source, offset).length;
}

// Offsets where each line starts, so `lineAt` is a binary search rather than
// a rescan from the top for every token.
function lineStarts(source) {
  const starts = [0];
  for (let index = 0; index < source.length; index++) {
    if (source[index] === "\n") starts.push(index + 1);
    else if (source[index] === "\r" && source[index + 1] !== "\n")
      starts.push(index + 1);
  }
  return starts;
}

function lineAt(starts, offset) {
  let low = 0,
    high = starts.length - 1;
  while (low < high) {
    const middle = (low + high + 1) >> 1;
    if (starts[middle] <= offset) low = middle;
    else high = middle - 1;
  }
  return low + 1;
}

function lineEnd(source, offset) {
  let index = offset;
  while (
    index < source.length &&
    source[index] !== "\r" &&
    source[index] !== "\n"
  )
    index++;
  return index;
}

// Markdown parser intentionally has no frontmatter extension. Frontmatter is
// a document-level syntax context, so exclude it before collecting tokens.
// Mirrors the editor's `yamlFrontmatter`: only `---` opens or closes it, and
// an unclosed block runs to the end of the document.
function frontmatterRange(source) {
  const firstEnd = lineEnd(source, 0);
  const first = source
    .slice(0, firstEnd)
    .replace(/^\uFEFF/, "")
    .trim();
  if (first !== "---") return null;
  let index = firstEnd;
  if (source[index] === "\r" && source[index + 1] === "\n") index += 2;
  else if (source[index] === "\r" || source[index] === "\n") index++;
  while (index <= source.length) {
    const end = lineEnd(source, index);
    const line = source.slice(index, end).trim();
    if (line === "---") return { from: 0, to: end };
    if (end === source.length) break;
    index = end + (source[end] === "\r" && source[end + 1] === "\n" ? 2 : 1);
  }
  return { from: 0, to: source.length };
}

function syntaxContexts(source) {
  const blocked = [];
  const tasks = [];
  const openHTMLTags = [];
  markdownParser.parse(source).iterate({
    enter(node) {
      if (BLOCKED_NODES.has(node.name))
        blocked.push({ from: node.from, to: node.to });
      if (node.name === "Task") tasks.push(node.from);
      if (node.name !== "HTMLTag") return;

      const tag = source.slice(node.from, node.to);
      const match = /^<\/?([A-Za-z][A-Za-z0-9-]*)\b[^>]*>$/u.exec(tag);
      if (!match || /\/>$/u.test(tag)) return;
      const name = match[1].toLowerCase();
      if (tag.startsWith("</")) {
        for (let index = openHTMLTags.length - 1; index >= 0; index--) {
          if (openHTMLTags[index].name !== name) continue;
          blocked.push({ from: openHTMLTags[index].from, to: node.to });
          openHTMLTags.splice(index, 1);
          break;
        }
      } else {
        openHTMLTags.push({ name, from: node.from });
      }
    },
  });
  const frontmatter = frontmatterRange(source);
  if (frontmatter) blocked.push(frontmatter);
  blocked.sort((left, right) => left.from - right.from || right.to - left.to);
  const merged = [];
  for (const range of blocked) {
    const previous = merged.at(-1);
    if (previous && range.from <= previous.to)
      previous.to = Math.max(previous.to, range.to);
    else merged.push({ ...range });
  }
  return { blocked: merged, tasks: [...new Set(tasks)] };
}

function isBlocked(offset, ranges) {
  let low = 0,
    high = ranges.length - 1;
  while (low <= high) {
    const middle = (low + high) >> 1;
    const range = ranges[middle];
    if (offset < range.from) high = middle - 1;
    else if (offset >= range.to) low = middle + 1;
    else return true;
  }
  return false;
}

function collectTokens(source, starts, ranges, result) {
  for (let offset = 0; offset < source.length; ) {
    const marker = characterAt(source, offset);
    if (marker !== "#" && marker !== "@" && marker !== "+") {
      offset = nextOffset(source, offset);
      continue;
    }
    const previous = offset === 0 ? "" : characterAt(source, offset - 1);
    const valueStart = nextOffset(source, offset);
    const first = characterAt(source, valueStart);
    if (
      isBlocked(offset, ranges) ||
      (previous && !WHITESPACE.test(previous)) ||
      !TOKEN_START.test(first)
    ) {
      offset = valueStart;
      continue;
    }

    let end = valueStart;
    while (end < source.length) {
      const character = characterAt(source, end);
      if (isBlocked(end, ranges) || !isTokenCharacter(character)) break;
      end = nextOffset(source, end);
    }
    const value = source.slice(valueStart, end);
    if (
      (!value.includes("/") || value.split("/").every(Boolean)) &&
      LETTER.test(value)
    ) {
      const token = {
        source: source.slice(offset, end),
        key: normalizedKey(value),
        line: lineAt(starts, offset),
      };
      if (marker === "#") result.tags.push(token);
      else if (marker === "@") result.contexts.push(token);
      else result.projects.push(token);
    }
    offset = end;
  }
}

function taskMetadata(source, starts, taskOffset, ranges) {
  const line = lineAt(starts, taskOffset);
  const end = lineEnd(source, taskOffset);
  const text = source.slice(taskOffset, end);
  const task = { line, due: null, scheduled: null, priority: null };
  for (const field of text.matchAll(TASK_FIELD)) {
    const fieldStart = taskOffset + field.index + field[1].length;
    if (isBlocked(fieldStart, ranges)) continue;
    if (field[2] === "due" && isTaskDate(field[3])) task.due ??= field[3];
    else if (field[2] === "scheduled" && isTaskDate(field[3]))
      task.scheduled ??= field[3];
    else if (field[4]) task.priority ??= field[4];
  }
  return task;
}

/// Extracts workspace metadata from Markdown without mutating `markdown`.
/// Token spelling stays in `source`; `key` is NFKC-normalized lowercase.
export function extractMetadata(markdown) {
  const source = String(markdown ?? "");
  const result = { tags: [], contexts: [], projects: [], tasks: [] };
  const { blocked, tasks } = syntaxContexts(source);
  const starts = lineStarts(source);
  collectTokens(source, starts, blocked, result);
  for (const offset of tasks) {
    if (!isBlocked(offset, blocked))
      result.tasks.push(taskMetadata(source, starts, offset, blocked));
  }
  return result;
}
