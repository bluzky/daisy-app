# plan

Lucy workflow. Run only when Lucy is addressed (see `../SKILL.md`).

After Gate 1, before tickets. Turns the approved spec into an **implementation plan**: phases, each one ticket and one PR, with a breakdown of what to change where. Runs as the **tech design agent** (plan mode). Rules: FLOW-10.

## Input

`plan <design ticket url or id>`

## Steps

1. **Gate check (FLOW-02).** Confirm the spec is **approved** as the tracker defines it (`docs/ai/flow/tracker.md`: ClickUp `done`/`complete`, GitHub issue closed as completed, no tracker: spec on the target branch). If not, stop. (Auto flow: the plan may be drafted before approval; it is part of checkpoint 1, FLOW-11.)
2. Load `docs/ai/roles/tech-design-agent.md` (plan mode), `docs/ai/templates/implementation-plan.md` and `docs/ai/checklists/gate-2-plan-review.md`. Read the spec from the target branch (`docs/ai/flow/spec.md`): §2 (design, impact table, ordering constraints), §3 (stories and ACs), §4 (decisions).
3. **Map to the code.** For every §2 part (migration, API, job, config, screen) and every AC, find the context / module and files it lands in, reusing the §2 impact table. Cite paths (CORE-05).
4. **Group into phases (FLOW-10).** As few phases as possible: put stories together unless a split is needed (PR too big to review, deploy order such as a migration before the code that uses it, or different risk). Each `US-n` goes in exactly one phase.
5. **Write each phase:** stories, depends on, why this phase, breakdown (`Context / module | What to do | Spec ref`), tests per AC, migration/config notes, risks.
6. **Self-check** against every item of the Gate 2 checklist (G2-01…G2-10). Fix what you can; gaps in the spec go back to the spec (FLOW-05), never into the plan.
7. Write `docs/features/<feature-slug>-plan.md` **on the current branch**. Don't create or switch branches. Don't commit unless the engineer asks.
8. Present the plan: phases table, then per phase the breakdown, why stories were grouped or split, and the Gate 2 checklist result (`G2-nn | pass / fail | gap`).

## Submit for review (Gate 2)

When the engineer asks ("Lucy, submit the plan for review") and the checklist has no failures: commit the plan on the current branch and open the plan PR into the target branch (`gh pr create --base <target branch>`), title `[PLAN] <feature>`, description with the design ticket and spec links, the phases table and the checklist result. If the current branch is the target branch itself, ask which branch to use. The tech lead approves and merges it; then run `create-tickets`.

## Never

- Change the spec (§1–§4). A gap found while planning is a spec change (FLOW-05).
- Create tickets (that's `create-tickets`, after the plan PR is merged).
- Write production code.
