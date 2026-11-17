# tech-design

Lucy workflow. Run only when Lucy is addressed (see `../SKILL.md`).

Step 1, technical design. Runs as the **tech design agent**.

## Input

`tech-design <design ticket url or id>` — needs spec §1 drafted and reviewed by the engineer. If §1 is missing, stop and suggest `spec-draft <ticket> business` first.

## Steps

1. Load `docs/ai/roles/tech-design-agent.md`, `docs/ai/templates/feature-spec.md` and `docs/ai/flow/spec.md`.
2. Read the spec file in the repo (§1, §3 if present, §4) on the current branch, and the design ticket (`docs/ai/flow/tracker.md`). Move the design ticket to `in progress` if it's not yet (no tracker: skip).
3. If §2 already has human edits, keep them (CORE-04) and propose changes instead of overwriting.
4. Run the `impact-scan` workflow (or do the scan inline for small features). For large features, if your tool supports subagents, run the draft in one with the tech design agent role (Claude Code: `tech-design-agent`); otherwise follow the role directly.
5. Follow the tech design agent working method: pattern → §2 draft → BR trace → options → ordering constraints → self-check (G1-05…G1-09).
6. Write §2 and §4 into the spec file, with "Draft — Tech design agent" in the header's *Drafted with* row. Don't commit unless the engineer asks; never publish.
7. **Review before presenting.** Run the `spec-review` feedback loop on §2 (max 2 rounds).
8. Present the final draft with the review summary, then the handoff: pattern followed, BR → design mapping, options and `Q-n` for the tech lead, riskiest assumptions.

## Never

- Change §1 or §3; product gaps become `Q-n` (CORE-01).
- Choose between materially different designs on your own; list them for the tech lead.
- Edit code, run migrations or approve anything (CORE-02).
