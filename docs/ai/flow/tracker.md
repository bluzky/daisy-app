# Tracker

Lucy works with the team's ticket tracker, or none. Which one is set once per repo. Everything that says "ticket", "design ticket" or "phase ticket" in the workflows means the thing in the table below for that tracker.

## Setting

Add one line to the project's own `AGENTS.md`, **outside** the block `install.py` manages:

```text
Lucy tracker: github
```

Values: `clickup`, `github`, `none`. Not set: `clickup` (so existing repos keep working). `scripts/check_pr.py` reads the same line (or `--tracker`, or the `LUCY_TRACKER` env var). At the start of a workflow, read the setting, say it in the reply (`Lucy · spec-draft · github`), and follow the column for that tracker. Anything this table doesn't say is the same in every tracker.

## What each tracker means

| Concept | `clickup` | `github` | `none` |
| --- | --- | --- | --- |
| **Design ticket** | ClickUp task `[DESIGN] <feature>` | Issue `[DESIGN] <feature>`, label `design` | None. The feature is its slug (`docs/features/<slug>.md`) |
| **Epic** (optional parent) | Parent task | Parent issue, label `epic`; design and phase issues are its sub-issues | None |
| **Phase ticket** | Task `[P<n>] <title>` under the epic, linked to the design ticket | Issue `[P<n>] <title>`, label `phase`, body line `Design: #<n>` | A row `P<n>` in the plan. The PR says `Phase: P<n>` |
| **Naming a ticket in a request** | URL or task ID | `#<n>`, issue URL or the title | The feature slug and `P<n>` |
| **Approved** (Gate 1 passed, FLOW-02; in the auto flow the engineer's recorded approval counts, FLOW-11) | Design task `done` or `complete` | Design issue **closed as completed** (the tech lead closes it after the spec PR is merged) | The spec **and** the plan exist on the target branch (their PRs are merged) |
| **Status moves by Lucy** | `in progress`, `in review` (statuses) | Labels `in progress`, `in review`; forward only, replace the previous one | None |
| **Create phase tickets** (`create-tickets`) | ClickUp CLI or MCP | `gh issue create`, see below | Not needed: the plan's phases table is the list. Say so and stop |
| **Spec publish** (`spec-publish`) | ClickUp Doc, link in a comment | No Doc. Comment on the design issue: `Spec approved: <permalink to the file on the target branch>` | Not needed. Say so and stop |
| **Read a ticket** | MCP, CLI, or the pasted ticket | `gh issue view <n> --json title,body,state,stateReason,labels,comments,url` | The spec and plan files; ask the engineer for requester notes |
| **Comment on a ticket** | `clickup comment add` | `gh issue comment <n> --body …` | Not applicable |
| **PR check** | `CLICKUP_API_TOKEN`, task link in the PR | `gh` login, `#<n>` in the PR | `git`: spec and plan on `--base` |

ClickUp details (fields, CLI commands, statuses): `docs/ai/flow/clickup.md`.

## GitHub details

- **Access:** the `gh` CLI, logged in (`gh auth status`). No MCP server is needed. If `gh` fails, show the error and fall back to doing the step by hand; never ask for tokens.
- **Labels:** `design`, `phase`, `epic`, `in progress`, `in review`. Create a missing one with `gh label create <name>` before using it.
- **Phase issue body** (written by `create-tickets`, copied from the plan and spec):

  ```markdown
  Design: #<design issue>
  Feature Spec: docs/features/<feature-slug>.md
  Plan: docs/features/<feature-slug>-plan.md → P<n>

  Stories: US-1, US-2

  US-1: As a <role>, I want <action>, so that <benefit>
  - AC-1.1 (BR-x): Given …, when …, then …

  Breakdown:
  | # | Context / module | What to do |
  | 1 | … | … |

  Depends on: #<phase issue>
  ```

- **Create:** `gh issue create --title "[P<n>] <title>" --body-file <file> --label phase`. If an epic issue is set, attach each new issue as its sub-issue (`gh api -X POST repos/{owner}/{repo}/issues/<epic>/sub_issues -F sub_issue_id=<id>`, where `<id>` is the new issue's numeric `id` from `gh api repos/{owner}/{repo}/issues/<n>`); if the sub-issue API isn't available, add `- [ ] #<n>` to the epic's task list. Dependencies are the `Depends on:` line.
- **Approval:** only the tech lead closes the design issue (CORE-02). Lucy never closes or reopens issues, and never sets labels other than `in progress` and `in review`.
- **PR:** the PR description has `Phase ticket: #<n>` under `## Ticket`. Use `Refs #<n>`, not `Closes #<n>`, unless the team wants the phase issue closed on merge.
- **Same rules as ClickUp:** writes run without a confirmation prompt when the engineer asked for the workflow and its checks pass; list each command run in the reply. Forward-only status moves, and a failed update is reported while the work carries on.

## `none` mode

There are no tickets. The unit of work is the spec file and the plan:

- Gate 1 passes when the spec PR is merged into the target branch; Gate 2 when the plan PR is merged. Lucy checks the files exist on the target branch (`git cat-file -e <target>:<path>`), and the tech lead is still the one who merges.
- Phases are worked in plan order. "Dependencies are merged" means the earlier phases' PRs are merged; list their PR links in the plan's phases table when they merge.
- The engineer names the feature by slug (`docs/features/<slug>.md`) wherever a workflow asks for a design ticket, and the phase as `P<n>`.
- Requester context that would have been in a ticket (what, why, links) is pasted by the engineer or lives in the spec's §1.
