import { EditorView } from "@codemirror/view"
import { Prec } from "@codemirror/state"
import { mermaidPreviews } from "./mermaid-previews.js"

// ---------------------------------------------------------------------------
// Editor extensions
//
// Optional editor behaviour that pairs with a render extension of the same id
// (see MarkdownRenderExtension.editor on the Swift side). Each module lives in
// its own compartment so the host can switch it on and off in one transaction
// without recreating the editor, losing the selection or clearing undo history.
// Core editing (history, keymaps, live preview) is deliberately not a module.
// ---------------------------------------------------------------------------

export const editorModules = new Map()

// `precedence` wraps the module's extensions so behaviour never depends on
// registration order: "lowest" | "default" | "highest".
export function registerEditorExtension({ id, extensions, precedence = "default" }) {
  if (editorModules.has(id)) throw new Error(`Editor extension "${id}" registered twice`)
  editorModules.set(id, { id, extensions, precedence })
}

export function editorModuleExtensions(module, options, host) {
  const extensions = module.extensions(options || {}, host || {})
  switch (module.precedence) {
    case "lowest": return Prec.lowest(extensions)
    case "highest": return Prec.highest(extensions)
    default: return extensions
  }
}

// A module the host says nothing about stays on, so headless hosts that pass
// no state keep the full editor.
export const editorModuleEnabled = (state, id) => !state || state[id] !== false

registerEditorExtension({ id: "mermaid", extensions: () => [mermaidPreviews] })

// Heading lines already carry cm-md-h1..h6; the host stylesheet colors them
// only under this class, so toggling the module is a single attribute change.
registerEditorExtension({
  id: "colorful-headings",
  extensions: () => [EditorView.editorAttributes.of({ class: "cm-colorful-headings" })],
})
