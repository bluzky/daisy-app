import { syntaxTree } from "@codemirror/language"
import { detectLanguage } from "./languages.js"

export function fencedCodeDetails(state, node) {
  let info = ""
  let infoNode = null
  const codeMarks = []
  for (let child = node.node.firstChild; child; child = child.nextSibling) {
    if (child.name === "CodeInfo") {
      infoNode = child
      info = state.doc.sliceString(child.from, child.to)
    }
    if (child.name === "CodeMark") codeMarks.push(child)
  }

  const explicitLanguage = info.trim().split(/\s+/, 1)[0].toLowerCase()
  const openingLine = state.doc.lineAt(node.from)
  const openingMark = codeMarks[0]
  const sourceFrom = openingLine.to < state.doc.length ? openingLine.to + 1 : openingLine.to
  let sourceTo = node.to
  if (codeMarks.length > 1) sourceTo = state.doc.lineAt(codeMarks[codeMarks.length - 1].from).from
  const prefix = state.sliceDoc(openingLine.from, node.from)
  const indentation = /^ {0,3}$/.test(prefix) ? prefix.length : 0
  const textNodes = node.node.getChildren('CodeText')
  const source = textNodes.map((text, index) => {
    const gap = index ? state.doc.lineAt(text.from).number - state.doc.lineAt(textNodes[index - 1].to).number : 0
    return '\n'.repeat(gap) + state.sliceDoc(text.from, text.to)
  }).join('').replace(new RegExp('^ {0,' + indentation + '}', 'gm'), '')
  const detectedLanguage = explicitLanguage ? "" : detectLanguage(source)
  const infoFrom = infoNode?.from ?? openingMark?.to ?? openingLine.to
  const infoTo = infoNode?.to ?? infoFrom

  return {
    explicitLanguage,
    language: explicitLanguage || detectedLanguage,
    detectedLanguage,
    metadata: info.trim().split(/\s+/).slice(1).join(" "),
    rawInfo: info,
    infoFrom,
    infoTo,
    sourceFrom,
    source,
  }
}

export function fencedCodeAt(state, pos) {
  // Stay in the outer Markdown tree—the innermost mounted language tree does
  // not retain FencedCode as one of its parents.
  let node = syntaxTree(state).resolve(pos, -1)
  while (node) {
    if (node.name === "FencedCode") {
      return {
        from: node.from,
        to: node.to,
        closed: node.node.lastChild?.name === "CodeMark",
      }
    }
    node = node.parent
  }
  return null
}
