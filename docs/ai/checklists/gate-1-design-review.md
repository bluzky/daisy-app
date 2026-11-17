# Gate 1: Design Review Checklist

Used by the engineer (self-review), `spec-check` and the tech lead. The tech lead moves the design ticket to `done` (= spec approved) only when every item passes.

| # | Check | Section |
| --- | --- | --- |
| G1-01 | Problem, goal and out-of-scope are clear and specific | §1 |
| G1-02 | Unhappy paths that are likely or costly are covered; the rest are listed under "Not handled" (FLOW-09) | §1 |
| G1-03 | Business rules are numbered, testable, in business words (not code) | §1 |
| G1-04 | No business rule was invented: each has a source (task, tech lead answer, current behaviour) | §1, §4 |
| G1-05 | Sequence diagram covers every service, API, queue and external system, including errors | §2 |
| G1-06 | API changes list method, path, request, response, error codes | §2 |
| G1-07 | DB design covers naming, types, indexes, constraints, migration, backfill, data volume, table locks | §2 |
| G1-08 | Impact table lists every reader and writer of the changed data (jobs, reports, integrations) | §2 |
| G1-09 | Rollout and rollback plans exist, and rollback works after real data is written | §2 |
| G1-10 | Every user story has Given/When/Then ACs, including error and edge cases | §3 |
| G1-11 | Every BR is covered by an AC; every AC traces to a BR or is marked UI-only | §1, §3 |
| G1-12 | Diagrams, BRs and stories agree with each other | all |
| G1-13 | Mockup (if any) matches the stories and has tech lead feedback applied | §3 |
| G1-14 | Open questions are answered, or accepted as risks by the tech lead | §4 |
| G1-15 | The engineer can explain every BR and AC without the agent | review meeting / comments |
| G1-16 | The spec is as simple as it can be: no speculative scope, no duplicate rules or diagrams, only BRs and stories that are needed, no common-sense ACs (usually 1–4 per story), existing patterns reused, size proportional to the feature (FLOW-09) | all |
