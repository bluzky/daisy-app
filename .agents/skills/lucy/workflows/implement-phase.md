# implement-phase

Lucy workflow. Run only when Lucy is addressed (see `../SKILL.md`).

Step 4. Runs as the **implementer** (implement mode). One phase ticket per run; one phase = one PR (FLOW-07).

## Input

`implement-phase <phase ticket url or id>` — the ticket title carries the phase, e.g. `[P1] Calculate suggestions`. No tracker: `implement-phase <feature slug> P<n>`.

## Steps

1. **Read the phase ticket.** Get `P<n>` from the title tag and the design ticket (the linked task whose title starts with `[DESIGN]`; the parent is the epic). No `[P<n>]` tag or no design ticket: stop and ask the engineer.
2. **Gate check (FLOW-02).** Confirm the spec is approved as the tracker defines it (`docs/ai/flow/tracker.md`). If not, or unknown, stop and tell the engineer. Don't continue on "it's approved, trust me": ask them to get the tech lead to move it to `done`.
3. **Dependencies.** If a phase in "Depends on" isn't merged yet (`dev ready` or later), warn the engineer and ask whether to continue.
   Once the checks pass, move the phase ticket to `in progress` before coding (`docs/ai/flow/tracker.md`; no tracker: skip).
4. Load `docs/ai/roles/implementer.md` (Implement mode). From the target branch, read phase `P<n>` in the plan, then spec §1, §2 and only this phase's stories in §3. The spec is the source of truth; if the ticket or the plan differs from it, flag it.
4b. **Find the project's guides** for the parts this phase changes (backend, frontend): coding conventions, style guides, review guides, lint configs (`docs/ai/flow/project-guides.md`, CORE-07). Read the coding conventions and the review guide before coding and write to both: the review (self-review and Gate 3) checks the same guides.
5. Branch: `feature/<phase-ticket-id>-<short-name>`, created from the current branch (reuse it if it exists).
6. Follow the phase breakdown row by row. Confirm with the engineer if any AC or row is ambiguous (CORE-06).
7. For each AC: write the test named in the plan (AC ID in the name, e.g. `test_AC_2_1_cancel_unpaid_order` or `"AC-2.1 cancel unpaid order"`), then the smallest code that passes it.
8. If the plan or §2 is wrong or incomplete: stop, explain, and wait for the plan or spec to be updated (FLOW-05, FLOW-10).
9. Run the tests, and the project's formatter and linter (from the guides or configs), for changed files. Report honestly: passing, failing, not run.
10. If the mockup branch has reusable UI for this phase, copy it and replace mock data with real API calls.

## Never

- Implement ACs of stories outside this phase (FLOW-07).
- Move the ticket to any status other than `in progress` (humans do).

## Output

Changed files per breakdown row, the guides followed (per part), test and lint results per AC, anything not done, and any plan or spec gaps found. Suggest the next steps: `code-review` as a self-review ("Lucy, review my changes"), then `pr-prepare`.
