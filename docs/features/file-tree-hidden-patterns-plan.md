# [PLAN] Hide files and folders from the file tree by pattern

| | |
| --- | --- |
| Design ticket | [#58](https://github.com/bluzky/daisy-app/issues/58) |
| Feature Spec | `docs/features/file-tree-hidden-patterns.md` |
| Target branch | `chore/install-lucy` |
| Plan PR | — (auto flow) |
| Drafted with | Lucy (tech design role) — reviewed by author |
| Reviewer | tech lead |
| Status | Approved by Daniel (flex) in chat, 2026-11-18 (auto flow) |

## Phases

One phase = one phase ticket = one PR.

| Phase | Title | Stories | Depends on | Ticket |
| --- | --- | --- | --- | --- |
| P1 | Hide file tree items by pattern | US-1 | — | [#59](https://github.com/bluzky/daisy-app/issues/59) |

### P1: Hide file tree items by pattern

- **Stories:** US-1
- **Depends on:** —
- **Why this phase:** one story, one setting, about six files: the matcher, the tree filter, the setting, the menu and keymap command, and tests. Splitting would leave a setting that does nothing, or a matcher with no caller.

**Breakdown:**

| # | Context / module | What to do | Spec ref |
| --- | --- | --- | --- |
| 1 | `daisy/Preferences/FileTreeHiddenPatterns.swift` (new) + symlink in `tests/swift-tests/Sources/MarkdownHelpers/` | Parse comma-separated patterns; `isHidden(name:relativePath:isDirectory:)` with `fnmatch`; defaults key; `didChangeNotification` | BR-1…BR-4 |
| 2 | `daisy/Features/Sidebar/ProjectNavigatorView.swift` (`FileNode`, `listing(of:)`, init) | `FileNode` keeps its root URL; `listing` drops hidden entries; the opened folder is never filtered; observe the notification → `refreshTree()` | BR-3, BR-5, AC-1.5, AC-1.6 |
| 3 | `daisy/Features/Settings/SettingsModel.swift`, `GeneralSettingsView.swift` | `fileTreeHiddenPatterns` property loaded in both load paths; "File Tree" section with a text field; save and post the notification on commit (Return or focus loss) | BR-6, AC-1.5 |
| 4 | `daisy/Preferences/Keymap.swift`, `daisy/App/AppDelegate.swift`, new `daisy/Document/DocumentWindowController+HiddenFiles.swift` (modelled on `+HideCompletedTasks.swift`), `docs/keybindings.md` | `view.toggleHiddenFiles` command (global, `shift+cmd+.`), View menu item titled Toggle Hidden Files, checkmark while on; handler flips `showHiddenFiles` and posts the notification; listing drops `.skipsHiddenFiles` when on | BR-7, BR-8, AC-1.7…AC-1.9 |
| 5 | `daisy/en.lproj/Localizable.strings` | Labels and help text for the field and menu title | — |
| 6 | `README.md` | One line on the setting and the View command, next to the Hide Completed Tasks bullet | — |
| 7 | `daisy.xcodeproj` | Add the new source file to the `daisy` target only if the project does not pick it up automatically; do not touch `DEVELOPMENT_TEAM` | — |

**Tests:**

| AC | Test (file and name) |
| --- | --- |
| AC-1.1 | `tests/swift-tests/Tests/MarkdownHelpersTests/FileTreeHiddenPatternsTests.swift` — `AC-1.1 name pattern hides at any depth` |
| AC-1.2 | same file — `AC-1.2 comma list with spaces and globs` |
| AC-1.3 | same file — `AC-1.3 path pattern matches relative path only` |
| AC-1.4 | same file — `AC-1.4 trailing slash matches folders only` |
| AC-1.5 | `FileTreeHiddenPatternsTests` — `AC-1.5 change posts the notification`; run in the app: change the setting with a tree open (runtime verification) |
| AC-1.6 | same file — `AC-1.6 opened folder is never hidden` (listing-level check on the opened folder) |
| AC-1.7 | same file — `AC-1.7 show flag reveals dot-files and pattern matches`; in-app check across two windows |
| AC-1.8 | same file — `AC-1.8 flag is stored and read back` |
| AC-1.9 | `KeymapTests.swift` — `AC-1.9 toggleHiddenFiles default binding and no clash`; in-app check of the menu title and checkmark |

**Migration / config / flags:** none. New `UserDefaults` keys `MarkdownPreview.fileTreeHiddenPatterns` and `MarkdownPreview.showHiddenFiles`.

**Risks / notes:** `FileNode` is `private` inside `ProjectNavigatorView.swift`, so the AC-1.6 check goes through the pure type; the in-app check covers the tree. Commit-on-focus-loss in SwiftUI needs a `@FocusState`; if that proves awkward, commit on Return and on the Settings window closing, and say so in the PR.
