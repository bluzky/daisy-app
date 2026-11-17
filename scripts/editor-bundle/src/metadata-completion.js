import { EditorSelection, StateEffect } from "@codemirror/state"
import { syntaxTree } from "@codemirror/language"
import { registerEditorExtension } from "./extensions.js"
import { completionExtensions } from "./completion.js"
import { METADATA_MARKERS, TOKEN_CHARACTER, TOKEN_START, isMetadataName, normalizedKey } from "./metadata-names.js"
import { extractMetadata } from "./workspace-metadata.js"

// Tag, context and project suggestions: typing `#`, `@` or `+` at the start of
// a line or after whitespace lists the names of that kind, from this document
// and from the host's workspace snapshot (`setWorkspaceCandidates`). Picking
// one replaces the whole token under the caret. A name nobody has used yet
// lists nothing: the typed text is already the name.

// Rows listed at most.
const MAX_ROWS = 50

// Same places the slash menu stays closed, plus inline HTML.
const BLOCKED = /^(?:Frontmatter|FencedCode|CodeBlock|HTMLBlock|HTMLTag|CommentBlock|Table|InlineCode|URL|Autolink|Link|Image)/
const BEFORE_CARET = /(?:^|\s)([#@+])([\p{L}\p{M}\p{N}_\-/]*)$/u
// `#` and `+` that start a line are also the heading and list markers, so
// there they wait for a name character before opening.
const LINE_START = /^[ \t>]*$/

// The workspace snapshot the host last sent, normalized as
// `{ version, indexing, truncated, tags, contexts, projects }` with a
// `Map(key -> { name, count })` per kind. `indexing` is true while the first
// scan runs; `truncated` when the scan stopped at a limit, so some files are
// not counted. Returns null, leaving `held` in place, for a malformed snapshot
// or one older than `held`.
export const workspaceCandidatesChanged = StateEffect.define()

export function readWorkspaceCandidates(snapshot, held) {
  if (!snapshot || typeof snapshot !== "object") return null
  const version = snapshot.version
  if (!Number.isSafeInteger(version) || version < 0) return null
  if (held && version < held.version) return null
  const next = { version, indexing: snapshot.indexing === true, truncated: snapshot.truncated === true }
  for (const kind of Object.values(METADATA_MARKERS)) {
    const names = new Map()
    for (const entry of Array.isArray(snapshot[kind]) ? snapshot[kind] : []) {
      if (!entry || !isMetadataName(entry.name)) continue
      const count = Number.isFinite(entry.count) && entry.count >= 1 ? Math.floor(entry.count) : 1
      const key = normalizedKey(entry.name)
      const known = names.get(key)
      if (known) known.count += count
      else names.set(key, { name: entry.name, count })
    }
    next[kind] = names
  }
  return next
}

// The token at the caret: its marker, the name typed so far (`query`) and any
// name characters after the caret, which a pick replaces too. `lineFrom` is
// the marker, so the session is this one token.
function metadataTrigger(state) {
  const selection = state.selection
  if (selection.ranges.length > 1 || !selection.main.empty) return null
  const head = selection.main.head
  const line = state.doc.lineAt(head)
  const before = state.doc.sliceString(line.from, head)
  const match = BEFORE_CARET.exec(before)
  if (!match) return null
  const [, marker, query] = match
  if (query && !TOKEN_START.test(query)) return null
  const from = head - query.length - 1
  if (!query && (marker === "#" || marker === "+") && LINE_START.test(before.slice(0, from - line.from))) return null
  for (let node = syntaxTree(state).resolveInner(head, -1); node; node = node.parent) {
    if (BLOCKED.test(node.name)) return null
  }
  let end = head
  for (const character of state.doc.sliceString(head, line.to)) {
    if (!TOKEN_CHARACTER.test(character)) break
    end += character.length
  }
  return {
    from, to: head, end, query, marker,
    kind: METADATA_MARKERS[marker],
    token: query + state.doc.sliceString(head, end),
    lineFrom: from,
    doc: state.doc,
  }
}

// Names in this document, leaving out the token being typed so a half-typed
// name never suggests itself. The text around that token stays the same while
// it is typed, so the last extraction is reused until the document changes
// elsewhere.
function bufferNames() {
  let lastText = null
  let lastResult = null
  return (session) => {
    const text = session.doc.sliceString(0, session.from) + session.doc.sliceString(session.end)
    if (text !== lastText) {
      lastText = text
      lastResult = extractMetadata(text)
    }
    const names = new Map()
    for (const token of lastResult[session.kind]) {
      const entry = names.get(token.key) || { count: 0, spellings: new Map() }
      entry.count++
      const spelling = token.source.slice(1)
      entry.spellings.set(spelling, (entry.spellings.get(spelling) || 0) + 1)
      names.set(token.key, entry)
    }
    // The spelling used most, the earliest one on a tie.
    const result = new Map()
    for (const [key, entry] of names) {
      let name = null
      for (const [spelling, count] of entry.spellings) {
        if (name === null || count > entry.spellings.get(name)) name = spelling
      }
      result.set(key, { name, count: entry.count })
    }
    return result
  }
}

// This document's names win for its own suggestions: their spelling replaces
// the snapshot's. The host leaves this document out of the snapshot, saved
// or unsaved, so its half-typed name is not listed and the counts add up.
function mergedNames(buffer, snapshot) {
  const merged = new Map(snapshot || [])
  for (const [key, entry] of buffer) {
    const known = merged.get(key)
    merged.set(key, { name: entry.name, count: entry.count + (known ? known.count : 0) })
  }
  return merged
}

// Exact name, then start of the name, then start of a later hierarchy
// segment (`front` finds `daisy/frontend`); then usage, then the name.
const MATCH_EXACT = 3
const MATCH_PREFIX = 2
const MATCH_SEGMENT = 1

function matchKind(key, needle) {
  if (!needle) return MATCH_PREFIX
  if (key === needle) return MATCH_EXACT
  if (key.startsWith(needle)) return MATCH_PREFIX
  return key.split("/").slice(1).some((segment) => segment.startsWith(needle)) ? MATCH_SEGMENT : 0
}

export function rankNames(names, query) {
  const needle = normalizedKey(query)
  const ranked = []
  for (const [key, entry] of names) {
    const kind = matchKind(key, needle)
    if (kind) ranked.push({ key, ...entry, kind })
  }
  return ranked.sort((a, b) => b.kind - a.kind || b.count - a.count
    || (a.key < b.key ? -1 : a.key > b.key ? 1 : 0)
    || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0))
}

// Why the workspace's names may be incomplete, under the rows; nothing once
// every file is counted. Labels come from the host (`options["label.<id>"]`).
function coverageNote(options, workspace) {
  if (!workspace) return null
  if (workspace.indexing) return options["label.indexing"] || "Indexing workspace…"
  if (workspace.truncated) return options["label.truncated"] || "Some files are not indexed: the workspace is over the file limit."
  return null
}

function metadataExtensions(options, host) {
  const names = bufferNames()
  const items = (_level, _query, session) => {
    const snapshot = host.workspaceCandidates && host.workspaceCandidates[session.kind]
    return rankNames(mergedNames(names(session), snapshot), session.query).slice(0, MAX_ROWS).map((entry) => ({
      id: `${session.kind}:${entry.key}`,
      label: session.marker + entry.name,
      name: entry.name,
    }))
  }

  return completionExtensions({
    classPrefix: "metadata",
    trigger: metadataTrigger,
    items,
    footer: () => coverageNote(options, host.workspaceCandidates),
    apply: (view, session, item) => {
      // A session the document has moved past changes nothing.
      if (view.state.doc.sliceString(session.from, session.end) !== session.marker + session.token) return
      const insert = session.marker + item.name
      view.dispatch({
        changes: { from: session.from, to: session.end, insert },
        selection: EditorSelection.cursor(session.from + insert.length),
        userEvent: "metadata.apply",
        scrollIntoView: true,
      })
    },
  })
}

registerEditorExtension({ id: "metadata-completion", precedence: "highest", extensions: metadataExtensions })
