import { WidgetType } from "@codemirror/view"
import { MapMode, StateEffect, StateField } from "@codemirror/state"
import { syntaxTree } from "@codemirror/language"
import { fencedCodeDetails } from "../fenced-code.js"

// Language input widget for every fenced block, including blocks without an
// info string. The source range is rebuilt after each commit, so the widget
// remains anchored while its input edits the opening line.
export const codeCopyHandlers = new WeakMap()
const toggleCodeWrap = StateEffect.define({ map: (pos, changes) => changes.mapPos(pos, 1, MapMode.TrackAfter) ?? undefined })
export const wrappedCodeBlocks = StateField.define({
  create: () => new Set(),
  update(value, tr) {
    if (!tr.docChanged && !tr.effects.some(e => e.is(toggleCodeWrap))) return value
    const next = new Set([...value].map(pos => tr.changes.mapPos(pos, 1, MapMode.TrackAfter)).filter(pos => pos != null))
    for (const effect of tr.effects) if (effect.is(toggleCodeWrap)) {
      if (next.has(effect.value)) next.delete(effect.value)
      else next.add(effect.value)
    }
    return next
  },
})
const codeActionIcon = (kind) => '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + ({
  copy: '<rect x="4" y="8" width="12" height="13" rx="3"/><path d="M8 8V6a3 3 0 0 1 3-3h6a3 3 0 0 1 3 3v9a3 3 0 0 1-3 3h-1"/>',
  check: '<path d="m5 12 4 4L19 6"/>',
  wrap: '<path d="M4 6h16M4 11h12a4 4 0 0 1 0 8h-5m3-3-3 3 3 3M4 16h3"/>',
  unwrap: '<path d="M4 6h16M4 12h16m-4-4 4 4-4 4M4 18h7"/>'
})[kind] + '</svg>'

export class CodeLanguageWidget extends WidgetType {
  constructor(details) {
    super()
    Object.assign(this, details)
  }

  eq(other) {
    return other.fenceFrom === this.fenceFrom
      && other.infoFrom === this.infoFrom
      && other.infoTo === this.infoTo
      && other.rawInfo === this.rawInfo
      && other.detectedLanguage === this.detectedLanguage
      && other.wrapped === this.wrapped
      && other.plain === this.plain
  }

  toDOM(view) {
    const container = document.createElement("span")
    container.className = "cm-md-code-language"
    container.contentEditable = "false"

    const input = document.createElement("input")
    input.type = "text"
    input.className = "cm-md-code-language-input"
    input.autocomplete = "off"
    input.spellcheck = false
    input.value = this.language
    input.readOnly = !!this.plain
    input.placeholder = "language"
    input.setAttribute("aria-label", "Code block language")
    input.dataset.fenceFrom = String(this.fenceFrom)

    const metadata = this.rawInfo.match(/^\S+([\s\S]*)$/)?.[1] || ""
    const initialDisplayValue = input.value
    let commitOnBlur = true
    let dispatchingCommit = false
    const commit = () => {
      if (this.plain) return
      const language = input.value.trim().split(/\s+/, 1)[0].toLowerCase()
      const nextInfo = language
        ? language + metadata
        : ""
      if (nextInfo === this.rawInfo) return
      if (input.value === initialDisplayValue) return
      dispatchingCommit = true
      view.dispatch({
        changes: { from: this.infoFrom, to: this.infoTo, insert: nextInfo },
        userEvent: "input",
      })
    }

    input.addEventListener("change", commit)
    input.addEventListener("keydown", (event) => {
      event.stopPropagation()
      if (event.key === "Enter") {
        event.preventDefault()
        commit()
        input.blur()
        view.focus()
      } else if (event.key === "Escape") {
        event.preventDefault()
        commitOnBlur = false
        input.value = this.language
        input.blur()
        view.focus()
      }
    })
    input.addEventListener("mousedown", (event) => event.stopPropagation())
    input.addEventListener("click", (event) => event.stopPropagation())
    input.addEventListener("blur", () => {
      if (commitOnBlur && !dispatchingCommit) commit()
      dispatchingCommit = false
      commitOnBlur = true
    })

    container.appendChild(input)
    const action = (label, icon, className, run) => {
      const button = document.createElement('button')
      button.type = 'button'
      button.className = `cm-md-code-action ${className}`
      button.title = label
      button.setAttribute('aria-label', label)
      button.innerHTML = codeActionIcon(icon)
      button.addEventListener('mousedown', event => { event.preventDefault(); event.stopPropagation() })
      button.addEventListener('click', event => { event.preventDefault(); event.stopPropagation(); run(button) })
      container.appendChild(button)
      return button
    }
    const toggle = action(this.wrapped ? 'Unwrap code' : 'Wrap code', this.wrapped ? 'unwrap' : 'wrap',
      'cm-md-code-toggle-wrap', () => view.dispatch({
        effects: toggleCodeWrap.of(view.state.doc.lineAt(this.fenceFrom).from),
      }))
    toggle.setAttribute('aria-pressed', String(this.wrapped))
    action('Copy code', 'copy', 'cm-md-code-copy', async button => {
      const line = view.state.doc.lineAt(this.fenceFrom)
      let node = syntaxTree(view.state).resolve(this.plain ? line.to : this.fenceFrom + 1, -1)
      while (node && node.name !== (this.plain ? 'CodeBlock' : 'FencedCode')) node = node.parent
      if (!node) return
      const source = this.plain
        ? node.getChildren('CodeText').map(text => view.state.sliceDoc(text.from, text.to)).join('')
        : fencedCodeDetails(view.state, node).source
      try {
        const handler = codeCopyHandlers.get(view)
        if (handler) handler(source)
        else await navigator.clipboard.writeText(source)
        button.innerHTML = codeActionIcon('check')
        button.title = 'Code copied'
        button.setAttribute('aria-label', button.title)
        clearTimeout(button.copyTimer)
        button.copyTimer = setTimeout(() => {
          button.innerHTML = codeActionIcon('copy')
          button.title = 'Copy code'
          button.setAttribute('aria-label', button.title)
        }, 1100)
      } catch (_) { /* Leave the copy action available when the clipboard is unavailable. */ }
    })
    return container
  }

  ignoreEvent() { return true }
}
