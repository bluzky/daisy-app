# Review: Code Structure

## Purpose

Check that the code is put in the right place and built the way the project builds things: layers, modules, data access and reuse. Backend and frontend. Runs in a fresh context. Used for self-review before the PR and at Gate 3 (`docs/ai/roles/pr-reviewer.md`). Business correctness belongs to `review-business`.

## Inputs

The PR diff, the surrounding code (similar existing modules), and the architecture, convention and review guides found for each part (backend, frontend) by `docs/ai/flow/project-guides.md`. Apply backend guides to backend code and frontend guides to frontend code only.

## What to check

| Area | Look for |
| --- | --- |
| **Layering** | Business logic in controllers, views or repositories; data access in actions; request handling outside the controller. Code in the wrong app or context |
| **Module placement and naming** | File path and module name follow the project's pattern (apps, contexts, actions, operations); new modules sit next to their siblings |
| **Existing patterns (CORE-03)** | A new helper, abstraction or table where an existing one fits; shared utilities (`Foundation.*` and the like) not reused; the pattern named in spec §2 not followed |
| **Data access** | Query meaning vs. intent; N+1 and unindexed filters; transactions that are too wide (external calls inside) or missing; status changes and counters done read-modify-write instead of conditional or atomic updates; cache invalidation |
| **Migrations and schema** | Reversible; generated, not hand-named; types, nullability, indexes and constraints; schema, changeset and migration agree |
| **API and permissions** | Route, permission plug and permission code registered together; params mapping; response shape; fallback errors |
| **Error handling** | The project's error wrapper and tuples used; no unsafe bang calls on paths that can fail |
| **Audit fields** | Explicit, role-specific fields, not a generic `user_id` |
| **Size and shape** | Functions or modules too large to follow; logic that forces readers to jump around; dead code |
| **Frontend** | Component, hook, state, routing and API-layer placement as the frontend guide says; types match the backend contract; permission gates, loading, error and empty states where the guide requires them; no business logic in presentational components |
| **Tests (structure only)** | Tests live where the project puts them and reuse its helpers and fixtures. Whether each AC is tested belongs to `review-business` |

Cite the guide section or the existing module that sets the pattern (CORE-05).

## Output

Findings with `STR-n` IDs, in the format in `docs/ai/roles/pr-reviewer.md`. Say which guides you read and which parts of the diff you didn't review.
