# Review: Business Implementation

## Purpose

Check that a phase PR does what the approved spec and plan say: no less, no more. Runs in a fresh context. Used for self-review before the PR and at Gate 3 (`docs/ai/roles/pr-reviewer.md`).

## Finding the business document

Review against the project's **existing business document**, found in this order:

1. **Lucy flow:** the phase ticket's design ticket → the Feature Spec (`docs/features/<feature-slug>.md`) and the plan phase `P<n>`, read from the target branch.
2. **Anything linked:** the PR description, the ticket or issue the branch or PR names, and files they link.
3. **Search the repo** for requirements: names or folders matching `spec`, `feature`, `requirement`, `prd`, `rfc`, `adr`, `design`, `flow`, `story`, `acceptance`, in `docs/`, `doc/`, `.github/`, or beside the code, whose title or content matches the changed feature (a hit must name the feature, not just sit nearby).
4. **Not found, or two documents disagree:** **ask the engineer** for the document: a path, a link, a ticket, or the requirement pasted in the chat (CORE-06). Don't guess the requirement, and don't review against the code's own behaviour.
5. **The engineer has none:** skip this angle and report "business not reviewed: no business document". Never invent requirements (CORE-01).

Without the Lucy flow's IDs, use whatever the document has (rule names, numbered requirements, acceptance criteria) as the references in findings; if it has none, quote the line.

## Inputs

The diff (PR or branch) and, at Gate 3, the PR description, plus the business document found above. In the Lucy flow: the phase `P<n>` in the plan (its `Stories:` line and breakdown); spec §1 (business rules, flow), §2 (technical design), the phase's stories and ACs in §3, and §4 decisions, read from the target branch. The checks below name the Lucy flow's IDs (BR, AC, §2); with another document, use its equivalents.

## What to check

| Area | Look for |
| --- | --- |
| **Scope (FLOW-07)** | The PR covers all and only the ACs of its phase's stories. Missing ACs; code or tests for another phase's stories |
| **ACs** | For each AC: implemented (cite code), tested (a test with the AC ID in its name, FLOW-04), evidence in the PR description (Gate 3 only; in self-review, say evidence is still to collect). The test really asserts the AC's Then, not just that the code runs |
| **Business rules** | Each relevant BR is enforced in the right place, including error and unhappy paths; no rule is changed, weakened or invented (CORE-01) |
| **Technical design (§2)** | The code follows §2 and the plan breakdown: API contract (method, path, request, response, error codes), DB design (columns, types, indexes, constraints, migration, backfill), sequence and ordering, rollout and rollback |
| **Not in spec** | Behaviour in the diff that no BR, AC or §2 part asks for (CORE-03); config, flags or abstractions nobody asked for |
| **Differences from the spec (FLOW-05)** | At Gate 3, "Differences from the spec" is honest (in self-review, list the differences you find so `pr-prepare` can fill it): every real difference is listed, or "None" is true. A difference that changes a requirement means the spec must change first |
| **Data risk** | Anything touching money, stock, order status or permissions that the spec doesn't cover |

Don't review style, structure or workflow JSON wiring here: other angles own them. If you see one, mention it in one line for the owner, not as a finding.

## Output

- The **Spec conformance** table (one row per AC in scope) and the **Not in spec** list, as in `docs/ai/roles/pr-reviewer.md`.
- Findings with `BIZ-n` IDs and spec refs (`BR-*`, `AC-*`, `§2 <part>`).
- A requirement that is unclear or missing in the spec is a spec gap: report it as a finding that asks for a spec change (FLOW-05), never decide it.
