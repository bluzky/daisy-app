import { WidgetType } from "@codemirror/view"
import { WIDGET_LANGUAGES } from "../fenced-code.js"

// ---------------------------------------------------------------------------
// Widgets (stat tiles, charts, progress, shortcodes) drawn in the editor.
//
// Nothing here draws a widget: the Read mode widget script does, through
// `window.MdWidgets` (`MarkdownHTML.widgetScript`), so a widget looks the
// same in both and one parser decides what is a widget. A page without the
// script (headless hosts, the smoke tests) shows the source as code.
// ---------------------------------------------------------------------------

export const mdWidgets = () => (typeof window !== "undefined" && window.MdWidgets) || null

// Whether a source is a widget, kept for the keys the latest build used, so
// an unchanged block isn't built again on every transaction and the cache
// doesn't grow. Only the answer is kept, never the node: a chart built while
// detached loses its resize observer, so `toDOM` builds a fresh one.
export class ValidityCache {
  constructor() { this.previous = new Map(); this.current = new Map() }
  begin() {
    this.previous = this.current
    this.current = new Map()
  }
  get(key, compute) {
    if (this.current.has(key)) return this.current.get(key)
    const value = this.previous.has(key) ? this.previous.get(key) : compute()
    this.current.set(key, value)
    return value
  }
}

// Whether a code span's content has CommonMark's single padding space on
// both sides, which isn't part of it.
export const isCodePadded = (raw) => raw.startsWith(" ") && raw.endsWith(" ") && /[^ ]/.test(raw)

// Whether a code span's content has a shortcode's `{{…}}` shape.
export const looksLikeShortcode = (text) => text.startsWith("{{") && text.endsWith("}}")

// The fence preview begins a block build; live preview an inline one.
export const blockValidity = new ValidityCache()
export const inlineValidity = new ValidityCache()

// Whether a fence (`fencedCodeDetails`) is drawn as a widget: its language
// is a widget's and the widget script reads its source.
export function isWidgetBlock(details) {
  const language = details.explicitLanguage
  const api = mdWidgets()
  if (!api || !WIDGET_LANGUAGES.includes(language)) return false
  return blockValidity.get(language + "\n" + details.source,
    () => api.block(language, details.source) != null)
}

// Whether a shortcode (`{{name: …}}`) is drawn as a widget.
export function isInlineWidget(text) {
  const api = mdWidgets()
  if (!api) return false
  return inlineValidity.get(text, () => api.inline(text) != null)
}

// A widget's height changes after it is drawn (a chart redraws at its real
// width), so the editor remeasures whenever the box resizes.
const resizeObservers = new WeakMap()
function watchSize(view, dom) {
  if (typeof ResizeObserver !== "function") return
  const observer = new ResizeObserver(() => view.requestMeasure())
  observer.observe(dom)
  resizeObservers.set(dom, observer)
}
function unwatchSize(dom) {
  resizeObservers.get(dom)?.disconnect()
  resizeObservers.delete(dom)
}

// A stat's `link:` is an `<a href>`; the editor page has no navigation
// policy, so a click must never follow it.
function preventNavigation(dom) {
  dom.addEventListener("click", (event) => {
    event.preventDefault()
    event.stopPropagation()
  }, true)
}

export class WidgetBlockWidget extends WidgetType {
  constructor(language, source) { super(); this.language = language; this.source = source }
  eq(other) { return other.language === this.language && other.source === this.source }

  toDOM(view) {
    const box = document.createElement("div")
    box.className = "cm-md-widget-preview"
    box.setAttribute("aria-label", `${this.language} widget. Click to edit source.`)
    const api = mdWidgets()
    const node = api?.block(this.language, this.source)
    if (node) {
      box.append(node)
      api.animate(node)
    }
    preventNavigation(box)
    box.addEventListener("mousedown", (event) => {
      event.preventDefault()
      view.focus()
      // Land on the first source line, not the opening fence, as a click on
      // a Mermaid diagram does.
      const opening = view.state.doc.lineAt(view.posAtDOM(box))
      const anchor = opening.number < view.state.doc.lines
        ? view.state.doc.line(opening.number + 1).from
        : opening.to
      view.dispatch({ selection: { anchor }, userEvent: "select.pointer" })
    })
    watchSize(view, box)
    view.requestMeasure()
    return box
  }

  destroy(dom) { unwatchSize(dom) }

  ignoreEvent() { return true }
}

// The box around a drawn shortcode's node, in running text or a table cell.
export function inlineWidgetBox(node) {
  const box = document.createElement("span")
  box.className = "cm-md-widget-inline"
  if (node) {
    box.append(node)
    mdWidgets().animate(node)
  }
  return box
}

export class WidgetInlineWidget extends WidgetType {
  // `text` is the code span's content; equal text draws the same widget, so
  // an edit elsewhere on the line doesn't redraw it.
  constructor(text) { super(); this.text = text }
  eq(other) { return other.text === this.text }

  toDOM(view) {
    const span = inlineWidgetBox(mdWidgets()?.inline(this.text))
    preventNavigation(span)
    span.addEventListener("mousedown", (event) => {
      event.preventDefault()
      event.stopPropagation()
      view.focus()
      // Just inside the code span: past its opening backticks.
      const from = view.posAtDOM(span)
      const line = view.state.doc.lineAt(from)
      const ticks = /^`+/.exec(line.text.slice(from - line.from))
      view.dispatch({
        selection: { anchor: Math.min(from + (ticks ? ticks[0].length : 1), line.to) },
        userEvent: "select.pointer",
      })
    })
    return span
  }

  ignoreEvent() { return true }
}
