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
    let theme = SlideTheme(id: "t", values: SlideYAML.parse("""
    colors:
      table_header: "#112233"
      table_header_text: white
      table_border: "#445566"
      table_stripe: "#778899"
    table:
      style: Striped
    """))
    XCTAssertEqual(theme.tableStyle, .striped)
    let css = theme.css
    XCTAssertTrue(css.contains("--table-header-bg: #112233;"))
    XCTAssertTrue(css.contains("--table-header-text: white;"))
    XCTAssertTrue(css.contains("--table-border: #445566;"))
    XCTAssertTrue(css.contains("--table-stripe: #778899;"))
    XCTAssertTrue(css.contains(".mdp-deck .mdp-slide .md-table-scroll > table tbody tr:nth-child(even)"))

    let plain = SlideTheme(id: "p", values: SlideYAML.parse("table:\n  style: lines"))
    XCTAssertFalse(plain.css.contains(".md-table-scroll"), "lines is the stylesheet's own look")
    let bad = SlideTheme(id: "b", values: SlideYAML.parse("table:\n  style: \"}</style>\""))
    XCTAssertNil(bad.tableStyle, "an unknown style is ignored")
    let child = SlideTheme(id: "c", values: SlideYAML.parse("name: C"), base: theme)
    XCTAssertEqual(child.tableStyle, .striped, "extends carries the table style")
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
    let css = SlideTheme.builtInCatalog["pitch"]!.css
    XCTAssertTrue(css.contains("--table-header-bg: #0057b8;"))
    XCTAssertTrue(css.contains("--table-header-text: #ffffff;"))
    XCTAssertTrue(css.contains("--table-border: #c9d6e8;"))
  }
}
