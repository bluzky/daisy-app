---
name: release-process
description: Prepare complete release PRs, publish, tag, and roll back Daisy releases — branch/PR naming, exactly what scripts/release.sh and scripts/rollback-release.sh do (including that release.sh publishes live), and the GitHub-based distribution setup (Developer ID signing, notary profile, EdDSA key, gh-pages appcast). Use when the user asks to create a release PR, release, ship, cut a version, bump the version, tag a release, roll back or unpublish a release, or asks about this project's distribution config (codesign identity, notary keychain profile, EdDSA key, appcast hosting).
---

## Release pipeline

### Branch and PR naming
Every release goes through a dedicated branch and PR — never push the version bump or changelog directly to `main`.
- **Branch name**: `release/X.Y.Z` — exactly the marketing version, no `v` prefix, no build number, no suffix. Examples: `release/0.0.10`, `release/1.2.0`. Beta cuts use `release/X.Y.Z-betaN` (e.g. `release/0.1.0-beta1`).
- **PR title**: `Release X.Y.Z (N)` where `N` is `CURRENT_PROJECT_VERSION`. Example: `Release 0.0.10 (14)`. This matches the commit message `scripts/release.sh` writes for the version-bump commit, so the PR, the bump commit, and the eventual git tag all line up. For betas: `Release X.Y.Z-betaN (build)`.
- **PR body**: short Summary (version bump + changelog added), a "What's in X.Y.Z" section that mirrors the changelog bullets, and a Test plan.
- **One PR per release**. The branch contains only the bump (`Version.xcconfig`, edited directly during PR preparation), the new `CHANGELOG.md` entry, and — only when the user confirms an announcement — the What's New window update (see below). Keep unrelated changes out so the release diff stays auditable.

### Create a release PR (prepare only)

A request to "create a release PR" includes **both** version fields and the changelog. It authorizes editing `Version.xcconfig` directly; do not defer the bump to publication or open a changelog-only release PR.

1. Fetch latest `origin/main` and tags, and inspect existing release PRs before selecting the next version. Reuse an existing open release PR when appropriate. Start a new release branch from latest main; use an isolated worktree if the current checkout has unrelated work.
2. Use the requested version, or the next patch version in this project's existing release series when unspecified. Increment `CURRENT_PROJECT_VERSION` by one from the latest release metadata. Check open release PRs to avoid duplicating a version already being prepared.
3. Update **both** `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `Version.xcconfig`, and add the matching `CHANGELOG.md` entry using `changelog-maintenance`, including contributor credits.
   Then review the new changelog entry for What's New candidates and **ask the user before announcing any** (see *What's New window* below). Without a confirmed pick, leave the window files untouched.
4. Verify that the PR's complete diff includes the intended version/build values and matching changelog heading; the title must agree with those values. Check `git diff --check`, unchanged historical notes, and that only these two release metadata files changed — plus the What's New files when the user confirmed an announcement, in which case build the app, run the policy tests, and look at the window as described below. Do not claim app tests were run for metadata-only validation.
5. Commit, push, and open a **ready, non-draft** PR titled `Release X.Y.Z (N)`. A release PR is incomplete if the version bump is missing, unless the user explicitly requested changelog-only work.

Do not run `scripts/release.sh`, including `--draft`, just to prepare the PR. Building, notarizing, uploading, tagging, and publishing are separate release execution steps; a release PR request alone does not request them.

### What's New window

Updated readers see a What's New window once, over their first document window after the update (Help › What's New in Daisy reopens it). It lives in `daisy/Features/WhatsNew/`:

- `WhatsNewPolicy.swift` — `featuresVersion` and `featuresBuild` name the release that introduced the listed features. A reader whose last recorded build is older than `featuresBuild` sees the window; fresh installs never do. The window title (`What's New in Daisy <featuresVersion>`) and the Release Notes button (`https://github.com/pluk-inc/markdown-preview/releases/tag/v<featuresVersion>`) both follow `featuresVersion`.
- `WhatsNewWindow.swift` — `WhatsNewFeature.current` is the list of features shown.

**Always ask before announcing.** While preparing a release PR, read the new `CHANGELOG.md` entry and pick the user-visible features worth announcing. Present them to the user as a proposal — title, description, SF Symbol, and any macOS version limit for each — and **wait for explicit confirmation** of which ones to use and their wording. Never add, drop, or reword an announcement without that confirmation. If the user picks none, leave `WhatsNewPolicy.swift` and `WhatsNewWindow.swift` untouched: the window then does not appear for this release, and readers who already saw the current announcement are not shown it again.

**Choosing candidates:**
- Announce what is new to readers of the previous release: new features and visible redesigns. Skip fixes, internal work, and anything that already existed (e.g. announce "wrap code blocks", not "copy code" when copy predates the release).
- Three to five features. Order them by how much a reader will notice them.
- A feature that only works on some systems is gated with `if #available(macOS NN, *)` so readers on older systems do not see it, and its description says so ("On macOS 26 and later, …").

**Wording format** (match the existing entries):
- **Title**: sentence case, about two to five words, no trailing period — e.g. "Find any document fast", "Redesigned formatting bar", "Faster document opening".
- **Description**: one short sentence, or two very short ones, about 20 words at most. Say what the reader can do or will notice; name a shortcut when it is the way in (e.g. "Press ⇧⌘O and type part of a file name to open it from the current project.").
- **Symbol**: an SF Symbol that exists on macOS 15 (the window also runs there), drawn in the accent tint.

**Once the user confirms:**
1. In `WhatsNewPolicy.swift`, set `featuresVersion` to the new `MARKETING_VERSION` and `featuresBuild` to the new `CURRENT_PROJECT_VERSION`. They must match `Version.xcconfig` in the same PR, or the title and release link name the wrong version and readers of the previous release may not see the window.
2. Replace the entries in `WhatsNewFeature.current` with the confirmed features.
3. Add every new title and description to `daisy/en.lproj/Localizable.strings` under `/* What's New */`, and remove strings that no entry uses any more (keep keys other UI still uses, such as "OmniSearch"). Run `plutil -lint` on the file.
4. Build the app and run `swift test --package-path tests/swift-tests --filter WhatsNewPolicyTests`.
5. Check the window in the Debug build as an updating reader: run `defaults delete doc.daisy.dev MarkdownPreview.whatsNewLastBuild` and `defaults write doc.daisy.dev MainSplitView.didSeedInitialState -bool true` (a fresh Debug profile otherwise counts as a new install, which never sees the window), launch the built app with a document, and confirm the window lists the confirmed features. Before the release is published, the Release Notes link returns 404; that is expected.

### How `scripts/release.sh` actually works
Read this before running it — the script ships the update, it doesn't just prepare a PR.

**Preflight** (checked in this order, before anything is changed):
- the working tree must be **clean** — commit everything, including the `CHANGELOG.md` entry, before running the script;
- a `## [X.Y.Z]` entry must already exist in `CHANGELOG.md` for the version being released (the script only validates and extracts it — it never writes the entry itself; that's the `changelog-maintenance` skill's job, see below);
- `jq`, `python3` and the Sparkle tools (`sign_update`, `generate_keys`, found in DerivedData or via `SPARKLE_BIN`) must be present;
- a `Developer ID Application` certificate for the signing team must be in the keychain (team = `DAISY_TEAM_ID`, defaulting to `DEVELOPMENT_TEAM` in the project), and the `notarytool` keychain profile (`NOTARY_PROFILE`, default `daisy-notary`) must work;
- the keychain EdDSA key must match `SUPublicEDKey` in `Info.plist` (skipped when `SPARKLE_KEY_FILE` is set);
- unless `--draft` / `--skip-github`: `gh` installed and authenticated, an `origin` remote, and no existing GitHub release for the tag. It also warns when `Info.plist`'s `SUFeedURL` is not `https://<owner>.github.io/<repo>/appcast.xml`, because installed apps would never see the release.

**What it does, once preflight passes:**
1. Resolves the version and build number (see the flag reference below).
2. If `Version.xcconfig` doesn't already match the resolved version/build, updates it and commits **directly on whatever branch is currently checked out**, as `Release X.Y.Z (N)`.
3. Extracts that version's release notes from `CHANGELOG.md`.
4. Archives and exports a Developer ID build with `xcodebuild`. `DEVELOPMENT_TEAM` is overridden on the command line only; `project.pbxproj` is not rewritten.
5. Builds `Daisy-X.Y.Z.dmg`, signs it, notarizes it with `notarytool`, and staples it.
6. Signs the DMG with Sparkle's `sign_update`. With `--draft` / `--skip-github` the script stops here and publishes nothing.
7. Pushes the `vX.Y.Z` tag and creates the GitHub release with the DMG attached (a `--prerelease` for `--beta`).
8. Adds the release to `appcast.xml` on the `gh-pages` branch (via `scripts/appcast.py`) and pushes it. GitHub Pages serves that file as the Sparkle feed. The release is created first so the feed never points at a missing DMG.

GitHub Pages must be enabled for the `gh-pages` branch (repo Settings → Pages). The script creates the branch on first release.

**The script never pushes the branch itself and never opens or merges the PR.** That remains a separate, manual step.

### Publish a prepared release

When publication is requested, use the prepared release commit with a clean working tree and run `./scripts/release.sh`. It reads the already-bumped version/build and matching changelog; the version sync becomes a no-op. If a version is supplied with `--version` and the file already matches, the script also retains the prepared build number.

Running the script before opening a PR publishes first unless `--draft` (or `--skip-github`) is passed. Follow the preparation workflow above when the request is for a review PR. If publication creates a tag before the release PR is merged, merge with a regular merge, **not squash**, to keep the tagged commit in main's ancestry.

### Commands
```bash
./scripts/release.sh                            # release current Version.xcconfig
./scripts/release.sh --version 0.0.2            # bump marketing version (auto-bumps build)
./scripts/release.sh --version 0.0.2 --build 7  # bump marketing version, force build 7 instead of auto-bumping
./scripts/release.sh --build 7                  # keep current marketing version, force build 7
./scripts/release.sh --beta                     # appcast beta channel + GH prerelease (still publishes live)
./scripts/release.sh --draft                    # build, sign, notarize only — the only mode that doesn't publish
./scripts/release.sh --skip-github              # same as --draft
```

Before running, **add a `CHANGELOG.md` entry** for the version being shipped **and commit it** — the script refuses to run on a dirty working tree. **Always invoke the `changelog-maintenance` skill** by reading its `SKILL.md` and following its instructions whenever the user asks you to write, generate, or update a changelog entry — do not draft freeform. The skill enforces the project's house format, the Keep-a-Changelog category split (Added / Changed / Fixed / Security), and contributor crediting (it always inspects `git log` and `gh pr list` for non-maintainer authors and adds a `### Contributors` block with `@username` GitHub tags when any are found).

Entry shape:
```md
## [0.0.2] – 2026-05-01
Short narrative summary.
- **Bullet for each change.**
- Bug fix bullet.
```
The en dash (`–`) between the version and the date matches the project's house style (used in the script's own help text and error messages) — follow it for consistency. The script's parser only checks that the line starts with `## [X.Y.Z]`; the date and dash aren't validated, so this is a style convention, not something tooling enforces.

Source of truth: `Version.xcconfig` for the version numbers, `CHANGELOG.md` for the notes.

## Rolling back a release
```bash
./scripts/rollback-release.sh --latest             # remove latest from the appcast, delete GH release+tag
./scripts/rollback-release.sh 0.0.2                # roll back a specific version
./scripts/rollback-release.sh 0.0.2 --keep-github  # leave GitHub release in place
./scripts/rollback-release.sh --latest --yes       # skip the confirmation prompt
```
The script removes the version from `appcast.xml` on `gh-pages` first (so nobody is offered a deleted DMG), then deletes the GitHub release and tag. Apps that already installed the release are not downgraded; ship a newer build to supersede it. To re-publish a rolled-back version, run `release.sh` again for it.

## Distribution configuration
- **Hosting**: GitHub. The DMG is a GitHub release asset; the appcast is `appcast.xml` on the `gh-pages` branch, served by GitHub Pages at `https://<owner>.github.io/<repo>/appcast.xml`. `Info.plist`'s `SUFeedURL` must be that URL — verify it before releasing.
- **Codesign identity**: a `Developer ID Application` certificate for `DEVELOPMENT_TEAM` (override with `DAISY_TEAM_ID`).
- **Notary keychain profile**: `daisy-notary` by default (override with `NOTARY_PROFILE`); create with `xcrun notarytool store-credentials`.
- **EdDSA key**: public key in `Info.plist` `SUPublicEDKey`; the private key is in the login Keychain (or `SPARKLE_KEY_FILE`). `generate_keys -p` prints the Keychain's public key — it must match the plist.
