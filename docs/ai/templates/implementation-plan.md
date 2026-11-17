# [PLAN] <feature>

<!-- Canonical template. create-tickets and the PR check parse the "### P<n>:" headings and the "Stories:" lines: keep them unchanged. -->

| | |
| --- | --- |
| Design ticket | <[DESIGN] ticket link> |
| Feature Spec | `docs/features/<feature-slug>.md` |
| Target branch | <same as the spec> |
| Plan PR | <link, once opened> |
| Drafted with | Tech design agent — reviewed by author |
| Reviewer | <tech lead> |
| Status | Draft / In review / Approved |

## Phases

One phase = one phase ticket = one PR.

| Phase | Title | Stories | Depends on | Ticket |
| --- | --- | --- | --- | --- |
| P1 | <title> | US-1, US-2 | — | <added by create-tickets> |
| P2 | <title> | US-3 | P1 | <added by create-tickets> |

### P1: <title>

- **Stories:** US-1, US-2
- **Depends on:** —
- **Why this phase:** <one line: why these stories ship together, or why this is separate>

**Breakdown:**

| # | Context / module | What to do | Spec ref |
| --- | --- | --- | --- |
| 1 | <context, e.g. `Inventory` — `backend/apps/core/lib/inventory/`> | <change, e.g. migration adds `allocation_suggestions` table> | §2 DB |
| 2 | <context> | <change, e.g. new action `CalculateSuggestions`, reusing `<existing module>`> | BR-2, AC-1.1 |
| 3 | <FE page/component path> | <change> | AC-2.1 |

**Tests:**

| AC | Test (file and name) |
| --- | --- |
| AC-1.1 | `<test file>` — `AC-1.1 <name>` |

**Migration / config / flags:** <or "None">

**Risks / notes:** <what could go wrong in this phase, or "None">

### P2: <title>

- **Stories:** US-3
- **Depends on:** P1
- **Why this phase:** <…>

**Breakdown:**

| # | Context / module | What to do | Spec ref |
| --- | --- | --- | --- |

**Tests:**

| AC | Test (file and name) |
| --- | --- |

**Migration / config / flags:** <or "None">

**Risks / notes:** <or "None">
