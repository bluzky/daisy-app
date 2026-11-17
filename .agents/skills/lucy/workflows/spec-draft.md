# spec-draft

Lucy workflow. Run only when Lucy is addressed (see `../SKILL.md`).

Step 1–2 of the flow. Runs as the **PO agent**.

## Input

`spec-draft <design ticket url or id> [part]`

| Part | Drafts | When |
| --- | --- | --- |
| `business` | §1 Business flow + open questions in §4 | First pass, before `tech-design` |
| `stories` | §3 User stories & ACs + any new open questions in §4 | After §1 (and ideally §2) is reviewed |
| *(none)* | Both | Small features only |

`stories` needs a reviewed §1: if §1 is missing, stop and suggest `spec-draft <ticket> business` first.

## Steps

1. Load `docs/ai/roles/po-agent.md`, `docs/ai/templates/feature-spec.md` and `docs/ai/flow/spec.md`.
2. Read the design ticket: description, comments, attachments, linked tickets (`docs/ai/flow/tracker.md`; with no tracker, the engineer's description). Ask the engineer for any context not in the tracker (requester notes, Slack threads). Move the design ticket to `in progress` if it's still `todo` (ClickUp) or has no status label (GitHub); no tracker: skip.
3. Find or create the spec file `docs/features/<feature-slug>.md` **on the current branch** (from the template if new; ask the engineer to confirm the slug). Don't create or switch branches: the engineer decides where the spec goes. If it exists, keep every human edit (CORE-04); propose changes rather than overwriting.
4. Follow the PO agent working method. For large features, if your tool supports subagents, run it in one with the PO agent role (Claude Code: `po-agent`).
5. Write the result into the spec file, with "Draft — PO agent" in the header's *Drafted with* row. Don't commit unless the engineer asks; never publish or comment approval (that's `spec-publish`, after approval).
6. **Review before presenting.** Run the `spec-review` feedback loop on the sections just drafted (max 2 rounds).
7. Present the final draft with the review summary, then the handoff: what was drafted, open questions for the tech lead, assumptions and their sources.

## Never

- Invent a business rule (CORE-01). Unknowns become `Q-n`.
- Write §2 Technical design (that's `tech-design`).
- Mark anything approved (CORE-02).
