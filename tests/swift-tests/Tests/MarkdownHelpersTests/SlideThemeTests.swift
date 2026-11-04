import Foundation
import WebKit
import XCTest

@testable import MarkdownHelpers

final class SlideThemeTests: XCTestCase {
  private let brand = """
  name: My Brand
  id: my-brand
  extends: light
  colors:
    heading: "#0057B8"
    bold: "#B8003F"
  fonts:
    body: "Inter, sans-serif"
  footer:
    show: true
    text: "{title} | {slide_number}/{total}"
  """

  func testBuiltInsIncludeDefaultAndResolveByName() {
    let ids = SlideTheme.builtIns.map(\.id)
    XCTAssertEqual(ids, ["default", "light", "dark", "paper", "midnight", "pitch"])
    XCTAssertEqual(SlideTheme.builtInCatalog["default"]?.css, "")
    XCTAssertTrue(SlideTheme.builtInCatalog["dark"]!.css.contains("--mdp-slide-bg: #1c1c1e;"))
  }

  func testThemeFileExtendsABuiltIn() throws {
    let theme = try XCTUnwrap(SlideTheme.catalog(files: ["brand": brand])["my-brand"])
    XCTAssertEqual(theme.name, "My Brand")
    XCTAssertEqual(theme.colors["background"], "#ffffff", "from light")
    XCTAssertEqual(theme.colors["heading"], "#0057b8")
    XCTAssertEqual(theme.fonts["body"], "Inter, sans-serif")
    XCTAssertEqual(theme.footer, "{title} | {slide_number}/{total}")
  }

  func testFileNameIsTheIdWithoutAnIdKeyAndFilesExtendEachOther() {
    let catalog = SlideTheme.catalog(files: [
      "base": "colors:\n  text: '#111111'",
      "child": "extends: base\ncolors:\n  heading: red",
    ])
    XCTAssertEqual(catalog["child"]?.colors["text"], "#111111")
    XCTAssertEqual(catalog["child"]?.colors["heading"], "red")
  }

  func testAFileReplacesABuiltInAndCyclesDoNotHang() {
    let catalog = SlideTheme.catalog(files: [
      "dark": "colors:\n  background: '#000000'",
      "a": "extends: b",
      "b": "extends: a",
    ])
    XCTAssertEqual(catalog["dark"]?.colors["background"], "#000000")
    XCTAssertNotNil(catalog["a"])
    XCTAssertNotNil(catalog["b"])
  }

  func testCodeColorsFollowTheSlidesNotTheWindow() {
    XCTAssertEqual(SlideTheme.builtInCatalog["dark"]?.isDark, true)
    XCTAssertEqual(SlideTheme.builtInCatalog["paper"]?.isDark, false)
    XCTAssertNil(SlideTheme.builtInCatalog["default"]?.isDark, "the default follows the window")
    let dark = SlideTheme.builtInCatalog["dark"]!.css
    XCTAssertTrue(dark.contains("color-scheme: dark;"))
    XCTAssertTrue(dark.contains("--hl-keyword: #fc5fa3;"))
    XCTAssertTrue(SlideTheme.builtInCatalog["light"]!.css.contains("--hl-keyword: #9b2393;"))
    let named = SlideTheme(id: "x", values: SlideYAML.parse("appearance: dark\ncolors:\n  background: navy"))
    XCTAssertEqual(named.isDark, true)
    XCTAssertEqual(SlideTheme.luminance(ofHex: "#fff") ?? 0, 1, accuracy: 0.001)
    XCTAssertEqual(SlideTheme.luminance(ofHex: "#000000") ?? 1, 0, accuracy: 0.001)
  }

  func testInvalidColorsAndFontsAreDropped() {
    let theme = SlideTheme(id: "x", values: SlideYAML.parse("""
    colors:
      text: "red; } body { display: none"
      heading: "#12"
    fonts:
      body: "Inter; } * { color: red"
      code: "Menlo, monospace"
    """))
    XCTAssertNil(theme.colors["text"])
    XCTAssertNil(theme.colors["heading"])
    XCTAssertNil(theme.fonts["body"])
    XCTAssertEqual(theme.fonts["code"], "Menlo, monospace")
    XCTAssertFalse(theme.css.contains("display: none"))
  }

  func testDeckThemeAndOverrides() {
    let settings = SlideDeckSettings(markdown: """
    ---
    theme: pitch
    theme_overrides:
      colors:
        heading: "#cc0000"
    ---
    """)
    let theme = SlideTheme.resolved(for: settings, in: SlideTheme.builtInCatalog)
    XCTAssertEqual(theme.id, "pitch")
    XCTAssertEqual(theme.colors["heading"], "#cc0000")
    XCTAssertEqual(theme.colors["primary"], "#0057b8")
    let unknown = SlideTheme.resolved(for: SlideDeckSettings(markdown: "---\ntheme: nope\n---\n"),
                                      in: SlideTheme.builtInCatalog)
    XCTAssertEqual(unknown.id, "default")
  }

  func testThemeFooterAppliesUnlessTheDeckSetsItsOwn() {
    let catalog = SlideTheme.catalog(files: ["brand": brand])
    let themed = MarkdownHTML.render(markdown: "---\nslides: true\ntheme: my-brand\n---\n\n# Deck",
                                     slideThemes: catalog).articleHTML
    XCTAssertTrue(themed.contains("<span>Deck</span><span></span><span>1/1</span>"), themed)
    let own = MarkdownHTML.render(markdown: "---\nslides: true\ntheme: my-brand\nfooter: Mine\n---\n\n# Deck",
                                  slideThemes: catalog).articleHTML
    XCTAssertTrue(own.contains("<span>Mine</span>"))
  }

  func testThemeCSSGoesInTheHeadAndKeysThePage() {
    let dark = MarkdownHTML.render(markdown: "---\nslides: true\ntheme: dark\n---\n\n# A", vendorLoading: .lazy)
    let light = MarkdownHTML.render(markdown: "---\nslides: true\ntheme: light\n---\n\n# A", vendorLoading: .lazy)
    let plain = MarkdownHTML.render(markdown: "---\nslides: true\n---\n\n# A", vendorLoading: .lazy)
    XCTAssertTrue(dark.html.contains("<style id=\"mdp-slide-theme\">:where(.mdp-deck) .mdp-slide {"))
    XCTAssertFalse(dark.scriptAssetIDs.isSubset(of: light.scriptAssetIDs))
    XCTAssertFalse(plain.scriptAssetIDs.isSubset(of: dark.scriptAssetIDs),
                   "a deck without a theme must not body-swap into a themed page")
    XCTAssertFalse(MarkdownHTML.render(markdown: "# Not a deck").html.contains("mdp-slide-theme"))
  }

  func testThemeStoreReadsYAMLFilesOnly() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try "colors:\n  text: '#123456'".write(to: folder.appendingPathComponent("Ocean.yaml"), atomically: true, encoding: .utf8)
    try "name: Forest".write(to: folder.appendingPathComponent("forest.yml"), atomically: true, encoding: .utf8)
    try "ignored".write(to: folder.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
    let catalog = SlideThemeStore.catalog(userDirectory: folder)
    XCTAssertEqual(catalog["ocean"]?.colors["text"], "#123456")
    XCTAssertEqual(catalog["forest"]?.name, "Forest")
    XCTAssertNil(catalog["notes"])
    XCTAssertNotNil(catalog["dark"])
  }

  @MainActor
  func testThemeColorsReachTheSlideAndInvertStillWins() async throws {
    let rendered = MarkdownHTML.render(markdown: """
    ---
    slides: true
    theme: midnight
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
}
