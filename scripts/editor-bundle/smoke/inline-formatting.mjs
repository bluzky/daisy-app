// Editor smoke tests: highlight syntax, links and inline commands.
import { dom, check } from "./harness.mjs"

const highlightHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(highlightHost)
const highlightSource = "before ==Highlighted text== after"
const highlightEditor = dom.window.MDEditor.create(highlightHost, highlightSource, {})
const highlightContent = highlightHost.querySelector(".cm-content")
check("highlight syntax keeps the source unchanged",
  highlightEditor.getMarkdown() === highlightSource)
check("highlight syntax decorates the content",
  highlightHost.querySelector(".cm-md-highlight") != null)
check("inactive highlight delimiters are hidden",
  !(highlightContent?.textContent ?? "").includes("=="))
highlightEditor.focus()
highlightEditor.select(highlightSource.indexOf("Highlighted") + 2)
check("active highlight reveals its delimiters",
  (highlightContent?.textContent ?? "").includes("==Highlighted text=="))

const codeHighlightHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(codeHighlightHost)
const codeHighlightEditor = dom.window.MDEditor.create(
  codeHighlightHost, "```\n==literal==\n```", {})
check("highlight syntax stays literal inside fenced code",
  (codeHighlightHost.querySelector(".cm-content")?.textContent ?? "").includes("==literal=="))

const nestedHighlightHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(nestedHighlightHost)
const nestedHighlightSource = "==**bold** and *italic*=="
const nestedHighlightEditor = dom.window.MDEditor.create(nestedHighlightHost, nestedHighlightSource, {})
check("nested Markdown stays inside a highlight",
  nestedHighlightHost.querySelector(".cm-md-highlight") != null
    && nestedHighlightHost.querySelector(".cm-md-strong") != null
    && !(nestedHighlightHost.querySelector(".cm-content")?.textContent ?? "").includes("=="))

const inlineCodeHighlightHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(inlineCodeHighlightHost)
dom.window.MDEditor.create(inlineCodeHighlightHost, "`==code==` and ==visible==", {})
check("inline code is excluded from highlights",
  inlineCodeHighlightHost.querySelectorAll(".cm-md-highlight").length === 1
    && (inlineCodeHighlightHost.querySelector(".cm-content")?.textContent ?? "").includes("==code=="))

const invalidHighlightHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(invalidHighlightHost)
dom.window.MDEditor.create(invalidHighlightHost, "== open == and ==unclosed", {})
check("unmatched or whitespace-delimited markers stay literal",
  invalidHighlightHost.querySelector(".cm-md-highlight") == null
    && (invalidHighlightHost.querySelector(".cm-content")?.textContent ?? "").includes("== open =="))

const evenHighlightHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(evenHighlightHost)
const evenHighlightSource = "====hello===="
dom.window.MDEditor.create(evenHighlightHost, evenHighlightSource, {})
check("even highlight runs split into independent pairs",
  evenHighlightHost.querySelectorAll(".cm-md-highlight").length === 2
    && Array.from(evenHighlightHost.querySelectorAll(".cm-md-highlight"))
      .every((element) => element.textContent === "hello"))

const oddHighlightHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(oddHighlightHost)
const oddHighlightSource = "=====hello====="
dom.window.MDEditor.create(oddHighlightHost, oddHighlightSource, {})
check("odd highlight runs leave one literal equals before each pair",
  oddHighlightHost.querySelectorAll(".cm-md-highlight").length === 2
    && Array.from(oddHighlightHost.querySelectorAll(".cm-md-highlight"))
      .every((element) => element.textContent === "hello=")
    && (oddHighlightHost.querySelector(".cm-content")?.textContent ?? "")
      === "=hello=")

const linkHighlightHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(linkHighlightHost)
const linkHighlightSource = "[==label==](https://example.com/?a==b==c) and \\==literal\\== and ==visible=="
dom.window.MDEditor.create(linkHighlightHost, linkHighlightSource, {})
const linkHighlightText = Array.from(linkHighlightHost.querySelectorAll(".cm-md-highlight"))
  .map((element) => element.textContent)
  .join("|")
check("links and escapes keep delimiter parsing in text context",
  linkHighlightHost.querySelectorAll(".cm-md-highlight").length === 2
    && linkHighlightText.includes("label")
    && linkHighlightText.includes("visible"))

const highlightCommandHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(highlightCommandHost)
const highlightCommandEditor = dom.window.MDEditor.create(highlightCommandHost, "text", {})
highlightCommandEditor.select(0, 4)
highlightCommandEditor.exec("highlight")
check("exec('highlight') wraps the selected text", highlightCommandEditor.getMarkdown() === "==text==")
