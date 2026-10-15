import { ViewPlugin } from "@codemirror/view"

// Publishes the width code blocks scroll within as --code-card-width. Their
// cards used to be CSS size containers (cqw units), but WebKit then kept
// re-laying them out while scrolling a long block, and the page could never
// scroll past the first screens of it.
export const codeCardWidth = ViewPlugin.fromClass(class {
  constructor(view) {
    this.view = view
    this.width = -1
    this.observer = new ResizeObserver(() => this.sync())
    this.observer.observe(view.contentDOM)
    this.sync()
  }

  sync() {
    const style = getComputedStyle(this.view.contentDOM)
    const width = this.view.contentDOM.clientWidth
      - (parseFloat(style.paddingLeft) || 0) - (parseFloat(style.paddingRight) || 0)
    if (width <= 0 || width === this.width) return
    this.width = width
    this.view.dom.style.setProperty('--code-card-width', width + 'px')
  }

  destroy() {
    this.observer.disconnect()
  }
})
