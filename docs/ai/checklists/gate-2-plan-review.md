# Gate 2: Plan Review Checklist

Used by Lucy's `plan` workflow (self-check before the plan PR), the engineer and the tech lead. The tech lead approves and merges the plan PR only when every item passes; phase tickets are created after that (FLOW-10).

| # | Check | Where |
| --- | --- | --- |
| G2-01 | Every `US-n` in spec §3 is in exactly one phase | Phases table |
| G2-02 | Every §2 part (migration, API, job, config, screen) is in a phase | Breakdown |
| G2-03 | As few phases as possible; every split has a reason (PR size, deploy order, different risk) | "Why this phase" |
| G2-04 | Each phase fits one reviewable PR, backend and frontend together | Breakdown |
| G2-05 | Dependencies point only to earlier phases, and the deploy order works (e.g. a migration before the code that uses it) | "Depends on" |
| G2-06 | Every breakdown row names the context / module and files, and cites a spec ID or §2 part | Breakdown |
| G2-07 | The breakdown follows the existing pattern named in §2; no new design in the plan | Breakdown |
| G2-08 | Every AC of the phase's stories has a planned test with the AC ID in its name | Tests |
| G2-09 | The plan adds or changes no requirement; any gap found is raised as a spec change (FLOW-05) | all |
| G2-10 | Migration, config, feature flags and risks are noted per phase | Each phase |
