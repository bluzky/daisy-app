import { EditorView, Decoration, BlockWrapper } from "@codemirror/view"
import { StateField } from "@codemirror/state"
import { tags as t } from "@lezer/highlight"
import { RuleWidget, TextWidget } from "./widgets/basic.js"

export const hide = Decoration.replace({})
export const bulletDeco = Decoration.replace({ widget: new TextWidget("•", "cm-md-bullet") })
export const activeBulletDeco = Decoration.mark({ class: "cm-md-bullet-source" })
// Ordered markers sit in the same hanging box as bullets, right-aligned and
// in the accent color, so item text lines up across list kinds like the
// preview's ::marker. The active marker stays editable source in that box.
const orderedDecoCache = new Map()
export const orderedDeco = (mark) => {
  let deco = orderedDecoCache.get(mark)
  if (!deco) {
    deco = Decoration.replace({ widget: new TextWidget(mark, "cm-md-ordered") })
    orderedDecoCache.set(mark, deco)
  }
  return deco
}
export const activeOrderedDeco = Decoration.mark({ class: "cm-md-ordered-source" })
export const hrDeco = Decoration.replace({ widget: new RuleWidget() })
export const ruleLine = Decoration.line({ class: "cm-md-rule-line" })
export const markdownListMarker = /^([ \t]*)([-+*]|\d+[.)])([ \t]+|$)/

export const joinDeco = Decoration.replace({ widget: new TextWidget(" ", "cm-md-join") })

export const HEADING_LINE = {}
const for_ = (i) => Decoration.line({ class: "cm-md-h" + i })
for (let i = 1; i <= 6; i++) HEADING_LINE[i] = for_(i)
export const inactiveHeadingLine = Decoration.line({ class: "cm-md-heading-inactive" })
export const headingAfterBlankLine = Decoration.line({ class: "cm-md-heading-after-blank" })
export const imageLine = Decoration.line({ class: "cm-md-image-line" })
// Inactive fence source lines collapse because the rendered code card owns
// their height.
export const collapsedLine = Decoration.line({ class: "cm-md-line-collapsed" })

// Preview block margin-top values in CSS px. The host passes the live values
// from MarkdownHTML.swift (the single source of truth) through
// MDEditor.create's `spacing` option; these defaults only serve headless
// harnesses. The final blank line of a run shrinks to `blankGap` (plus the
// adjacent blocks' semantic margins) so a single authored blank reads like a
// normal paragraph gap; earlier blanks in a run keep their natural
// source-line height, so extra authored blanks still grow the gap.
export const METRICS = {
  line: 22.8,
  blankGap: 4,    // final blank of a run (.md-source-blank-line)
  paragraph: 12,  // p / ul / ol / pre / .md-code-wrap
  quote: 18,      // blockquote
  alert: 24,      // .markdown-alert
  table: 24,      // .md-table-scroll
  hr: 12,         // hr (top only; the next block's margin supplies the bottom)
}
export const SEPARATOR_BLOCKS = new Set([
  "Paragraph", "FencedCode", "CodeBlock", "Blockquote",
  "BulletList", "OrderedList", "Table", "HorizontalRule", "HTMLBlock",
])
const separatorLineCache = new Map()
export const blockSeparatorLine = (height) => {
  let deco = separatorLineCache.get(height)
  if (!deco) {
    deco = Decoration.line({
      class: "cm-md-block-separator",
      attributes: {
        style: `height:${height}px;min-height:0;line-height:${height}px;overflow:hidden;`,
      },
    })
    separatorLineCache.set(height, deco)
  }
  return deco
}
// A block that starts on the line right after another block (no authored
// blank between them) still gets its margin-top in the preview. Mirror it as
// padding-bottom on the previous block's last line; padding, not margin, so
// CodeMirror's per-line height measurement stays exact. The same value is
// exposed as a variable so pseudo-element bars can stop above the gap.
const blockGapLineCache = new Map()
export const blockGapLine = (height) => {
  let deco = blockGapLineCache.get(height)
  if (!deco) {
    deco = Decoration.line({
      class: "cm-md-block-gap",
      attributes: { style: `padding-bottom:${height}px;--cm-md-block-gap:${height}px;` },
    })
    blockGapLineCache.set(height, deco)
  }
  return deco
}
// Quotation lines carry their nesting depth: the preview indents each nested
// blockquote by another 1.5em and draws one rule per level. Depth is
// resolved per line after the tree walk, so a line inside two blockquotes
// gets one decoration at depth 2 rather than two competing ones.
const quoteLineCache = new Map()
export const quoteLine = (depth, starts, ends, gap) => {
  const key = `${depth}:${starts}:${ends}:${gap}`
  let deco = quoteLineCache.get(key)
  if (!deco) {
    const positions = []
    const images = []
    for (let level = 0; level < depth; level++) {
      positions.push(`calc(0.3em + ${level * 1.5}em) var(--cm-md-quote-top)`)
      images.push("linear-gradient(var(--quote-border), var(--quote-border))")
    }
    deco = Decoration.line({
      class: "cm-md-quote",
      attributes: {
        style: `padding-inline-start:${depth * 1.5}em;`
          + `--cm-md-quote-top:calc(${starts * 0.4}em + ${gap}px);--cm-md-quote-bottom:${ends * 0.4}em;`
          + `background-image:${images.join(",")};`
          + `background-position:${positions.join(",")};`,
      },
    })
    quoteLineCache.set(key, deco)
  }
  return deco
}
// Lines of a list item that carry no marker (a continuation paragraph, a
// nested code block) align with the item text: same depth padding, but no
// hanging indent, and the source indentation is hidden like a nested
// marker's.
export const listContinuationLine = Decoration.line({ class: "cm-md-list-continuation" })
export const taskLine = Decoration.line({ class: "cm-md-task-line" })
export const completedTaskLine = Decoration.line({ class: "cm-md-task-completed" })
export const codeLine = Decoration.line({ class: "cm-md-codeblock" })
export const codeLineFirst = Decoration.line({ class: "cm-md-codeblock cm-md-codeblock-first" })
export const codeLineLast = Decoration.line({ class: "cm-md-codeblock cm-md-codeblock-last" })
export const codeScrollText = Decoration.mark({ class: "cm-md-code-scroll-text" })

// One native scrollport per code block keeps momentum, text, and selection
// together without mirroring horizontal offsets between editable lines.
export function codeBlockWrappers(decorations, state) {
  const groups = new Map()
  for (let cursor = decorations.iter(); cursor.value; cursor.next()) {
    const attrs = cursor.value.spec.attributes
    const group = attrs?.['data-code-scroll-group']
    if (group == null) continue
    const line = state.doc.lineAt(cursor.from)
    const end = Math.min(state.doc.length, Math.max(line.to, line.from + 1))
    const existing = groups.get(group)
    if (existing) existing.to = end
    else groups.set(group, { from: cursor.from, to: end,
      wrapped: attrs.class === 'cm-md-code-wrapped' })
  }
  return BlockWrapper.set([...groups.values()].map(({ from, to, wrapped }) =>
    BlockWrapper.create({ tagName: 'div', attributes: {
      class: `cm-md-code-card${wrapped ? ' cm-md-code-card-wrapped' : ''}`,
    } }).range(from, to)), true)
}
export const tableLine = Decoration.line({ class: "cm-md-table" })
// Preview gives every list item after the first a 0.4em margin-top (and a
// nested list the same via li > ul). Mirror it on the item's first line.
export const listItemGapLine = Decoration.line({ class: "cm-md-list-item-gap" })
// Mirrors the preview's list geometry: ul/ol start padding with the marker
// hanging inside it, so item text and wrapped lines align like rendered <li>s.
export const listItemLine = Decoration.line({ class: "cm-md-list-item" })
const listDepthLineCache = new Map()
export const listDepthLine = (depth) => {
  let deco = listDepthLineCache.get(depth)
  if (!deco) {
    deco = Decoration.line({
      class: `cm-md-list-depth-${depth}`,
      attributes: {
        style: `padding-inline-start:${depth * 2.1}em;text-indent:-2.1em;`,
      },
    })
    listDepthLineCache.set(depth, deco)
  }
  return deco
}
export const fenceMark = Decoration.mark({ class: "cm-md-fence-info" })
export const hiddenCodeFenceSource = Decoration.mark({ class: "cm-md-code-fence-source-hidden" })
export const hiddenHeadingSource = Decoration.mark({ class: "cm-md-heading-source-hidden" })
export const headingPrefix = Decoration.mark({ class: "cm-md-heading-prefix" })
export const headingMarker = Decoration.mark({ class: "cm-md-heading-marker" })
export const setextMarkerLine = Decoration.line({ class: "cm-md-setext-marker-line" })
export const setextSource = Decoration.mark({ class: "cm-md-setext-source" })
export const linkMark = Decoration.mark({ class: "cm-md-link" })
export const urlMark = Decoration.mark({ class: "cm-md-url" })
export const strongMark = Decoration.mark({ class: "cm-md-strong" })
export const emphasisMark = Decoration.mark({ class: "cm-md-emphasis" })
export const strikethroughMark = Decoration.mark({ class: "cm-md-strikethrough" })
export const highlightMark = Decoration.mark({ class: "cm-md-highlight" })
export const frontmatterLine = Decoration.line({ class: "cm-md-frontmatter" })
export const frontmatterFirstLine = Decoration.line({ class: "cm-md-frontmatter-first" })
export const frontmatterLastLine = Decoration.line({ class: "cm-md-frontmatter-last" })
export const frontmatterDelim = Decoration.mark({ class: "cm-md-frontmatter-delim" })

const autoDirectionLine = Decoration.line({ attributes: { dir: "auto" } })

function buildDirectionLines(state) {
  const ranges = []
  for (let lineNumber = 1; lineNumber <= state.doc.lines; lineNumber++) {
    ranges.push(autoDirectionLine.range(state.doc.line(lineNumber).from))
  }
  return Decoration.set(ranges)
}

export const directionLines = StateField.define({
  create: buildDirectionLines,
  update(value, transaction) {
    return transaction.docChanged ? buildDirectionLines(transaction.state) : value
  },
  provide: (field) => EditorView.decorations.from(field),
})
