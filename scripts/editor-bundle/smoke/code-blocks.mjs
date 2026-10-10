// Editor smoke tests: code block rendering, language detection, Mermaid.
import { dom, check, enterIn } from "./harness.mjs"

const leadingCodeHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(leadingCodeHost)
const leadingCodeEditor = dom.window.MDEditor.create(
  leadingCodeHost, "```javascript\nconst answer = 42\n```", {})
check("implicit initial cursor keeps the leading code block in live preview",
  leadingCodeHost.querySelectorAll(".cm-md-line-collapsed").length === 2)
check("leading preview code block keeps syntax highlighting",
  leadingCodeHost.querySelector(".hl-keyword")?.textContent === "const")
leadingCodeEditor.select(18)
check("pointer click activates the code block",
  leadingCodeHost.querySelectorAll(".cm-md-line-collapsed").length === 2)
check("activated code block remains syntax highlighted",
  leadingCodeHost.querySelector(".hl-keyword")?.textContent === "const")
check("activated code block keeps raw fence lines visually hidden",
  leadingCodeHost.querySelectorAll(".cm-md-line-collapsed").length === 2)
leadingCodeEditor.destroy()

const inactiveCodeHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(inactiveCodeHost)
const inactiveCodeEditor = dom.window.MDEditor.create(
  inactiveCodeHost, "intro\n```javascript\nconst answer = 42\n```", {})
check("inactive code block hides both fence source lines",
  inactiveCodeHost.querySelectorAll(".cm-md-code-fence-source-hidden").length === 2)
check("inactive code block keeps syntax highlighting",
  inactiveCodeHost.querySelector(".hl-keyword")?.textContent === "const")
check("inactive fence source lines collapse to zero height",
  inactiveCodeHost.querySelectorAll(".cm-md-line-collapsed").length === 2)
check("interior code line carries the card styling when fences collapse",
  inactiveCodeHost.querySelector(".cm-md-codeblock-first.cm-md-codeblock-last") != null)
inactiveCodeEditor.destroy()

const legacyCodeHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(legacyCodeHost)
const legacyCodeEditor = dom.window.MDEditor.create(
  legacyCodeHost, "intro\n```swift\nlet answer = 42\n```", {})
check("bundled legacy language support constructs",
  legacyCodeHost.querySelectorAll(".cm-md-code-fence-source-hidden").length === 2)
check("bundled legacy language stays syntax highlighted",
  legacyCodeHost.querySelector(".hl-keyword")?.textContent === "let")
legacyCodeEditor.destroy()

const detectedCodeHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(detectedCodeHost)
let detectedCodeDirtyCount = 0
const detectedCodeSource = "intro\n```\nconst answer = 42\n```"
const detectedCodeEditor = dom.window.MDEditor.create(
  detectedCodeHost,
  detectedCodeSource,
  { onDirty: () => { detectedCodeDirtyCount++ } },
)
const detectedLanguageInput = detectedCodeHost.querySelector(
  ".cm-md-code-language-input"
)
check("detected language is shown as the language input value",
  detectedLanguageInput != null
    && detectedLanguageInput.value === "javascript"
    && detectedLanguageInput.placeholder === "language")
check("detected language applies its CodeMirror highlighting rules",
  detectedCodeHost.querySelector(".hl-keyword")?.textContent === "const")
check("automatic language rendering leaves Markdown byte-faithful",
  detectedCodeEditor.getMarkdown() === detectedCodeSource
    && detectedCodeDirtyCount === 0)
detectedLanguageInput?.focus()
detectedLanguageInput?.blur()
check("focusing and blurring a detected language does not write the fence",
  detectedCodeEditor.getMarkdown() === detectedCodeSource
    && detectedCodeDirtyCount === 0)
const editableDetectedLanguageInput = detectedCodeHost.querySelector(
  ".cm-md-code-language-input"
)
editableDetectedLanguageInput?.focus()
if (editableDetectedLanguageInput) {
  editableDetectedLanguageInput.value = "typescript"
  editableDetectedLanguageInput.dispatchEvent(
    new dom.window.Event("change", { bubbles: true })
  )
}
check("language input writes the explicit fence language",
  detectedCodeEditor.getMarkdown() === "intro\n```typescript\nconst answer = 42\n```")
detectedCodeEditor.destroy()

const detectedCHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(detectedCHost)
const detectedCSource = "intro\n```\nint main(){\nreturn 0;\n}\n```"
const detectedCEditor = dom.window.MDEditor.create(
  detectedCHost, detectedCSource, {})
const detectedCInput = detectedCHost.querySelector(".cm-md-code-language-input")
check("C code is automatically marked as c",
  detectedCInput?.value === "c"
    && detectedCInput.placeholder === "language")
check("automatically detected C uses the bundled C parser",
  Array.from(detectedCHost.querySelectorAll(".hl-keyword"))
    .some((node) => node.textContent === "int" || node.textContent === "return"))
check("automatic C rendering does not rewrite the opening fence",
  detectedCEditor.getMarkdown() === detectedCSource)
detectedCEditor.destroy()

const metadataCodeHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(metadataCodeHost)
const metadataCodeEditor = dom.window.MDEditor.create(
  metadataCodeHost, "```js title=\"answer.js\"\nconst answer = 42\n```", {})
const metadataInput = metadataCodeHost.querySelector(".cm-md-code-language-input")
metadataInput?.focus()
if (metadataInput) {
  metadataInput.value = "typescript"
  metadataInput.dispatchEvent(new dom.window.Event("change", { bubbles: true }))
}
check("language edits preserve fence metadata",
  metadataCodeEditor.getMarkdown() ===
    "```typescript title=\"answer.js\"\nconst answer = 42\n```")
metadataCodeEditor.destroy()

const autoFenceHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(autoFenceHost)
const autoFenceEditor = dom.window.MDEditor.create(autoFenceHost, "intro\n", {})
autoFenceEditor.select(autoFenceEditor.getMarkdown().length)
for (const character of "```") autoFenceEditor.insert(character)
check("typing an opening fence alone does not pair it",
  autoFenceEditor.getMarkdown() === "intro\n```")
check("a lone opening fence renders as plain text, not a code block",
  autoFenceHost.querySelector(".cm-md-codeblock") == null
    && autoFenceHost.querySelector(".cm-md-code-language") == null)
enterIn(autoFenceHost)
check("Enter after an opening fence inserts the closing fence",
  autoFenceEditor.getMarkdown() === "intro\n```\n\n```")
const emptyCodeLine = autoFenceHost.querySelector(".cm-md-codeblock-first")
check("auto-closed empty code line keeps its caret buffer after the language widget",
  emptyCodeLine?.querySelector(".cm-md-code-language + .cm-widgetBuffer") != null)
check('empty code block keeps its editable line in a native scroll wrapper',
  emptyCodeLine?.closest('.cm-md-code-card') != null)
autoFenceEditor.insert("body")
check("auto-closed fence leaves the cursor in its content",
  autoFenceEditor.getMarkdown() === "intro\n```\nbody\n```")
autoFenceEditor.destroy()

const authoredCHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(authoredCHost)
const authoredCEditor = dom.window.MDEditor.create(authoredCHost, "intro\n", {})
authoredCEditor.select(authoredCEditor.getMarkdown().length)
for (const character of "```") authoredCEditor.insert(character)
enterIn(authoredCHost)
authoredCEditor.insert("int main(){\nreturn 0;\n}")
check("newly authored C code is detected and highlighted immediately",
  authoredCHost.querySelector(".cm-md-code-language-input")?.value === "c"
    && Array.from(authoredCHost.querySelectorAll(".hl-keyword"))
      .some((node) => node.textContent === "int" || node.textContent === "return")
    && authoredCEditor.getMarkdown() ===
      "intro\n```\nint main(){\nreturn 0;\n}\n```")
authoredCEditor.destroy()

const unclosedFenceHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(unclosedFenceHost)
const unclosedFenceEditor = dom.window.MDEditor.create(
  unclosedFenceHost, "```\nbody\n", {})
unclosedFenceEditor.select(unclosedFenceEditor.getMarkdown().length)
for (const character of "```") unclosedFenceEditor.insert(character)
check("typing an existing block's closing fence does not pair it again",
  unclosedFenceEditor.getMarkdown() === "```\nbody\n```")
unclosedFenceEditor.destroy()

const emptyFenceHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(emptyFenceHost)
const emptyFenceEditor = dom.window.MDEditor.create(
  emptyFenceHost, "intro\n```\n```", {})
check("empty fenced blocks keep their language input visible",
  emptyFenceHost.querySelector(".cm-md-code-language-input") != null
    && emptyFenceHost.querySelector(".cm-md-code-language-input")
      .closest(".cm-line")?.classList.contains("cm-md-line-collapsed") !== true)
emptyFenceEditor.destroy()

const hclSource = `terraform {
  required_providers {
    random = { source = "hashicorp/random", version = "~> 3.0" }
    local  = { source = "hashicorp/local",  version = "~> 2.0" }
  }
}

resource "random_pet" "name" {
  length = 2
}`
for (const language of ["hcl", "terraform", "tf"]) {
  const hclHost = dom.window.document.createElement("div")
  dom.window.document.body.appendChild(hclHost)
  const hclEditor = dom.window.MDEditor.create(
    hclHost, `intro\n\`\`\`${language}\n${hclSource}\n\`\`\``, {})
  check(`${language} fence highlights HCL block keywords`,
    Array.from(hclHost.querySelectorAll(".hl-keyword"))
      .some((node) => node.textContent === "resource"))
  check(`${language} fence highlights HCL strings`,
    Array.from(hclHost.querySelectorAll(".hl-string"))
      .some((node) => node.textContent.includes("hashicorp/random")))
  check(`${language} fence highlights HCL numbers`,
    Array.from(hclHost.querySelectorAll(".hl-number"))
      .some((node) => node.textContent === "2"))
  hclEditor.destroy()
}

const mermaidHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(mermaidHost)
const mermaidEditor = dom.window.MDEditor.create(
  mermaidHost, "intro\n```mermaid\nflowchart LR\n  A --> B\n```", {})
check("inactive Mermaid block uses diagram preview widget",
  mermaidHost.querySelector(".cm-md-mermaid-preview") != null)
const stableMermaidPreview = mermaidHost.querySelector(".cm-md-mermaid-preview")
mermaidEditor.exec("bold")
check("unrelated edits preserve the Mermaid preview DOM",
  mermaidHost.querySelector(".cm-md-mermaid-preview") === stableMermaidPreview)
mermaidEditor.select(mermaidEditor.getMarkdown().indexOf("flowchart") + 2)
check("active Mermaid block reveals editable source",
  mermaidHost.querySelector(".cm-md-mermaid-preview") == null)
check("active Mermaid block preserves source",
  mermaidEditor.getMarkdown().includes("flowchart LR\n  A --> B"))
mermaidEditor.destroy()

// One click on the diagram reveals its source, wherever the caret was before.
for (const [where, start] of [["above", 0], ["below", -1]]) {
  const host = dom.window.document.createElement("div")
  dom.window.document.body.appendChild(host)
  const source = "intro\n\n```mermaid\nflowchart LR\n  A --> B\n```\n\nafter"
  const editor = dom.window.MDEditor.create(host, source, {})
  editor.select(start < 0 ? source.length : start)
  host.querySelector(".cm-md-mermaid-preview").dispatchEvent(
    new dom.window.MouseEvent("mousedown", { bubbles: true, cancelable: true, button: 0, detail: 1 }))
  dom.window.document.dispatchEvent(new dom.window.MouseEvent("mouseup", { bubbles: true }))
  await new Promise((resolve) => setTimeout(resolve, 10))
  check(`one click on a Mermaid diagram with the caret ${where} reveals its source`,
    host.querySelector(".cm-md-mermaid-preview") == null)
  editor.destroy()
}

// Selecting inside revealed Mermaid source keeps it revealed; a selection
// reaching outside the block shows the diagram again.
{
  const host = dom.window.document.createElement("div")
  dom.window.document.body.appendChild(host)
  const source = "intro\n\n```mermaid\nflowchart LR\n  A --> B\n```\n\nafter"
  const editor = dom.window.MDEditor.create(host, source, {})
  const view = host.querySelector(".cm-content").cmTile.view
  const code = source.indexOf("flowchart")
  view.dispatch({ selection: { anchor: code + 2 }, userEvent: "select.pointer" })
  view.dispatch({ selection: { anchor: code, head: code + 9 }, userEvent: "select.pointer" })
  check("a word selected in Mermaid source keeps the source revealed",
    host.querySelector(".cm-md-mermaid-preview") == null)
  view.dispatch({ selection: { anchor: code, head: code + 14 }, userEvent: "select" })
  check("a Shift-arrow selection in Mermaid source keeps the source revealed",
    host.querySelector(".cm-md-mermaid-preview") == null)
  view.dispatch({ selection: { anchor: code, head: source.length }, userEvent: "select" })
  check("a selection reaching past the Mermaid block shows the diagram",
    host.querySelector(".cm-md-mermaid-preview") != null)
  editor.destroy()
}

const authoredMermaidHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(authoredMermaidHost)
const authoredMermaidEditor = dom.window.MDEditor.create(
  authoredMermaidHost, "intro\n", {})
authoredMermaidEditor.select(authoredMermaidEditor.getMarkdown().length)
for (const character of "```") {
  authoredMermaidEditor.insert(character)
}
enterIn(authoredMermaidHost)
const authoredMermaidLanguage = authoredMermaidHost.querySelector(
  ".cm-md-code-language-input"
)
if (authoredMermaidLanguage) {
  authoredMermaidLanguage.value = "mermaid"
  authoredMermaidLanguage.dispatchEvent(
    new dom.window.Event("change", { bubbles: true })
  )
}
authoredMermaidEditor.insert("flowchart LR\n  A --> B")
check("newly typed Mermaid fence remains editable at the cursor",
  authoredMermaidHost.querySelector(".cm-md-mermaid-preview") == null
    && authoredMermaidHost.querySelector(".cm-md-code-fence-source-hidden") == null)
authoredMermaidEditor.select(0)
check("newly typed Mermaid fence previews after the cursor leaves",
  authoredMermaidHost.querySelector(".cm-md-mermaid-preview") != null)
authoredMermaidEditor.destroy()
