// Editor smoke tests: comments hide their markup like bold and italic until
// the caret is on their line, and collapse their notes into a bubble.
import { dom, check } from "./harness.mjs"

const create = (source) => {
  const host = dom.window.document.createElement("div")
  dom.window.document.body.appendChild(host)
  const editor = dom.window.MDEditor.create(host, source, {})
  return { host, editor }
}
const lines = (host) => Array.from(host.querySelectorAll(".cm-line")).map((el) => el.textContent)
const bubbles = (host) => Array.from(host.querySelectorAll(".cm-comment-point"))
const anchors = (host) => Array.from(host.querySelectorAll(".cm-comment-anchor[data-comment]"))

const source = "intro\n\nThe API returns {==a 404==}{>>Should be 410<<} today.\n\nlast line"
const commentLine = source.indexOf("The API")

{
  const { host, editor } = create(source)
  editor.select(source.length)
  check("off the caret's line, highlighted text carries the note as in Read mode",
    anchors(host).length === 1 && anchors(host)[0].getAttribute("data-comment") === "Should be 410"
      && anchors(host)[0].textContent === "a 404")
  check("a comment with highlighted text gets no bubble", bubbles(host).length === 0)
  check("its markup and note text are hidden",
    !lines(host).some((line) => line.includes("{==") || line.includes("{>>") || line.includes("Should be 410")))
  check("the commented text stays, highlighted",
    lines(host).some((line) => line.includes("The API returns a 404") && line.includes("today.")))
  check("hiding leaves the document untouched", editor.getMarkdown() === source)

  editor.select(commentLine + 5)
  check("the caret on its line shows the source and drops the popover",
    anchors(host).length === 0
      && lines(host).some((line) => line.includes("{==a 404==}{>>Should be 410<<}")))
  check("the shown source is dimmed and the note tinted",
    host.querySelectorAll(".cm-comment-syntax").length === 4 && host.querySelector(".cm-comment-note") != null)

  editor.select(source.length)
  check("it collapses again when the caret leaves", anchors(host).length === 1)
  editor.destroy()
}

{
  const doc = "one {>>a spot<<} two\n\nplain"
  const { host, editor } = create(doc)
  editor.select(doc.length)
  check("a comment on a spot is a bubble with no highlight",
    bubbles(host).length === 1 && bubbles(host)[0].getAttribute("data-comment") === "a spot"
      && host.querySelector(".cm-comment-anchor") == null
      && lines(host)[0].replace(/\s+/g, " ").trim() === "one two")
  editor.destroy()
}

{
  const doc = "{==x==}{>>first<<}{>>AI: done<<}\n\nplain"
  const { host, editor } = create(doc)
  editor.select(doc.length)
  check("replies share the comment's one popover, each behind a bullet",
    anchors(host).length === 1 && anchors(host)[0].getAttribute("data-comment") === "\u2022 first\n\u2022 AI: done"
      && anchors(host)[0].hasAttribute("data-list"))
  editor.destroy()
}

{
  const doc = "`{>>not a comment<<}` and\n\n```\n{==x==}{>>nor this<<}\n```\n\nend"
  const { host, editor } = create(doc)
  editor.select(doc.length)
  check("code is left alone", bubbles(host).length === 0 && anchors(host).length === 0)
  editor.destroy()
}

{
  const doc = "one {>>a spot<<} two\n\nplain"
  const { host, editor } = create(doc)
  editor.select(doc.length)
  bubbles(host)[0].dispatchEvent(new dom.window.MouseEvent("mousedown", { bubbles: true, cancelable: true }))
  check("clicking the bubble brings the source back to edit",
    bubbles(host).length === 0 && lines(host).some((line) => line.includes("{>>a spot<<}")))
  editor.destroy()
}

{
  const { host, editor } = create("find the limit here\n\nlast")
  editor.select("find the ".length, "find the limit".length)
  editor.exec("comment")
  check("Insert ▸ Comment wraps the selection and leaves the caret in the note",
    editor.getMarkdown() === "find the {==limit==}{>><<} here\n\nlast"
      && lines(host)[0].includes("{==limit==}{>><<}"))
  editor.destroy()
}

{
  const doc = "a {>>   <<} b {==x==}{>> <<} c\n\nplain"
  const { host, editor } = create(doc)
  editor.select(doc.length)
  check("a note with no text is no comment, as in Read mode",
    bubbles(host).length === 0 && anchors(host).length === 0
      && lines(host)[0].includes("{>>   <<}") && lines(host)[0].includes("{==x==}{>> <<}"))
  editor.destroy()
}

{
  const doc = "{==x==}{>><<}{>>real<<}\n\nplain"
  const { host, editor } = create(doc)
  editor.select(doc.length)
  check("an empty note beside a real one stays inside the one comment, with no bullet",
    anchors(host).length === 1 && anchors(host)[0].getAttribute("data-comment") === "real"
      && !anchors(host)[0].hasAttribute("data-list")
      && !lines(host)[0].includes("{>>"))
  editor.destroy()
}

{
  const doc = "plain `inline code` here\n\n```\nfenced code\n```\n"
  const { host, editor } = create(doc)
  editor.select(doc.indexOf("inline"), doc.indexOf("inline") + 6)
  editor.exec("comment")
  check("Insert ▸ Comment does nothing inside inline code", editor.getMarkdown() === doc)
  editor.select(doc.indexOf("fenced"), doc.indexOf("fenced") + 6)
  editor.exec("comment")
  check("Insert ▸ Comment does nothing inside a code block", editor.getMarkdown() === doc)
  editor.select(doc.indexOf("fenced"))
  editor.exec("comment")
  check("nor with just the caret in code", editor.getMarkdown() === doc)
  editor.destroy()
}

{
  const { host, editor } = create("find the limit here")
  editor.select("find the ".length, "find the limit".length)
  editor.exec("comment")
  editor.exec("comment")
  check("pressing Insert ▸ Comment again inside the empty note adds nothing",
    editor.getMarkdown() === "find the {==limit==}{>><<} here")
  editor.destroy()
}

{
  const doc = "{==a==} x ==}{>>n<<} end\n\nplain"
  const { host, editor } = create(doc)
  editor.select(doc.length)
  check("an anchor ends at its first closing mark, as in Read mode",
    anchors(host).length === 0 && bubbles(host).length === 1
      && lines(host)[0].includes("{==a==} x"))
  editor.destroy()
}

{
  // A paragraph taller than the viewport: only its tail is visible, yet the
  // anchor that starts at its top is still decorated.
  const rows = Array.from({ length: 60 }, (_, index) => `row ${index}`)
  const doc = ["{==start of a long", ...rows, "end of it==}{>>tall note<<}", "", "plain"].join("\n")
  const { host, editor } = create(doc)
  editor.select(doc.length)
  const anchor = host.querySelector(".cm-comment-anchor[data-comment]")
  check("a multi-line anchor is decorated as a whole", anchor != null && anchor.getAttribute("data-comment") === "tall note")
  editor.destroy()
}
