# create-tickets

Lucy workflow. Run only when Lucy is addressed (see `../SKILL.md`).

After Gate 2 (the plan PR is approved and merged). Creates one **phase ticket** per phase in the implementation plan. Ticket model: `docs/ai/flow/tracker.md` (ClickUp details: `docs/ai/flow/clickup.md`). **No tracker:** there are no tickets to create. Say that the plan's phases table is the list, and stop.

## Input

`create-tickets <design ticket url or id>`

## Steps

1. **Gate check (FLOW-02).** Both must be true, otherwise stop and say which fails (auto flow: the engineer's recorded approval of the spec and the plan in their headers, FLOW-11, replaces "approved" and "merged"; read them from the base branch):
   - the spec is approved (`docs/ai/flow/tracker.md`: ClickUp `done`/`complete`, GitHub issue closed as completed);
   - the plan `docs/features/<feature-slug>-plan.md` is merged into the target branch (`git show <target branch>:<plan path>`; the plan PR approved, via `gh pr list --search <plan path> --state merged` if available).
2. Read the plan and the spec from the target branch. Find the epic ticket: the design ticket's parent. If the design ticket has no parent, ask the engineer for the epic ticket (GitHub: an epic is optional, so without one create the phase issues unattached and link them to the design issue).
3. For each phase `P<n>`, in plan order, prepare a ticket: title `[P<n>] <phase title>`, description in the format in `docs/ai/flow/tracker.md` (GitHub) or `docs/ai/flow/clickup.md` (ClickUp), dependencies from the plan's "Depends on". Skip phases that already have a ticket.
4. No confirmation needed: create the tickets.
   - **GitHub:** `gh issue create` with the `phase` label and `Design: #<n>` in the body, attach to the epic if there is one, `Depends on: #<m>` for dependencies (`docs/ai/flow/tracker.md`).
   - **ClickUp**, if Lucy can write to it (MCP or the CLI — `docs/ai/flow/clickup.md`): create each as a **subtask of the epic ticket** (the design ticket's parent, a sibling of the design ticket), status `todo`, then link it to the design ticket and add the dependencies.
   - Otherwise: print each ticket (title + description) for the engineer to create.
5. Report the created ticket links. Suggest a small plan PR that fills the "Ticket" column of the phases table (no re-approval needed for that column alone).

## Never

- Create tickets before the design ticket is approved and the plan is merged (FLOW-02).
- Change phases, stories or ACs here: that's a plan or spec change. Raise it with the engineer.
- Set any status other than `todo`.
- Create a phase ticket as a subtask of the design ticket: the parent is the epic.
