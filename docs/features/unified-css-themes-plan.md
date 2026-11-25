# [PLAN] Unified CSS themes for reading, editor and slides

| | |
| --- | --- |
| Design ticket | [#75 [DESIGN] Unified CSS themes for reading, editor and slides](https://github.com/bluzky/daisy-app/issues/75) |
| Feature Spec | `docs/features/unified-css-themes.md` |
| Target branch | Not set yet (same as the spec) |
| Plan PR | Not opened |
| Drafted with | Draft — Tech design agent; not yet reviewed by the author |
| Reviewer | tech lead |
| Status | Draft |

## Phases

One phase = one phase ticket, normally one PR.

| Phase | Title | Stories | Depends on | Ticket |
| --- | --- | --- | --- | --- |
| P1 | CSS theme model replaces slide themes | US-3, US-4 | — | <added by create-tickets> |
| P2 | Any theme as the reading theme | US-1, US-2 | P1 | <added by create-tickets> |

Why two phases (FLOW-10): P1 is a refactor with a golden-test safety net and almost no visible change (renames in BR-17, YAML dropped in BR-18). P2 adds new UI and new stores (menu, user themes as reading theme, new color slots and fonts). Together they would make one PR too big to review, and they carry different risk: P1's risk is that existing looks change (BR-9), P2's is new behaviour. P1 ships nothing alone: both merge into the target branch before a release, because P1 removes YAML user themes and P2 adds the View ▸ Theme way to pick CSS ones.

### P1: CSS theme model replaces slide themes

- **Stories:** US-3, US-4
- **Depends on:** —
- **Why this phase:** The `Theme` model, its parser and the 12 built-ins are what everything else reads. Decks (US-3) and the upgrade path (US-4) only need the model and the slide renderer, not the reading-theme UI.

**Breakdown:**

| # | Context / module | What to do | Spec ref |
| --- | --- | --- | --- |
| 1 | Rendering — new `daisy/Rendering/Theme.swift` | `Theme` (`id`, `name`, `appearance`, `extends`, `light`, `dark`, `header`, `footer`): parse the `@theme` comment with `SlideYAML.parse` (`SlideDeckSettings.swift:33`); read only `--name: value;` in `:root` and the dark `@media` block; sanitize per token (hex colors via `sanitizedHexColor` with `#rgb`/`#rgba` expanded, fonts via today's `sanitizedFontFamily`, `--body-weight` 400/600, `--table-style`, `--slide-font-size`); drop everything else; resolve `extends` like `SlideTheme.swift:268-291` (one-palette base fills both schemes; appearance inherited); ignore a theme with no appearance after resolving | BR-1, BR-5, BR-6, BR-7, §2 Theme file format, Q-18, Q-24 |
| 2 | Resources — new `daisy/Resources/Themes/<id>.css`; Rendering — new `daisy/Rendering/BuiltInThemes.swift` | One folder holds all 12 built-ins as theme files in the reader's format: the nine gallery themes written from today's `ThemePreset.builtIn` values (`ThemePreset.swift:223`), `pitch.css`, `paper-warm.css`, `midnight-navy.css` from today's slide YAML (`SlideTheme.swift:199-259`); `light`/`dark` slide themes removed; `original.css` has only its `@theme` header. `BuiltInThemes` loads them from the bundle like `DocxThemeStore` (`DocxThemeStore.swift:40-42`) and takes a directory for tests | BR-2, BR-17, Q-17, Q-21 |
| 3 | Rendering — `Theme.slideCSS` | Rewrite slide CSS from tokens: variables scoped to `:where(.mdp-deck) .mdp-slide`, three buckets for `system` themes, light/dark-only pinning as `SlideTheme.swift:130-137`; keep the non-variable rules listed in §2 Data model (heading reset `:143-149`, `li::marker` accent `:166-167`, `--secondary` `:141`, title/section rules `:172-179`); `--bold`, header/footer, `--slide-font-size` | BR-4, BR-6, BR-8, BR-9, Q-30 |
| 4 | Rendering — `daisy/Rendering/Slides/SlideDeckSettings.swift:150-151` | `theme_overrides:` `colors:`/`fonts:` keys mapped to tokens (inverse of `SlideTheme.swift:53-72`) and applied on top of the deck's theme or alone; `theme: default` = reading theme; unknown id = reading theme; id match ignores case | BR-4, BR-17, Q-21, Q-25 |
| 5 | Rendering — `MarkdownHTML.swift:386-395, 583-589`, `MarkdownWebView.swift:420-426`, `MarkdownWebView+PDFExport.swift:850` | `render(…slideThemes:)` takes `[String: Theme]`. Catalog: app = built-ins + `~/.config/daisy/themes/*.css` (user file with a built-in id skipped); Quick Look = built-ins only | BR-4, BR-11, BR-12, BR-15, BR-18 |
| 6 | Theme — new `daisy/Theme/ThemeLibrary.swift` (catalog part only) | User folder from the real home dir (as `SlideThemeStore.swift:22-27`), `catalog()` read on each deck render. The `applied` / refresh parts come in P2 | BR-11, BR-12, Q-1, Q-10 |
| 7 | Theme — `daisy/Theme/ThemePreset.swift` | `ThemePreset` built from the built-in `Theme`s (name, flavor, font matched against `DocumentFontSetting.fontFamily`, boldText, swatches, `ThemeColorsSetting(theme:)`); `builtIn` stays the nine; add `ThemePreset.all` (12). Stored ids unchanged | BR-2, BR-9, Q-26 |
| 8 | Remove — `SlideTheme.swift`, `SlideThemeStore.swift` | Delete both and YAML theme reading; `~/.config/daisy/slide-themes/` no longer read, nothing written there | BR-18, Q-28 |
| 9 | Build — `daisy.xcodeproj/project.pbxproj:107-150`; `tests/swift-tests/Sources/MarkdownHelpers/` | Add `Theme.swift`, `BuiltInThemes.swift` and the 12 `Resources/Themes/*.css` to Quick Look exceptions; check the built app and extension contain the CSS files and no other bundled `<id>.css` clashes with their names (resources are copied flat). Symlink `Theme.swift`, `BuiltInThemes.swift`, `ThemeLibrary.swift` into the test package, remove the `SlideTheme*` links; tests read `daisy/Resources/Themes/` from the repo (as `DocxThemeTests.swift:11`). Check the pbxproj diff for `DEVELOPMENT_TEAM` changes | §2 Impact (Quick Look target, Test package) |
| 10 | Docs — `docs/slides.md:96-169`, `.agents/skills/daisy-slides/SKILL.md:3, 30, 177-204`, `.agents/skills/daisy-slides/scripts/check_deck.py:29, 122-147` | Theme list (renames, `light`/`dark` gone), CSS theme format, `~/.config/daisy/themes/`, YAML no longer read and how to rewrite one; `check_deck.py` knows the new ids | BR-17, BR-18, AGENTS.md "Documentation…" |

**Tests:**

| AC | Test (file and name) |
| --- | --- |
| AC-3.1 | `ThemeTests.swift` — `testAC_3_1_deckThemeEmberAppliesItsTokensOverReadingTheme` |
| AC-3.2 | `ThemeTests.swift` — `testAC_3_2_noThemeOrUnknownThemeEmitsNoSlideThemeCSS` (render level: only `theme_overrides`, reading theme underneath; the "my own reading theme" part is checked by hand in P2) |
| AC-3.3 | `ThemeTests.swift` — `testAC_3_3_darkOnlyThemePinsSlidesAndCodeDark` |
| AC-3.4 | `ThemeTests.swift` — `testAC_3_4_quickLookCatalogHasBuiltInsOnly` |
| AC-4.1 | `ThemeTests.swift` — `testAC_4_1_builtInPresetsMatchTodaysValues` (golden: recorded settings, font, boldText of today's nine presets) and `testAC_4_1_savedLookJSONStillDecodes` |
| AC-4.2 | `ThemeTests.swift` — `testAC_4_2_pitchSlideCSSMatchesTodaysComputedValues` (golden vs today's `SlideTheme.css` for `pitch`, `paper`→`paper-warm`, `midnight`→`midnight-navy`) and `testAC_4_2_themeMidnightIsTheReadingMidnight` |
| AC-4.3 | `ThemeTests.swift` — `testAC_4_3_yamlSlideThemeIsNotReadAndLeftOnDisk` |
| AC-4.4 | `ThemeTests.swift` — `testAC_4_4_themeDarkFallsBackToReadingTheme` |
| Parser | `ThemeTests.swift` — invalid values dropped, color names rejected, `#rgb` expanded, extends chain, missing appearance ignored, built-in id skipped (BR-5, BR-6, BR-7, BR-12) |

Port the surviving `SlideThemeTests` cases (overrides, footer, font sanitizing) to `ThemeTests.swift` before deleting it.

**Migration / config / flags:** None. Stored theme ids and saved-look keys unchanged.

**Risks / notes:**
- Built-in CSS is a resource, not compiled code: a file missing from the Quick Look bundle only shows at runtime. `testAC_3_4` loads all 12 ids from the folder, and the PR shows a Quick Look deck with `theme: pitch`.
- The golden tests are recorded from today's code **before** removing `SlideTheme`: write them first, against the old output.
- Between P1 and P2 the reader can't pick a CSS theme for reading; don't release from the target branch until P2 is merged.

### P2: Any theme as the reading theme

- **Stories:** US-1, US-2
- **Depends on:** P1
- **Why this phase:** Everything that lets a CSS theme drive the reading view and the editor: the menu, applying and refreshing user themes, and the new tokens (BR-10) in the page and editor CSS. US-1 and US-2 share all of it.

**Breakdown:**

| # | Context / module | What to do | Spec ref |
| --- | --- | --- | --- |
| 1 | Theme — `daisy/Theme/ThemeColorsSetting.swift:20-47, 178-222, 227-327` | 16 new `ThemeColorSlot`s (`tableHeaderText`, `boldText`, 14 widget colors, defaults from `WidgetColor.defaultHex`); font fields `themeFont.body/.heading/.code`; `ThemeColorsSetting(theme:)` fills them; emitted by `markdownThemeOverrides` and `editorOverrideCSS` | BR-10, Q-13, §2 DB |
| 2 | Rendering — `MarkdownHTML.swift:69-207` (`ThemeOverrides.css`) | New color and font fields in the three buckets; font tokens outside the `@media screen` wrapper so they print | BR-10, §2 Impact |
| 3 | Rendering — `MarkdownHTML+Stylesheet.swift:200, 391, 473, 699, 715, 1052`; `MarkdownHTML+Widgets.swift:193-215` | `--font-body`, `h1…h6 { font-family: var(--font-heading, inherit) }`, `--font-code`, `strong, b { color: var(--bold, inherit) }`, widget buckets from tokens; no change when unset | BR-10 |
| 4 | Editor — `daisy/Features/Editor/EditorHTML.swift:126, 158, 749` (body), `:190, 357, 540, 633, 661, 736` (code) | Same font and bold variables | BR-10 |
| 5 | Theme — `ThemeLibrary` (from P1) | `applied` (`.builtIn(ThemePreset)` / `.user(Theme)`), `refreshAppliedUserTheme()` (re-apply only when resolved values change; Original when gone or invalid) | BR-6, BR-14, BR-16, Q-8, Q-31 |
| 6 | Settings — `daisy/Features/Settings/SettingsModel.swift:326-340` | New `applyUserTheme` writes its values into the stores (spacing = app defaults; appearance locked or `.automatic`); `applyPresetValues` saves the outgoing look only for a built-in | BR-3, BR-6, BR-9, BR-13, Q-26, Q-29 |
| 7 | All `ThemePreset.applied()` call sites: `AppDelegate.swift:137, 192, 206, 390, 694, 737`; `SettingsModel.swift:41, 295, 315, 457`; `CustomizeThemeView.swift:137`; `ThemeSettingsView.swift:21`; `ThemePresetGallery.swift:22` | Read `ThemeLibrary.applied`; the gallery shows no card selected for a user theme | BR-2, BR-6, §2 Impact |
| 8 | Settings UI — `ThemesPopoverView.swift:75`, `ThemeSettingsView.swift:70` | Customize disabled while a user theme is applied; Customize works for all 12 built-ins | BR-13, Q-26 |
| 9 | App — `daisy/App/AppDelegate.swift:1467-1500, 1920-1924` | View ▸ Theme after Content Width, rebuilt in `menuNeedsUpdate` (guard by menu identity like Bookmarks `:1120-1126`): 9 gallery, 3 other built-ins, separator, user themes by name, separator, "Open Themes Folder" (creates the folder like `DocxThemeStore.ensureUserDirectory`); applied theme checked | BR-3, BR-11, BR-16 |
| 10 | App — `AppDelegate.swift:135-139, 184-208` | Launch appearance lock from `ThemeLibrary.applied`; `applicationDidBecomeActive` and the menu call `refreshAppliedUserTheme()` | BR-6, BR-14, BR-16 |
| 11 | Docs — `docs/widgets.md:275`, `README.md:55-56`, `docs/slides.md` (theme section) | Themes can set widget colors; user themes for reading; View ▸ Theme | AGENTS.md "Documentation…" |

**Tests:**

| AC | Test (file and name) |
| --- | --- |
| AC-1.1 | Manual: two files in `~/.config/daisy/themes/`, View ▸ Theme order and check mark (screenshot). Unit: `ThemeLibraryTests.swift` — `testAC_1_1_catalogListsBuiltInsThenUserThemesByName` |
| AC-1.2 | Manual: two windows, choose a user theme, both redraw (screenshot) |
| AC-1.3 | Manual: aA popover with a user theme applied, no card selected (screenshot) |
| AC-1.4 | Manual: dark-only user theme locks dark, appearance button disabled. Unit: `ThemeTests.swift` — `testAC_1_4_darkOnlyThemeRequiresDarkAppearance` |
| AC-1.5 | Manual: Paper line spacing customized, then user theme: Customize disabled in popover and Settings, default spacing |
| AC-1.6 | Manual: delete the active theme file, switch back to Daisy, Original. Unit: `ThemeLibraryTests.swift` — `testAC_1_6_missingAppliedFileResolvesToOriginal` |
| AC-2.1 | Manual: `brand.css` as reading theme and `theme: brand` deck. Unit: `ThemeTests.swift` — `testAC_2_1_sameThemeFeedsPageEditorAndSlideCSS` |
| AC-2.2 | `ThemeTests.swift` — `testAC_2_2_invalidColorFallsBackToBaseValue` |
| AC-2.3 | `ThemeTests.swift` — `testAC_2_3_systemThemeEmitsLightAndDarkBuckets` |
| AC-2.4 | `ThemeTests.swift` — `testAC_2_4_extendsEmberOverridesOnlyLink` |
| AC-2.5 | `ThemeTests.swift` — `testAC_2_5_fontsAndH2InPageCSSSlideOnlyKeysOnlyInSlideCSS` |
| AC-2.6 | `WidgetTests.swift` — `testAC_2_6_accentWidgetColorFromThemeInPageAndSlides` |
| AC-2.8 | `ThemeLibraryTests.swift` — `testAC_2_8_themeWithoutAppearanceIsNotListed` |
| AC-2.9 | `ThemeLibraryTests.swift` — `testAC_2_9_userEmberFileIsSkipped` |
| AC-2.10 | Manual: edit the link color in another app, switch back. Unit: `ThemeLibraryTests.swift` — `testAC_2_10_refreshReportsChangeOnlyWhenValuesDiffer` |

`SettingsModel` and `AppDelegate` aren't in the test package, so the menu, popover and window ACs get manual evidence (screenshots in the PR).

**Migration / config / flags:** New shared-defaults keys (`themeColor.<scheme>.<new slot>`, `themeFont.*`); missing keys mean the default, no migration. Saved-look JSON gains keys; old JSON decodes unchanged.

**Risks / notes:**
- A missed `ThemePreset.applied()` call site shows a user theme as Original and skips the appearance lock: grep for every call site before the PR.
- Leaving a user theme must not write its colors into a built-in's saved look (row 6 guard).
- On a downgrade, saved-look JSON with new keys fails to decode in the old app and that theme shows defaults (§2 Rollback); accepted.
