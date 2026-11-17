# mockup

Lucy workflow. Run only when Lucy is addressed (see `../SKILL.md`).

Step 3. Runs as the **implementer** (mockup mode).

## Steps

1. Load `docs/ai/roles/implementer.md` (Mockup mode) and the spec's §3. Find the frontend guides (`docs/ai/flow/project-guides.md`) and follow them.
2. `git checkout -b mockup/<feature>` from the current branch.
3. Build the screens using the repo's real FE components and routing. TODO: FE root and component library path.
4. Mock data only: a local fixture file or mock handlers (TODO: the repo's mock approach, e.g. MSW). No calls to real APIs.
5. Cover, for each story: main flow, error states, empty states, loading states named in the ACs.
6. Add a short `MOCKUP.md` on the branch: which AC each screen shows, how to run it.
7. Tell the engineer how to demo it (preview URL or run command). Feedback goes in the design ticket's comments.

## Never (FLOW-06)

- Change backend, API, DB, migrations or shared config.
- Open a PR to merge the mockup branch.
