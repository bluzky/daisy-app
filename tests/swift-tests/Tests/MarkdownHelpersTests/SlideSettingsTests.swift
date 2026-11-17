import Foundation
import Markdown
import WebKit
import XCTest

@testable import MarkdownHelpers

/// Phase 3: frontmatter settings, header and footer, page numbers,
/// captions and slide chrome.
final class SlideSettingsTests: XCTestCase {
  private func slidesHTML(_ markdown: String) -> String {
    MarkdownHTML.render(markdown: markdown, forcesSlides: true).articleHTML
  }

  // MARK: - YAML

  func testYAMLReadsNestedMappingsQuotesAndComments() {
    let values = SlideYAML.parse("""
    name: My Brand   # shown in lists
    colors:
      background: "#FFFFFF"
      heading: '#0057B8'
      nested:
        deep: yes
    fonts:
      body: Inter, sans-serif
    # a comment line
    footer:
      text: "{title} | {slide_number}/{total}"
    """)
    XCTAssertEqual(values["name"]?.string, "My Brand")
    XCTAssertEqual(values["colors"]?["background"]?.string, "#FFFFFF")
    XCTAssertEqual(values["colors"]?["heading"]?.string, "#0057B8")
    XCTAssertEqual(values["colors"]?["nested"]?["deep"]?.string, "yes")
    XCTAssertEqual(values["fonts"]?["body"]?.string, "Inter, sans-serif")
    XCTAssertEqual(values["footer"]?["text"]?.string, "{title} | {slide_number}/{total}")
  }

  // MARK: - Settings

  func testFrontmatterSettings() {
    let settings = SlideDeckSettings(markdown: """
    ---
    slides: true
    aspect: 4:3
    paginate: true
    header: Daisy
    footer: "{title} | {date} | {slide_number}/{total}"
    title: Review
    author: Linh
    date: 2026-11-04
    theme: Dark
    theme_overrides:
      colors:
        heading: "#C00"
    ---
    # A
    """)
    XCTAssertEqual(settings.aspect, .standard)
    XCTAssertTrue(settings.paginate)
    XCTAssertEqual(settings.header, "Daisy")
    XCTAssertEqual(settings.footer, "{title} | {date} | {slide_number}/{total}")
    XCTAssertEqual(settings.title, "Review")
    XCTAssertEqual(settings.author, "Linh")
    XCTAssertEqual(settings.date, "2026-11-04")
    XCTAssertEqual(settings.theme, "dark")
    XCTAssertEqual(settings.themeOverrides["colors"]?["heading"]?.string, "#C00")
  }

  func testUnknownAspectFallsBackToWide() {
    XCTAssertEqual(SlideDeckSettings(markdown: "---\naspect: 21:9\n---\n").aspect, .wide)
    XCTAssertEqual(SlideDeckSettings.Aspect.standard.canvasHeight, 960)
    XCTAssertEqual(SlideDeckSettings.Aspect.wideTall.canvasHeight, 800)
  }

  func testTemplatePartsFillVariablesAndSplitAtBars() {
    let parts = { (template: String) in
      SlideDeckSettings.templateParts(template, title: "Deck", author: "Linh", date: "Today",
                                      slideNumber: 3, total: 9)
    }
    XCTAssertEqual(parts("{title} | {date} | {slide_number}/{total}"), ["Deck", "Today", "3/9"])
    XCTAssertEqual(parts("{author}"), ["Linh", "", ""])
    XCTAssertEqual(parts("left | right"), ["left", "", "right"])
    XCTAssertEqual(parts("a | b | c | d"), ["a", "b", "c | d"])
  }

  // MARK: - Header, footer, page numbers

  func testHeaderFooterAndPageNumbersOnEverySlide() {
    let html = slidesHTML("""
    ---
    slides: true
    paginate: true
    footer: "{title} | | {slide_number}/{total}"
    ---

    # Quarterly <review>

    ---

    ## Two
    """)
    XCTAssertTrue(html.contains(
      "<div class=\"mdp-slide-footer\" aria-hidden=\"true\"><span>Quarterly &lt;review&gt;</span><span></span><span>1/2</span></div>"),
      html)
    XCTAssertTrue(html.contains("<span>2/2</span>"))
    XCTAssertTrue(html.contains("<div class=\"mdp-slide-number\" aria-hidden=\"true\">2</div>"))
    XCTAssertFalse(html.contains("mdp-slide-header"))
  }

  func testSpotDirectivesHideOrReplaceChromeOnOneSlide() {
    let html = slidesHTML("""
    ---
    slides: true
    paginate: true
    header: Daisy
    ---

    <!--
    _paginate: false
    _header: ""
    -->

    # Title

    ---

    <!-- _header: Appendix -->

    ## Two
    """)
    let slides: [String] = Array(html.components(separatedBy: "class=\"mdp-slide-frame\"").dropFirst())
    XCTAssertFalse(slides[0].contains("mdp-slide-header"))
    XCTAssertFalse(slides[0].contains("mdp-slide-number"))
    XCTAssertTrue(slides[1].contains("<span>Appendix</span>"))
    XCTAssertTrue(slides[1].contains("mdp-slide-number"))
  }

  func testDeckCarriesItsAspect() {
    XCTAssertTrue(slidesHTML("---\nslides: true\naspect: 16:10\n---\n\n# A").contains("data-aspect=\"16:10\""))
  }

  // MARK: - Captions

  func testCaptionRendersUnderTheBlockAndDoesNotChangeTheLayout() {
    let markdown = "## Chart\n\n![chart](c.png)\n\n!caption[Figure 1: <sales>]"
    let slide = SlideDeck(document: Document(parsing: markdown)).slides[0]
    XCTAssertEqual(slide.layout, .titleImage)
    let html = slidesHTML(markdown)
    XCTAssertTrue(html.contains(">Figure 1: &lt;sales&gt;</p>"), html)
    XCTAssertTrue(html.contains("<p class=\"mdp-slide-caption\""))
    XCTAssertFalse(html.contains("!caption"))
  }

  func testCaptionOutsideADeckIsText() {
    XCTAssertTrue(MarkdownHTML.render(markdown: "!caption[x]").articleHTML.contains("!caption[x]"))
  }

  // MARK: - Lines to slides

  func testSourceLinesMapToSlides() {
    let markdown = """
    ---
    slides: true
    ---

    # One

    ---

    ## Two
    text

    ---

    ## Three
    """
    // Lines 1-3 are frontmatter, 5 is "# One", 7 the first ---, 9 "## Two", 12 the second ---.
    XCTAssertEqual(MarkdownHTML.slideStartLines(markdown: markdown), [1, 7, 12])
    XCTAssertEqual(MarkdownHTML.slideIndex(atSourceLine: 2, markdown: markdown), 0)
    XCTAssertEqual(MarkdownHTML.slideIndex(atSourceLine: 5, markdown: markdown), 0)
    XCTAssertEqual(MarkdownHTML.slideIndex(atSourceLine: 7, markdown: markdown), 1, "a break opens the next slide")
    XCTAssertEqual(MarkdownHTML.slideIndex(atSourceLine: 10, markdown: markdown), 1)
    XCTAssertEqual(MarkdownHTML.slideIndex(atSourceLine: 14, markdown: markdown), 2)
    XCTAssertEqual(MarkdownHTML.slideIndex(atSourceLine: 99, markdown: markdown), 2)
  }

  func testSlideContentLinesPointAtEachSlidesFirstContent() {
    let markdown = "---\nslides: true\n---\n\n# One\n\n---\n\n## Two\ntext\n\n---\n"
    // "# One" is line 5, "## Two" line 9; the closing `---` adds no slide.
    XCTAssertEqual(MarkdownHTML.slideContentLines(markdown: markdown), [5, 9])
    XCTAssertEqual(MarkdownHTML.slideContentLines(markdown: "# Solo\n\n---\n\n## Two"), [1, 5])
    XCTAssertEqual(MarkdownHTML.slideContentLines(markdown: ""), [1])
  }

  func testMathAndFootnotesKeepLinesAligned() {
    let markdown = "# One[^a]\n\n$$\nx\n$$\n\n[^a]: Note\n\n---\n\n## Two"
    XCTAssertEqual(MarkdownHTML.slideStartLines(markdown: markdown), [1, 9])
    XCTAssertEqual(MarkdownHTML.slideIndex(atSourceLine: 4, markdown: markdown), 0)
    XCTAssertEqual(MarkdownHTML.slideIndex(atSourceLine: 11, markdown: markdown), 1)
  }

  // MARK: - Page

  @MainActor
  private func loadedWebView(_ markdown: String, width: CGFloat = 1100, height: CGFloat = 900)
    async throws -> WKWebView {
    let rendered = MarkdownHTML.render(markdown: markdown, vendorLoading: .lazy, forcesSlides: true)
    let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: width, height: height))
    webView.loadHTMLString(rendered.html, baseURL: nil)
    let deadline = Date().addingTimeInterval(10)
    while webView.isLoading && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
    return webView
  }

  @MainActor
  func testSlidePreviewPaneIsAZoomedStripWithoutNotes() async throws {
    let rendered = MarkdownHTML.render(markdown: "# One\n\n???\n\nnotes\n\n---\n\n## Two",
                                       vendorLoading: .lazy, forcesSlides: true)
    let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 460, height: 700))
    webView.pageZoom = 460.0 / 1100.0
    webView.loadHTMLString(rendered.html, baseURL: nil)
    let deadline = Date().addingTimeInterval(10)
    while webView.isLoading && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
    let result = try await webView.evaluateJavaScript("""
    (() => {
      document.documentElement.setAttribute('data-mdp-slides-pane', '');
      document.querySelectorAll('.mdp-slide-frame')[1].setAttribute('data-mdp-pane-current', '');
      const slides = document.querySelectorAll('.mdp-slide');
      return [Math.round(slides[0].getBoundingClientRect().width),
              document.querySelector('.mdp-slide-notes').offsetParent === null,
              getComputedStyle(slides[1]).outlineStyle,
              getComputedStyle(slides[0]).outlineStyle].join('|');
    })()
    """) as? String
    // 1100 CSS px less the 24 px margins, laid out before the zoom.
    XCTAssertEqual(result, "1052|true|solid|none")
  }

  @MainActor
  func testAspectSetsTheSlideShape() async throws {
    for (aspect, ratio) in [("16:9", 16.0 / 9), ("16:10", 1.6), ("4:3", 4.0 / 3)] {
      let webView = try await loadedWebView("---\nslides: true\naspect: \(aspect)\n---\n\n# A")
      let measured = try await webView.evaluateJavaScript("""
      (() => { const r = document.querySelector('.mdp-slide').getBoundingClientRect(); return r.width / r.height; })()
      """) as? Double
      XCTAssertEqual(try XCTUnwrap(measured), ratio, accuracy: 0.01, aspect)
    }
  }

  @MainActor
  func testFooterSitsInTheBottomPaddingBelowTheContent() async throws {
    let webView = try await loadedWebView("""
    ---
    slides: true
    paginate: true
    footer: "Left | Middle | Right"
    ---

    ## Slide

    - Point
    """)
    let result = try await webView.evaluateJavaScript("""
    (() => {
      const slide = document.querySelector('.mdp-slide').getBoundingClientRect();
      const body = document.querySelector('.mdp-slide-body').getBoundingClientRect();
      const footer = document.querySelector('.mdp-slide-footer').getBoundingClientRect();
      const number = document.querySelector('.mdp-slide-number').getBoundingClientRect();
      const spans = Array.from(document.querySelectorAll('.mdp-slide-footer span')).map(s => s.getBoundingClientRect());
      return [footer.top >= body.bottom - 1, footer.bottom <= slide.bottom,
              spans[0].left < spans[1].left && spans[1].left < spans[2].left,
              number.left >= footer.right - 1].join('|');
    })()
    """) as? String
    XCTAssertEqual(result, "true|true|true|true")
  }
}
