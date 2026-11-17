# spec-check

Lucy workflow. Run only when Lucy is addressed (see `../SKILL.md`).

Before Gate 1. Runs as the **spec reviewer** (readiness mode). Read-only.

## Steps

1. Load `docs/ai/roles/spec-reviewer.md` and `docs/ai/checklists/gate-1-design-review.md`.
2. Read the spec file in the repo (`docs/ai/flow/spec.md` → "Finding the spec") and, for impact checks, the relevant code.
3. If your tool supports subagents, run the review in a fresh one with the spec reviewer role (Claude Code: `spec-reviewer-agent`), so it doesn't share the drafting context; otherwise do the review directly.
4. Report in the spec reviewer's **readiness mode** format (`docs/ai/roles/spec-reviewer.md`), including the 3–5 G1-15 questions for the tech lead.
5. **Submit for review** (only if the engineer asks, e.g. "Lucy, submit the spec for review"): if there are no blockers, commit the spec on the **current branch** and open the spec PR from it into the target branch (`gh pr create --base <target branch>`), taken from the spec header; if it's empty, ask the engineer which feature or epic branch and fill it in. If the current branch is the target branch itself, stop and ask which branch to use; don't pick one. PR title `[DESIGN] <feature>`, description with the design ticket link, mockup link (if any) and the readiness summary. Then move the design ticket to `in review` (`docs/ai/flow/tracker.md`; no tracker: skip) and tell the engineer to request the tech lead's review.

Never mark the spec approved, approve the spec PR or move the design ticket to `done` (CORE-02).
