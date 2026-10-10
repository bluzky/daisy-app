// Editor smoke tests: toggling editor extension modules.
import { dom, check } from "./harness.mjs"

const moduleMermaidSource = "```mermaid\ngraph TD; A-->B\n```\n\nafter"
const moduleMermaidHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(moduleMermaidHost)
dom.window.mermaid = { render: () => new Promise(() => {}) }
const moduleMermaidEditor = dom.window.MDEditor.create(moduleMermaidHost, moduleMermaidSource, { extensionState: { mermaid: true } })
moduleMermaidEditor.focus()
moduleMermaidEditor.select(moduleMermaidSource.length)
check("mermaid module renders a preview when enabled",
  moduleMermaidHost.querySelector(".cm-md-mermaid-preview") != null)
moduleMermaidEditor.select(moduleMermaidSource.length - 2)
moduleMermaidEditor.setExtensionState({ mermaid: false })
check("disabling the mermaid module removes the preview",
  moduleMermaidHost.querySelector(".cm-md-mermaid-preview") == null)
check("disabling a module leaves the document untouched",
  moduleMermaidEditor.getMarkdown() === moduleMermaidSource)
moduleMermaidEditor.setExtensionState({ mermaid: true })
check("re-enabling the mermaid module restores the preview",
  moduleMermaidHost.querySelector(".cm-md-mermaid-preview") != null)
const moduleDisabledMermaidHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(moduleDisabledMermaidHost)
dom.window.MDEditor.create(moduleDisabledMermaidHost, moduleMermaidSource, { extensionState: { mermaid: false } })
check("a module disabled at creation never mounts",
  moduleDisabledMermaidHost.querySelector(".cm-md-mermaid-preview") == null)

const headingsHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(headingsHost)
const headingsEditor = dom.window.MDEditor.create(headingsHost, "# Title\n\n## Sub", { extensionState: { "colorful-headings": true } })
const headingsRoot = () => headingsHost.querySelector(".cm-editor")
check("colorful-headings module marks the editor when enabled",
  headingsRoot().classList.contains("cm-colorful-headings"))
check("heading lines keep their level classes",
  headingsHost.querySelector(".cm-md-h1") != null && headingsHost.querySelector(".cm-md-h2") != null)
headingsEditor.setExtensionState({ "colorful-headings": false })
check("disabling colorful-headings removes the editor class",
  !headingsRoot().classList.contains("cm-colorful-headings"))
headingsEditor.setExtensionState({ "colorful-headings": true })
check("re-enabling colorful-headings restores the editor class",
  headingsRoot().classList.contains("cm-colorful-headings"))
check("toggling colorful-headings leaves the document untouched",
  headingsEditor.getMarkdown() === "# Title\n\n## Sub")
