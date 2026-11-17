# Flow Rules

Apply to every feature or big improvement covered by the Design-Before-Code flow (see `docs/ai/flow/lifecycle.md` for when the flow applies).

## FLOW-01 — One spec per feature

**Severity:** MUST

- Each feature has one **design ticket** (`[DESIGN] <feature>`; with no tracker, the feature slug stands in, see `docs/ai/flow/tracker.md`) and one Feature Spec **in the repo** at `docs/features/<feature-slug>.md` (template: `docs/ai/templates/feature-spec.md`), linked from the design ticket (description or comment). See `docs/ai/flow/spec.md`.
- After Gate 1, an **implementation plan** (`docs/features/<feature-slug>-plan.md`) splits the work into **phases** (FLOW-10). Each phase is one **phase ticket** (`[P1] <title>`), linked to the design ticket, and one PR. See `docs/ai/flow/tracker.md`.
- The spec is the requirement. Ticket titles and copied ACs are not: if they differ, the spec wins.

## FLOW-02 — No code before approval

**Severity:** MUST NOT

- Don't write production code until the spec is **approved** at Gate 1: the design ticket is `done` or `complete` (ClickUp), closed as completed (GitHub), or the spec and plan are merged on the target branch (no tracker). What "approved" means is set by the tracker, `docs/ai/flow/tracker.md`.
- Don't create phase tickets before that, and before the implementation plan is merged into the target branch (FLOW-10).
- In the auto flow (FLOW-11), the engineer's recorded approval of the spec and plan counts as approved.
- Allowed before approval: the spec, the plan draft, `spec-draft`, `tech-design`, `impact-scan`, a `mockup/<feature>` branch (FE only, mock data), throwaway spikes on `spike/*` branches.

## FLOW-03 — Stable IDs

**Severity:** MUST

- Business rules: `BR-1`, `BR-2`, …
- User stories: `US-1`, `US-2`, …
- Acceptance criteria: `AC-<story>.<n>` (e.g. `AC-1.2`).
- Open questions: `Q-1`, `Q-2`, …
- Never renumber an approved ID. Add new IDs at the end; mark removed ones as `~~removed~~`.

## FLOW-04 — Traceability

**Severity:** MUST

- Every AC traces to at least one BR (or is marked as UI-only).
- Every AC in a PR's scope has at least one test with the AC ID in its name (`test_AC_1_2_…` or `"AC-1.2 …"`).
- Every AC in a PR's scope has evidence (screenshot, recording or test output) in the PR description.

## FLOW-05 — Spec matches code

**Severity:** MUST

- If the design must change during implementation, stop, update the spec, and tell the tech lead before coding the change.
- A PR lists every difference from the approved spec under "Differences from the spec".

## FLOW-06 — Mockups are never merged

**Severity:** MUST NOT

- `mockup/*` branches contain FE code with mock data only: no backend, API, DB or migration changes.
- They are never merged. UI code may be copied into the feature branch in Step 4.

## FLOW-07 — One PR, one phase ticket

**Severity:** MUST

- Each PR belongs to exactly one phase ticket and covers **all and only** the ACs of that phase's stories (from the plan, e.g. `AC-1.*` and `AC-2.*` for `Stories: US-1, US-2`), backend and frontend together.
- If a phase turns out too big for one PR, split the phase in the plan (plan PR), not the PR.
- Work on phases in plan order; don't start a phase before the phases it depends on are merged (`dev ready` or later), unless the tech lead agrees.

## FLOW-08 — Spec in the repo, tracker after approval

**Severity:** MUST

- Write and review the spec in the repo, on the branch the engineer chooses, through a PR into the feature or epic branch (the **target branch**), reviewed by the tech lead. Agents don't create or switch branches for the spec.
- The spec on the target branch is the source of truth. Any published copy (a ClickUp Doc) is read-only.
- Publish (`spec-publish`, where the tracker has something to publish to) only after the spec PR is approved and merged. Never publish a draft.

## FLOW-09 — Keep the spec simple

**Severity:** MUST

- Solve the stated problem only. No speculative features, config, flags or extensibility.
- Handle an edge case only if it's **likely**, or if getting it wrong costs money, stock, order state, permissions, security or data that can't be fixed by hand. Otherwise list it under §1 "Not handled" and move on.
- Prefer existing patterns, tables, endpoints and services over new ones.
- **Only BRs that are needed.** Add a BR only for a rule that changes behavior and that the design or an AC depends on. No BR for current behavior that doesn't change, for something the code or framework already guarantees, or for a restatement of another BR.
- **Only stories that are needed.** One story per distinct user goal that ships or gets tested on its own. Don't split one goal into several stories, or add stories for setup, refactors or "nice to have".
- One AC per behavior, not per input variation.
- **Only ACs that matter.** Write an AC only for behavior someone could reasonably get wrong or a reviewer would ask about. Common sense, so no AC: "other rows are unchanged", "nothing else happens", "the saved value is shown", standard validation, auth or permissions the framework already enforces, the same happy path restated. Usually **1–4 ACs per story**; more than 5 needs a reason.
- **Fewer is better.** Never add a BR, story or AC to reach a number. A small feature can have 2 BRs and 1 story.
- Scale rollout and rollback to the risk.
- Upper bound, not a target: about 10 BRs, 5 stories, 4 ACs per story for one feature. Much more usually means the feature should be split.
- Every draft goes through the `spec-review` feedback loop (spec reviewer) before it's presented.

## FLOW-10 — Implementation plan

**Severity:** MUST

- After Gate 1 and before any ticket, the tech design agent drafts `docs/features/<feature-slug>-plan.md` (template: `docs/ai/templates/implementation-plan.md`) on the current branch (`plan` workflow). It's reviewed at **Gate 2** in a plan PR into the target branch, against `docs/ai/checklists/gate-2-plan-review.md`; the tech lead approves and merges it.
- The plan splits the work into **phases**. One phase = one phase ticket (`[P<n>] <title>`) = one PR.
- **As few phases as possible.** Keep stories in the same phase unless a split is needed: the PR would be too big to review, something must deploy first (e.g. a migration before the code that uses it), or the parts carry different risk.
- Each `US-n` is in exactly one phase; every §2 part (migration, API, job, config, screen) is in a phase. Dependencies point only to earlier phases.
- Each phase lists: stories, depends on, a **breakdown** by context / module (what to do there, with file paths and spec refs), the test per AC, migration/config notes and risks.
- The plan never adds or changes requirements. A gap found while planning is a spec change (FLOW-05).
- Changing the plan after approval: a new plan PR. Don't reshape phases already in progress or merged; add a new phase instead.

## FLOW-11 — Auto flow

**Severity:** MUST

- The **auto flow** (`auto` workflow) is opt-in: it runs only when the engineer asks for it ("Lucy, auto: …", "build this end to end"). It runs the normal steps in order with the engineer as the human in the loop.
- It has exactly **two human checkpoints**: (1) review of the spec **and** the plan together, (2) final verification of the finished work. Between them Lucy keeps going without asking, and she stops at once on a stop condition (see the `auto` workflow).
- At checkpoint 1 the engineer's explicit "approved" counts as Gate 1 and Gate 2 for this feature. Lucy **records** it (spec and plan header *Status*: `Approved by <engineer> in chat, <date>`, auto flow) and tells the tracker where she can (a comment); she does not approve anything herself (CORE-02), and she never closes the design issue or sets `done`. Where a workflow's gate check asks for approval (FLOW-02), this record satisfies it **only for a feature run through the auto flow**.
- Without an explicit approval the gates are the normal ones. Changing the approved spec or plan later (FLOW-05) means a new checkpoint 1.
- The engineer's request counts as the tech lead's agreement to work phases on stacked branches before the earlier phase is merged (FLOW-07). Merging, approving a PR and any tracker status beyond `in progress` / `in review` stay with humans.
- Checkpoint 2 is verification by the engineer, not a PR approval: Lucy opens the PRs only after the engineer says it is verified.
