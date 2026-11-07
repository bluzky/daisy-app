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
