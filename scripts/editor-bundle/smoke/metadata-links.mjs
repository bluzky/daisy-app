// Editor smoke tests: metadata tokens as links in a workspace window, and
// Cmd+click opening of tokens and Markdown links.
import { dom, check } from "./harness.mjs"

const create = (source, extra = {}) => {
  const host = dom.window.document.createElement("div")
  dom.window.document.body.appendChild(host)
  const opened = []
  const editor = dom.window.MDEditor.create(host, source, { onOpenLink: (link) => opened.push(link), ...extra })
  return { host, editor, opened }
}
const links = (host) => Array.from(host.querySelectorAll(".cm-md-metadata-link")).map((el) => el.textContent)
const json = (value) => JSON.stringify(value)

// --- Decorations -----------------------------------------------------------

{
  const { host, editor } = create("Plan #review with @alex for +daisy\n")
  check("tokens are plain text outside a workspace", links(host).length === 0
    && !host.querySelector(".cm-editor").classList.contains("cm-metadata-links"))
  editor.setMetadataLinks(true)
  check("tokens read as links in a workspace", links(host).join() === "#review,@alex,+daisy"
    && host.querySelector(".cm-editor").classList.contains("cm-metadata-links"))
  editor.setMetadataLinks(false)
  check("leaving the workspace turns the links off", links(host).length === 0)
  editor.destroy()
}

{
  const { host, editor } = create("#area/sub and #a/ and C#x and `#code` and [#text](x.md) and #tag.\n")
  editor.setMetadataLinks(true)
  check("only tokens the extractor reads become links", links(host).join() === "#area/sub,#tag")
  editor.destroy()
}

{
  const { host, editor } = create("#review\n", { extensionState: { "metadata-links": false } })
  editor.setMetadataLinks(true)
  check("the module off leaves tokens as text", links(host).length === 0)
  editor.destroy()
}

// --- Cmd+click ---------------------------------------------------------------

{
  const source = "Plan #review today\n"
  const { editor, opened } = create(source)
  check("a token outside a workspace opens nothing", editor.openLinkAt(source.indexOf("#review") + 2) === null)
  editor.setMetadataLinks(true)
  const link = editor.openLinkAt(source.indexOf("#review") + 2)
  check("a token opens its page", json(link) === json({ token: "#review" }) && json(opened) === json([{ token: "#review" }]))
  check("plain text opens nothing", editor.openLinkAt(1) === null && opened.length === 1)
  editor.destroy()
}

for (const [name, source, at, destination] of [
  ["an inline link", "See [docs](notes/a.md) now\n", "docs", "notes/a.md"],
  ["a link's URL", "See [docs](notes/a.md) now\n", "notes", "notes/a.md"],
  ["a link with a title", "See [docs](https://example.com \"Example\")\n", "docs", "https://example.com"],
  ["an angle-bracket destination", "See [docs](<my notes.md>)\n", "docs", "my notes.md"],
  ["an autolink", "See <https://example.com> now\n", "example", "https://example.com"],
  ["a bare URL", "See https://example.com now\n", "example", "https://example.com"],
]) {
  const { editor, opened } = create(source)
  const link = editor.openLinkAt(source.indexOf(at) + 1)
  check(`Cmd+click opens ${name}`, json(link) === json({ destination }) && opened.length === 1)
  editor.destroy()
}

for (const [name, source, at] of [
  ["a section link", "See [top](#top)\n", "top"],
  ["an image", "![alt](a.png)\n", "alt"],
  ["a reference link", "See [docs][ref]\n\n[ref]: a.md\n", "docs"],
]) {
  const { editor, opened } = create(source)
  check(`Cmd+click leaves ${name} alone`, editor.openLinkAt(source.indexOf(at) + 1) === null && opened.length === 0)
  editor.destroy()
}

// --- Cmd held -----------------------------------------------------------------

{
  const { host, editor } = create("See [docs](a.md)\n")
  const root = host.querySelector(".cm-editor")
  const content = host.querySelector(".cm-content")
  const key = (type, extra) => content.dispatchEvent(new dom.window.KeyboardEvent(type, { key: "Meta", bubbles: true, ...extra }))
  key("keydown", { metaKey: true })
  check("holding Cmd marks the editor", root.classList.contains("cm-mod-held"))
  key("keyup", { metaKey: false })
  check("releasing Cmd clears the mark", !root.classList.contains("cm-mod-held"))
  content.dispatchEvent(new dom.window.MouseEvent("mousemove", { metaKey: true, bubbles: true }))
  check("moving with Cmd held marks the editor", root.classList.contains("cm-mod-held"))
  content.dispatchEvent(new dom.window.MouseEvent("mousemove", { metaKey: false, bubbles: true }))
  check("moving without Cmd clears the mark", !root.classList.contains("cm-mod-held"))
  editor.destroy()
}

// --- Autolinks ---------------------------------------------------------------

{
  const source = "See https://example.com/a, www.daisy.app and me@example.com or <https://x.y> here\n\nEnd"
  const { host, editor } = create(source)
  editor.select(source.length)
  const linked = Array.from(host.querySelectorAll(".cm-md-link")).map((el) => el.textContent)
  check("bare URLs, www. and email addresses read as links",
    json(linked) === json(["https://example.com/a", "www.daisy.app", "me@example.com", "https://x.y"]))
  check("trailing punctuation stays outside a bare URL", !linked.some((text) => text.endsWith(",")))
  check("an autolink's brackets hide while the caret is elsewhere", !host.textContent.includes("<https://x.y>"))
  check("Cmd+click opens a www. address over http",
    editor.openLinkAt(source.indexOf("www.") + 2)?.destination === "http://www.daisy.app")
  check("Cmd+click opens an email address as mail",
    editor.openLinkAt(source.indexOf("me@") + 1)?.destination === "mailto:me@example.com")
  check("Cmd+click opens a bare URL as written",
    editor.openLinkAt(source.indexOf("https://ex") + 3)?.destination === "https://example.com/a")
  editor.destroy()
}

// --- Open Link at Caret ---------------------------------------------------------

{
  const source = "See [docs](a.md) and #review, @alex +daisy\nplain\n"
  const { editor, opened } = create(source)
  editor.setMetadataLinks(true)
  const at = (offset) => { editor.select(offset); return editor.openLinkAtCaret() }
  check("the caret inside a link opens it", json(at(source.indexOf("docs") + 2)) === json({ destination: "a.md" }))
  check("the caret right after a link opens it", json(at(source.indexOf(")") + 1)) === json({ destination: "a.md" }))
  for (const token of ["#review", "@alex", "+daisy"]) {
    const from = source.indexOf(token)
    check(`the caret before, inside and after ${token} opens it`,
      [from, from + 2, from + token.length].every((offset) => json(at(offset)) === json({ token })))
  }
  const count = opened.length
  check("the caret in plain text opens nothing",
    at(source.indexOf("See") + 1) === null && at(source.indexOf("plain")) === null && opened.length === count)
  editor.destroy()
}
