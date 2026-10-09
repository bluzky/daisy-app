import { EditorView, ViewPlugin, BlockWrapper } from "@codemirror/view"
import { syntaxTree } from "@codemirror/language"
import { codeBlockWrappers } from "../decoration-parts.js"
import { documentFind } from "../find.js"
import { buildDecorations } from "./build-decorations.js"
import { pointerPreview } from "../pointer.js"
import { wrappedCodeBlocks } from "../widgets/code.js"

export const livePreview = ViewPlugin.fromClass(class {
  constructor(view) {
    this.detectedCodeCache = new Map()
    this.decorations = buildDecorations(view, this.detectedCodeCache)
    this.codeWrappers = codeBlockWrappers(this.decorations, view.state)
  }
  update(update) {
    if (update.docChanged) this.detectedCodeCache.clear()
    // Background parsing can finish without a document, selection, or viewport
    // change. Refresh widgets then too, or images can stay as source until input.
    if (update.docChanged || update.selectionSet || update.viewportChanged || update.focusChanged
        || update.startState.field(pointerPreview) !== update.state.field(pointerPreview)
        || update.startState.field(wrappedCodeBlocks) !== update.state.field(wrappedCodeBlocks)
        || syntaxTree(update.startState) !== syntaxTree(update.state)
        || update.startState.field(documentFind) !== update.state.field(documentFind)) {
      this.decorations = buildDecorations(update.view, this.detectedCodeCache)
      this.codeWrappers = codeBlockWrappers(this.decorations, update.state)
    }
  }
}, {
  decorations: (v) => v.decorations,
  provide: plugin => EditorView.blockWrappers.of(view => view.plugin(plugin)?.codeWrappers ?? BlockWrapper.set([])),
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
