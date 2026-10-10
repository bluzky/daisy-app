// Editor smoke tests: in-document search.
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
const findResult = (query, backwards = false, beginsWith = false) =>
  findEditor.find(query, backwards, beginsWith)
check("editor search counts case-insensitive source matches", findResult("needle").total === 5)
check("editor search highlights without editor focus", findHost.querySelectorAll(".cm-find-match").length === 5)
check("next match advances", findResult("needle").index === 2)
check("previous match goes backwards", findResult("needle", true).index === 1)
check("previous wraps to last match", findResult("needle", true).index === 5)
check("next wraps to first match", findResult("needle").index === 1)
check("begins-with excludes mid-word matches and resets index",
  JSON.stringify(findResult("needle", false, true)) === JSON.stringify({ index: 1, total: 4 }))
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
