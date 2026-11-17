# spec-publish

Lucy workflow. Run only when Lucy is addressed (see `../SKILL.md`).

After Gate 1. Copies the **approved** spec from the repo into ClickUp. See `docs/ai/flow/spec.md`.

**Tracker (`docs/ai/flow/tracker.md`):** this workflow is for `clickup`. With `github`, don't create a Doc: check the spec PR is merged (step 2), then comment on the design issue `Spec approved: <permalink to the file on the target branch at the commit>` and tell the engineer the tech lead can now close the issue. With no tracker, say there is nothing to publish (the spec on the target branch is the approved copy) and stop.

## Input

`spec-publish <design ticket url or id> [to <location>]`

The engineer can say where the Doc goes, e.g. "Lucy, publish the spec for 86abc123 to <ClickUp link>". `<location>` can be:

| Location given | Result |
| --- | --- |
| A Space, Folder or List link (or name) | New Doc `[FEATURE] <name>` created there |
| A Doc link | Spec added as a new page inside that Doc |
| A Doc page link | That page's content replaced (re-publish to a known place) |

## Choosing the location

1. If the engineer gave a location, use it.
2. Else, if the design ticket already has a `Spec published: <Doc link>` comment (latest one; read the comments), update that Doc (re-publish).
3. Else, if `docs/ai/flow/clickup.md` sets a default publish location, propose it.
4. Else, **ask** where to publish. Don't guess.

If the engineer gives a new location but the ticket already links a Doc, ask whether to move (publish to the new place and update the link) or keep the existing Doc.

## Steps

1. Find the spec file (`docs/ai/flow/spec.md` → "Finding the spec").
2. **Finalized check.** All must be true, otherwise stop and say which one fails:
   - the spec PR is merged to the target branch (spec header) and was approved by the tech lead (check with `gh pr view` / `gh pr list --search <file>` if available, else ask the engineer for the PR link);
   - the file on the target branch is the version being published (no local or unmerged changes to it);
   - §4 has no open questions left without a decision.
3. Build the Doc content from the file on the target branch:
   - Title `[FEATURE] <name>` (from the spec's H1).
   - At the top: "Source: `<repo>/docs/features/<feature-slug>.md` on `<target branch>` at `<commit>`. Edit the repo, not this Doc."
   - The spec body unchanged (Mermaid blocks stay as code blocks if ClickUp can't render them).
4. No confirmation needed: if every check in step 2 passes and the location is resolved, publish. Stop and ask only if a check fails or the location is unclear.
5. Publish:
   - If Lucy can write to ClickUp (MCP or the CLI — `docs/ai/flow/clickup.md`): create the Doc or page at the chosen location (or replace the content of the existing one), comment on the design ticket: "Spec published: <Doc link> (from `<commit>`)". Report what was created or replaced, where, and the commands run.
   - Otherwise: print the Doc content, the target location and the steps for the engineer to do it by hand.
6. Tell the engineer the tech lead can now move the design ticket to `done`.

## Never

- Publish a draft, an unmerged branch or a spec PR that isn't approved.
- Edit the spec content while publishing; fix it in a spec PR instead.
- Move the design ticket to `done` (CORE-02).
