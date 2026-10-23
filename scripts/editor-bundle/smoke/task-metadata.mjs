// Editor smoke tests: task metadata badges for `due:`, `scheduled:` and `p:`.
import { dom, check } from "./harness.mjs"

// Fixed clock: Sunday 4 October 2026.
const sunday = () => new Date(2026, 9, 4, 14, 5)

const create = (source, extra = {}) => {
  const host = dom.window.document.createElement("div")
  dom.window.document.body.appendChild(host)
  const editor = dom.window.MDEditor.create(host, source, { slashClock: sunday, ...extra })
  return { host, editor }
}
const badges = (host) => Array.from(host.querySelectorAll(".mdp-task-badge"))
const texts = (host) => badges(host).map((badge) => badge.textContent)

{
  const { host, editor } = create("- [ ] Buy milk scheduled:2026-10-20 due:2026-10-23 p:high\n\nAfter")
  check("valid task fields render as badges",
    texts(host).join("|") === "2026-10-20 Tue|2026-10-23 Fri|HIGH")
  check("dates carry their field class and icon",
    badges(host)[0].classList.contains("mdp-task-badge-scheduled")
      && badges(host)[1].classList.contains("mdp-task-badge-due")
      && badges(host).slice(0, 2).every((badge) => badge.querySelector("svg") != null))
  check("priority is a tinted tag", badges(host)[2].classList.contains("mdp-task-badge-high")
    && badges(host)[2].classList.contains("mdp-task-badge-priority"))
  check("badges have accessible names",
    badges(host)[1].getAttribute("aria-label") === "Due: Friday, October 23, 2026"
      && badges(host)[2].getAttribute("aria-label") === "Priority: High")
  check("badges never change the Markdown",
    editor.getMarkdown() === "- [ ] Buy milk scheduled:2026-10-20 due:2026-10-23 p:high\n\nAfter")
  editor.destroy()
}

{
  const { host, editor } = create("- [ ] a p:medium\n- [ ] b p:low")
  check("each priority has its own tint",
    badges(host).map((badge) => [...badge.classList].find((name) => /-(medium|low)$/.test(name))).join()
      === "mdp-task-badge-medium,mdp-task-badge-low")
  editor.destroy()
}

{
  const { host, editor } = create("- [ ] late due:2026-10-03\n- [ ] today due:2026-10-04\n- [x] done due:2026-01-01\n- [ ] later scheduled:2026-01-01")
  check("a past due date on an open task is overdue",
    badges(host).map((badge) => badge.classList.contains("mdp-task-badge-overdue")).join() === "true,false,false,false")
  check("an overdue badge says so", badges(host)[0].getAttribute("aria-label").endsWith(", Overdue"))
  editor.destroy()
}

for (const [name, source] of [
  ["plain text", "Buy milk due:2026-10-20"],
  ["a bullet without a checkbox", "- Buy milk due:2026-10-20"],
  ["inline code", "- [ ] Buy `due:2026-10-20`"],
  ["an impossible date", "- [ ] Buy due:2026-02-30"],
  ["an unknown priority", "- [ ] Buy p:urgent"],
  ["a glued token", "- [ ] Buy xdue:2026-10-20"],
  ["a continuation line", "- [ ] Buy milk\n  due:2026-10-20"],
  ["a fenced code block", "```\n- [ ] Buy due:2026-10-20\n```"],
]) {
  const { host, editor } = create(source)
  check(`no badge in ${name}`, badges(host).length === 0)
  editor.destroy()
}

{
  const { host, editor } = create("- [ ] Buy due:2026-10-20, then p:low.")
  check("trailing punctuation stays outside the badge",
    texts(host).join("|") === "2026-10-20 Tue|LOW" && host.querySelector(".cm-line").textContent.includes(","))
  editor.destroy()
}

{
  const { host, editor } = create("- [ ] Buy due:2026-10-20 p:high")
  editor.focus()
  editor.select(17, 17)
  check("the caret on a field shows its source",
    texts(host).join("|") === "HIGH" && host.querySelector(".cm-line").textContent.includes("due:2026-10-20"))
  editor.select(0, 0)
  check("moving the caret away shows the badge again", texts(host).join("|") === "2026-10-20 Tue|HIGH")
  editor.select(24, 24)
  check("a caret at a field's end also shows its source", texts(host).join("|") === "HIGH")
  editor.destroy()
}

{
  const { host, editor } = create("- [ ] Buy due:2026-10-20", { extensionState: { "task-metadata": false } })
  check("disabling the module shows the literal text", badges(host).length === 0)
  editor.setExtensionState({ "task-metadata": true })
  check("re-enabling the module shows badges", badges(host).length === 1)
  editor.destroy()
}

{
  const { host, editor } = create("- [ ] Buy due:2026-10-20 p:medium", {
    extensionOptions: { "task-metadata": { due: "截止", medium: "中", priority: "优先级", locale: "zh-Hans" } },
  })
  check("badge labels follow the app language",
    texts(host)[1] === "中" && badges(host)[0].getAttribute("aria-label").startsWith("截止: "))
  editor.destroy()
}

{
  const { host, editor } = create("- [ ] Buy milk ", { extensionState: { "slash-commands": true } })
  editor.insertTextAt("/high", 15, 15)
  host.querySelector(".cm-content").dispatchEvent(
    new dom.window.KeyboardEvent("keydown", { key: "Enter", bubbles: true, cancelable: true }))
  // Park the caret off the field (line start now lands after the checkbox,
  // right where the field begins).
  editor.select(editor.getMarkdown().length)
  check("a field written by a slash command renders as a badge", texts(host).join() === "HIGH")
  editor.destroy()
}
