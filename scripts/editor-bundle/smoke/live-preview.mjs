// Editor smoke tests: live-preview styling: spacing, headings, images, markers.
import { dom, check } from "./harness.mjs"

const largeHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(largeHost)
const largeDoc = [
  "# Large synthetic document",
  "",
  "```text",
  "PACKAGE VALIDATION PASS:",
  "1200 synthetic sections",
  "```",
  "",
  ...Array.from({ length: 1200 }, (_, index) =>
    `## Section ${index + 1}\nSynthetic paragraph ${index + 1} remains byte-faithful.`),
].join("\n")
const largeEditor = dom.window.MDEditor.create(largeHost, largeDoc, {})
largeEditor.focus()
const largeContent = largeHost.querySelector(".cm-content")
largeContent?.dispatchEvent(new dom.window.KeyboardEvent("keydown", {
  key: "a",
  code: "KeyA",
  ctrlKey: true,
  bubbles: true,
  cancelable: true,
}))
check("Cmd-A keeps hidden heading syntax in live-preview form",
  largeHost.querySelector(".cm-md-heading-source-hidden") != null)
check("Cmd-A keeps fenced-code markers in live-preview form",
  largeHost.querySelector(".cm-md-code-fence-source-hidden") != null)
largeEditor.insert("replacement")
check("Cmd-A replaces the complete virtualized document",
  largeEditor.getMarkdown() === "replacement")
largeEditor.destroy()

const bidiHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(bidiHost)
const bidiEditor = dom.window.MDEditor.create(
  bidiHost, "English line\nمرحبا بالعالم\nשלום עולם", {})
const bidiLines = Array.from(bidiHost.querySelectorAll(".cm-line"))
check("every editor line derives its direction from its own text",
  bidiLines.length === 3 && bidiLines.every((line) => line.getAttribute("dir") === "auto"))
bidiEditor.destroy()

const frontmatterHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(frontmatterHost)
const frontmatterDoc = "---\nname: \"openai-docs\"\ntags:\n  - links\n---\n# Body heading"
const frontmatterEditor = dom.window.MDEditor.create(frontmatterHost, frontmatterDoc, {})
check("frontmatter renders as a metadata card, not markdown blocks",
  frontmatterHost.querySelectorAll(".cm-md-frontmatter").length === 5
    && frontmatterHost.querySelector(".cm-md-frontmatter-first") != null
    && frontmatterHost.querySelector(".cm-md-frontmatter-last") != null
    && frontmatterHost.querySelector(".cm-md-h2") == null
    && frontmatterHost.querySelector(".cm-md-hr") == null)
check("frontmatter delimiters are dimmed",
  frontmatterHost.querySelectorAll(".cm-md-frontmatter-delim").length === 2)
check("body markdown still live-previews below frontmatter",
  frontmatterHost.querySelector(".cm-md-h1") != null)
check("frontmatter round-trips byte-faithfully",
  frontmatterEditor.getMarkdown() === frontmatterDoc)
frontmatterEditor.destroy()

const headingHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(headingHost)
const headingEditor = dom.window.MDEditor.create(headingHost, "### Stable heading", {})
check("unfocused leading heading source stays hidden",
  headingHost.querySelector(".cm-md-heading-source-hidden")?.textContent === "### ")
headingEditor.focus()
headingEditor.select(4, 10)
check("ordinary heading range selection keeps source hidden",
  headingHost.querySelector(".cm-md-heading-source-hidden")?.textContent === "### ")
const headingContent = headingHost.querySelector(".cm-content")
headingContent.dispatchEvent(new dom.window.CompositionEvent("compositionstart", { bubbles: true }))
headingEditor.select(4, 9)
check("IME composition range reveals heading source",
  headingHost.querySelector(".cm-md-heading-source-hidden") == null)
headingContent.dispatchEvent(new dom.window.CompositionEvent("compositionend", { bubbles: true }))
headingEditor.exec("h0")
check("Normal Text removes the heading marker",
  headingEditor.getMarkdown() === "Stable heading")
headingEditor.destroy()

const inactiveHeadingHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(inactiveHeadingHost)
const inactiveHeadingEditor = dom.window.MDEditor.create(
  inactiveHeadingHost, "intro\n\n### Stable heading", {})
check("inactive heading source reserves its width",
  inactiveHeadingHost.querySelector(".cm-md-heading-source-hidden")?.textContent === "### ")
check("inactive heading line receives visual offset class",
  inactiveHeadingHost.querySelector(".cm-md-heading-inactive") != null)
check("blank source line before heading remains visible",
  inactiveHeadingHost.querySelector(".cm-md-line-collapsed") == null)
check("heading receives compact spacing above a visible blank line",
  inactiveHeadingHost.querySelector(".cm-md-heading-after-blank") != null)
inactiveHeadingEditor.destroy()

const headingFollowHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(headingFollowHost)
const headingFollowEditor = dom.window.MDEditor.create(
  headingFollowHost, "## Heading\n\nFollowing paragraph", {})
// The final blank of a run shrinks to blankGap plus the next block's margin
// (headless defaults: 4 + 12).
check("separator after heading is the blank gap plus the paragraph margin",
  Math.abs(
    parseFloat(headingFollowHost.querySelector(".cm-md-block-separator")?.style.height)
      - 16
  ) < 0.01)
headingFollowEditor.destroy()

const paragraphGapHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(paragraphGapHost)
const paragraphGapEditor = dom.window.MDEditor.create(
  paragraphGapHost, "First paragraph.\n\nSecond paragraph.\n\n\nThird paragraph.", {})
check("blank paragraph separators are the blank gap plus the paragraph margin",
  Array.from(paragraphGapHost.querySelectorAll(".cm-md-block-separator"))
    .every((line) => Math.abs(parseFloat(line.style.height) - 16) < 0.01))
paragraphGapEditor.destroy()

// A block right under a heading (no blank line) gets the preview's margin as
// bottom padding on the heading line.
const adjacentHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(adjacentHost)
const adjacentEditor = dom.window.MDEditor.create(
  adjacentHost, "## Heading\nParagraph right under it", {})
check("adjacent block adds the paragraph margin below the heading line",
  adjacentHost.querySelector(".cm-md-block-gap")?.style.paddingBottom === "12px")
adjacentEditor.destroy()

// Ordered markers share the bullet's hanging box; continuation lines drop the
// hanging indent; nested quotations carry their depth.
const structureHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(structureHost)
const structureEditor = dom.window.MDEditor.create(
  structureHost,
  "1. First\n2. Second\n\n- Item\n\n  Continuation line\n\n> outer\n>> inner",
  {})
const orderedMarkers = Array.from(structureHost.querySelectorAll(".cm-md-ordered"))
check("inactive ordered markers render in the hanging marker box",
  orderedMarkers.map((el) => el.textContent).join("|") === "1.|2.")
check("continuation line inside a list item drops the hanging indent",
  structureHost.querySelector(".cm-md-list-continuation")?.textContent.includes("Continuation line") === true)
const quoteLines = Array.from(structureHost.querySelectorAll(".cm-md-quote"))
check("nested quotation lines carry one rule per depth",
  quoteLines.length === 2
    && quoteLines[0].style.paddingInlineStart === "1.5em"
    && quoteLines[1].style.paddingInlineStart === "3em"
    && quoteLines[1].style.backgroundImage.split("linear-gradient").length === 3)
structureEditor.destroy()

const inlineCodeHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(inlineCodeHost)
const inlineCodeEditor = dom.window.MDEditor.create(
  inlineCodeHost, "before `highlight` after", {})
const inlineCodeSpans = inlineCodeHost.querySelectorAll(".cm-md-inline-code")
check("inline code renders as one styled content span",
  inlineCodeSpans.length === 1 && inlineCodeSpans[0].textContent === "highlight")
check("inactive inline code hides both backtick markers",
  inlineCodeHost.querySelector(".cm-content")?.textContent === "before highlight after")
inlineCodeEditor.destroy()

const imageHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(imageHost)
const imageMarkdown = "Before\n\n![Preview](md-asset:///test-pictures/1.png)\n\nAfter"
let requestedImageRename = null
dom.window.__mdRequestImageRename = (source) => { requestedImageRename = source }
const imageEditor = dom.window.MDEditor.create(imageHost, imageMarkdown, {})
const imagePreview = imageHost.querySelector(".cm-md-image-preview")
const image = imagePreview?.querySelector("img")
const imageSource = imagePreview?.querySelector(".cm-md-image-source")
check("inactive Markdown image renders as a preview",
  image?.getAttribute("src") === "md-asset:///test-pictures/1.png")
check("standalone image uses a line without extra baseline spacing",
  imagePreview?.closest(".cm-line")?.classList.contains("cm-md-image-line"))
check("image preview retains the exact Markdown source",
  imageSource?.textContent === "![Preview](md-asset:///test-pictures/1.png)")
image?.dispatchEvent(new dom.window.MouseEvent("click", {
  bubbles: true,
  cancelable: true,
}))
check("clicking a local image requests its native rename flow",
  requestedImageRename === "md-asset:///test-pictures/1.png")
// A real click has detail 1, which is what lets the pointer-preview snapshot
// activate the new selection and reveal the source.
imageSource?.dispatchEvent(new dom.window.MouseEvent("mousedown", {
  bubbles: true,
  cancelable: true,
  detail: 1,
}))
check("clicking image source restores editable Markdown without changing it",
  imageHost.querySelector(".cm-md-image-preview") == null
    && imageHost.querySelector(".cm-md-image-line") == null
    && imageEditor.getMarkdown() === imageMarkdown)
imageEditor.destroy()
delete dom.window.__mdRequestImageRename

const inlineImageHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(inlineImageHost)
const inlineImageMarkdown = "Before ![Preview](image.png) after"
const inlineImageEditor = dom.window.MDEditor.create(inlineImageHost, inlineImageMarkdown, {})
check("an image surrounded by text keeps its inline alignment",
  inlineImageHost.querySelector(".cm-md-image-preview") != null
    && inlineImageHost.querySelector(".cm-md-image-line") == null
    && inlineImageEditor.getMarkdown() === inlineImageMarkdown)
inlineImageEditor.destroy()

for (const imageSource of [
  "![Preview](image.png)",
  "[![Preview](image.png)](https://example.com)",
  "Before ![Preview](image.png) after",
  "![Preview][reference]\n\n[reference]: image.png",
  "![Preview](//example.com/image.png)",
  "> ![Preview](image.png)",
]) {
  const host = dom.window.document.createElement("div")
  dom.window.document.body.appendChild(host)
  const source = `Before\n\n${imageSource}\n\nAfter image\n\nFinal paragraph`
  const instance = dom.window.MDEditor.create(host, source, {})
  const lines = Array.from(host.querySelectorAll(".cm-line"))
  for (const text of ["After image", "Final paragraph"]) {
    const line = lines.find((line) => line.textContent === text)
    check(`paragraph spacing survives ${imageSource.split("\n")[0]} before ${text}`,
      parseFloat(line?.previousElementSibling?.style.height) === 16)
  }
  instance.destroy()
}

const renameHistoryHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(renameHistoryHost)
const renameHistoryEditor = dom.window.MDEditor.create(
  renameHistoryHost, "![Preview](test-pictures/1.png)", {})
renameHistoryEditor.replaceMarkdown("![Preview](test-pictures/hero.png)")
const renameHistoryContent = renameHistoryHost.querySelector(".cm-content")
renameHistoryContent?.focus()
// jsdom reports a non-macOS platform, so Mod maps to Ctrl in this test.
const renameUndoEvent = new dom.window.KeyboardEvent("keydown", {
  key: "z",
  code: "KeyZ",
  ctrlKey: true,
  bubbles: true,
  cancelable: true,
})
renameHistoryContent?.dispatchEvent(renameUndoEvent)
check("Undo after image rename does not restore the old path",
  renameUndoEvent.defaultPrevented
    && renameHistoryEditor.getMarkdown() === "![Preview](test-pictures/hero.png)")
renameHistoryEditor.destroy()

const indentedCodeHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(indentedCodeHost)
const indentedCodeEditor = dom.window.MDEditor.create(
  indentedCodeHost, "    <script>\n        run()\n    </script>", {})
const indentedCodeLines = Array.from(indentedCodeHost.querySelectorAll(".cm-line"))
check("indented code block receives preview block styling",
  indentedCodeLines[0]?.classList.contains("cm-md-codeblock-first")
    && indentedCodeLines.at(-1)?.classList.contains("cm-md-codeblock-last"))
check("inactive indented code hides source indentation",
  indentedCodeLines[0]?.textContent === "<script>"
    && indentedCodeLines.at(-1)?.textContent === "</script>")
indentedCodeEditor.destroy()

const nativeCodeHost = document.createElement('div')
document.body.appendChild(nativeCodeHost)
const nativeCodeSource = 'Before\n\n```text\nfirst\nsecond\n```\n\nBetween\n\n```\nthird\n```\n\nAfter'
const nativeCodeEditor = dom.window.MDEditor.create(nativeCodeHost, nativeCodeSource, {})
const nativeCards = [...nativeCodeHost.querySelectorAll('.cm-md-code-card')]
check('each editable code block has one native scroll wrapper',
  nativeCards.length === 2 && nativeCards[0].querySelectorAll('.cm-md-codeblock').length === 2)
check('native code wrappers exclude surrounding paragraphs and separators',
  nativeCards.every(card => !/Before|Between|After/.test(card.textContent)
    && card.querySelector('.cm-md-block-separator') == null))
nativeCodeEditor.select(nativeCodeSource.indexOf('second') + 3)
nativeCodeEditor.insert('X')
check('editing inside a native code wrapper preserves source positions',
  nativeCodeEditor.getMarkdown() === nativeCodeSource.replace('second', 'secXond'))
nativeCodeHost.querySelector('.cm-content').dispatchEvent(new dom.window.KeyboardEvent('keydown', {
  key: 'z', code: 'KeyZ', ctrlKey: true, bubbles: true, cancelable: true,
}))
check('native code wrapper editing supports undo', nativeCodeEditor.getMarkdown() === nativeCodeSource)
nativeCodeEditor.destroy()

const listLikeCodeHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(listLikeCodeHost)
const listLikeCodeEditor = dom.window.MDEditor.create(
  listLikeCodeHost, "    - literal code output", {})
check("standalone indented code that starts with a dash remains code",
  listLikeCodeHost.querySelector(".cm-md-codeblock") != null
    && listLikeCodeHost.querySelector("[class*='cm-md-list-depth-']") == null)
listLikeCodeEditor.destroy()

const emphasisHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(emphasisHost)
const emphasisEditor = dom.window.MDEditor.create(
  emphasisHost, "plain\n**bold text** and *italic text* and ~~struck text~~", {})
check("inactive strong emphasis keeps bold decoration",
  emphasisHost.querySelector(".cm-md-strong")?.textContent === "bold text")
check("inactive emphasis keeps italic decoration",
  emphasisHost.querySelector(".cm-md-emphasis")?.textContent === "italic text")
check("inactive strikethrough keeps decoration",
  emphasisHost.querySelector(".cm-md-strikethrough")?.textContent === "struck text")
emphasisEditor.select(10)
check("unfocused selection does not reveal strong markers",
  emphasisHost.querySelector(".cm-md-strong")?.textContent === "bold text")
emphasisEditor.destroy()

const setextHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(setextHost)
const setextEditor = dom.window.MDEditor.create(setextHost, "Stable heading\n=====", {})
check("Setext marker stays visible without editor focus",
  setextHost.querySelector(".cm-md-heading-source-hidden") == null
  && setextHost.textContent.includes("====="))
check("Setext source line uses collapsed overlay styling",
  setextHost.querySelector(".cm-md-setext-marker-line") != null
  && setextHost.querySelector(".cm-md-setext-source")?.textContent === "=====")
setextEditor.destroy()

const markerHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(markerHost)
const markerSource = "## [Unreleased]\n\n- **Bold** and *italic*\n\n[Real link](https://example.com)"
const markerEditor = dom.window.MDEditor.create(markerHost, markerSource, {})
for (const position of [0, markerSource.indexOf("Bold"), markerSource.indexOf("Real link")]) {
  markerEditor.select(position)
  check(`Markdown markers do not inherit code metadata colors at ${position}`,
    markerHost.querySelector(".hl-meta") == null)
}
check("actual Markdown links retain link styling", markerHost.querySelector(".cm-md-link") != null)
check("marker styling preserves Markdown source", markerEditor.getMarkdown() === markerSource)
markerEditor.destroy()

const preprocessorHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(preprocessorHost)
const preprocessorSource = "```c\n#include <stdio.h>\nint answer = 42;\n```"
const preprocessorEditor = dom.window.MDEditor.create(preprocessorHost, preprocessorSource, {})
for (const position of [0, preprocessorSource.indexOf("include")]) {
  preprocessorEditor.select(position)
  check(`code preprocessors keep metadata highlighting at ${position}`,
    preprocessorHost.querySelector(".hl-meta")?.textContent.includes("#include"))
}
preprocessorEditor.destroy()
