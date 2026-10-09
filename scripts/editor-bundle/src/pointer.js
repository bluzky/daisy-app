import { EditorView, ViewPlugin } from "@codemirror/view"
import { EditorSelection, StateEffect, StateField } from "@codemirror/state"
import { fencedCodeAt } from "./fenced-code.js"

// Snapshot only the state that controls source visibility during a gesture.
const setPointerPreview = StateEffect.define()
export const pointerPreview = StateField.define({
  create: () => null,
  update(value, tr) {
    // Typing, paste, or an external document update ends the visual snapshot.
    if (tr.docChanged) return null
    for (const effect of tr.effects) {
      if (effect.is(setPointerPreview)) return effect.value
    }
    if (value?.activateOnSelection && tr.isUserEvent('select.pointer')) {
      return { selection: tr.state.selection.main, focused: true,
        fence: tr.state.field(activeCodeBlock), activateOnSelection: false }
    }
    return value
  },
})

// Capture before CodeMirror focuses the editor or changes its selection.
// Keep source-reveal decisions stable, not the entire decoration set: viewport
// changes during auto-scroll must still render newly visible content.
export const stablePointerPreview = ViewPlugin.fromClass(class {
  constructor(view) {
    this.view = view
    this.releaseTimer = null
    this.down = (event) => {
      if (event.button !== 0 || event.target.closest('input, textarea, button, select, .cm-md-table-widget')) return
      clearTimeout(this.releaseTimer)
      if (view.state.field(pointerPreview)) return
      view.dispatch({ effects: setPointerPreview.of({
        selection: view.state.selection.main,
        focused: view.hasFocus,
        fence: view.state.field(activeCodeBlock),
        activateOnSelection: event.detail === 1 && !event.shiftKey && !event.metaKey && !event.ctrlKey && !event.altKey,
      }) })
    }
    this.finish = () => {
      if (!view.state.field(pointerPreview)) return
      clearTimeout(this.releaseTimer)
      // CodeMirror's document mouseup listener must finish selecting first.
      this.releaseTimer = setTimeout(() => this.release(), 0)
    }
    this.release = () => {
      clearTimeout(this.releaseTimer)
      if (view.state.field(pointerPreview)) {
        view.dispatch({ effects: setPointerPreview.of(null) })
      }
    }
    this.move = (event) => { if (event.buttons === 0) this.finish() }
    view.contentDOM.addEventListener('mousedown', this.down, true)
    view.contentDOM.addEventListener('keydown', this.release, true)
    view.dom.ownerDocument.addEventListener('mouseup', this.finish)
    view.dom.ownerDocument.addEventListener('mousemove', this.move)
    view.dom.ownerDocument.addEventListener('dragend', this.finish)
    view.win.addEventListener('blur', this.finish)
  }
  destroy() {
    clearTimeout(this.releaseTimer)
    const view = this.view
    view.contentDOM.removeEventListener('mousedown', this.down, true)
    view.contentDOM.removeEventListener('keydown', this.release, true)
    view.dom.ownerDocument.removeEventListener('mouseup', this.finish)
    view.dom.ownerDocument.removeEventListener('mousemove', this.move)
    view.dom.ownerDocument.removeEventListener('dragend', this.finish)
    view.win.removeEventListener('blur', this.finish)
  }
})

// Capture the source position before the first selection reveals syntax.
// Reusing the same screen coordinates after that reveal would hit a different
// character. Only real dragging should start hit-testing the new layout.
export const anchoredPointerSelection = EditorView.mouseSelectionStyle.of((view, event) => {
  if (event.button !== 0 || event.detail !== 1 || event.shiftKey || event.metaKey || event.ctrlKey || event.altKey) return null
  let anchor = view.posAtCoords({ x: event.clientX, y: event.clientY })
  if (anchor == null) return null
  let dragged = false
  return {
    update(update) { anchor = update.changes.mapPos(anchor) },
    get(current) {
      dragged ||= Math.hypot(current.clientX - event.clientX, current.clientY - event.clientY) > 3
      const head = dragged ? view.posAtCoords({ x: current.clientX, y: current.clientY }, false) ?? anchor : anchor
      return EditorSelection.single(anchor, head)
    },
  }
})

// A cursor exists at offset zero as soon as CodeMirror is created. Do not let
// that implicit cursor put a leading code block into source mode. A fenced
// block becomes active only after a pointer selection lands inside it.
export const activeCodeBlock = StateField.define({
  create: () => null,
  update(value, tr) {
    if (value && tr.docChanged) {
      value = {
        from: tr.changes.mapPos(value.from, 1),
        to: tr.changes.mapPos(value.to, -1),
      }
    }

    const selection = tr.state.selection.main
    if (!selection.empty) return null

    const head = selection.head
    if (tr.isUserEvent("select.pointer")) return fencedCodeAt(tr.state, head)
    // A fence authored from plain text has no prior active range. Resolve it
    // after input so its source stays editable as soon as the opening marker
    // becomes valid, including while a Mermaid block is being typed.
    if (!value && tr.docChanged && tr.isUserEvent("input")) {
      return fencedCodeAt(tr.state, head)
    }
    if (!value) return null
    if (head < value.from || head > value.to) return null

    if (tr.docChanged) return fencedCodeAt(tr.state, head) || value
    return value
  },
})
