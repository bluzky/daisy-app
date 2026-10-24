import { GFM, parser } from "@lezer/markdown";
import {
  PRIORITY_KEY,
  PRIORITY_VALUES,
  TASK_DATE_KEYS,
  isTaskDate,
} from "./task-fields.js";
import {
  METADATA_MARKERS,
  TOKEN_CHARACTER,
  TOKEN_START,
  isMetadataName,
  isMetadataValue,
  normalizedKey,
} from "./metadata-names.js";

// This module deliberately has no CodeMirror view/state or DOM dependency. It
// is bundled once for native callers and is also imported by editor API code.
const markdownParser = parser.configure(GFM);
const WHITESPACE = /\s/u;
// Fields start at the line start or after whitespace, like `#`/`@`/`+`
// tokens. The leading group captures that boundary so `fieldStart` can point
// at the key itself.
const TASK_FIELD = new RegExp(
  String.raw`(^|\s)(?:(${TASK_DATE_KEYS.join("|")}):(\d{4}-\d{2}-\d{2})|${PRIORITY_KEY}:(${PRIORITY_VALUES.join("|")}))(?=$|[\s,;.!?])`,
  "gu",
);
// Nodes inside which a Markdown link is literal text. Links themselves are
// blocked for tokens but are what the link collector reads.
const LINK_BLOCKING_NODES = new Set([
  "CodeBlock",
  "FencedCode",
  "HTMLBlock",
  "HTMLTag",
  "Image",
  "InlineCode",
  "Table",
]);
// A scheme of two or more letters, as `DocumentLink.kind` reads it: one
// letter is a Windows drive (`C:\…`), not a scheme.
const SCHEME = /^([A-Za-z][A-Za-z0-9+.-]+):/u;
// Excerpts are for display, so a very long line is cut.
const EXCERPT_LENGTH = 200;
// Frontmatter keys whose values are names, and the marker each one takes.
const FRONTMATTER_NAME_KEYS = { tags: "#", contexts: "@", projects: "+" };
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

function mergedRanges(ranges) {
  ranges.sort((left, right) => left.from - right.from || right.to - left.to);
  const merged = [];
  for (const range of ranges) {
    const previous = merged.at(-1);
    if (previous && range.from <= previous.to)
      previous.to = Math.max(previous.to, range.to);
    else merged.push({ ...range });
  }
  return merged;
}

function syntaxContexts(source) {
  const blocked = [];
  const linkBlocked = [];
  const tasks = [];
  const links = [];
  const openHTMLTags = [];
  markdownParser.parse(source).iterate({
    enter(node) {
      if (BLOCKED_NODES.has(node.name))
        blocked.push({ from: node.from, to: node.to });
      if (LINK_BLOCKING_NODES.has(node.name))
        linkBlocked.push({ from: node.from, to: node.to });
      if (node.name === "Task") tasks.push(node.from);
      if (node.name === "URL" && node.node.parent?.name === "Link")
        links.push({ from: node.node.parent.from, url: source.slice(node.from, node.to) });
      if (node.name !== "HTMLTag") return;

      const tag = source.slice(node.from, node.to);
      const match = /^<\/?([A-Za-z][A-Za-z0-9-]*)\b[^>]*>$/u.exec(tag);
      if (!match || /\/>$/u.test(tag)) return;
      const name = match[1].toLowerCase();
      if (tag.startsWith("</")) {
        for (let index = openHTMLTags.length - 1; index >= 0; index--) {
          if (openHTMLTags[index].name !== name) continue;
          blocked.push({ from: openHTMLTags[index].from, to: node.to });
          linkBlocked.push({ from: openHTMLTags[index].from, to: node.to });
          openHTMLTags.splice(index, 1);
          break;
        }
      } else {
        openHTMLTags.push({ name, from: node.from });
      }
    },
  });
  const frontmatter = frontmatterRange(source);
  if (frontmatter) {
    blocked.push(frontmatter);
    linkBlocked.push(frontmatter);
  }
  return {
    blocked: mergedRanges(blocked),
    linkBlocked: mergedRanges(linkBlocked),
    tasks: [...new Set(tasks)],
    links,
    frontmatter,
  };
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

// The trimmed source line, for showing where a token or link is.
function excerpt(source, starts, line) {
  const from = starts[line - 1];
  const text = source.slice(from, lineEnd(source, from)).trim();
  const characters = Array.from(text);
  return characters.length > EXCERPT_LENGTH
    ? characters.slice(0, EXCERPT_LENGTH).join("") + "…"
    : text;
}

function collectTokens(source, starts, ranges, result) {
  for (let offset = 0; offset < source.length; ) {
    const marker = characterAt(source, offset);
    if (!METADATA_MARKERS[marker]) {
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
    if (isMetadataValue(value)) {
      const line = lineAt(starts, offset);
      const token = {
        source: source.slice(offset, end),
        key: normalizedKey(value),
        line,
        excerpt: excerpt(source, starts, line),
      };
      result[METADATA_MARKERS[marker]].push(token);
    }
    offset = end;
  }
}

// Inline links to local files: `[text](destination)`. Section links, web and
// mail links (any scheme but `file:`) and empty destinations are left out.
function collectLinks(source, starts, links, ranges) {
  const result = [];
  for (const link of links) {
    if (isBlocked(link.from, ranges)) continue;
    let destination = link.url.trim();
    if (destination.startsWith("<") && destination.endsWith(">"))
      destination = destination.slice(1, -1).trim();
    if (!destination || destination.startsWith("#")) continue;
    const scheme = SCHEME.exec(destination);
    if (scheme && scheme[1].toLowerCase() !== "file") continue;
    const line = lineAt(starts, link.from);
    result.push({ destination, line, excerpt: excerpt(source, starts, line) });
  }
  return result;
}

// MARK: Frontmatter

// A YAML subset: top-level `key: value` pairs whose value is a scalar, a
// flow sequence `[a, b]`, or a block sequence of `- item` lines. Nested maps,
// block scalars and anything else are skipped, so a key the subset cannot
// read is simply absent.
const FRONTMATTER_KEY = /^([^\s#:\-[\]{},&*!|>'"%@`][^:]*?)\s*:(?:\s+(.*))?$/u;
const NUMBER = /^[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?$/u;
const MARKDOWN_LINK = /^\[[^\]]*\]\(\s*<?([^()<>\s]+)>?\s*\)$/u;

// Drops a ` #` comment outside quotes.
function withoutComment(text) {
  let quote = null;
  for (let index = 0; index < text.length; index++) {
    const character = text[index];
    if (quote) {
      if (character === quote) quote = null;
    } else if (character === '"' || character === "'") {
      quote = character;
    } else if (character === "#" && (index === 0 || /\s/u.test(text[index - 1]))) {
      return text.slice(0, index).trimEnd();
    }
  }
  return text.trim();
}

function unquoted(text) {
  if (text.length >= 2 && text[0] === "'" && text.at(-1) === "'")
    return text.slice(1, -1).replaceAll("''", "'");
  if (text.length >= 2 && text[0] === '"' && text.at(-1) === '"')
    return text
      .slice(1, -1)
      .replace(/\\(["\\/nt])/gu, (_, escaped) =>
        escaped === "n" ? "\n" : escaped === "t" ? "\t" : escaped,
      );
  return null;
}

// A typed value, or null for an empty one (`~`, `null`, nothing).
function scalarValue(raw) {
  const text = raw.trim();
  if (!text || text === "~" || /^null$/iu.test(text)) return null;
  const quoted = unquoted(text);
  if (quoted !== null) {
    const link = MARKDOWN_LINK.exec(quoted);
    if (link) return { type: "link", text: quoted, destination: link[1] };
    return { type: "text", text: quoted };
  }
  if (/^(?:true|false)$/iu.test(text))
    return { type: "bool", text, bool: text.toLowerCase() === "true" };
  if (NUMBER.test(text)) return { type: "number", text, number: Number(text) };
  if (isTaskDate(text)) return { type: "date", text, date: text };
  return { type: "text", text };
}

// Splits `a, "b, c", d` on commas outside quotes.
function flowItems(text) {
  const items = [];
  let quote = null;
  let start = 0;
  for (let index = 0; index < text.length; index++) {
    const character = text[index];
    if (quote) {
      if (character === quote) quote = null;
    } else if (character === '"' || character === "'") {
      quote = character;
    } else if (character === ",") {
      items.push(text.slice(start, index));
      start = index + 1;
    }
  }
  items.push(text.slice(start));
  return items.map((item) => item.trim()).filter(Boolean);
}

function listValue(items) {
  const values = items
    .map((item) => ({ ...item, value: scalarValue(item.text) }))
    .filter((item) => item.value);
  return {
    value: { type: "list", text: values.map((item) => item.value.text).join(", "), items: values.map((item) => item.value) },
    lines: values.map((item) => item.line),
  };
}

function frontmatterAttributes(source, starts, range) {
  const attributes = [];
  const lines = [];
  const lastLine = lineAt(starts, range.to);
  // Line 1 is the opening `---`; a closed block's last line is `---` too.
  for (let line = 2; line <= lastLine && line <= starts.length; line++) {
    const from = starts[line - 1];
    const text = source.slice(from, lineEnd(source, from));
    if (from >= range.to && text.trim() === "") break;
    lines.push({ line, text });
  }
  if (lines.length && lines.at(-1).text.trim() === "---") lines.pop();

  const seen = new Set();
  for (let index = 0; index < lines.length; index++) {
    const { line, text } = lines[index];
    if (/^\s/u.test(text)) continue;
    const match = FRONTMATTER_KEY.exec(text);
    if (!match) continue;
    const spelling = match[1].trim();
    const key = normalizedKey(spelling);
    const rest = withoutComment(match[2] ?? "");
    let parsed = null;
    if (rest === "") {
      const items = [];
      while (index + 1 < lines.length && /^\s*-(?:\s|$)/u.test(lines[index + 1].text)) {
        index++;
        const item = lines[index];
        items.push({ line: item.line, text: withoutComment(item.text.replace(/^\s*-\s*/u, "")) });
      }
      if (items.length) parsed = listValue(items);
    } else if (rest.startsWith("[") && rest.endsWith("]")) {
      parsed = listValue(flowItems(rest.slice(1, -1)).map((item) => ({ line, text: item })));
    } else if (!/^[|>{&*!]/u.test(rest)) {
      const value = scalarValue(rest);
      if (value) parsed = { value, lines: [line] };
    }
    // Skip what the subset does not read, including a nested block.
    while (index + 1 < lines.length && /^\s+\S/u.test(lines[index + 1].text)) index++;
    if (!parsed || seen.has(key)) continue;
    seen.add(key);
    attributes.push({ key, spelling, line, value: parsed.value, valueLines: parsed.lines });
  }
  return attributes;
}

// `tags`, `contexts` and `projects` values as tokens, on the lines where
// they are written. A value may repeat its marker: `tags: ["#a"]`.
function frontmatterTokens(source, starts, attributes, result) {
  for (const attribute of attributes) {
    const marker = FRONTMATTER_NAME_KEYS[attribute.key];
    if (!marker) continue;
    const values = attribute.value.type === "list" ? attribute.value.items : [attribute.value];
    values.forEach((value, index) => {
      if (value.type !== "text") return;
      const name = value.text.startsWith(marker) ? value.text.slice(marker.length) : value.text;
      if (!isMetadataName(name)) return;
      const line = attribute.valueLines[index];
      result[METADATA_MARKERS[marker]].push({
        source: marker + name,
        key: normalizedKey(name),
        line,
        excerpt: excerpt(source, starts, line),
      });
    });
  }
}

function taskMetadata(source, starts, taskOffset, ranges) {
  const line = lineAt(starts, taskOffset);
  const end = lineEnd(source, taskOffset);
  const text = source.slice(taskOffset, end);
  const task = { line, text: "", checked: /^\[[xX]\]/u.test(text), due: null, scheduled: null, priority: null, tokens: [] };
  const removed = [];
  for (const field of text.matchAll(TASK_FIELD)) {
    const fieldStart = taskOffset + field.index + field[1].length;
    if (isBlocked(fieldStart, ranges)) continue;
    if (field[2] === "due" && isTaskDate(field[3])) task.due ??= field[3];
    else if (field[2] === "scheduled" && isTaskDate(field[3]))
      task.scheduled ??= field[3];
    else if (field[4]) task.priority ??= field[4];
    if (field[4] || isTaskDate(field[3]))
      removed.push([field.index + field[1].length, field.index + field[0].length]);
  }
  let label = text;
  for (const [from, to] of removed.reverse()) label = label.slice(0, from) + label.slice(to);
  task.text = label.replace(/^\[[ xX]\]\s*/u, "").replace(/\s+/gu, " ").trim();
  // The line as written after its checkbox, fields included, for showing
  // the task the way the document does.
  task.source = text.replace(/^\[[ xX]\]\s*/u, "").trim();
  return task;
}

/// Extracts workspace metadata from Markdown without mutating `markdown`.
/// Token spelling stays in `source`; `key` is NFKC-normalized lowercase.
/// Lines are 1-based. Frontmatter values are typed `attributes`; its `tags`,
/// `contexts` and `projects` also count as tokens.
export function extractMetadata(markdown) {
  const source = String(markdown ?? "");
  const result = { tags: [], contexts: [], projects: [], tasks: [], attributes: [], links: [] };
  const { blocked, linkBlocked, tasks, links, frontmatter } = syntaxContexts(source);
  const starts = lineStarts(source);
  if (frontmatter) {
    const attributes = frontmatterAttributes(source, starts, frontmatter);
    frontmatterTokens(source, starts, attributes, result);
    result.attributes = attributes.map(({ key, spelling, line, value }) => ({ key, spelling, line, value }));
  }
  collectTokens(source, starts, blocked, result);
  result.links = collectLinks(source, starts, links, linkBlocked);
  const tokensByLine = new Map();
  for (const kind of Object.values(METADATA_MARKERS)) {
    for (const token of result[kind]) {
      const line = tokensByLine.get(token.line) ?? [];
      line.push({ kind, ...token });
      tokensByLine.set(token.line, line);
    }
  }
  for (const offset of tasks) {
    if (isBlocked(offset, blocked)) continue;
    const task = taskMetadata(source, starts, offset, blocked);
    task.tokens = tokensByLine.get(task.line) ?? [];
    result.tasks.push(task);
  }
  return result;
}
