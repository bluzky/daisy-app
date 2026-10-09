import { WidgetType } from "@codemirror/view"

// ---------------------------------------------------------------------------
// Live preview decorations
// ---------------------------------------------------------------------------

export class TextWidget extends WidgetType {
  constructor(text, className) { super(); this.text = text; this.className = className }
  eq(other) { return other.text === this.text && other.className === this.className }
  toDOM() {
    const span = document.createElement("span")
    span.textContent = this.text
    span.className = this.className
    return span
  }
  ignoreEvent() { return false }
}

export class ImageWidget extends WidgetType {
  constructor(source, alt, raw, from, to) {
    super()
    this.source = source
    this.alt = alt
    this.raw = raw
    this.from = from
    this.to = to
  }

  eq(other) {
    return other.source === this.source
      && other.alt === this.alt
      && other.raw === this.raw
      && other.from === this.from
      && other.to === this.to
  }

  toDOM(view) {
    const root = document.createElement("span")
    root.className = "cm-md-image-preview"
    root.setAttribute("role", "figure")

    const image = document.createElement("img")
    image.src = this.source
    image.alt = this.alt
    image.draggable = false
    image.addEventListener("error", () => root.classList.add("cm-md-image-error"), { once: true })

    const source = document.createElement("code")
    source.className = "cm-md-image-source"
    source.textContent = this.raw
    source.title = "Click to edit image source"

    const revealSource = (event) => {
      event.preventDefault()
      event.stopPropagation()
      view.focus()
      view.dispatch({
        selection: { anchor: Math.min(this.from + 2, this.to) },
        userEvent: "select.pointer",
      })
    }
    source.addEventListener("mousedown", revealSource)
    source.addEventListener("click", revealSource)
    image.addEventListener("mousedown", (event) => {
      event.preventDefault()
      event.stopPropagation()
    })
    image.addEventListener("click", (event) => {
      event.preventDefault()
      event.stopPropagation()
      const resolved = image.currentSrc || image.src
      if (resolved.startsWith("md-asset:")) {
        window.__mdRequestImageRename?.(resolved)
      } else {
        revealSource(event)
      }
    })

    root.append(image, source)
    return root
  }

  ignoreEvent() { return true }
}

export class RuleWidget extends WidgetType {
  eq() { return true }
  toDOM() {
    const el = document.createElement("span")
    el.className = "cm-md-hr"
    return el
  }
  ignoreEvent() { return false }
}
