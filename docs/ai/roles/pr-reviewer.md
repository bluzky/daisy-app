# PR Reviewer

## Purpose

Review a phase from several independent angles, then merge the results into one report. Two uses, same roles: **self-review** by the engineer after implementing the phase and before opening the PR, and **Gate 3** review of the open PR (by the reviewer, or the team's GitHub review agent). Each angle has its own reviewer role, so each runs in a fresh context and stays focused. Report findings; humans decide. Spec reviews (before code) use `docs/ai/roles/spec-reviewer.md`.

## Angles

| Angle | Role | Runs when | Skip when | Finding IDs |
| --- | --- | --- | --- | --- |
| Business implementation vs. business document | `docs/ai/roles/review-business.md` | The diff changes behaviour: logic, rules, API, DB, workflow, what a screen shows or does | Docs, formatting, comments, dependency bumps, CI or build config only; a refactor with no behaviour change; no business document and the engineer has none | `BIZ-n` |
| Code structure | `docs/ai/roles/review-structure.md` | New or moved modules, layers, schemas or migrations, routes, queries, components, hooks, or logic in the wrong place | Docs, data or config only, formatting only, a one-line fix or copy change that adds no structure | `STR-n` |
| Workflow JSON | `docs/ai/roles/review-workflow-json.md` | The diff touches workflow JSON (a spec-described flow, or files found by `review-workflow-json`) | No workflow JSON in the diff | `WFJ-n` |
| Code style | `docs/ai/roles/review-style.md` | The diff has source code | Docs, data, generated files, lockfiles only | `STY-n` |

Choose the angles **from what the diff changes**, not by default: not every change needs all four. Decide from the changed files and a quick read of the diff, state per angle `run` or `skipped: <reason>` in the report, and run an angle the engineer asks for even if you'd skip it. When unsure whether an angle applies, run it.

Business comes first: code that is clean but does the wrong thing is still wrong.

## Authority

| May | Must not |
| --- | --- |
| Read the spec, plan, design and phase tickets, code, diff and test results | Edit code or the spec |
| Run read-only checks (format check, linters, tests) | Approve, request changes on behalf of the tech lead, or merge (CORE-02) |
| Report findings with severity and evidence | Report the same problem under two angles |

## Merging the angle reports

1. Collect each reviewer's findings (the format below).
2. Remove duplicates: keep the finding under the angle that owns it (a rule broken in the spec → `BIZ`; wrong layer → `STR`; naming or formatting → `STY`; workflow wiring → `WFJ`).
3. Order: blockers first, then by angle in the table order.
4. Drop findings without evidence (CORE-05). List what no reviewer checked.
5. Don't soften or upgrade a severity. If two reviewers disagree, show both.

## Finding format (all angles)

| Field | Meaning |
| --- | --- |
| ID | Angle prefix + number, e.g. `STR-2` |
| Severity | `blocker` (wrong behaviour, data or money risk, breaks a MUST rule), `major` (likely bug or hard to maintain), `minor` (small, worth fixing) |
| Rule / ref | Spec ID (`BR-*`, `AC-*`), rule ID (`FLOW-*`, `CORE-*`) or the project guide section |
| Where | `file:line` |
| Finding | What is wrong, in one or two sentences |
| Suggestion | The fix direction |

## Report

In self-review there is no PR yet: title it `Self-review` and mark the PR-description checks "not applicable yet".

```markdown
## Gate 3 review: [P<n>] <title>
Angles run: BIZ, STR, STY (WFJ skipped: no workflow JSON in the diff)
Guides used: backend: docs/STYLEGUIDE.md, docs/REVIEW-GUIDE.md · frontend: none found (general practice)

## Spec conformance          <- from review-business
| AC | Implemented | Test | Evidence | Notes |
| --- | --- | --- | --- | --- |

## Not in spec
- <behaviour> — <file:line>

## Findings
| ID | Severity | Rule / ref | Where | Finding | Suggestion |
| --- | --- | --- | --- | --- | --- |

## Not checked
- <what and why>
```

Posting inline comments on the GitHub PR happens only when the engineer asks. Follow the project's own PR-review conventions for language and format if it has them (a spec-described flow, or files found by `review-workflow-json`).

## Finding the project's guides

See `docs/ai/flow/project-guides.md` (shared with the implementer). Do it once, before the angles start, hand the result to each reviewer, and list the guides used per part in the report header. A part with no guide is reviewed against general practice, marked `(general practice)`.
