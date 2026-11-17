// Editor smoke tests: hiding checked task items while the host turns it on.
import { dom, check } from "./harness.mjs"

const create = (source, extra = {}) => {
  const host = dom.window.document.createElement("div")
  dom.window.document.body.appendChild(host)
  const editor = dom.window.MDEditor.create(host, source, extra)
  return { host, editor }
}
const lines = (host) => Array.from(host.querySelectorAll(".cm-line")).map((el) => el.textContent)
const shows = (host, text) => lines(host).some((line) => line.includes(text))

const source = "# Plan\n\n- [ ] open one\n- [x] done one\n  - [ ] open child\n- [X] done two\n- [ ] open two\n\nafter\n"

{
  const { host, editor } = create(source)
  editor.select(source.length)
  check("every task shows until the host turns hiding on",
    shows(host, "done one") && shows(host, "open child") && shows(host, "done two"))
  editor.setHostState({ "hide-completed-tasks": true })
  check("checked items and their nested items are hidden",
    !shows(host, "done one") && !shows(host, "open child") && !shows(host, "done two"))
  check("open items and other text stay",
    shows(host, "open one") && shows(host, "open two") && shows(host, "after") && shows(host, "Plan"))
  check("hiding leaves the document untouched", editor.getMarkdown() === source)
  editor.setHostState({ "hide-completed-tasks": false })
  check("turning hiding off shows them again", shows(host, "done one") && shows(host, "done two"))
  editor.destroy()
}

{
  const { host, editor } = create(source)
  editor.setHostState({ "hide-completed-tasks": true })
  editor.select(source.indexOf("done two") + 2)
  check("the item the caret is in stays shown", shows(host, "done two") && !shows(host, "done one"))
  editor.select(source.length)
  check("it hides once the caret leaves", !shows(host, "done two"))
  editor.destroy()
}

{
  const { host, editor } = create("- [ ] task\n\nend\n")
  editor.setHostState({ "hide-completed-tasks": true })
  editor.select(15)
  editor.replaceIfUnchanged("- [ ] task\n\nend\n", "- [x] task\n\nend\n")
  check("a task checked while hiding is on disappears", !shows(host, "task") && shows(host, "end"))
  editor.destroy()
}

{
  const { host, editor } = create(source, { extensionState: { "hide-completed-tasks": false } })
  editor.select(source.length)
  editor.setHostState({ "hide-completed-tasks": true })
  check("the module off shows every task", shows(host, "done one") && shows(host, "done two"))
  editor.destroy()
}
