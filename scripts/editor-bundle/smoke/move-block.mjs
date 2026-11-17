// Editor smoke tests: `/move` — the block it takes, removing it once the host
// has written the target, moves within the document, and the Undo button.
import { dom, check } from "./harness.mjs"

const slashMenu = () => Array.from(dom.window.document.querySelectorAll(".cm-md-slash-menu")).at(-1)
const slashLabels = () => Array.from(slashMenu()?.querySelectorAll(".cm-md-slash-label") ?? []).map((el) => el.textContent)
const slashKey = (host, key) => host.querySelector(".cm-content").dispatchEvent(
  new dom.window.KeyboardEvent("keydown", { key, bubbles: true, cancelable: true }))

// An editor whose host records what `/move` hands it.
const moveEditor = (source) => {
  const host = dom.window.document.createElement("div")
  dom.window.document.body.appendChild(host)
  const picks = []
  const stale = []
  const editor = dom.window.MDEditor.create(host, source, {
    extensionState: { "slash-commands": true },
    onPickMoveTarget: (request) => picks.push(request),
    onMoveStale: (id) => stale.push(id),
  })
  editor.setMoveBlocks(true)
  return { host, editor, picks, stale }
}

// Types `/move` at the end of line `number` (1-based) and picks it.
const typeMove = ({ host, editor }, number) => {
  const lines = editor.getMarkdown().split("\n")
  const end = lines.slice(0, number).join("\n").length
  editor.insertTextAt(" /move", end, end)
  const offered = slashLabels()[0] === "Move to…"
  slashKey(host, "Enter")
  return offered
}

{
  const { editor } = moveEditor("Text\n\n")
  editor.insertTextAt("/move", 6, 6)
  check("move is not offered on a line with nothing to move", !slashLabels().includes("Move to…"))
}

{
  const { editor } = moveEditor("> quoted ")
  editor.insertTextAt("/move", 9, 9)
  check("move is not offered in a quote", !slashLabels().includes("Move to…"))
}

{
  const host = dom.window.document.createElement("div")
  dom.window.document.body.appendChild(host)
  const editor = dom.window.MDEditor.create(host, "Text ", { extensionState: { "slash-commands": true } })
  editor.insertTextAt("/move", 5, 5)
  check("move is hidden when the page cannot pick a target", !slashLabels().includes("Move to…"))
}

{
  const { editor } = moveEditor("Text ")
  editor.setMoveBlocks(false)
  editor.insertTextAt("/move", 5, 5)
  check("move is hidden outside a project", !slashLabels().includes("Move to…"))
}

{
  const setup = moveEditor("# Today\n\n- [ ] Ship p:high\n  - [ ] Build\n  - [ ] Test\n- [ ] Other\n")
  const offered = typeMove(setup, 3)
  const [pick] = setup.picks
  check("move is offered on a task line", offered)
  check("move takes the task with its subtasks",
    pick?.kind === "listItem" && pick.text === "- [ ] Ship p:high\n  - [ ] Build\n  - [ ] Test"
      && pick.firstLine === 3 && pick.lastLine === 5)
  check("move removes the typed query and its space, nothing else yet",
    setup.editor.getMarkdown() === "# Today\n\n- [ ] Ship p:high\n  - [ ] Build\n  - [ ] Test\n- [ ] Other\n")
  check("completing the move removes the block",
    setup.editor.completeMove(pick.id) === true && setup.editor.getMarkdown() === "# Today\n\n- [ ] Other\n")
  check("the Undo button puts it back", setup.editor.undoMove(pick.id) === true
    && setup.editor.getMarkdown() === "# Today\n\n- [ ] Ship p:high\n  - [ ] Build\n  - [ ] Test\n- [ ] Other\n")
  check("a move is undone only once", setup.editor.undoMove(pick.id) === false)
}

{
  const setup = moveEditor("- Parent\n    - Child\n      more\n    - Sibling\n")
  typeMove(setup, 2)
  check("a nested item moves to the margin with its continuation",
    setup.picks[0]?.text === "- Child\n  more" && setup.picks[0].firstLine === 2 && setup.picks[0].lastLine === 3)
}

{
  const setup = moveEditor("# A\nText\n## Sub\nMore\n\n# B\nOther\n")
  typeMove(setup, 1)
  const [pick] = setup.picks
  check("move on a heading takes its whole section",
    pick?.kind === "section" && pick.text === "# A\nText\n## Sub\nMore" && pick.lastLine === 4)
  setup.editor.completeMove(pick.id)
  check("removing a section leaves no double gap", setup.editor.getMarkdown() === "# B\nOther\n")
}

{
  const setup = moveEditor("Intro\n\nOne line\nand two\n\nOutro\n")
  typeMove(setup, 3)
  const [pick] = setup.picks
  check("move on a paragraph takes all of it", pick?.kind === "paragraph" && pick.text === "One line\nand two")
  setup.editor.completeMove(pick.id)
  check("removing a paragraph keeps one blank line", setup.editor.getMarkdown() === "Intro\n\nOutro\n")
}

{
  const setup = moveEditor("Keep\n\nLast")
  typeMove(setup, 3)
  setup.editor.completeMove(setup.picks[0].id)
  check("removing the last block takes the gap before it", setup.editor.getMarkdown() === "Keep")
}

{
  const setup = moveEditor("- a\n- b\n")
  typeMove(setup, 1)
  const [pick] = setup.picks
  setup.editor.insertTextAt("x", 0, 0)
  check("a block edited while the target was picked is not removed",
    setup.editor.completeMove(pick.id) === false && setup.editor.getMarkdown() === "x- a\n- b\n")
}

{
  const setup = moveEditor("- a\n- b\n")
  typeMove(setup, 1)
  const [pick] = setup.picks
  setup.editor.completeMove(pick.id)
  setup.editor.insertTextAt("c", 0, 0)
  check("an edit after the move tells the host", setup.stale.includes(pick.id))
  check("and the Undo button no longer applies",
    setup.editor.undoMove(pick.id) === false && setup.editor.getMarkdown() === "c- b\n")
}

{
  const setup = moveEditor("- a\n\n# Done\n")
  typeMove(setup, 1)
  const [pick] = setup.picks
  const expected = setup.editor.getMarkdown()
  check("a move within the document applies the host's text",
    setup.editor.applyMove(pick.id, expected, "# Done\n\n- a\n") === true
      && setup.editor.getMarkdown() === "# Done\n\n- a\n")
  check("and undoes in one step", setup.editor.undoMove(pick.id) === true
    && setup.editor.getMarkdown() === expected)
  check("a move within a changed document is refused",
    setup.editor.applyMove(99, "stale", "next") === false && setup.editor.getMarkdown() === expected)
}
