import Foundation
import WebKit
import XCTest

@testable import MarkdownHelpers

final class ThemeTests: XCTestCase {
  /// A theme file with an `@theme` header.
  private func file(_ id: String, _ css: String, appearance: String? = "light", extends: String? = nil,
                    extra: String = "") -> Theme.File {
    var header = "/* @theme\nname: \(id.capitalized)\n"
    if let appearance { header += "appearance: \(appearance)\n" }
    if let extends { header += "extends: \(extends)\n" }
    header += extra + "*/\n"
    return Theme.File(id: id, css: header + css)
  }

  private let brandCSS = """
  /* @theme
  name: My Brand
  appearance: system        # light | dark | system
  extends: ember
  footer: "{title} | | {slide_number}/{total}"
  */
  /* Brand colors. */
  :root { --link: #0057B8; --font-heading: Inter, sans-serif; --font-code: Menlo, monospace; }
  @media (prefers-color-scheme: dark) { :root { --link: #64A8FF; --font-body: Ignored; } }
  .markdown-body { display: none; }
  """

  /// The deck's slide CSS as `selector → property → value`, a later
  /// declaration winning: what the browser computes from it.
  private func declarations(_ css: String) -> [String: [String: String]] {
    var result: [String: [String: String]] = [:]
    let regex = try! NSRegularExpression(pattern: "([^{}]+)\\{([^{}]*)\\}")
    let text = css as NSString
    for match in regex.matches(in: css, range: NSRange(location: 0, length: text.length)) {
      let selector = text.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
      for declaration in text.substring(with: match.range(at: 2)).split(separator: ";") {
        guard let colon = declaration.firstIndex(of: ":") else { continue }
        let property = declaration[..<colon].trimmingCharacters(in: .whitespacesAndNewlines)
        let value = declaration[declaration.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
        result[selector, default: [:]][property] = value
      }
    }
    return result
  }

  @MainActor
  private func evaluate(_ html: String, _ script: String, width: CGFloat = 1100) async throws -> String? {
    let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: width, height: 900))
    webView.loadHTMLString(html, baseURL: nil)
    let deadline = Date().addingTimeInterval(10)
    while webView.isLoading && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
    return try await webView.evaluateJavaScript(script) as? String
  }

  // MARK: - Parsing (BR-5, BR-6, BR-7, BR-12)

  func testParsesMetadataPalettesAndDropsEverythingElse() throws {
    let catalog = Theme.catalog(builtIns: BuiltInThemes.files, user: [Theme.File(id: "Brand", css: brandCSS)])
    let theme = try XCTUnwrap(catalog["brand"], "the id is the lowercased file name")
    XCTAssertEqual(theme.name, "My Brand")
    XCTAssertEqual(theme.appearance, .system)
    XCTAssertEqual(theme.footer, "{title} | | {slide_number}/{total}")
    XCTAssertEqual(theme.light["link"], "#0057B8")
    XCTAssertEqual(theme.dark["link"], "#64A8FF")
    XCTAssertEqual(theme.light["font-heading"], "Inter, sans-serif")
    XCTAssertNil(theme.dark["font-body"], "fonts are read from :root only")
    XCTAssertFalse(theme.slideCSS.contains("display: none"))
  }

  func testColorsAreHexOnlyAndShortFormsExpand() {
    let parsed = file("x", """
    :root { --text: #abc; --link: #abcd; --bg: navy; --heading: rgb(1, 2, 3); --font-body: Inter;
            --bold: #12; --unknown: #ffffff; --code-bg: "red; } body { display: none"; }
    * { color: red; --font-code: Menlo, monospace; }
    """)
    XCTAssertEqual(parsed.light["text"], "#aabbcc")
    XCTAssertEqual(parsed.light["link"], "#aabbccdd")
    XCTAssertNil(parsed.light["bg"], "color names are not accepted")
    XCTAssertNil(parsed.light["heading"])
    XCTAssertNil(parsed.light["code-bg"])
    XCTAssertNil(parsed.light["bold"])
    XCTAssertNil(parsed.light["unknown"])
    XCTAssertEqual(parsed.light["font-body"], "Inter")
    XCTAssertNil(parsed.light["font-code"], "a declaration outside :root is not a token")
  }

  func testAThemeWithoutAppearanceIsIgnoredUnlessItsBaseHasOne() {
    let catalog = Theme.catalog(builtIns: BuiltInThemes.files, user: [
      file("loose", ":root { --link: #111111; }", appearance: nil),
      file("child", ":root { --link: #222222; }", appearance: nil, extends: "ember"),
      file("bad", "", appearance: "sepia"),
    ])
    XCTAssertNil(catalog["loose"])
    XCTAssertNil(catalog["bad"])
    XCTAssertEqual(catalog["child"]?.appearance, .system)
  }

  func testAUserFileWithABuiltInIdIsSkippedAndCyclesDoNotHang() {
    let catalog = Theme.catalog(builtIns: BuiltInThemes.files, user: [
      file("ember", ":root { --link: #000000; }"),
      file("a", "", extends: "b"),
      file("b", "", extends: "a"),
    ])
    XCTAssertEqual(catalog["ember"]?.light["link"], "#8F4E0E", "the built-in wins")
    XCTAssertNotNil(catalog["a"])
    XCTAssertNotNil(catalog["b"])
  }

  func testAOnePaletteBaseGivesItsPaletteToBothSchemes() throws {
    let catalog = Theme.catalog(builtIns: BuiltInThemes.files, user: [
      file("night", "@media (prefers-color-scheme: dark) { :root { --link: #333333; } }",
           appearance: "system", extends: "midnight"),
    ])
    let theme = try XCTUnwrap(catalog["night"])
    XCTAssertEqual(theme.light["bg"], "#363846")
    XCTAssertEqual(theme.dark["bg"], "#363846")
    XCTAssertEqual(theme.dark["link"], "#333333")
    XCTAssertEqual(theme.light["link"], "#8BE9FD")
  }

  func testLuminance() {
    XCTAssertEqual(Theme.luminance(ofHex: "#fff") ?? 0, 1, accuracy: 0.001)
    XCTAssertEqual(Theme.luminance(ofHex: "#000000") ?? 1, 0, accuracy: 0.001)
  }

  // MARK: - US-3: a deck names any theme

  @MainActor
  func testAC_3_1_deckThemeEmberAppliesItsTokensOverReadingTheme() async throws {
    let paper = try XCTUnwrap(ThemePreset.builtIn.first { $0.name == "Paper" })
    for (scheme, expected) in [(MarkdownHTML.ColorScheme.light, "rgb(163, 59, 32)|rgb(143, 78, 14)"),
                               (.dark, "rgb(240, 138, 108)|rgb(224, 164, 88)")] {
      let rendered = MarkdownHTML.render(
        markdown: "---\nslides: true\ntheme: ember\n---\n\n# Title [link](https://example.com)\n",
        vendorLoading: .lazy, colorScheme: scheme, themeOverrides: paper.setting.markdownThemeOverrides)
      let result = try await evaluate(rendered.html, """
      (() => { const h = document.querySelector('.mdp-slide h1');
        return getComputedStyle(h).color + '|' + getComputedStyle(h.querySelector('a')).color })()
      """)
      XCTAssertEqual(result, expected, "\(scheme): Ember's H1 and link, not Paper's")
    }
    let css = BuiltInThemes.catalog["ember"]!.slideCSS
    XCTAssertTrue(css.contains("font-family: \"Iowan Old Style\", ui-serif, Georgia, serif;"))
  }

  @MainActor
  func testAC_3_2_noThemeOrUnknownThemeKeepsTheReadingTheme() async throws {
    let paper = try XCTUnwrap(ThemePreset.builtIn.first { $0.name == "Paper" })
    for frontmatter in ["slides: true", "slides: true\ntheme: nope", "slides: true\ntheme: default"] {
      let settings = SlideDeckSettings(markdown: "---\n\(frontmatter)\n---\n")
      XCTAssertEqual(Theme.forDeck(settings, in: BuiltInThemes.catalog).slideCSS, "", frontmatter)
      let rendered = MarkdownHTML.render(markdown: "---\n\(frontmatter)\n---\n\n# Title\n",
                                         vendorLoading: .lazy, colorScheme: .light,
                                         themeOverrides: paper.setting.markdownThemeOverrides)
      let color = try await evaluate(rendered.html, "getComputedStyle(document.querySelector('.mdp-slide h1')).color")
      XCTAssertEqual(color, "rgb(179, 54, 59)", "\(frontmatter): Paper's H1")
    }
  }

  func testAC_3_3_darkOnlyThemePinsSlidesAndCodeDark() {
    let css = BuiltInThemes.catalog["midnight-navy"]!.slideCSS
    XCTAssertTrue(css.contains("color-scheme: dark;"))
    XCTAssertTrue(css.contains("--hl-keyword: #fc5fa3;"), "dark code colors in any window")
    XCTAssertTrue(BuiltInThemes.catalog["pitch"]!.slideCSS.contains("--hl-keyword: #9b2393;"))
    XCTAssertFalse(BuiltInThemes.catalog["ember"]!.slideCSS.contains("{ color-scheme:"),
                   "a theme that follows the system follows the window")
  }

  @MainActor
  func testAC_3_3_darkOnlyDeckStaysDarkInALightWindow() async throws {
    let rendered = MarkdownHTML.render(
      markdown: "---\nslides: true\ntheme: midnight-navy\n---\n\n## Code\n\n```swift\nlet x = 1\n```\n",
      vendorLoading: .lazy, colorScheme: .light)
    let result = try await evaluate(rendered.html, """
    (() => { const slide = document.querySelectorAll('.mdp-slide')[0];
      return [getComputedStyle(slide).backgroundColor,
              getComputedStyle(slide).getPropertyValue('--hl-keyword').trim(),
              getComputedStyle(slide.querySelector('pre')).backgroundColor].join('|') })()
    """)
    XCTAssertEqual(result, "rgb(15, 23, 42)|#fc5fa3|rgb(30, 41, 59)",
                   "navy slide, dark code colors and the theme's code background in a light window")
  }

  func testAC_3_4_quickLookCatalogHasBuiltInsOnly() throws {
    XCTAssertEqual(BuiltInThemes.all.map(\.id), BuiltInThemes.ids, "every built-in file is bundled and valid")
    XCTAssertEqual(BuiltInThemes.ids.count, 11)
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try brandCSS.write(to: folder.appendingPathComponent("brand.css"), atomically: true, encoding: .utf8)
    XCTAssertNotNil(ThemeLibrary.catalog(userDirectory: folder)["brand"], "the app reads the folder")
    let settings = SlideDeckSettings(markdown: "---\ntheme: brand\n---\n")
    XCTAssertEqual(Theme.forDeck(settings, in: BuiltInThemes.catalog).id, Theme.readingThemeID,
                   "Quick Look's catalog: the reading theme")
  }

  // MARK: - US-4: the update keeps the look

  /// Today's nine presets, recorded before the themes moved to CSS.
  private struct RecordedPreset {
    let name: String
    let flavor: ThemePreset.Flavor
    let font: DocumentFontSetting
    let boldText: Bool
    let light: [ThemeColorSlot: String]
    let dark: [ThemeColorSlot: String]
  }

  private static func colors(_ bg: String, _ code: String, _ text: String, _ link: String,
                             headings: [String] = []) -> [ThemeColorSlot: String] {
    var result: [ThemeColorSlot: String] = [.windowBackground: bg, .codeBlockBackground: code,
                                            .textColor: text, .linkColor: link]
    for (index, color) in headings.enumerated() { result[ThemeColorSlot.heading(level: index + 1)!] = color }
    return result
  }

  private static let recordedPresets: [RecordedPreset] = {
    let quiet = colors("#4A4A4D", "#59595D", "#EBEBF4", "#99B7C4")
    let paper = colors("#EEEDED", "#E3E1E1", "#262626", "#DE4A4F",
                       headings: ["#B3363B", "#8F5410", "#46702A", "#1F6F7A", "#4B5CA8", "#8A4C7A"])
    let bold = colors("#FFFFFF", "#F2F2F2", "#1C1C1E", "#007AFF")
    let calm = colors("#FDF6E3", "#F6EDDB", "#313D45", "#A0630F")
    let focus = colors("#FFFCF5", "#F5F1E4", "#14120B", "#A0630F")
    let dusk = colors("#0C3742", "#103E49", "#C3CFCC", "#299385")
    let midnight = colors("#363846", "#313343", "#FFFFFF", "#8BE9FD")
    return [
      RecordedPreset(name: "Original", flavor: .system, font: .system, boldText: false, light: [:], dark: [:]),
      RecordedPreset(name: "Quiet", flavor: .dark, font: .system, boldText: false, light: quiet, dark: quiet),
      RecordedPreset(name: "Paper", flavor: .light, font: .charter, boldText: false, light: paper, dark: paper),
      RecordedPreset(name: "Bold", flavor: .light, font: .system, boldText: true, light: bold, dark: bold),
      RecordedPreset(name: "Calm", flavor: .light, font: .georgia, boldText: false, light: calm, dark: calm),
      RecordedPreset(name: "Focus", flavor: .light, font: .newYork, boldText: false, light: focus, dark: focus),
      RecordedPreset(name: "Ember", flavor: .system, font: .iowan, boldText: false,
                     light: colors("#F6EFE3", "#ECE2D1", "#2B2219", "#8F4E0E",
                                   headings: ["#A33B20", "#945410", "#52702A", "#2B6C70", "#585796", "#86496A"]),
                     dark: colors("#2B2620", "#37312A", "#E8DFCF", "#E0A458",
                                  headings: ["#F08A6C", "#F0B27A", "#B5CE85", "#7FCBC8", "#B3B0F0", "#E1A3C0"])),
      RecordedPreset(name: "Dusk", flavor: .dark, font: .system, boldText: false, light: dusk, dark: dusk),
      RecordedPreset(name: "Midnight", flavor: .dark, font: .system, boldText: false, light: midnight, dark: midnight),
    ]
  }()

  func testAC_4_1_builtInPresetsMatchTodaysValues() throws {
    // Q-34: Pitch took Bold's gallery card; the other eight keep their ids,
    // order and values, so their applied-theme and saved-look keys still work.
    let expectedOrder = Self.recordedPresets.map { $0.name == "Bold" ? "Pitch" : $0.name }
    XCTAssertEqual(ThemePreset.builtIn.map(\.id), expectedOrder)
    for recorded in Self.recordedPresets where recorded.name != "Bold" {
      let preset = try XCTUnwrap(ThemePreset.builtIn.first { $0.id == recorded.name })
      var expected = ThemeColorsSetting()
      for (slot, hex) in recorded.light { expected.setHex(hex, slot, .light) }
      for (slot, hex) in recorded.dark { expected.setHex(hex, slot, .dark) }
      XCTAssertEqual(preset.setting, expected, preset.name)
      XCTAssertEqual(preset.flavor, recorded.flavor, preset.name)
      XCTAssertEqual(preset.font, recorded.font, preset.name)
      XCTAssertEqual(preset.boldText, recorded.boldText, preset.name)
    }
    XCTAssertEqual(ThemePreset.all.map(\.name).suffix(2), ["Paper Warm", "Midnight Navy"])
  }

  func testQ34_boldIsRemovedAndASavedBoldFallsBackToOriginal() {
    XCTAssertNil(BuiltInThemes.catalog["bold"])
    XCTAssertFalse(ThemePreset.all.contains { $0.id == "Bold" })
    XCTAssertEqual(ThemeLibrary.applied(id: "Bold", catalog: { BuiltInThemes.catalog }), .builtIn(.defaultPreset))
    XCTAssertEqual(ThemeLibrary.refresh(appliedID: "Bold", catalog: BuiltInThemes.catalog,
                                        current: ThemePreset.defaultPreset.restoredLook()),
                   .original, "the next activation applies Original")
    let deck = SlideDeckSettings(markdown: "---\nslides: true\ntheme: bold\n---\n")
    XCTAssertEqual(Theme.forDeck(deck, in: BuiltInThemes.catalog).slideCSS, "", "a deck uses the reading theme")
  }

  func testAC_4_1_customizedLookIsStillRestored() throws {
    let suite = "ThemeTests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let paper = try XCTUnwrap(ThemePreset.builtIn.first { $0.name == "Paper" })
    var colors = paper.setting
    colors.setHex("#123456", .linkColor, .light)
    paper.save(ThemePreset.SavedLook(colors: colors, font: .charter, layout: ReaderLayoutSetting(),
                                     appearance: .light), in: defaults)
    paper.recordApplied(in: defaults)
    XCTAssertEqual(ThemeLibrary.applied(in: defaults, userDirectory: nil).id, "Paper")
    XCTAssertEqual(paper.restoredLook(in: defaults).colors.hexValue(.linkColor, .light), "#123456")
  }

  /// Today's slide CSS for the former slide themes, recorded before the move.
  private static let recordedSlideCSS: [String: String] = [
    "pitch": """
      :where(.mdp-deck) .mdp-slide { color-scheme: light;
        --hl-plain: var(--text);
        --hl-plain: var(--text);
        --hl-keyword: #9b2393;
        --hl-string: #c41a16;
        --hl-comment: #5d6c79;
        --hl-doc-keyword: #4a5560;
        --hl-number: #1c00cf;
        --hl-type: #3900a0;
        --hl-builtin: #6c36a9;
        --hl-declaration: #0b4f79;
        --hl-function: #0f68a0;
        --hl-variable: #326d74;
        --hl-preprocessor: #643820;
        --hl-attribute: #815f03;
        --hl-url: #0e0eff;
        --code-bg: #f9f9f9;
        --widget-card: #f9f9f9;
        --code-border: #f0f0f0;
        --quote-border: rgb(0 0 0 / 15%);
        --grid: rgb(0 0 0 / 15%);
        --mdp-slide-bg: #ffffff;
        --text: #111111;
        --secondary: color-mix(in srgb, #111111 70%, transparent);
        --heading: #0057b8;
        --link: #0057b8;
        --table-header-bg: #0057b8;
        --table-header-text: #ffffff;
        --table-border: #c9d6e8;
        }
      .mdp-deck .mdp-slide li::marker { color: #0057b8;
        }
      .mdp-deck .mdp-slide :is(strong, b) { color: #b8003f;
        }
      .mdp-deck :where(.mdp-slide--title, .mdp-slide--section) { --mdp-slide-bg: #0057b8;
        --text: #ffffff;
        --secondary: color-mix(in srgb, #ffffff 80%, transparent);
        --heading: #ffffff;
        }
      """,
    "paper-warm": """
      :where(.mdp-deck) .mdp-slide { color-scheme: light;
        --hl-plain: var(--text);
        --hl-plain: var(--text);
        --hl-keyword: #9b2393;
        --hl-string: #c41a16;
        --hl-comment: #5d6c79;
        --hl-doc-keyword: #4a5560;
        --hl-number: #1c00cf;
        --hl-type: #3900a0;
        --hl-builtin: #6c36a9;
        --hl-declaration: #0b4f79;
        --hl-function: #0f68a0;
        --hl-variable: #326d74;
        --hl-preprocessor: #643820;
        --hl-attribute: #815f03;
        --hl-url: #0e0eff;
        --code-bg: #f9f9f9;
        --widget-card: #f9f9f9;
        --code-border: #f0f0f0;
        --quote-border: rgb(0 0 0 / 15%);
        --grid: rgb(0 0 0 / 15%);
        --mdp-slide-bg: #fbf7ef;
        --text: #2b2a27;
        --secondary: color-mix(in srgb, #2b2a27 70%, transparent);
        --heading: #8a4b1f;
        --link: #b0602c;
        --code-bg: #f1eadb;
        --widget-card: #f1eadb;
        }
      .mdp-deck .mdp-slide li::marker { color: #b0602c;
        }
      .mdp-deck .mdp-slide { font-family: Georgia, 'Times New Roman', serif;
        }
      .mdp-deck .mdp-slide :is(h1, h2, h3, h4, h5, h6) { font-family: Georgia, 'Times New Roman', serif;
        }
      """,
    "midnight-navy": """
      :where(.mdp-deck) .mdp-slide { color-scheme: dark;
        --hl-plain: var(--text);
        --hl-keyword: #fc5fa3;
        --hl-string: #fc6a5d;
        --hl-comment: #6c7986;
        --hl-doc-keyword: #92a1b1;
        --hl-number: #d0bf69;
        --hl-type: #d0a8ff;
        --hl-builtin: #a167e6;
        --hl-declaration: #5dd8ff;
        --hl-function: #41a1c0;
        --hl-variable: #67b7a4;
        --hl-preprocessor: #fd8f3f;
        --hl-attribute: #bf8555;
        --hl-url: #5482ff;
        --code-bg: #262626;
        --widget-card: #262626;
        --code-border: #323232;
        --quote-border: rgb(255 255 255 / 25%);
        --grid: rgb(255 255 255 / 20%);
        --mdp-slide-bg: #0f172a;
        --text: #e2e8f0;
        --secondary: color-mix(in srgb, #e2e8f0 70%, transparent);
        --heading: #93c5fd;
        --link: #38bdf8;
        --code-bg: #1e293b;
        --widget-card: #1e293b;
        }
      .mdp-deck .mdp-slide li::marker { color: #38bdf8;
        }
      .mdp-deck :where(.mdp-slide--title, .mdp-slide--section) { --mdp-slide-bg: #1e3a8a;
        --text: #ffffff;
        --secondary: color-mix(in srgb, #ffffff 80%, transparent);
        --heading: #ffffff;
        }
      """,
  ]

  func testAC_4_2_formerSlideThemesComputeTheSameValues() {
    for (id, recorded) in Self.recordedSlideCSS {
      let css = BuiltInThemes.catalog[id]!.slideCSS
      XCTAssertEqual(declarations(css), declarations(recorded), id)
    }
    let pitch = Theme.forDeck(SlideDeckSettings(markdown: "---\ntheme: pitch\n---\n"), in: BuiltInThemes.catalog)
    XCTAssertEqual(pitch.id, "pitch")
  }

  func testAC_4_2_themeMidnightIsTheReadingMidnight() {
    let theme = Theme.forDeck(SlideDeckSettings(markdown: "---\ntheme: Midnight\n---\n"), in: BuiltInThemes.catalog)
    XCTAssertEqual(theme.name, "Midnight")
    XCTAssertTrue(theme.slideCSS.contains("--mdp-slide-bg: #363846;"))
    XCTAssertTrue(theme.slideCSS.contains("color-scheme: dark;"))
  }

  func testAC_4_3_yamlSlideThemeIsNotReadAndLeftOnDisk() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let yaml = folder.appendingPathComponent("brand.yaml")
    try "name: Brand\ncolors:\n  text: '#123456'".write(to: yaml, atomically: true, encoding: .utf8)
    let catalog = ThemeLibrary.catalog(userDirectory: folder)
    XCTAssertNil(catalog["brand"])
    let settings = SlideDeckSettings(markdown: "---\ntheme: brand\n---\n")
    XCTAssertEqual(Theme.forDeck(settings, in: catalog).id, Theme.readingThemeID)
    XCTAssertTrue(FileManager.default.fileExists(atPath: yaml.path))
  }

  func testAC_4_4_removedSlideThemesFallBackToTheReadingTheme() {
    for id in ["dark", "light"] {
      let settings = SlideDeckSettings(markdown: "---\ntheme: \(id)\n---\n")
      XCTAssertEqual(Theme.forDeck(settings, in: BuiltInThemes.catalog).id, Theme.readingThemeID, id)
    }
  }

  // MARK: - Original on slides

  func testOriginalOnSlidesBringsBackTheDefaultColors() {
    let css = BuiltInThemes.catalog["original"]!.slideCSS
    XCTAssertTrue(css.contains("--text: -apple-system-label;"))
    XCTAssertTrue(css.contains("--link: rgb(0, 104, 218);"))
    XCTAssertTrue(css.contains("--link: rgb(65, 156, 255);"), "and the dark default")
  }

  // MARK: - Deck overrides, header and footer

  func testDeckThemeAndOverrides() {
    let settings = SlideDeckSettings(markdown: """
    ---
    theme: pitch
    theme_overrides:
      colors:
        heading: "#cc0000"
    ---
    """)
    let theme = Theme.forDeck(settings, in: BuiltInThemes.catalog)
    XCTAssertEqual(theme.id, "pitch")
    XCTAssertEqual(theme.light["heading"], "#cc0000")
    XCTAssertEqual(theme.light["slide-title-bg"], "#0057b8")
  }

  func testOverridesOnTheReadingThemePinTheSchemeFromTheBackground() {
    let settings = SlideDeckSettings(markdown: """
    ---
    theme_overrides:
      colors:
        background: "#000000"
        primary: "#000080"
        text: white
    ---
    """)
    let theme = Theme.forDeck(settings, in: BuiltInThemes.catalog)
    XCTAssertEqual(theme.appearance, .dark)
    XCTAssertEqual(theme.light["link"], "#000080", "primary colors links when nothing else does")
    XCTAssertNil(theme.light["text"], "color names are not accepted")
    XCTAssertTrue(theme.slideCSS.contains("color-scheme: dark;"))
  }

  func testThemeFooterAppliesUnlessTheDeckSetsItsOwn() {
    let catalog = Theme.catalog(builtIns: BuiltInThemes.files, user: [Theme.File(id: "brand", css: brandCSS)])
    let themed = MarkdownHTML.render(markdown: "---\nslides: true\ntheme: brand\n---\n\n# Deck",
                                     slideThemes: catalog).articleHTML
    XCTAssertTrue(themed.contains("<span>Deck</span><span></span><span>1/1</span>"), themed)
    let own = MarkdownHTML.render(markdown: "---\nslides: true\ntheme: brand\nfooter: Mine\n---\n\n# Deck",
                                  slideThemes: catalog).articleHTML
    XCTAssertTrue(own.contains("<span>Mine</span>"))
  }

  func testThemeCSSGoesInTheHeadAndKeysThePage() {
    let dark = MarkdownHTML.render(markdown: "---\nslides: true\ntheme: midnight-navy\n---\n\n# A", vendorLoading: .lazy)
    let light = MarkdownHTML.render(markdown: "---\nslides: true\ntheme: pitch\n---\n\n# A", vendorLoading: .lazy)
    let plain = MarkdownHTML.render(markdown: "---\nslides: true\n---\n\n# A", vendorLoading: .lazy)
    XCTAssertTrue(dark.html.contains("<style id=\"mdp-slide-theme\">:where(.mdp-deck) .mdp-slide {"))
    XCTAssertFalse(dark.scriptAssetIDs.isSubset(of: light.scriptAssetIDs))
    XCTAssertFalse(plain.scriptAssetIDs.isSubset(of: dark.scriptAssetIDs),
                   "a deck without a theme must not body-swap into a themed page")
    XCTAssertFalse(MarkdownHTML.render(markdown: "# Not a deck").html.contains("mdp-slide-theme"))
  }

  func testThemeLibraryReadsCSSFilesOnly() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try "/* @theme\nappearance: light\n*/ :root { --text: #123456; }"
      .write(to: folder.appendingPathComponent("Ocean.css"), atomically: true, encoding: .utf8)
    try "ignored".write(to: folder.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
    let catalog = ThemeLibrary.catalog(userDirectory: folder)
    XCTAssertEqual(catalog["ocean"]?.light["text"], "#123456")
    XCTAssertNil(catalog["notes"])
    XCTAssertNotNil(catalog["pitch"])
  }

  @MainActor
  func testThemeColorsReachTheSlideAndInvertStillWins() async throws {
    let rendered = MarkdownHTML.render(markdown: """
    ---
    slides: true
    theme: midnight-navy
    ---

    # Title

    ---

    ## Content

    Text and **bold**

    ???

    Notes in the page's colors

    ---

    <!-- _class: invert -->

    ## Inverted
    """, vendorLoading: .lazy)
    let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1100, height: 900))
    webView.loadHTMLString(rendered.html, baseURL: nil)
    let deadline = Date().addingTimeInterval(10)
    while webView.isLoading && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
    let result = try await webView.evaluateJavaScript("""
    (() => {
      const slides = Array.from(document.querySelectorAll('.mdp-slide'));
      const style = (el) => getComputedStyle(el);
      return [style(slides[0]).backgroundColor,
              style(slides[0].querySelector('h1')).color,
              style(slides[1]).backgroundColor,
              style(slides[1]).color,
              style(slides[1].querySelector('h2')).color,
              style(slides[2]).backgroundColor,
              (() => {
                // The page's own secondary color, outside the deck.
                const probe = document.createElement('div');
                probe.style.color = 'var(--secondary)';
                document.body.appendChild(probe);
                return style(document.querySelector('.mdp-slide-notes')).color === style(probe).color;
              })()].join('|');
    })()
    """) as? String
    XCTAssertEqual(result, [
      "rgb(30, 58, 138)",    // title slide: primary
      "rgb(255, 255, 255)",  // title_text
      "rgb(15, 23, 42)",     // background
      "rgb(226, 232, 240)",  // text
      "rgb(147, 197, 253)",  // heading
      "rgb(29, 29, 31)",     // invert's own background
      "true",                // notes keep the page's text color
    ].joined(separator: "|"))
  }

  @MainActor
  func testClickingASlideInThePaneAsksTheHostToGoThere() async throws {
    let rendered = MarkdownHTML.render(
      markdown: "---\nslides: true\n---\n\n# One\n\n---\n\n## Two [link](https://example.com)\n",
      vendorLoading: .lazy
    )
    let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1100, height: 900))
    webView.loadHTMLString(rendered.html, baseURL: nil)
    let deadline = Date().addingTimeInterval(10)
    while webView.isLoading && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
    let result = try await webView.evaluateJavaScript("""
    (() => {
      const posted = [];
      window.webkit = { messageHandlers: { mdPreviewHost: { postMessage: m => posted.push(m) } } };
      const click = el => el.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
      const frames = document.querySelectorAll('.mdp-slide-frame');
      click(frames[1].querySelector('h2'));
      const readMode = posted.length;
      document.documentElement.setAttribute('data-mdp-slides-pane', '');
      click(frames[1].querySelector('h2'));
      click(frames[0].querySelector('h1'));
      click(frames[1].querySelector('a'));
      return [readMode, posted.map(m => m.kind + ':' + m.index).join(',')].join('|');
    })()
    """) as? String
    XCTAssertEqual(result, "0|slideClicked:1,slideClicked:0", "only the pane reports clicks, and not on links")
  }

  func testFontSizeValuesAreScaledAndClamped() {
    let base = SlideDeck.defaultFontSize
    XCTAssertEqual(SlideDeck.fontSize("100%") ?? 0, base, accuracy: 0.0001)
    XCTAssertEqual(SlideDeck.fontSize("120%") ?? 0, base * 1.2, accuracy: 0.0001)
    // Pixels on the 1280 px canvas: 12.8 px is 1cqw.
    XCTAssertEqual(SlideDeck.fontSize("32") ?? 0, 2.5, accuracy: 0.0001)
    XCTAssertEqual(SlideDeck.fontSize("32px") ?? 0, 2.5, accuracy: 0.0001)
    XCTAssertEqual(SlideDeck.fontSize("5%") ?? 0, base * 0.5, accuracy: 0.0001, "too small is brought up")
    XCTAssertEqual(SlideDeck.fontSize("900%") ?? 0, base * 2, accuracy: 0.0001, "too large is brought down")
    for bad in ["", "big", "-10%", "0", "1e3", "12em", "50% 60%"] {
      XCTAssertNil(SlideDeck.fontSize(bad), bad)
    }
  }

  @MainActor
  func testFontSizeComesFromTheDeckThemeAndSlideInThatOrder() async throws {
    func sizes(frontmatter: String, slide: String = "") async throws -> [Double] {
      let rendered = MarkdownHTML.render(markdown: """
      ---
      slides: true
      \(frontmatter)
      ---

      \(slide)# One

      ---

      ## Two
      """, vendorLoading: .lazy)
      let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 900))
      webView.loadHTMLString(rendered.html, baseURL: nil)
      let deadline = Date().addingTimeInterval(10)
      while webView.isLoading && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
      let result = try await webView.evaluateJavaScript("""
      Array.from(document.querySelectorAll('.mdp-slide')).map(s => parseFloat(getComputedStyle(s).fontSize)).join(',')
      """) as? String
      return (result ?? "").split(separator: ",").compactMap { Double($0) }
    }
    let byDefault = try await sizes(frontmatter: "")
    XCTAssertEqual(byDefault.count, 2)
    let bigger = try await sizes(frontmatter: "font_size: 150%")
    XCTAssertEqual(bigger[0] / byDefault[0], 1.5, accuracy: 0.01)
    let themed = try await sizes(frontmatter: "theme_overrides:\n  fonts:\n    size: 50%")
    XCTAssertEqual(themed[0] / byDefault[0], 0.5, accuracy: 0.01)
    let both = try await sizes(frontmatter: "font_size: 200%\ntheme_overrides:\n  fonts:\n    size: 50%")
    XCTAssertEqual(both[0] / byDefault[0], 2, accuracy: 0.01, "the deck's font_size wins over the theme")
    let perSlide = try await sizes(frontmatter: "font_size: 150%", slide: "<!-- _font_size: 100% -->\n\n")
    XCTAssertEqual(perSlide[0], byDefault[0], accuracy: 0.01, "a slide's own size wins")
    XCTAssertEqual(perSlide[1] / byDefault[1], 1.5, accuracy: 0.01, "other slides keep the deck's")
  }

  /// The Slide Preview lays the deck out at the pane's own width. Headings
  /// must keep their size against the slide at any width.
  @MainActor
  func testSlideTextKeepsItsProportionsAtPaneWidths() async throws {
    let rendered = MarkdownHTML.render(
      markdown: "---\nslides: true\nfont_size: 130%\n---\n\n# A\n\n---\n\n## Today's agenda\n\n1. Goal and what success looks like\n",
      vendorLoading: .lazy, forcesSlides: true)
    var shares: [Double] = []
    for width in [1100.0, 700.0, 345.0] {
      let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: width, height: 800))
      webView.loadHTMLString(rendered.html, baseURL: nil)
      let deadline = Date().addingTimeInterval(10)
      while webView.isLoading && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
      try await Task.sleep(for: .milliseconds(300))
      let share = try await webView.evaluateJavaScript("""
      (() => { document.documentElement.setAttribute('data-mdp-slides-pane', '');
        const slide = document.querySelectorAll('.mdp-slide')[1];
        const range = document.createRange();
        range.selectNodeContents(slide.querySelector('h2'));
        return range.getBoundingClientRect().width / slide.getBoundingClientRect().width })()
      """) as? Double
      shares.append(try XCTUnwrap(share))
    }
    XCTAssertEqual(shares[1], shares[0], accuracy: shares[0] * 0.05)
    XCTAssertEqual(shares[2], shares[0], accuracy: shares[0] * 0.10)
  }

  func testThemeReadsTableColorsAndStyle() {
    var theme = Theme(id: "t", name: "T", appearance: .light)
    theme.applyOverrides(SlideYAML.parse("""
    colors:
      table_header: "#112233"
      table_header_text: "#fff"
      table_border: "#445566"
      table_stripe: "#778899"
    table:
      style: Striped
    """))
    XCTAssertEqual(theme.light["table-style"], "striped")
    let css = theme.slideCSS
    XCTAssertTrue(css.contains("--table-header-bg: #112233;"))
    XCTAssertTrue(css.contains("--table-header-text: #ffffff;"))
    XCTAssertTrue(css.contains("--table-border: #445566;"))
    XCTAssertTrue(css.contains("--table-stripe: #778899;"))
    XCTAssertTrue(css.contains(".mdp-deck .mdp-slide .md-table-scroll > table tbody tr:nth-child(even)"))

    let plain = file("p", ":root { --table-style: lines; }")
    XCTAssertFalse(Theme(file: plain, base: nil)!.slideCSS.contains(".md-table-scroll"),
                   "lines is the stylesheet's own look")
    XCTAssertNil(file("b", ":root { --table-style: \"}</style>\"; }").light["table-style"],
                 "an unknown style is ignored")
    let base = Theme(file: file("base", ":root { --table-style: striped; }"), base: nil)
    let child = Theme(file: file("c", ""), base: base)
    XCTAssertEqual(child?.light["table-style"], "striped", "extends carries the table style")
  }

  @MainActor
  func testTableStylesDrawTablesInSlides() async throws {
    func borders(style: String) async throws -> String {
      let rendered = MarkdownHTML.render(markdown: """
      ---
      slides: true
      theme_overrides:
        colors:
          table_header: "#102030"
          table_border: "#ff0000"
          table_stripe: "#00ff00"
        table:
          style: \(style)
      ---

      | A | B |
      | - | - |
      | 1 | 2 |
      | 3 | 4 |
      """, vendorLoading: .lazy)
      let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1100, height: 900))
      webView.loadHTMLString(rendered.html, baseURL: nil)
      let deadline = Date().addingTimeInterval(10)
      while webView.isLoading && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
      return try await webView.evaluateJavaScript("""
      (() => {
        const css = el => getComputedStyle(el);
        const cell = document.querySelector('.mdp-slide td');
        const rows = document.querySelectorAll('.mdp-slide tbody tr');
        return [css(document.querySelector('.mdp-slide th')).backgroundColor,
                css(cell).borderLeftWidth, css(cell).borderTopWidth, css(cell).borderTopColor,
                css(rows[0]).backgroundColor, css(rows[1]).backgroundColor].join('|');
      })()
      """) as? String ?? ""
    }
    let none = "rgba(0, 0, 0, 0)"
    // header | left | top | top color | row 1 | row 2
    let lines = try await borders(style: "lines")
    XCTAssertEqual(lines, "rgb(16, 32, 48)|0px|1px|rgb(255, 0, 0)|\(none)|\(none)")
    let grid = try await borders(style: "grid")
    XCTAssertEqual(grid, "rgb(16, 32, 48)|1px|1px|rgb(255, 0, 0)|\(none)|\(none)")
    let striped = try await borders(style: "striped")
    XCTAssertEqual(striped, "rgb(16, 32, 48)|0px|1px|rgb(255, 0, 0)|\(none)|rgb(0, 255, 0)")
    let minimal = try await borders(style: "minimal")
    // With no border the color is moot.
    XCTAssertTrue(minimal.hasPrefix("rgb(16, 32, 48)|0px|0px|"), minimal)
    XCTAssertTrue(minimal.hasSuffix("|\(none)|\(none)"), minimal)
  }

  func testPitchTablesHaveABlueHeader() {
    let css = BuiltInThemes.catalog["pitch"]!.slideCSS
    XCTAssertTrue(css.contains("--table-header-bg: #0057b8;"))
    XCTAssertTrue(css.contains("--table-header-text: #ffffff;"))
    XCTAssertTrue(css.contains("--table-border: #c9d6e8;"))
  }

  // MARK: - Any theme as the reading theme (P2: US-1, US-2)

  /// A reader's `brand.css`, resolved against the built-ins.
  private func userTheme(_ css: String, id: String = "brand") throws -> Theme {
    let catalog = Theme.catalog(builtIns: BuiltInThemes.files, user: [Theme.File(id: id, css: css)])
    return try XCTUnwrap(catalog[id])
  }

  func testAC_1_4_darkOnlyThemeRequiresDarkAppearance() throws {
    let dark = try userTheme("/* @theme\nname: Night\nappearance: dark\n*/ :root { --bg: #101010; }")
    XCTAssertEqual(ThemeLibrary.Applied.user(dark).requiredAppearance, .dark)
    XCTAssertEqual(ThemeLibrary.look(for: dark).appearance, .dark)
    let system = try userTheme("/* @theme\nname: Sys\nappearance: system\n*/ :root { --bg: #FAFAFA; }")
    XCTAssertNil(ThemeLibrary.Applied.user(system).requiredAppearance)
    XCTAssertEqual(ThemeLibrary.look(for: system).appearance, .automatic, "Q-29: back to Automatic")
  }

  func testAC_1_5_userThemeUsesTheDefaultSpacing() throws {
    let bold = try userTheme("/* @theme\nname: Heavy\nappearance: light\n*/ :root { --body-weight: 600; }")
    XCTAssertEqual(ThemeLibrary.look(for: bold).layout, ReaderLayoutSetting(boldText: true))
    XCTAssertNil(ThemeLibrary.Applied.user(bold).preset, "No preset: Customize is unavailable")
  }

  func testAC_2_1_sameThemeFeedsPageEditorAndSlideCSS() throws {
    let brand = try userTheme("""
    /* @theme
    name: Brand
    appearance: light
    */
    :root { --link: #0057B8; --text: #1A1A1A; --font-body: Inter, sans-serif; }
    """)
    let colors = ThemeLibrary.look(for: brand).colors
    let page = try XCTUnwrap(colors.markdownThemeOverrides).css
    XCTAssertTrue(page.contains(":root { --link: #0057B8; }"))
    XCTAssertTrue(page.contains("--font-body: Inter, sans-serif;"))
    XCTAssertTrue(colors.editorOverrideCSS.contains(":root { --link: #0057B8; }"))
    XCTAssertTrue(colors.editorOverrideCSS.contains("--font-body: Inter, sans-serif;"))
    let deck = Theme.forDeck(SlideDeckSettings(markdown: "---\nslides: true\ntheme: brand\n---\n"),
                             in: ["brand": brand])
    XCTAssertTrue(deck.slideCSS.contains("#0057B8"))
    XCTAssertTrue(deck.slideCSS.contains("font-family: Inter, sans-serif;"))
  }

  func testAC_2_2_invalidColorFallsBackToBaseValue() throws {
    let brand = try userTheme("""
    /* @theme
    name: Brand
    extends: ember
    */
    :root { --link: red; --text: #111111; }
    """)
    let colors = ThemeColorsSetting(theme: brand)
    let ember = ThemeColorsSetting(theme: try XCTUnwrap(BuiltInThemes.catalog["ember"]))
    XCTAssertEqual(colors.hexValue(.linkColor, .light), ember.hexValue(.linkColor, .light))
    XCTAssertEqual(colors.hexValue(.textColor, .light), "#111111")
  }

  @MainActor
  func testAC_2_3_systemThemeEmitsLightAndDarkBuckets() async throws {
    let brand = try userTheme("""
    /* @theme
    name: Brand
    appearance: system
    */
    :root { --link: #112233; }
    @media (prefers-color-scheme: dark) { :root { --link: #445566; } }
    """)
    let overrides = ThemeLibrary.look(for: brand).colors.markdownThemeOverrides
    for (scheme, expected) in [(MarkdownHTML.ColorScheme.light, "rgb(17, 34, 51)"),
                               (.dark, "rgb(68, 85, 102)")] {
      let rendered = MarkdownHTML.render(markdown: "[link](https://example.com)\n", vendorLoading: .lazy,
                                         colorScheme: scheme, themeOverrides: overrides)
      let color = try await evaluate(rendered.html, "getComputedStyle(document.querySelector('a')).color")
      XCTAssertEqual(color, expected, "\(scheme) link color")
    }
  }

  func testAC_2_4_extendsEmberOverridesOnlyLink() throws {
    let brand = try userTheme("""
    /* @theme
    name: Brand
    extends: ember
    */
    :root { --link: #0057B8; }
    """)
    let emberTheme = try XCTUnwrap(BuiltInThemes.catalog["ember"])
    let colors = ThemeColorsSetting(theme: brand)
    let ember = ThemeColorsSetting(theme: emberTheme)
    XCTAssertEqual(colors.hexValue(.linkColor, .light), "#0057B8")
    for scheme in ThemeColorScheme.allCases {
      for slot in ThemeColorSlot.allCases where slot != .linkColor {
        XCTAssertEqual(colors.hexValue(slot, scheme), ember.hexValue(slot, scheme), "\(scheme) \(slot)")
      }
    }
    XCTAssertEqual(colors.tableStyle, ember.tableStyle)
    XCTAssertEqual(ThemeLibrary.look(for: brand).font, emberTheme.documentFont ?? .system)
  }

  @MainActor
  func testAC_2_5_fontsAndH2InPageCSSSlideOnlyKeysOnlyInSlideCSS() async throws {
    let brand = try userTheme("""
    /* @theme
    name: Brand
    appearance: light
    footer: "Brand | | {slide_number}"
    */
    :root { --font-heading: Futura, sans-serif; --font-code: Courier, monospace; --heading-2: #AA0000;
            --slide-title-bg: #003366; --slide-title-text: #FFFFFF; }
    """)
    let colors = ThemeLibrary.look(for: brand).colors
    let page = try XCTUnwrap(colors.markdownThemeOverrides).css
    XCTAssertTrue(page.contains("--font-heading: Futura, sans-serif;"))
    XCTAssertTrue(page.contains("--font-code: Courier, monospace;"))
    XCTAssertTrue(page.contains("--heading-2: #AA0000;"))
    XCTAssertFalse(page.contains("#003366"), "Title slide colors are slides only")
    XCTAssertFalse(page.contains("Brand |"), "The footer is slides only")
    XCTAssertTrue(colors.editorOverrideCSS.contains("--font-heading: Futura, sans-serif;"))
    let deck = Theme.forDeck(SlideDeckSettings(markdown: "---\nslides: true\ntheme: brand\n---\n"),
                             in: ["brand": brand])
    XCTAssertTrue(deck.slideCSS.contains("#003366"))
    XCTAssertEqual(deck.footer, "Brand | | {slide_number}")

    let rendered = MarkdownHTML.render(markdown: "## Two\n\n`code`\n", vendorLoading: .lazy,
                                       colorScheme: .light, themeOverrides: colors.markdownThemeOverrides)
    let result = try await evaluate(rendered.html, """
    (() => { const h = document.querySelector('h2'), c = document.querySelector('code');
      return getComputedStyle(h).fontFamily + '|' + getComputedStyle(h).color + '|' + getComputedStyle(c).fontFamily })()
    """)
    XCTAssertEqual(result, "Futura, sans-serif|rgb(170, 0, 0)|Courier, monospace")
  }

  func testThemeFontsAreOutsideTheScreenOnlyBlockSoTheyPrint() throws {
    let css = MarkdownHTML.ThemeOverrides(lightLink: "#112233", bodyFont: "Inter, sans-serif").css
    let screen = try XCTUnwrap(css.components(separatedBy: "\n}\n").first)
    XCTAssertTrue(screen.hasPrefix("@media screen {"))
    XCTAssertFalse(screen.contains("--font-body"))
    XCTAssertTrue(css.contains(":root { --font-body: Inter, sans-serif; }"))
  }

  func testAnEmptySettingEmitsNoOverrides() {
    XCTAssertNil(ThemeColorsSetting().markdownThemeOverrides)
  }

  func testAListedFaceGoesThroughTheDocumentFontNotThemeFont() throws {
    let paper = try XCTUnwrap(ThemePreset.builtIn.first { $0.name == "Paper" })
    XCTAssertEqual(paper.font, .charter)
    XCTAssertNil(paper.setting.bodyFont)
  }

  func testEveryPageColorTokenFillsASlot() {
    let slideOnly: Set = ["slide-title-bg", "slide-title-text"]
    for (token, kind) in Theme.tokenKinds where kind == .color && !slideOnly.contains(token) {
      XCTAssertNotNil(ThemeColorsSetting.themeTokenSlots[token], token)
    }
  }

  @MainActor
  func testASolidCardOnADeckUsesTheDeckThemesColorAndKeepsBoldReadable() async throws {
    let css = """
    /* @theme
    name: Brand
    appearance: light
    */
    :root { --bold: #2f5fcc; --widget-accent: #3a6fd8; }
    """
    let catalog = Theme.catalog(builtIns: BuiltInThemes.files, user: [Theme.File(id: "brand", css: css)])
    let rendered = MarkdownHTML.render(markdown: """
    ---
    slides: true
    theme: brand
    ---

    ## Numbers

    <!-- card style=solid color=accent -->
    **Bold on blue**
    <!-- end-card -->
    """, vendorLoading: .lazy, colorScheme: .light, slideThemes: catalog)
    let result = try await evaluate(rendered.html, """
    (() => { const card = document.querySelector('.mdp-slide .md-card');
      return getComputedStyle(card).backgroundColor + '|' + getComputedStyle(card.querySelector('strong')).color })()
    """)
    XCTAssertEqual(result, "rgb(58, 111, 216)|rgb(255, 255, 255)", "The theme's accent fill, white bold text")
  }
}

