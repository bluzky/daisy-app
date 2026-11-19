# [PLAN] Install the Daisy slides skill from the menu

| | |
| --- | --- |
| Design ticket | none (slug `install-slides-skill`) |
| Feature Spec | `docs/features/install-slides-skill.md` |
| Target branch | `feature/59-file-tree-hidden-patterns` |
| Plan PR | — (auto flow) |
| Drafted with | Lucy (tech design role) — reviewed by author |
| Reviewer | tech lead |
| Status | Approved by Daniel (flex) in chat, 2026-11-19 (auto flow) |

## Phases

One phase = one phase ticket = one PR. With no tracker ticket, the phase is `P1`.

| Phase | Title | Stories | Depends on | Ticket |
| --- | --- | --- | --- | --- |
| P1 | Install Slides Skill menu action | US-1 | — | none |

### P1: Install Slides Skill menu action

- **Stories:** US-1
- **Depends on:** —
- **Why this phase:** one story, one menu action. Bundling, the installer and the menu are useless apart.

**Breakdown:**

| # | Context / module | What to do | Spec ref |
| --- | --- | --- | --- |
| 1 | `daisy/App/SlidesSkillInstaller.swift` (new) + symlink in `tests/swift-tests/Sources/MarkdownHelpers/` | `Target` presets with real-home default folders; `install(bundledSkill:into:)` copying via temp folder and replacing `daisy-slides` | BR-2, BR-3, BR-5 |
| 2 | `daisy.xcodeproj` | Run Script phase copying `.agents/skills/daisy-slides` to Resources as `daisy-slides-skill` with `rsync -aL`; declare input and output paths. Check `git diff` for `DEVELOPMENT_TEAM` | BR-3 |
| 3 | `daisy/App/AppDelegate.swift` | Menu item after Install CLI…; open panel with Claude / Codex / Custom accessory; run the installer; success and error alerts | BR-1, BR-2, BR-4, BR-6 |
| 4 | `daisy/en.lproj/Localizable.strings` | New labels | — |
| 5 | `README.md`, `docs/slides.md` | Mention the menu action where the skill is described | — |

**Tests:** `SlidesSkillInstallerTests` — preset folders, fresh install, reinstall replaces and leaves siblings, failed copy keeps the old install (AC-1.3 to AC-1.5). Runtime check: build, open the menu item, install to a temp folder.
