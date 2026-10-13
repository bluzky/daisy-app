import { WidgetType } from "@codemirror/view"

let mermaidWidgetID = 0

// The host page fetches Mermaid after first paint; a diagram rendered before
// then waits for it (window.__mdLoadMermaid). Null when it isn't available.
function loadMermaid() {
  const mermaid = window.mermaid
  if (mermaid && typeof mermaid.render === "function") return Promise.resolve(mermaid)
  if (typeof window.__mdLoadMermaid === "function") return window.__mdLoadMermaid()
  return Promise.resolve(null)
}

export class MermaidWidget extends WidgetType {
  constructor(source) { super(); this.source = source }
  eq(other) { return other.source === this.source }

  toDOM(view) {
    const figure = document.createElement("figure")
    figure.className = "cm-md-mermaid-preview"
    figure.setAttribute("role", "img")
    figure.setAttribute("aria-label", "Mermaid diagram. Click to edit source.")

    const stage = document.createElement("div")
    stage.className = "cm-md-mermaid-stage"
    stage.textContent = "Rendering diagram…"
    figure.appendChild(stage)

    figure.addEventListener("mousedown", (event) => {
      event.preventDefault()
      view.focus()
      // Land on the first source line, not the opening fence: the caret never
      // rests on a fence, and from below it would be bounced above the block.
      const opening = view.state.doc.lineAt(view.posAtDOM(figure))
      const anchor = opening.number < view.state.doc.lines
        ? view.state.doc.line(opening.number + 1).from
        : opening.to
      view.dispatch({
        selection: { anchor },
        userEvent: "select.pointer",
      })
    })

    loadMermaid()
      .then((mermaid) => {
        if (!mermaid || typeof mermaid.render !== "function") {
          stage.textContent = "Mermaid preview unavailable. Click to edit source."
          view.requestMeasure()
          return
        }
        const id = `md-editor-mermaid-${++mermaidWidgetID}`
        return Promise.resolve(mermaid.render(id, this.source)).then(({ svg }) => {
          stage.innerHTML = svg
          const diagram = stage.querySelector("svg")
          const box = diagram?.viewBox?.baseVal
          if (diagram && box?.width > 0 && box?.height > 0) {
            figure.style.setProperty("--mm-aspect", `${box.width} / ${box.height}`)
            figure.style.setProperty("--mm-natural-width", `${box.width}px`)
            diagram.removeAttribute("width")
            diagram.removeAttribute("height")
            diagram.setAttribute("preserveAspectRatio", "xMidYMid meet")
            diagram.style.width = "100%"
            diagram.style.height = "100%"
          }
          view.requestMeasure()
        })
      })
      .catch(() => {
        stage.textContent = "Unable to render Mermaid diagram. Click to edit source."
        figure.classList.add("cm-md-mermaid-error")
        view.requestMeasure()
      })
    return figure
  }

  ignoreEvent() { return true }
}
