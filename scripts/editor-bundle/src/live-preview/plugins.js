import { Decoration, EditorView, ViewPlugin, BlockWrapper } from "@codemirror/view"
import { RangeSetBuilder } from "@codemirror/state"
import { syntaxTree } from "@codemirror/language"
import { codeBlockWrappers } from "../decoration-parts.js"
import { documentFind } from "../find.js"
import { buildDecorations } from "./build-decorations.js"
import { pointerPreview } from "../pointer.js"
import { unwrappedCodeBlocks } from "../widgets/code.js"
import { TaskCheckboxWidget } from "../task-list.js"

// A rendered checkbox stands for `- [ ] `: the caret steps over it as one
// unit. Otherwise Right stops inside the hidden marker, where the caret looks
// like it follows the checkbox but typing comes out reversed in WebKit.
function taskMarkerRanges(decorations) {
  const builder = new RangeSetBuilder()
  decorations.between(0, 1e9, (from, to, value) => {
    if (value.spec.widget instanceof TaskCheckboxWidget) builder.add(from, to, value)
  })
  return builder.finish()
}

export const livePreview = ViewPlugin.fromClass(class {
  constructor(view) {
    this.detectedCodeCache = new Map()
    this.decorations = buildDecorations(view, this.detectedCodeCache)
    this.codeWrappers = codeBlockWrappers(this.decorations, view.state)
    this.taskMarkers = taskMarkerRanges(this.decorations)
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
      this.taskMarkers = taskMarkerRanges(this.decorations)
    }
  }
}, {
  decorations: (v) => v.decorations,
  provide: plugin => [
    EditorView.blockWrappers.of(view => view.plugin(plugin)?.codeWrappers ?? BlockWrapper.set([])),
    EditorView.atomicRanges.of(view => view.plugin(plugin)?.taskMarkers ?? Decoration.none),
  ],
})

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
