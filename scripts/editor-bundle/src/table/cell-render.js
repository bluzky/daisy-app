import { markdownLanguage } from "@codemirror/lang-markdown"
import { obsidianHighlight } from "../obsidian-highlight.js"

// Inactive cells render inline formatting; focused cells expose their exact
// Markdown. Build DOM nodes so authored HTML stays text and links stay editable.
const tableInlineParser = markdownLanguage.parser.configure(obsidianHighlight)
export const tableRenderedTextOffsets = new WeakMap()

export function renderTableCell(element, source) {
  const classes = {
    StrongEmphasis: 'cm-md-strong',
    Emphasis: 'cm-md-emphasis',
    Strikethrough: 'cm-md-strikethrough',
    Highlight: 'cm-md-highlight',
  }
  const appendText = (parent, text, from) => {
    if (!text) return
    const node = document.createTextNode(text)
    tableRenderedTextOffsets.set(node, from)
    parent.append(node)
  }
  const appendRange = (parent, node, from, to) => {
    let offset = from
    for (let child = node.firstChild; child; child = child.nextSibling) {
      if (child.from < from || child.to > to) continue
      appendText(parent, source.slice(offset, child.from), offset)
      appendNode(parent, child)
      offset = child.to
    }
    appendText(parent, source.slice(offset, to), offset)
  }
  const appendNode = (parent, node) => {
    if (node.name === 'InlineCode') {
      const code = document.createElement('code')
      code.className = 'cm-md-inline-code'
      let text = source.slice(node.firstChild.to, node.lastChild.from).replace(/\n/g, ' ')
      const padded = text.startsWith(' ') && text.endsWith(' ') && /[^ ]/.test(text)
      if (padded) text = text.slice(1, -1)
      appendText(code, text, node.firstChild.to + (padded ? 1 : 0))
      parent.append(code)
    } else if (classes[node.name]) {
      const span = document.createElement('span')
      span.className = classes[node.name]
      appendRange(span, node, node.firstChild.to, node.lastChild.from)
      parent.append(span)
    } else if (node.name === 'Link' && node.getChild('URL')) {
      const marks = node.getChildren('LinkMark')
      const label = document.createElement('span')
      label.className = 'cm-md-link'
      appendRange(label, node, marks[0].to, marks[1].from)
      parent.append(label)
    } else if (node.name === 'Escape') {
      appendText(parent, source.slice(node.from + 1, node.to), node.from + 1)
    } else if (node.name === 'Image') {
      appendText(parent, source.slice(node.from, node.to), node.from)
    } else {
      appendRange(parent, node, node.from, node.to)
    }
  }
  element.replaceChildren()
  appendNode(element, tableInlineParser.parse(source).topNode)
}
