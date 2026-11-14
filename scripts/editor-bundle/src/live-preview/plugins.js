import { Decoration, EditorView, ViewPlugin, BlockWrapper } from "@codemirror/view"
import { EditorSelection, EditorState, RangeSetBuilder } from "@codemirror/state"
import { syntaxTree } from "@codemirror/language"
import { codeBlockWrappers } from "../decoration-parts.js"
import { documentFind } from "../find.js"
import { buildDecorations } from "./build-decorations.js"
import { pointerPreview } from "../pointer.js"
import { unwrappedCodeBlocks } from "../widgets/code.js"
import { TaskCheckboxWidget } from "../task-list.js"
import { TextWidget } from "../widgets/basic.js"

// A rendered list marker — checkbox, bullet or number — stands for its
// source (`- [ ] `, `- `, `1. `): the caret steps over it as one unit.
// Otherwise Right stops inside the hidden marker, where the caret looks like
// it follows the marker but typing comes out reversed in WebKit.
const LIST_MARKER_CLASSES = new Set(["cm-md-bullet", "cm-md-ordered"])
function listMarkerRanges(decorations) {
  const builder = new RangeSetBuilder()
  decorations.between(0, 1e9, (from, to, value) => {
    const widget = value.spec.widget
    if (widget instanceof TaskCheckboxWidget
        || (widget instanceof TextWidget && LIST_MARKER_CLASSES.has(widget.className))) {
      builder.add(from, to, value)
    }
  })
  return builder.finish()
}

export const livePreview = ViewPlugin.fromClass(class {
  constructor(view) {
    this.detectedCodeCache = new Map()
    this.decorations = buildDecorations(view, this.detectedCodeCache)
    this.codeWrappers = codeBlockWrappers(this.decorations, view.state)
    this.listMarkers = listMarkerRanges(this.decorations)
  }
  update(update) {
    if (update.docChanged) this.detectedCodeCache.clear()
    // Background parsing can finish without a document, selection, or viewport
    // change. Refresh widgets then too, or images can stay as source until input.
    if (update.docChanged || update.selectionSet || update.viewportChanged || update.focusChanged
        || update.startState.field(pointerPreview) !== update.state.field(pointerPreview)
        || update.startState.field(unwrappedCodeBlocks) !== update.state.field(unwrappedCodeBlocks)
        || syntaxTree(update.startState) !== syntaxTree(update.state)
        || update.startState.field(documentFind) !== update.state.field(documentFind)) {
      this.decorations = buildDecorations(update.view, this.detectedCodeCache)
      this.codeWrappers = codeBlockWrappers(this.decorations, update.state)
      this.listMarkers = listMarkerRanges(this.decorations)
    }
  }
}, {
  decorations: (v) => v.decorations,
  provide: plugin => [
    EditorView.blockWrappers.of(view => view.plugin(plugin)?.codeWrappers ?? BlockWrapper.set([])),
    EditorView.atomicRanges.of(view => view.plugin(plugin)?.listMarkers ?? Decoration.none),
  ],
})

// Line-start moves (Cmd-Left, Home, Ctrl-A) on a list line stop after the
// rendered marker. The marker is one atomic unit, so the plain command lands
// before it: the caret still draws beside the marker, but typing goes in
// front of the source and breaks the item.
export const stopAfterListMarker = (command) => (view) => {
  if (!command(view)) return false
  const markers = view.plugin(livePreview)?.listMarkers
  if (!markers) return true
  const { state } = view
  let moved = false
  const ranges = state.selection.ranges.map((range) => {
    const line = state.doc.lineAt(range.head)
    let markerEnd = -1
    markers.between(line.from, line.to, (from, to) => {
      if (from >= line.from && to <= line.to) markerEnd = to
    })
    if (markerEnd < 0 || range.head >= markerEnd) return range
    moved = true
    return range.empty
      ? EditorSelection.cursor(markerEnd)
      : EditorSelection.range(range.anchor, markerEnd)
  })
  if (moved) {
    view.dispatch({
      selection: EditorSelection.create(ranges, state.selection.mainIndex),
      scrollIntoView: true,
      userEvent: "select",
    })
  }
  return true
}

// The caret never rests in front of a rendered list marker (a click left of
// it, Up / Down landing at column 0, or a line-start move): there, typing
// would go before the marker's source and break the item. It lands after the
// marker instead.
const LIST_TEXT_START = /^((?:[ \t]{0,3}>[ \t]?)*[ \t]*)([-+*]|\d{1,9}[.)])[ \t](?:\[[ xX]\](?:[ \t]|$))?/
function listTextStart(state, line) {
  const match = LIST_TEXT_START.exec(line.text)
  if (!match) return null
  if (syntaxTree(state).resolveInner(line.from + match[1].length, 1).name !== "ListMark") return null
  return line.from + match[0].length
}

export const keepCaretAfterListMarker = EditorState.transactionFilter.of((tr) => {
  if (tr.docChanged || !tr.selection) return tr
  const state = tr.startState
  let moved = false
  const ranges = tr.newSelection.ranges.map((range) => {
    const line = state.doc.lineAt(range.head)
    const textStart = listTextStart(state, line)
    if (textStart == null || range.head >= textStart) return range
    moved = true
    return range.empty ? EditorSelection.cursor(textStart) : EditorSelection.range(range.anchor, textStart)
  })
  if (!moved) return tr
  return [tr, { selection: EditorSelection.create(ranges, tr.newSelection.mainIndex), sequential: true }]
})

// Left from the start of an item's text goes on to the end of the line
// above, as from the start of any line, instead of stopping at the marker.
export const leaveListMarkerBackward = (extend) => (view) => {
  const { state } = view
  if (state.selection.ranges.length > 1) return false
  const range = state.selection.main
  if (!extend && !range.empty) return false
  const line = state.doc.lineAt(range.head)
  if (line.number === 1 || listTextStart(state, line) !== range.head) return false
  const target = line.from - 1
  view.dispatch({
    selection: extend ? EditorSelection.range(range.anchor, target) : EditorSelection.cursor(target),
    scrollIntoView: true,
    userEvent: "select",
  })
  return true
}

// Align inactive headings with the document column. Active headings show
// their source prefix inline, with pointer selection anchored in source space.
export const alignInactiveHeadings = ViewPlugin.fromClass(class {
  constructor(view) { this.schedule(view) }

  update(update) {
    if (update.docChanged || update.selectionSet || update.viewportChanged
        || update.geometryChanged || update.focusChanged) {
      this.schedule(update.view)
    }
  }

  docViewUpdate(view) { this.schedule(view) }

  schedule(view) {
    view.requestMeasure({
      key: this,
      read(view) {
        return Array.from(view.dom.querySelectorAll(".cm-md-heading-prefix"))
          .map((marker) => {
            const line = marker.closest(".cm-line")
            return line ? { line, width: marker.getBoundingClientRect().width } : null
          })
          .filter(Boolean)
      },
      write(measurements) {
        for (const { line, width } of measurements) {
          const value = `${width}px`
          if (line.style.getPropertyValue("--cm-md-heading-prefix-width") !== value) {
            line.style.setProperty("--cm-md-heading-prefix-width", value)
          }
        }
      },
    })
  }
})
