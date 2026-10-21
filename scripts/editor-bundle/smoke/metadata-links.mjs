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
