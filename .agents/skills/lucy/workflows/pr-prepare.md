# pr-prepare

Lucy workflow. Run only when Lucy is addressed (see `../SKILL.md`).

Step 5. Runs as the **implementer** (PR mode). One PR covers one phase ticket (FLOW-07).

## Steps

0. If no self-review was run on this branch, suggest `code-review` first ("Lucy, review my changes"); don't block on it.
1. Find the phase ticket from the branch name (`feature/<phase-ticket-id>-…`) or ask the engineer. Read it, its design ticket, the plan (phase `P<n>`) and the spec.
2. Read `.github/pull_request_template.md` and `git diff <base>...HEAD` (`<base>`: the branch this PR merges into).
3. Fill in:
   - Under `## Ticket`: the phase ticket (ClickUp link, GitHub `#<n>`, or `Phase: P<n>` with no tracker), the Feature Spec path (`docs/features/<feature-slug>.md`) and the plan path (`docs/features/<feature-slug>-plan.md`).
   - ACs covered: all ACs of the phase's stories (from the plan's "Stories:" line). Check each has a test in the diff (search for the AC IDs). If any is missing, stop and tell the engineer to finish it in this PR (one PR per phase).
   - If the diff contains tests or code for ACs of a story **not in this phase**, stop and tell the engineer: it belongs to another phase.
   - Evidence table: one row per AC. Use test output where that is the evidence. For UI ACs, take screenshots with your tool's browser automation if it has one; otherwise leave `TODO: screenshot` and tell the engineer.
   - Test results: run the test suite for changed areas and paste the summary.
   - Migration / config / feature flag notes from the diff.
   - Differences from the spec and plan: compare the diff with §2, the phase breakdown and the stories in §3; write "None" only if you checked.
4. Run the PR check and fix anything it reports. It's the only automated check (there's no CI job):
   - Run `python scripts/check_pr.py --body <file> --branch <branch>`; it reads the tracker (`docs/ai/flow/tracker.md`) and also checks the spec is approved: ClickUp needs `CLICKUP_API_TOKEN`, GitHub needs a `gh` login, no tracker needs `git` (add `--base <target branch ref>` if the PR doesn't target the default branch).
   - If the tracker can't be reached: add `--local --phase P<n>`, and confirm with the engineer that the spec is approved.
   - Paste the result in your report so the engineer can mention it in the PR.
5. If the engineer asked to open the PR and the PR check passes, open it (`gh pr create --base <base>`, title `[P<n>] <phase title>`) without asking again, then move the phase ticket to `in review` (`docs/ai/flow/tracker.md`; no tracker: skip). Otherwise show the description and what failed. Never merge, and never set any other status.
