import { HighlightStyle } from "@codemirror/language"
import { tags as t } from "@lezer/highlight"

// ---------------------------------------------------------------------------
// Syntax highlighting inside code fences (colors come from page CSS vars)
// ---------------------------------------------------------------------------

export const codeHighlight = HighlightStyle.define([
  { tag: [t.keyword, t.modifier, t.operatorKeyword, t.controlKeyword, t.definitionKeyword, t.moduleKeyword], class: "hl-keyword" },
  { tag: [t.string, t.special(t.string), t.regexp], class: "hl-string" },
  { tag: [t.comment, t.blockComment, t.lineComment], class: "hl-comment" },
  { tag: [t.number, t.integer, t.float, t.character], class: "hl-number" },
  { tag: [t.bool, t.atom, t.null], class: "hl-keyword" },
  { tag: [t.typeName, t.namespace], class: "hl-type" },
  { tag: [t.className, t.definition(t.typeName)], class: "hl-declaration" },
  { tag: [t.function(t.variableName), t.function(t.propertyName), t.macroName], class: "hl-function" },
  { tag: [t.propertyName, t.labelName], class: "hl-property" },
  { tag: t.attributeName, class: "hl-attribute" },
  { tag: [t.standard(t.variableName), t.standard(t.typeName)], class: "hl-builtin" },
  { tag: [t.meta, t.processingInstruction], class: "hl-meta" },
  { tag: [t.punctuation, t.operator], class: "hl-plain" },
])
