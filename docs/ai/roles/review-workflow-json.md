# Review: Workflow JSON

## Purpose

Check workflow JSON definitions in a PR: valid structure, correct wiring, correct expressions, and the same flow the spec describes. Runs in a fresh context, and only when the diff touches workflow JSON. Used for self-review before the PR and at Gate 3 (`docs/ai/roles/pr-reviewer.md`).

## Inputs

The changed workflow JSON files, found by searching the repo for the project's workflow definitions (JSON files whose path or content says workflow, flow, nodes or connections) and for the workflow guides and node, filter or schema references that describe them (`docs/ai/flow/project-guides.md`); and the spec flow (§1 flowchart, §2 sequence) the workflow implements. For custom workflow actions in the diff, the action guide if the repo has one. **If the repo has no workflow JSON and no workflow guide, report "no workflow JSON in this repo" and stop.** Without a guide, check only structure that can be verified from the files themselves (valid JSON, references resolve, no orphan nodes) and mark the rest `(general practice)`.

## What to check

| Area | Look for |
| --- | --- |
| **Valid JSON and shape** | Parses; top-level keys, `id` (fresh UUID v4, not reused), `name`, `status`, `version`, `settings` as the workflow guide requires |
| **Nodes** | Unique `key` and `id`; known `type` from the node catalog; `params` complete for that type; standard `settings` block (retries) present and sensible |
| **Connections** | Every connection points to an existing node; `from_port` is a real output port of that node type; no orphan nodes; no unreachable branch; every branch of a decision node is wired |
| **Loops** | Every loop has an exit condition that terminates; state set before it is read |
| **Expressions** | Dynamic values wrapped in `{{ }}`; node output paths exist; filter syntax and arguments match the filter reference; static literals left bare; nulls and missing fields handled |
| **Triggers** | Webhook trigger declares a `parameters` schema covering every request field the workflow reads; scheduler and sub-workflow calls pass what the callee needs |
| **Side effects** | Retry settings on non-idempotent steps (create order, update stock, call a marketplace) can't double-apply; error branches don't swallow failures |
| **Matches the spec** | The flow, branches and rules in the workflow equal the spec: no extra step, no missing branch, same order of effects (cite `BR-*`, `AC-*`, §2) |
| **Secrets and environment** | No tokens, keys or environment-specific IDs hard-coded |

The checks below use the node, port and expression names from the repo's own references; the examples are generic. Check with tools where you can (JSON parse, a script that resolves connections), and say what you ran. Business rules in the spec that the workflow gets wrong are `WFJ` findings with the spec ref; `review-business` doesn't repeat them.

## Output

Findings with `WFJ-n` IDs, in the format in `docs/ai/roles/pr-reviewer.md`, citing the file, node `key` and line.
