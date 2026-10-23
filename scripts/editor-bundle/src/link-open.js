import { EditorView } from "@codemirror/view"
import { Facet, Prec, StateEffect, StateField } from "@codemirror/state"
import { syntaxTree } from "@codemirror/language"

// Cmd+click opens a link: the host gets `onOpenLink({ destination })` with the
// destination as written, and resolves it the way a click in Read mode or the
// inspector does. A plain click still places the caret, and Cmd+click
// anywhere else keeps CodeMirror's behaviour (adding a cursor). Other kinds
// of text (metadata tokens) open through the `linkOpener` facet.
//
// While Cmd is held the editor has `cm-mod-held`, so a hovered link shows
// the pointer (it underlines on hover either way).

// Each opener is `(view, pos) => link | null`, with `link` passed to the host.
export const linkOpener = Facet.define()

// The destination of the inline link, autolink or bare URL at `pos`. Images,
// reference links and `#section` links give null.
export function linkDestinationAt(state, pos) {
  for (let node = syntaxTree(state).resolveInner(pos, 1); node; node = node.parent) {
    if (node.name === "Image") return null
    if (node.name === "Link" || node.name === "Autolink" || node.name === "URL") {
      const url = node.name === "URL" ? node : node.getChild("URL")
      if (!url) return null
      const destination = state.doc.sliceString(url.from, url.to).replace(/^<(.*)>$/s, "$1").trim()
      if (!destination || destination.startsWith("#")) return null
      // GFM autolinks: `www.` addresses open over http, email addresses as mail.
      if (node.name !== "Link") {
        if (/^www\./i.test(destination)) return "http://" + destination
        if (!/^[a-z][a-z0-9+.-]*:/i.test(destination) && destination.includes("@")) return "mailto:" + destination
      }
      return destination
    }
  }
  return null
}

export function linkAt(view, pos) {
  for (const opener of view.state.facet(linkOpener)) {
    const link = opener(view, pos)
    if (link) return link
  }
  const destination = linkDestinationAt(view.state, pos)
  return destination ? { destination } : null
}

// Sends the link at `pos` to the host; returns it, or null when there is none.
export function openLinkAt(view, pos, callbacks) {
  const link = linkAt(view, pos)
  if (link && callbacks && callbacks.onOpenLink) callbacks.onOpenLink(link)
  return link
}

// Kept in state so the class goes through `editorAttributes`, which owns
// the editor's class attribute.
const modifierHeldChanged = StateEffect.define()
const modifierHeld = StateField.define({
  create: () => false,
  update(held, transaction) {
    for (const effect of transaction.effects) if (effect.is(modifierHeldChanged)) held = effect.value
    return held
  },
  provide: (field) => EditorView.editorAttributes.from(field, (held) => (held ? { class: "cm-mod-held" } : {})),
})

function setModifierHeld(view, held) {
  if (view.state.field(modifierHeld) !== held) view.dispatch({ effects: modifierHeldChanged.of(held) })
}

export function linkOpening(callbacks) {
  return [
    Prec.highest(EditorView.domEventHandlers({
      mousedown(event, view) {
        if (event.button !== 0 || !event.metaKey || event.shiftKey || event.altKey || event.ctrlKey) return false
        const pos = view.posAtCoords({ x: event.clientX, y: event.clientY }, false)
        if (pos == null) return false
        if (!openLinkAt(view, pos, callbacks)) return false
        event.preventDefault()
        return true
      },
      keydown(event, view) { setModifierHeld(view, event.metaKey || event.key === "Meta") },
      keyup(event, view) { setModifierHeld(view, event.metaKey && event.key !== "Meta") },
      mousemove(event, view) { setModifierHeld(view, event.metaKey) },
      blur(_event, view) { setModifierHeld(view, false) },
    })),
    modifierHeld,
  ]
}
