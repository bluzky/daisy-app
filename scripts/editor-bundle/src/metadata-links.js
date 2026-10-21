import { Decoration, EditorView, ViewPlugin } from "@codemirror/view"
import { StateEffect, StateField } from "@codemirror/state"
import { syntaxTree } from "@codemirror/language"
import { registerEditorExtension } from "./extensions.js"
import { linkOpener } from "./link-open.js"
import { isMetadataValue } from "./metadata-names.js"

// Metadata links: in a workspace window (the host calls `setMetadataLinks`),
// each `#tag`, `@context` and `+project` reads as a link, and Cmd+click opens
// its page through `onOpenLink({ token })`. Elsewhere tokens stay text. Read
// mode does the same with `MarkdownHTML.metadataLinksScript`; the stylesheet
// is shared.

// Carries the host's new on/off value.
export const metadataLinksChanged = StateEffect.define()

// Rules from `metadata-names.js`: a marker after whitespace or at the line
// start, then name characters with at least one letter and no empty segment.
const TOKEN = /(^|\s)([#@+])([\p{L}\p{N}_-][\p{L}\p{M}\p{N}_\-/]*)/gu
// Where the extractor reads no metadata (see `metadata-completion.js`).
const BLOCKED = /^(?:Frontmatter|FencedCode|CodeBlock|HTMLBlock|HTMLTag|CommentBlock|Table|InlineCode|URL|Autolink|Link|Image)/
const tokenMark = Decoration.mark({ class: "cm-md-metadata-link" })

function isBlocked(state, pos) {
  for (let node = syntaxTree(state).resolveInner(pos, 1); node; node = node.parent) {
    if (BLOCKED.test(node.name)) return true
  }
  return false
}

// Tokens on `line` as `{ from, to, token }`, in document offsets.
export function lineTokens(state, line) {
  const tokens = []
  if (!/[#@+]/.test(line.text)) return tokens
  TOKEN.lastIndex = 0
  for (let match; (match = TOKEN.exec(line.text));) {
    if (!isMetadataValue(match[3])) continue
    const from = line.from + match.index + match[1].length
    const to = line.from + match.index + match[0].length
    if (isBlocked(state, from)) continue
    tokens.push({ from, to, token: match[2] + match[3] })
  }
  return tokens
}

function decorations(view) {
  const ranges = []
  let lastLine = 0
  for (const { from, to } of view.visibleRanges) {
    for (let position = from; position <= to;) {
      const line = view.state.doc.lineAt(position)
      position = line.to + 1
      if (line.number <= lastLine) continue
      lastLine = line.number
      for (const token of lineTokens(view.state, line)) ranges.push(tokenMark.range(token.from, token.to))
    }
  }
  return Decoration.set(ranges, true)
}

function metadataLinksExtensions(_options, host) {
  const on = StateField.define({
    create: () => host.metadataLinks === true,
    update(value, transaction) {
      for (const effect of transaction.effects) if (effect.is(metadataLinksChanged)) value = effect.value
      return value
    },
  })
  const plugin = ViewPlugin.fromClass(class {
    constructor(view) { this.decorations = view.state.field(on) ? decorations(view) : Decoration.none }
    update(update) {
      if (update.docChanged || update.viewportChanged
          || syntaxTree(update.startState) !== syntaxTree(update.state)
          || update.startState.field(on) !== update.state.field(on)) {
        this.decorations = update.state.field(on) ? decorations(update.view) : Decoration.none
      }
    }
  }, { decorations: (plugin) => plugin.decorations })
  return [
    on,
    plugin,
    EditorView.editorAttributes.compute([on], (state) => (state.field(on) ? { class: "cm-metadata-links" } : {})),
    linkOpener.of((view, pos) => {
      if (!view.state.field(on)) return null
      const line = view.state.doc.lineAt(pos)
      const hit = lineTokens(view.state, line).find((token) => pos >= token.from && pos < token.to)
      return hit ? { token: hit.token } : null
    }),
  ]
}

registerEditorExtension({ id: "metadata-links", extensions: metadataLinksExtensions })
