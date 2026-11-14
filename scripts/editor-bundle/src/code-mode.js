import { EditorView, keymap, dropCursor, lineNumbers, highlightActiveLine } from "@codemirror/view"
import { defaultKeymap, history, historyKeymap, indentWithTab } from "@codemirror/commands"
import { closeBrackets, closeBracketsKeymap } from "@codemirror/autocomplete"
import { LanguageDescription, indentUnit, syntaxHighlighting } from "@codemirror/language"
import { codeHighlight } from "./code-highlight.js"
import { documentFind, findTheme } from "./find.js"
import { codeLanguages } from "./languages.js"

// ---------------------------------------------------------------------------
// Code-only editing
//
// Source and text files edit as plain code: no live preview, tables, slash
// commands, formatting shortcuts or rich-text paste conversion. The editor
// shares everything else with the Markdown editor (find and replace, scroll
// anchors, host bridge) because it is the same `create()`; only the extension
// list differs. The language is a fence name or alias, "" for plain text.
// ---------------------------------------------------------------------------

// ⌘[ and ⌘] are the app's Back and Forward, so CodeMirror's indent bindings
// for them must not swallow the keys; Tab and Shift-Tab indent instead.
export const editorDefaultKeymap = defaultKeymap.filter(
  (binding) => binding.key !== "Mod-[" && binding.key !== "Mod-]",
)

export function codeModeExtensions(language) {
  const description = language
    ? LanguageDescription.matchLanguageName(codeLanguages, language, true)
    : null
  return [
    history(),
    documentFind,
    findTheme,
    dropCursor(),
    EditorView.lineWrapping,
    indentUnit.of("    "),
    lineNumbers(),
    highlightActiveLine(),
    description ? description.support : [],
    syntaxHighlighting(codeHighlight),
    closeBrackets(),
    keymap.of([
      indentWithTab,
      ...closeBracketsKeymap,
      ...editorDefaultKeymap,
      ...historyKeymap,
    ]),
  ]
}
