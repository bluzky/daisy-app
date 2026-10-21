// Editor smoke tests: `setTaskChecked`, which the Tasks sidebar uses to check
// a task off in an editor with unsaved changes.
import { dom, check } from "./harness.mjs"

let host
const create = (source) => {
  host = dom.window.document.createElement("div")
  dom.window.document.body.appendChild(host)
  return dom.window.MDEditor.create(host, source, {})
}
const undo = () => host.querySelector(".cm-content").dispatchEvent(new dom.window.KeyboardEvent("keydown", {
  key: "z", code: "KeyZ", ctrlKey: true, bubbles: true, cancelable: true,
}))

{
  const editor = create("# Notes\n- [ ] Draft notes due:2026-10-21\n- [ ] Other")
  const result = editor.setTaskChecked(2, true, "Draft notes")
  check("setTaskChecked flips only the marker",
    result?.changed === true && result.line === 2
      && editor.getMarkdown() === "# Notes\n- [x] Draft notes due:2026-10-21\n- [ ] Other")
  check("setTaskChecked returns the updated buffer", result.markdown === editor.getMarkdown())
  undo()
  check("setTaskChecked is one undoable edit",
    editor.getMarkdown() === "# Notes\n- [ ] Draft notes due:2026-10-21\n- [ ] Other")
  editor.destroy()
}

{
  const editor = create("Intro\n\n> - [x] Quoted p:high")
  const result = editor.setTaskChecked(1, false, "Quoted")
  check("setTaskChecked follows a task that moved to another line",
    result?.line === 3 && editor.getMarkdown() === "Intro\n\n> - [ ] Quoted p:high")
  editor.destroy()
}

{
  const editor = create("- [ ] Same\n- [ ] Same")
  check("setTaskChecked refuses duplicate text on a stale line",
    editor.setTaskChecked(5, true, "Same") === null && editor.getMarkdown() === "- [ ] Same\n- [ ] Same")
  editor.destroy()
}

{
  const editor = create("- [x] Done")
  const result = editor.setTaskChecked(1, true, "Done")
  check("setTaskChecked on a task already in that state changes nothing",
    result?.changed === false && editor.getMarkdown() === "- [x] Done")
  check("setTaskChecked refuses a task that is gone", editor.setTaskChecked(1, true, "Missing") === null)
  editor.destroy()
}

{
  const editor = create("```\n- [ ] Code\n```")
  check("setTaskChecked ignores tasks in code", editor.setTaskChecked(2, true, "Code") === null)
  editor.destroy()
}
