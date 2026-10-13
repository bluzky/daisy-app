// Editor smoke tests: in-document search.
import { readFileSync } from "node:fs"
import { dom, check } from "./harness.mjs"

const findHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(findHost)
const findSource = "# Needle\n\nneedle one\n\npinneedle two\n\nNEEDLE three\n\nliteral a.b [x]\n\nİ needle after unicode\n"
let lastFindResult
let searchDirtyCount = 0
const findEditor = dom.window.MDEditor.create(findHost, findSource, {
  onDirty: () => searchDirtyCount++,
  onSearchChange: (result) => { lastFindResult = result },
})
const findResult = (query, backwards = false, options = null) =>
  findEditor.find(query, backwards, options)
check("editor search counts case-insensitive source matches", findResult("needle").total === 5)
check("editor search highlights without editor focus", findHost.querySelectorAll(".cm-find-match").length === 5)
check("next match advances", findResult("needle").index === 2)
check("previous match goes backwards", findResult("needle", true).index === 1)
check("previous wraps to last match", findResult("needle", true).index === 5)
check("next wraps to first match", findResult("needle").index === 1)
check("word mode excludes mid-word matches and resets index",
  (({ index, total }) => index === 1 && total === 4)(findResult("needle", false, { mode: "word" })))
check("match case excludes other casings",
  findResult("needle", false, { caseSensitive: true }).total === 3)
check("search treats regex characters literally", findResult("a.b [x]").total === 1)
findResult("needle")
findResult("needle", true)
check("Unicode before a match preserves highlight offsets",
  findHost.querySelector(".cm-find-current")?.textContent === "needle")
check("search navigation preserves document and does not mark dirty",
  findEditor.getMarkdown() === findSource && searchDirtyCount === 0)
check("no-match query clears highlights", findResult("absent").total === 0
  && findHost.querySelector(".cm-find-match") == null)
findResult("needle")
findEditor.insertTextAt("needle new\n", findSource.length, findSource.length)
check("unsaved edits update search count", lastFindResult?.total === 6)
findResult("")
check("clearing search removes all decorations", findHost.querySelector(".cm-find-match") == null)
findEditor.destroy()

const blockFindHost = dom.window.document.createElement("div")
dom.window.document.body.appendChild(blockFindHost)
const blockFindSource = "| Heading |\n| --- |\n| needle |\n\n```mermaid\ngraph LR\nneedle-->end\n```\n"
const blockFindEditor = dom.window.MDEditor.create(blockFindHost, blockFindSource, {})
check("search finds text inside a rendered table", blockFindEditor.find("needle").total === 2
  && blockFindHost.querySelector(".cm-find-current")?.textContent === "needle")
blockFindEditor.find("needle")
check("search reveals and highlights Mermaid source", blockFindHost.querySelector(".cm-find-current")?.textContent === "needle")
check("searching rendered blocks preserves source", blockFindEditor.getMarkdown() === blockFindSource)
blockFindEditor.destroy()

// Modes, case and replace.
const run = (source, fn) => {
  const host = dom.window.document.createElement("div")
  dom.window.document.body.appendChild(host)
  let dirty = 0
  const editor = dom.window.MDEditor.create(host, source, { onDirty: () => dirty++ })
  try { return fn(editor, host, () => dirty) } finally { editor.destroy() }
}
const total = (editor, query, options) => editor.find(query, false, options).total

run("café cafés Café\nnaïve 日本語 日本\nfoo.bar foo-bar\n", (editor) => {
  check("word mode treats accented letters as word characters",
    total(editor, "café", { mode: "word" }) === 2)
  check("word mode with match case", total(editor, "café", { mode: "word", caseSensitive: true }) === 1)
  check("word mode treats CJK characters as word characters", total(editor, "日本", { mode: "word" }) === 1)
  check("substring mode escapes regex characters", total(editor, "foo.bar") === 1)
  check("regex mode honours metacharacters", total(editor, "foo.bar", { mode: "regex" }) === 2)
  check("regex ^ anchors every line", total(editor, "^\\p{L}+", { mode: "regex" }) === 3)
  check("regex is case-insensitive unless match case is on",
    total(editor, "CAFÉ", { mode: "regex" }) === 3 && total(editor, "CAFÉ", { mode: "regex", caseSensitive: true }) === 0)
  const invalid = editor.find("(", false, { mode: "regex" })
  check("invalid regex reports an error and no matches", invalid.error === true && invalid.total === 0)
  check("zero-length regex matches are ignored", total(editor, "x*", { mode: "regex" }) === 0)
  check("changing options resets the current match",
    editor.find("café", false, { mode: "word" }).index === 1)
})

run("one two one two one\n", (editor, host, dirty) => {
  const source = editor.getMarkdown()
  editor.find("one")
  const replaced = editor.replaceCurrent("1", "one")
  check("replace current swaps one match and moves on",
    editor.getMarkdown() === "1 two one two one\n" && replaced.replaced === 1
    && replaced.total === 2 && replaced.index === 1)
  check("replace marks the document dirty", dirty() === 1)
  check("replace highlights the next match", host.querySelector(".cm-find-current")?.textContent === "one")
  const all = editor.replaceAll("uno", "one")
  check("replace all swaps every remaining match", editor.getMarkdown() === "1 two uno two uno\n" && all.replaced === 2)
  check("replace all leaves no stale matches", all.total === 0)
  editor.replaceMarkdown(source)
})

run("a a a\n", (editor) => {
  editor.find("a")
  editor.replaceCurrent("aa", "a")
  check("a replacement containing the query is not matched again",
    editor.getMarkdown() === "aa a a\n" && editor.find("a").total === 4)
  editor.replaceCurrent("", "a")
  check("an empty replacement deletes the match", editor.getMarkdown().length < "aa a a\n".length)
})

run("x1 y22\nfoo(bar)\n", (editor) => {
  editor.replaceAll("[$&|$1|$$]", "([a-z])(\\d+)", { mode: "regex" })
  check("regex replacement expands $&, groups and $$", editor.getMarkdown() === "[x1|x|$] [y22|y|$]\nfoo(bar)\n")
  editor.replaceAll("<$<w>>\\n", "(?<w>foo)", { mode: "regex" })
  check("regex replacement expands named groups and escapes", editor.getMarkdown().includes("<foo>\n(bar)"))
})

run("a$1b $&\n", (editor) => {
  editor.replaceAll("$&$1\\n", "a", { mode: "substring" })
  check("substring replacement is literal", editor.getMarkdown() === "$&$1\\n$1b $&\n")
})

run("hit hit hit\n", (editor, host) => {
  editor.replaceAll("miss", "hit")
  check("replace all changed the document", editor.getMarkdown() === "miss miss miss\n")
  host.querySelector(".cm-content").dispatchEvent(new dom.window.KeyboardEvent("keydown", {
    key: "z", code: "KeyZ", ctrlKey: true, bubbles: true, cancelable: true,
  }))
  check("replace all is one undo step", editor.getMarkdown() === "hit hit hit\n")
})

run("| Head |\n| --- |\n| needle |\n\n```mermaid\ngraph LR\nneedle-->end\n```\n", (editor, host) => {
  editor.replaceAll("pin", "needle")
  check("replace edits table and fenced source", editor.getMarkdown().split("pin").length === 3)
})

run("big\n".repeat(11000), (editor) => {
  const result = editor.find("big")
  check("match count is capped for highlighting", result.total === 10000 && result.capped === true)
  const all = editor.replaceAll("x", "big")
  check("replace all ignores the highlight cap", all.replaced === 11000 && !editor.getMarkdown().includes("big"))
})

// The preview builds its patterns separately (SearchPatternScript.swift); this
// shared fixture keeps both engines on the same matches.
const parity = JSON.parse(readFileSync(new URL("../../../tests/fixtures/find-parity.json", import.meta.url), "utf8"))
for (const item of parity) {
  run(item.text, (editor, host) => {
    const result = editor.find(item.query, false, { mode: item.mode, caseSensitive: item.caseSensitive })
    const found = [...host.querySelectorAll(".cm-find-match")].map((node) => node.textContent)
    check(`parity: ${item.mode}${item.caseSensitive ? "+case" : ""} "${item.query}" in "${item.text}"`,
      JSON.stringify(found) === JSON.stringify(item.matches) && !!result.error === !!item.error)
  })
}
