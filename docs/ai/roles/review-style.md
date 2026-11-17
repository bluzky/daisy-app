# Review: Code Style

## Purpose

Check that the code reads well and follows the project's style guide and formatter. Runs in a fresh context. Used for self-review before the PR and at Gate 3 (`docs/ai/roles/pr-reviewer.md`). Keep it short: what the formatter or linter can enforce is checked by running it, not by eye.

## Inputs

The PR diff and the style guide, lint and format configs found for each part (backend, frontend) by `docs/ai/flow/project-guides.md`. Apply the backend guide to backend code and the frontend guide to frontend code only.

## Steps

1. Run the project's format check and linter on the changed files, in check mode only (the commands come from the guide or configs, e.g. `mix format --check-formatted`, `mix credo`, `eslint`, `prettier --check`, `tsc --noEmit`). Report failures as findings. If you can't run them, say so.
2. Review the diff by eye for what tools miss.

## What to check

| Area | Look for |
| --- | --- |
| **Naming** | Whatever the guide says, e.g. names that don't say what a thing is, boolean and time-unit naming, public vs. private names, breaking existing naming patterns |
| **Module layout** | Attributes, aliases, imports, `use` and functions in the project's order; grouped aliases |
| **Types and docs** | Missing types or specs where the guide requires them (e.g. `@spec`, TypeScript types); missing or wrong docs; comments that restate the code instead of explaining a non-obvious case |
| **Readability** | Over-compact inline code; nested conditionals that need a clearer `case` or `with`; long functions; actions without a clear outline of the flow; leftover debug output or commented-out code |
| **Error handling style** | Style of error handling as the guide says (what to return and where is `review-structure`) |
| **Frontend** | Component and hook conventions, props and state naming, styling approach, i18n usage and formatting, as the frontend guide says |
| **Tests style** | Test names say the behaviour; AC ID in the name where the flow needs it; no unrelated setup |

Skip personal preferences and anything the guide doesn't say. Every finding cites the guide section.

## Output

Findings with `STY-n` IDs, in the format in `docs/ai/roles/pr-reviewer.md`. Group repeated findings (same rule in many places) into one finding with the locations listed.
