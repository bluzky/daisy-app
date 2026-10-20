// Editor smoke tests: code-only mode for source and text files.
import { dom, check } from "./harness.mjs"

const host = dom.window.document.createElement("div")
dom.window.document.body.appendChild(host)
const source = "# not a heading\nlet value = 1 // note\n| a | b |\n|---|---|\n"
let dirty = 0
let lastFind
const editor = dom.window.MDEditor.create(host, source, {
  codeLanguage: "swift",
  onDirty: () => dirty++,
  onSearchChange: (result) => { lastFind = result },
})
check("code mode keeps the document byte for byte", editor.getMarkdown() === source)
check("code mode shows line numbers", host.querySelector(".cm-lineNumbers") != null)
check("code mode applies no Markdown live preview", host.querySelector(".cm-md-h1, .cm-md-table, [class*=cm-md-]") == null)
check("a Markdown heading marker is plain text", host.querySelector(".cm-line")?.textContent === "# not a heading")
check("highlighting follows the language", host.querySelector(".hl-keyword") != null)
editor.insertTextAt("x", 0, 0)
check("edits mark the document dirty", dirty === 1)
check("code mode find counts matches", editor.find("value").total === 1)
check("code mode replace all rewrites matches",
  editor.replaceAll("count", "value").replaced === 1 && editor.getMarkdown().includes("let count = 1"))
editor.destroy()

const elixirHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(elixirHost)
const elixirEditor = dom.window.MDEditor.create(elixirHost, "defmodule Greeter do\n  :world\nend\n", {
  codeLanguage: "exs",
})
check("code mode highlights Elixir aliases", elixirHost.querySelector(".hl-keyword") != null)
elixirEditor.destroy()

const plain = dom.window.document.createElement("div")
dom.window.document.body.appendChild(plain)
const plainEditor = dom.window.MDEditor.create(plain, "just text", { codeLanguage: "" })
check("an empty language edits plain text", plainEditor.getMarkdown() === "just text"
  && plain.querySelector(".hl-keyword") == null)
plainEditor.destroy()

const unknown = dom.window.document.createElement("div")
dom.window.document.body.appendChild(unknown)
const unknownEditor = dom.window.MDEditor.create(unknown, "a", { codeLanguage: "no-such-language" })
check("an unknown language falls back to plain text", unknownEditor.getMarkdown() === "a")
unknownEditor.destroy()

const modules = dom.window.document.createElement("div")
dom.window.document.body.appendChild(modules)
const moduleEditor = dom.window.MDEditor.create(modules, "```mermaid\ngraph TD\n```\n", {
  codeLanguage: "",
  extensionState: { mermaid: true, "colorful-headings": true },
})
let threw = false
try { moduleEditor.setExtensionState({ mermaid: false, "colorful-headings": false }) } catch (_) { threw = true }
check("changing extension settings does not break a code editor", !threw && moduleEditor.getMarkdown().includes("mermaid"))
check("render extensions do not apply in code mode",
  modules.querySelector(".cm-colorful-headings, .cm-mermaid-preview, [class*=mermaid]") == null
  && !modules.querySelector(".cm-editor")?.classList.contains("cm-colorful-headings"))
check("slash commands do not apply in code mode", (() => {
  moduleEditor.insertTextAt("/", 0, 0)
  return modules.querySelector(".cm-slash-menu, [class*=slash]") == null
})())
moduleEditor.destroy()
