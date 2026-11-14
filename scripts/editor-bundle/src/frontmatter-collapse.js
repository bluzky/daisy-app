import { Decoration, EditorView, WidgetType } from "@codemirror/view"
import { EditorState, StateEffect, StateField } from "@codemirror/state"

// The leading `---` block is collapsed to one "Properties" row until the
// reader opens it. Only the view changes; the YAML stays in the document.

export const setFrontmatterExpanded = StateEffect.define()

export const frontmatterExpanded = StateField.define({
  create: () => false,
  update(value, transaction) {
    for (const effect of transaction.effects) {
      if (effect.is(setFrontmatterExpanded)) value = effect.value
    }
    return value
  },
})

// The same block `yamlFrontmatter` parses: `---` on the first line, closed by
// another `---`. An unclosed block is left as it is.
export function frontmatterBounds(doc) {
  if (doc.lines < 2 || doc.line(1).text.replace(/^﻿/, "").trim() !== "---") return null
  for (let number = 2; number <= doc.lines; number++) {
    if (doc.line(number).text.trim() === "---") return { to: doc.line(number).to, lastLine: number }
  }
  return null
}

const TOP_LEVEL_KEY = /^([^\s#:\-[\]{},&*!|>'"%@`][^:]*?)\s*:/u

function frontmatterKeys(doc, bounds) {
  const keys = []
  for (let number = 2; number < bounds.lastLine; number++) {
    const key = TOP_LEVEL_KEY.exec(doc.line(number).text)
    if (key) keys.push(key[1])
  }
  return keys
}

class FrontmatterWidget extends WidgetType {
  constructor(keys, expanded) {
    super()
    this.keys = keys
    this.expanded = expanded
  }
  eq(other) {
    return other.expanded === this.expanded && other.keys.join("\n") === this.keys.join("\n")
  }
  toDOM(view) {
    const header = document.createElement("div")
    header.className = "cm-md-frontmatter-header" + (this.expanded ? " is-expanded" : "")
    header.setAttribute("role", "button")
    header.setAttribute("aria-expanded", String(this.expanded))
    header.setAttribute("aria-label", this.expanded ? "Collapse properties" : "Expand properties")

    const chevron = document.createElement("span")
    chevron.className = "cm-md-frontmatter-chevron"
    chevron.textContent = this.expanded ? "▾" : "▸"
    const label = document.createElement("span")
    label.className = "cm-md-frontmatter-label"
    label.textContent = "Properties"
    header.append(chevron, label)

    if (!this.expanded && this.keys.length) {
      const summary = document.createElement("span")
      summary.className = "cm-md-frontmatter-summary"
      summary.textContent = this.keys.join(", ")
      header.append(summary)
    }

    header.addEventListener("mousedown", (event) => {
      event.preventDefault()
      toggleFrontmatter(view)
    })
    return header
  }
  ignoreEvent() { return true }
}

function toggleFrontmatter(view) {
  const { state } = view
  const expand = !state.field(frontmatterExpanded)
  const spec = { effects: setFrontmatterExpanded.of(expand) }
  const bounds = frontmatterBounds(state.doc)
  // A caret inside the block would be hidden with it: move it to the body.
  if (!expand && bounds && state.selection.ranges.some((range) => range.from <= bounds.to)) {
    spec.selection = { anchor: Math.min(bounds.to + 1, state.doc.length) }
  }
  view.dispatch(spec)
}

function buildFrontmatter(state) {
  const bounds = frontmatterBounds(state.doc)
  if (!bounds) return Decoration.none
  const keys = frontmatterKeys(state.doc, bounds)
  if (state.field(frontmatterExpanded)) {
    return Decoration.set([
      Decoration.widget({ block: true, side: -1, widget: new FrontmatterWidget(keys, true) }).range(0),
    ])
  }
  return Decoration.set([
    Decoration.replace({ block: true, widget: new FrontmatterWidget(keys, false) }).range(0, bounds.to),
  ])
}

const frontmatterDecorations = StateField.define({
  create: buildFrontmatter,
  update: (value, transaction) => transaction.docChanged
    || transaction.effects.some((effect) => effect.is(setFrontmatterExpanded))
    ? buildFrontmatter(transaction.state) : value,
  provide: (field) => [
    EditorView.decorations.from(field),
    EditorView.atomicRanges.of((view) => view.state.field(field)),
  ],
})

// Typing at the edge of a collapsed block, or deleting into it, would change
// text the reader can't see. Edits that replace the whole block still go
// through, as do programmatic ones such as a reload from disk.
const protectCollapsedFrontmatter = EditorState.transactionFilter.of((transaction) => {
  if (!transaction.docChanged
      || !(transaction.isUserEvent("input") || transaction.isUserEvent("delete"))) return transaction
  const { startState } = transaction
  if (startState.field(frontmatterExpanded)) return transaction
  const bounds = frontmatterBounds(startState.doc)
  if (!bounds) return transaction
  let blocked = false
  transaction.changes.iterChanges((from, to, _fromB, _toB, inserted) => {
    const replacesBlock = from <= 0 && to >= bounds.to
    // New lines after the closing `---` leave it intact (the journal appends
    // an entry this way when the note holds only frontmatter).
    const startsAfterBlock = from === to && from === bounds.to && inserted.sliceString(0, 1) === "\n"
    if (from <= bounds.to && !replacesBlock && !startsAfterBlock) blocked = true
  })
  return blocked ? [] : transaction
})

export const frontmatterCollapse = [frontmatterExpanded, frontmatterDecorations, protectCollapsedFrontmatter]
