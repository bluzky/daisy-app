# Core Rules

Apply to every task. Cite rules by ID in findings and handoffs.

## CORE-01 — Don't invent business rules

**Severity:** MUST NOT

- Never invent product rules, permissions, states, limits or contracts.
- If the spec or the code doesn't answer it, add it to the spec's §4 Open questions and say who must decide (tech lead).
- Block only the work that depends on the answer; continue the rest.

## CORE-02 — Humans decide

**Severity:** MUST NOT

- Agents never approve a spec, close an open question, move a design ticket to `done`, approve a PR or merge.
- Agents draft, check and recommend. Mark agent output as a draft until a human reviews it.
- Recording a human's explicit approval in the auto flow (FLOW-11) is not approving: the human decided, Lucy wrote it down.

## CORE-03 — Stay in scope

**Severity:** MUST

- Do only what the current step and user story need.
- Prefer existing patterns over new abstractions. No speculative flexibility, no adjacent cleanup.
- Every changed line must trace to a story, AC or business rule.

## CORE-04 — Preserve user work

**Severity:** MUST NOT

- Don't overwrite, revert or delete changes you didn't make.
- Don't rewrite spec sections a human already edited; propose changes instead.

## CORE-05 — Cite evidence

**Severity:** MUST

- Back every claim about the code with a file path and line, and every claim about requirements with a spec ID (`BR-*`, `US-*`, `AC-*`) or a ticket link.
- Say plainly what you didn't verify.

## CORE-06 — Ask, don't guess

**Severity:** MUST

- When two reasonable readings lead to different behaviour, stop and ask the engineer.
- Ask focused questions with options, not open-ended ones.

## CORE-07 — Follow the project's guides

**Severity:** MUST

- When writing or reviewing code, follow the repository's own coding conventions, style guides, architecture and review guides, and lint configs, found as in `docs/ai/flow/project-guides.md`. Backend code follows backend guides and frontend code follows frontend guides. The implementer follows the coding conventions **and** the review guide while writing, so reviews find less.
- Don't invent a rule and attribute it to a guide. With no guide, follow the existing code around the change and say so.
- A guide never overrides the approved spec on behaviour; flag a conflict (FLOW-05).
