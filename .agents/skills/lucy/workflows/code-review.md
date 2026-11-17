# code-review

Lucy workflow. Run only when Lucy is addressed (see `../SKILL.md`).

Reviews a phase from several angles in two situations: **self-review** by the engineer after implementing the phase and before opening the PR, and **Gate 3** review of the open PR. Each angle is its own reviewer in a fresh context, and the results are merged. Runs as the **PR reviewer** (coordinator). Read-only.

## Modes

| Mode | When | Reviews | Differences |
| --- | --- | --- | --- |
| **Self-review** | After `implement-phase`, before `pr-prepare` (no PR yet) | `git diff <base>...HEAD` of the current branch | No PR description exists, so the business reviewer skips the PR-description checks (evidence table, "Differences from the spec") and says so; `pr-prepare` fills them later. Findings are for the engineer to fix |
| **Gate 3** | The PR is open | `gh pr diff <PR>` and the PR description | Full review, including the PR-description checks. Run by the reviewer or the engineer |

The mode is picked from the request: "review my changes" / "self-review" → self-review; "review PR 123" → Gate 3. With no PR number, use the current branch's open PR if there is one, else self-review.

## Input

`code-review [angle] [PR number | phase ticket | branch]` — default: the open PR of the current branch (Gate 3), else the branch diff (self-review); all angles.

| Angle | Say something like | Role |
| --- | --- | --- |
| `business` | "review the business implementation", "does the PR match the spec?" | `review-business` |
| `structure` | "review the code structure" | `review-structure` |
| `style` | "review the code style" | `review-style` |
| `workflow-json` | "review the workflow JSON" | `review-workflow-json` |
| *(none)* | "review the PR", "review my changes", "self-review [P1] …" | All that apply |

## Steps

1. **Find the phase and the business document.** From the PR, the branch name (`feature/<phase-ticket-id>-…`) or the engineer: read the phase ticket, the plan phase `P<n>` and the spec from the target branch. If there is no phase ticket, search the repo for an existing business document as in `docs/ai/roles/review-business.md` → "Finding the business document". If none is found, **ask the engineer** for it (path, link, ticket or pasted text) before the business angle runs; if they have none, skip that angle and say so.
2. **Get the diff.** Gate 3: `gh pr diff <PR>` and the PR description. Self-review: `git diff <base>...HEAD` (`<base>`: the branch the PR will merge into) and the uncommitted changes. Note the changed paths and the mode.
3. **Find the project's guides** (`docs/ai/flow/project-guides.md`): search the repo for coding conventions, style guides and review guides, per part (backend, frontend), and pass them to the reviewers.
4. **Pick the angles from the diff.** Not every change needs all four. Use the "Runs when / Skip when" table in `docs/ai/roles/pr-reviewer.md` on the changed files and a quick read of the diff (e.g. docs-only: none; formatting or a copy change: style only; a new endpoint with a migration: business, structure and style; workflow JSON only: workflow-json, plus business if it changes behaviour). If the engineer named an angle, run it even if you'd skip it. When unsure, run it.
5. **Run each angle** in a fresh context with its role. If your tool supports subagents (Claude Code: `review-business-agent`, `review-structure-agent`, `review-style-agent`, `review-workflow-json-agent`), start them **in parallel** and give each the PR, the phase, the diff and the spec and plan paths. Otherwise do the angles one after another, following one role at a time.
6. **Merge** as in `docs/ai/roles/pr-reviewer.md` → "Merging the angle reports", then present the report. List every angle as `run` or `skipped: <reason>`.
7. **Next steps.** Self-review: offer to fix the findings the engineer picks (a normal change on the branch, done after the review, not by the reviewers), then suggest `pr-prepare`. Gate 3: offer to post the findings as inline comments on the PR, only when asked, using the project's PR-review conventions. After fixes, re-run only the angles that had findings.

## Never

- Edit code, the spec or the plan, or commit, during the review itself.
- Approve or request changes on the PR, merge, or move any ticket (CORE-02).
- Post comments on the PR unless the engineer asked.
- Report a finding without a `file:line` or spec reference (CORE-05).
