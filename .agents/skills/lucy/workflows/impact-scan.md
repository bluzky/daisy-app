# impact-scan

Lucy workflow. Run only when Lucy is addressed (see `../SKILL.md`).

Step 1, first part of the technical design. Runs as the **tech design agent** (working method steps 1–2). Read-only.

## Steps

1. Load `docs/ai/roles/tech-design-agent.md`.
2. From the spec's §1 and §3 (or the engineer's description), list the entities, tables, columns, statuses, APIs, events and config the feature changes.
3. For each, search the codebase for every reader and writer:
   - schema/model definitions and migrations
   - queries, repositories, actions/services
   - API routes, controllers, serializers
   - background jobs, schedulers, queue consumers
   - reports, exports, dashboards
   - external integrations (marketplaces, WMS, payment, …)
   - frontend callers
4. Output:
   - a draft impact table (`Area | What changes | Impact | Risk | Mitigation`) with `file:line` citations,
   - DB notes: table sizes if known, migrations that could lock large tables,
   - questions the design must answer.
5. Don't edit the spec or any code. `tech-design` uses this output to draft §2.
