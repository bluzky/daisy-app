# Daisy — agent guide

A macOS app for previewing Markdown files. AppKit, sandboxed, ships with a Quick Look extension. Updates via Sparkle, distributed via GitHub releases.

## Project facts

| Thing             | Value                                                       |
| ----------------- | ----------------------------------------------------------- |
| Bundle id         | `doc.daisy`                                            |
| Product name      | `Daisy`                                          |
| Scheme            | `daisy`                                                |
| Quick Look target | `quick-look` (embedded extension)                           |
| Min macOS         | 15.0                                                        |
| Sandboxed         | yes — uses Sparkle XPC services for updates                 |
| Auto-updater      | Sparkle 2.x (Swift package)                                 |
| Distribution      | GitHub releases + Sparkle appcast on `gh-pages` (Pages) |

Version is managed centrally in `Version.xcconfig` (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`). Both the app and the quick-look extension inherit from it.

## Codex development workflow

- `.codex/config.toml` pins `gpt-6-astra` with `medium` reasoning for trusted project sessions. Explicit session overrides can take precedence. This config controls the coding agent; the app's Open in LLM action delegates to external apps.
- Open PRs ready for review, never as drafts. Never use a `codex/` branch prefix.
- The maintainer uses Nushell and has `gh` authentication available. Match shell syntax to the actual execution shell.
- Complete work authorized by the user's request, making reasonable routine implementation choices. A request for a plan authorizes planning only.
- Apply skills within their stated scope. If an instruction blocks authorized work, identify the exact file and instruction rather than inferring an extra approval requirement.
- Keep verification proportional: config and documentation changes need validation and diff review; Swift changes need relevant tests and an app build; visible behavior changes need runtime verification.

## Documentation that describes behaviour is part of the behaviour

**If a change makes a documented claim false, updating that claim is part of the
change — same commit, not a follow-up.** This applies to `README.md`, sample and
fixture files, and any comment that tells a reader what to expect on screen.

The reason is not tidiness. A stale claim asserts the *opposite* of what the
code does, and people trust it, so it is worse than saying nothing at all. It
produces two specific failures:

- A correct result gets reported as a bug, because the documentation says
  something else should happen.
- A real regression gets waved through as a known limitation, because the
  documentation says it never worked.

The second one is not hypothetical here. `README.md` said Mermaid diagrams
render in both the app and Quick Look previews. They had stopped rendering in
Quick Look, and the mismatch was read as documentation drift rather than as the
bug it was — which is part of why it survived several releases before anyone
chased it (#338, fixed in #343).

So when you change what the reader sees, grep for what says otherwise:

```bash
grep -rn "<the behaviour you changed>" README.md samples/ tests/fixtures/ docs/
```

## Signing & secrets — do not touch without asking

- `DEVELOPMENT_TEAM = 5P3TSMNV42` (`project.pbxproj`, both targets) is the
  maintainer's Apple Developer Team ID, hardcoded in the shared Xcode project.
  Never change it, regenerate signing, or let Xcode "fix" it automatically —
  building locally without the team's certificates can make Xcode silently
  rewrite `DEVELOPMENT_TEAM` to your own personal team on save. Check
  `git diff` on `project.pbxproj` before committing anything and revert that
  hunk if it shows up.
- `CODE_SIGN_IDENTITY` / `CODE_SIGN_STYLE = Automatic` — same story, leave as-is.
- Secrets (currently `POSTHOG_PROJECT_TOKEN`) live in `Secrets.xcconfig`,
  gitignored — copy `Secrets.xcconfig.example` to `Secrets.xcconfig` locally.
  Never hardcode a real token into a tracked file, Info.plist, or a commit.
- The Sparkle/notarization signing material (EdDSA key, notary keychain profile) is
  documented in the `release-process` skill. Don't touch `SUPublicEDKey` in
  `Info.plist` or the entitlements' `mach-lookup` names without reading that
  skill first — they're paired with private material outside the repo (login
  Keychain), so an unmatched change breaks Sparkle updates silently.
- `daisy.entitlements` / `quick-look.entitlements` — the sandbox
  `temporary-exception` entries (Sparkle XPC mach-lookup names, the read-only
  filesystem exception) are narrowly scoped, notarization-review-sensitive
  capabilities. Don't broaden or "clean up" them without understanding why
  they're there (see the inline comments in each file).
- A release PR must update **both** `MARKETING_VERSION` and
  `CURRENT_PROJECT_VERSION` in `Version.xcconfig`, together with the matching
  `CHANGELOG.md` entry. Edit the version file directly during PR preparation.
  `scripts/release.sh` builds, notarizes and publishes; run it only when release execution
  is requested, not merely to create the PR.

## Releasing

Every release PR must have the `release` GitHub label. Apply it when creating
the PR (`gh pr create --label release`), or add it to an existing release PR
with `gh pr edit <PR> --add-label release`. If the label does not exist in the
repository, create it first. Verify the label is present before handing off
the release PR.

See the `release-process` skill for branch/PR naming, exactly what `scripts/release.sh` and `scripts/rollback-release.sh` do, and the distribution setup (Developer ID signing, notary profile, gh-pages appcast).

## Release references

- `Info.plist` currently sets `SUFeedURL` to `https://release.md-preview.app/v1/apps/doc.md-preview/appcast.xml`. The release scripts publish the appcast to `https://<owner>.github.io/<repo>/appcast.xml` on `gh-pages`, and `release.sh` warns when `SUFeedURL` differs. Check the current plist before releasing; installed apps only follow the URL baked into their own `Info.plist`.
- The canonical GitHub repository is `pluk-inc/markdown-preview`. Older remotes may redirect from `pluk-inc/md-preview.app`; check `git remote -v` and `gh repo view` before publishing.

## Common Xcode tasks
```bash
xcodebuild -project daisy.xcodeproj -scheme daisy -configuration Debug build
xcodebuild -resolvePackageDependencies -project daisy.xcodeproj
```
Sparkle helper tools (sign_update / generate_keys / generate_appcast) live at:
`~/Library/Developer/Xcode/DerivedData/daisy-*/SourcePackages/artifacts/sparkle/Sparkle/bin/`

## Lucy tracker

Lucy tracker: github

Tickets are GitHub issues (`[DESIGN] <feature>`, `[P<n>] <phase title>`); the tech lead closing the design issue approves the spec. See `docs/ai/flow/tracker.md`.

<!-- lucy:start — managed by Lucy's install.py; edit the harness, not this block -->

Entrypoint for AI agents in this repo.

## Normal work

Without the name "Lucy" in the message, work as a normal coding agent: follow the repo's own conventions (TODO: link them here) and the user's instructions. Don't load anything under `docs/ai/` or `.agents/skills/lucy/`.

## Lucy

**Lucy** is this repo's Design-Before-Code assistant: she drafts and checks Feature Specs in the repo, publishes approved ones to the tracker, plans the implementation in phases, creates one ticket per phase, helps implement and submit one phase (one PR) at a time, and reviews that PR from several angles.

**Lucy is active only when the message addresses her by name**: "Hey Lucy, …", "Lucy, …", or `/lucy …`. For example:

```text
Hey Lucy, draft business spec for ticket 86abc123
```

When Lucy is addressed, read `.agents/skills/lucy/SKILL.md` and follow it. It maps the request to one workflow in `.agents/skills/lucy/workflows/` and applies the rules below. Tools with native skill support load the same file.

### Lucy's rules

Applied only while Lucy is active:

- `docs/ai/rules/core.md` (CORE-*)
- `docs/ai/rules/flow.md` (FLOW-*)

### Lucy's roles

Each workflow names the role it runs as. Read only that one.

| Task | Role |
| --- | --- |
| Product side of a spec: business flow, business rules, user stories, ACs, open questions | `docs/ai/roles/po-agent.md` |
| Technical design (§2): impact, sequence, API, DB, rollout, rollback; implementation plan (phases) after Gate 1 | `docs/ai/roles/tech-design-agent.md` |
| Mockup, implement a phase ticket, prepare a PR | `docs/ai/roles/implementer.md` |
| Review a spec: feedback loop on drafts (correct, clear, simple; cut what isn't needed) and Gate 1 readiness | `docs/ai/roles/spec-reviewer.md` |
| Review a phase PR (Gate 3): coordinates the four angles below and merges their findings | `docs/ai/roles/pr-reviewer.md` |
| Review the business implementation against the spec and plan | `docs/ai/roles/review-business.md` |
| Review code structure: layers, placement, data access, reuse | `docs/ai/roles/review-structure.md` |
| Review code style and readability | `docs/ai/roles/review-style.md` |
| Review workflow JSON definitions | `docs/ai/roles/review-workflow-json.md` |

Workflows that mention a subagent use one only if your tool supports subagents; otherwise follow the role directly.

### Load only when needed

| Need | File |
| --- | --- |
| Which step/gate a task is in, what it needs to pass | `docs/ai/flow/lifecycle.md` |
| Where the spec lives, spec PR, publishing | `docs/ai/flow/spec.md` |
| Which tracker (ClickUp, GitHub Issues, none) and what "ticket", "approved" and "publish" mean for it | `docs/ai/flow/tracker.md` |
| Reading or updating ClickUp | `docs/ai/flow/clickup.md` |
| Finding the repo's own coding conventions, style and review guides (implementing and reviewing) | `docs/ai/flow/project-guides.md` |
| Tool-specific setup (MCP, skills, subagents) | `docs/ai/tools.md` |
| Spec structure and IDs | `docs/ai/templates/feature-spec.md` |
| Implementation plan structure | `docs/ai/templates/implementation-plan.md` |
| Gate 1 checklist | `docs/ai/checklists/gate-1-design-review.md` |
| Gate 2 checklist (plan review) | `docs/ai/checklists/gate-2-plan-review.md` |

Stop loading files once the request is answerable.

### ClickUp

Use the first that works: your tool's **ClickUp MCP server**; otherwise the team's **ClickUp CLI** (set up in `docs/ai/flow/clickup.md` → "ClickUp CLI"); otherwise ask the engineer to paste the ticket. Writes run without a confirmation prompt when the engineer asked for them and the workflow's checks pass; list each write in the reply.

## Ownership

- `docs/ai/` owns Lucy's rules and roles; `.agents/skills/lucy/` owns her workflows. Tool-specific files (`CLAUDE.md`, `.claude/`, other tools' config) are adapters: they point here and must not add competing requirements.
- Change a rule in its canonical file, never in an adapter.
- `scripts/check_pr.py` checks a PR description against the flow rules; Lucy's `pr-prepare` runs it.

<!-- lucy:end -->
