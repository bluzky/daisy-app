import Foundation
import Markdown
import WebKit
import XCTest

@testable import MarkdownHelpers

/// Phase 2: backgrounds, image sizes, `layout`, `_class`, `color` and `step`.
final class SlideDirectiveTests: XCTestCase {
  private func slide(_ markdown: String) -> SlideDeck.Slide {
    SlideDeck(document: Document(parsing: markdown)).slides[0]
  }

  private func slidesHTML(_ markdown: String) -> String {
    MarkdownHTML.render(markdown: markdown, forcesSlides: true).articleHTML
  }

  // MARK: - Backgrounds

  func testBackgroundKeywordsLiveInTheAltText() {
    XCTAssertEqual(slide("![bg](a.jpg)").background, .init(source: "a.jpg"))
    XCTAssertEqual(slide("![bg left](a.jpg)").background, .init(source: "a.jpg", position: .left))
    XCTAssertEqual(slide("![bg right fit](a.jpg)").background,
                   .init(source: "a.jpg", position: .right, fits: true))
    XCTAssertEqual(slide("![bg contain](a.jpg)").background?.fits, true)
    XCTAssertEqual(slide("![BG Left](a.jpg)").background?.position, .left)
  }

  func testOnlyAnImageAloneInItsParagraphIsABackground() {
    XCTAssertNil(slide("See ![bg](a.jpg) here").background)
    XCTAssertNil(slide("- ![bg](a.jpg)").background)
    XCTAssertNil(slide("![background](a.jpg)").background)
    XCTAssertNil(slide("![photo](a.jpg)").background)
  }

  func testTheTitleIsNeverABackgroundKeyword() {
    let background = slide("![bg](a.jpg \"contain\")").background
    XCTAssertEqual(background?.fits, false)
  }

  func testFirstBackgroundWinsAndBackgroundsLeaveTheBlocks() {
    let first = slide("# Title\n\n![bg](a.jpg)\n\n![bg](b.jpg)")
    XCTAssertEqual(first.background?.source, "a.jpg")
    XCTAssertEqual(first.blocks.count, 1)
  }

  func testBackgroundLayouts() {
    let cases: [(String, SlideDeck.Layout)] = [
      ("![bg](a.jpg)", .fullBleed),
      ("![bg](a.jpg)\n\n![bg](b.jpg)", .fullBleed),
      ("# Title\n\n![bg](a.jpg)", .title),
      ("![bg left](a.jpg)", .split),
      ("# Title\n\n![bg right](a.jpg)", .split),
      ("## Heading\n\n- a\n- b\n\n![bg left](a.jpg)", .split),
    ]
    for (markdown, expected) in cases {
      XCTAssertEqual(slide(markdown).layout, expected, markdown)
    }
  }

  func testBackgroundRendersAsAnImageBehindTheBody() {
    let html = slidesHTML("## Side\n\n![bg left fit](photo.jpg)")
    XCTAssertTrue(html.contains("mdp-slide--split"))
    XCTAssertTrue(html.contains("mdp-slide--bg-left"))
    XCTAssertTrue(html.contains(
      "<div class=\"mdp-slide-bg mdp-slide-bg--left mdp-slide-bg--fit\"><img src=\"photo.jpg\" alt=\"\" /></div>"))
    XCTAssertFalse(html.contains("alt=\"bg"))
  }

  // MARK: - Image sizes

  func testImageSizeComesFromTheTitle() {
    XCTAssertEqual(SlideDeck.imageSize("50%"), "50%")
    XCTAssertEqual(SlideDeck.imageSize(" 320px "), "320px")
    XCTAssertEqual(SlideDeck.imageSize("2.5rem"), "2.5rem")
    XCTAssertEqual(SlideDeck.imageSize("12em"), "12em")
    XCTAssertEqual(SlideDeck.imageSize("40cqi"), "40cqi")
    XCTAssertNil(SlideDeck.imageSize("A chart"))
    XCTAssertNil(SlideDeck.imageSize("0%"))
    XCTAssertNil(SlideDeck.imageSize("50"))
    XCTAssertNil(SlideDeck.imageSize("50%;color:red"))
  }

  func testSlideImageSizeIsADataAttributeNotATitle() {
    XCTAssertTrue(slidesHTML("![chart](c.png \"50%\")").contains("data-mdp-size=\"50%\""))
    XCTAssertTrue(slidesHTML("![chart](c.png \"A chart\")").contains("title=\"A chart\""))
    let document = MarkdownHTML.render(markdown: "![chart](c.png \"50%\")").articleHTML
    XCTAssertTrue(document.contains("title=\"50%\""), "ordinary documents keep the title")
  }

  // MARK: - Directives

  func testLayoutDirectiveOverridesInference() {
    XCTAssertEqual(slide("<!-- layout: title -->\n\n## Heading\n\n- a").layout, .title)
    XCTAssertEqual(slide("## Heading\n\n- a\n\n<!-- layout: section -->").layout, .section)
    XCTAssertEqual(slide("<!-- layout: nonsense -->\n\n## Heading").layout, .section)
  }

  func testClassAndColorDirectives() {
    let styled = slide("<!-- _class: invert center -->\n<!-- color: #FFF -->\n\n## Heading")
    XCTAssertEqual(styled.classes, ["invert", "center"])
    XCTAssertEqual(styled.color, "#fff")
    XCTAssertEqual(slide("<!-- _color: white -->\n\n## A").color, "white")
    XCTAssertEqual(slide("<!-- _class: ok bad\"name x<y -->").classes, ["ok"])
    XCTAssertNil(slide("<!-- color: red; background: url(x) -->").color)
    XCTAssertNil(slide("<!-- color: #12 -->").color)
  }

  func testSeveralDirectivesInOneComment() {
    let styled = slide("<!-- layout: title --> <!-- _class: lead -->\n\n## A")
    XCTAssertEqual(styled.layout, .title)
    XCTAssertEqual(styled.classes, ["lead"])
  }

  func testDirectivesAreReadInSwiftAndRenderedAsClasses() {
    let html = slidesHTML("<!-- _class: invert -->\n<!-- _color: white -->\n\n## A")
    XCTAssertTrue(html.contains("class=\"mdp-slide mdp-slide--section mdp-slide-class-invert\""))
    XCTAssertTrue(html.contains("data-slide-color=\"white\""))
    XCTAssertFalse(html.contains("<!--"), "directive comments are not emitted")
  }

  func testDirectivesApplyOnlyToTheirSlide() {
    let slides = SlideDeck(document: Document(parsing: "<!-- _class: invert -->\n\n# A\n\n---\n\n## B")).slides
    XCTAssertEqual(slides[0].classes, ["invert"])
    XCTAssertEqual(slides[1].classes, [])
  }

  // MARK: - Steps

  func testInlineStepsTargetListItemsAndParagraphs() {
    let markdown = """
    ## Points

    - one
    - two <!-- step -->
    - three <!-- step -->

    Closing line. <!-- step -->
    """
    let deck = slide(markdown)
    XCTAssertEqual(deck.stepCount, 3)
    let html = slidesHTML(markdown)
    XCTAssertTrue(html.contains("<li data-source-line=\"4\" data-source-start=\"4\" data-source-end=\"4\" data-step=\"1\">"), html)
    XCTAssertTrue(html.contains("data-source-line=\"5\" data-source-start=\"5\" data-source-end=\"5\" data-step=\"2\">"))
    XCTAssertTrue(html.contains("<p data-source-line=\"7\" data-source-start=\"7\" data-source-end=\"7\" data-step=\"3\">"))
    XCTAssertTrue(html.contains("data-steps=\"3\""))
    XCTAssertFalse(html.contains("<li data-source-line=\"3\" data-source-start=\"3\" data-source-end=\"3\" data-step"))
  }

  func testOwnLineStepRevealsTheNextBlock() {
    let markdown = "## Code\n\n<!-- step -->\n```swift\nlet a = 1\n```"
    XCTAssertEqual(slide(markdown).blockSteps, [1: 1])
    let html = slidesHTML(markdown)
    XCTAssertTrue(html.contains("<div class=\"mdp-step\" data-step=\"1\"><pre data-source-line=\"4\""), html)
  }

  func testNumberedStepsGroupElements() {
    let deck = slide("- a <!-- step: 2 -->\n- b <!-- step: 2 -->\n- c <!-- step -->")
    XCTAssertEqual(Set(deck.elementSteps.values), [2, 3])
    XCTAssertEqual(deck.stepCount, 3)
  }

  func testStepCountsPerSlide() {
    let markdown = "- a <!-- step -->\n- b <!-- step -->\n\n---\n\n## None\n\n---\n\n<!-- step -->\nText"
    XCTAssertEqual(MarkdownHTML.slideStepCounts(markdown: markdown), [2, 0, 1])
  }

  func testStepOnlyCountsAtTheEndOfTheText() {
    XCTAssertTrue(slide("Visible <!-- step --> still visible").elementSteps.isEmpty)
    XCTAssertTrue(slide("- *a <!-- step -->* b").elementSteps.isEmpty)
    XCTAssertEqual(slide("Last word <!-- step -->  ").stepCount, 1)
    XCTAssertEqual(slide("Two lines\nend <!-- step -->").stepCount, 1)
    XCTAssertFalse(slidesHTML("Visible <!-- step --> still visible").contains("data-step=\""))
  }

  func testStepCommentsDoNotChangeTheLayout() {
    XCTAssertEqual(slide("## Image\n\n![a](a.png) <!-- step -->").layout, .titleImage)
  }

  // MARK: - Page

  @MainActor
  private func loadedWebView(_ markdown: String, width: CGFloat = 1000, height: CGFloat = 600)
    async throws -> WKWebView {
    let rendered = MarkdownHTML.render(markdown: markdown, vendorLoading: .lazy, forcesSlides: true)
    let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: width, height: height))
    webView.loadHTMLString(rendered.html, baseURL: nil)
    let deadline = Date().addingTimeInterval(10)
    while webView.isLoading && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
    return webView
  }

  @MainActor
  func testPresentingRevealsStepsInOrderAndReadModeShowsAll() async throws {
    let webView = try await loadedWebView("- a\n- b <!-- step -->\n- c <!-- step -->")
    let visible = """
    Array.from(document.querySelectorAll('li'))
      .filter(li => getComputedStyle(li).visibility === 'visible')
      .map(li => li.textContent.trim()).join('')
    """
    let readMode = try await webView.evaluateJavaScript(visible) as? String
    XCTAssertEqual(readMode, "abc")
    var shown: [String] = []
    for step in 0...2 {
      let result = try await webView.evaluateJavaScript("""
      document.documentElement.setAttribute('data-mdp-slides-presenting', '');
      MdPreviewSlides.show(0, \(step));
      \(visible)
      """) as? String
      shown.append(result ?? "")
    }
    XCTAssertEqual(shown, ["a", "ab", "abc"])
  }

  @MainActor
  func testScriptAppliesImageSizesAndSlideColors() async throws {
    let webView = try await loadedWebView("""
    <!-- color: #ff0000 -->

    ## Red

    ![box](data:image/gif;base64,R0lGODlhAQABAAAAACw= "25%")
    """)
    let result = try await webView.evaluateJavaScript("""
    (() => {
      const slide = document.querySelector('.mdp-slide');
      const img = document.querySelector('.mdp-slide-body img');
      return [getComputedStyle(slide.querySelector('h2')).color,
              Math.round(img.getBoundingClientRect().width / slide.querySelector('.mdp-slide-body').getBoundingClientRect().width * 100)].join('|');
    })()
    """) as? String
    XCTAssertEqual(result, "rgb(255, 0, 0)|25")
  }

  @MainActor
  func testGridLaysImagesOutAsOneGalleryHoweverTheyAreWritten() async throws {
    let gif = "data:image/gif;base64,R0lGODlhAQABAAAAACw="
    for markdown in [
      "## Gallery\n\n![a](\(gif))\n\n![b](\(gif))\n\n![c](\(gif))",
      "## Gallery\n\n![a](\(gif)) ![b](\(gif)) ![c](\(gif))",
    ] {
      let webView = try await loadedWebView(markdown)
      let result = try await webView.evaluateJavaScript("""
      (() => {
        const heading = document.querySelector('.mdp-slide-body h2').getBoundingClientRect();
        const images = Array.from(document.querySelectorAll('.mdp-slide-body img'))
          .map(img => img.getBoundingClientRect());
        const tops = new Set(images.map(r => Math.round(r.top)));
        const lefts = images.map(r => Math.round(r.left));
        return [document.querySelector('.mdp-slide').classList.contains('mdp-slide--grid'),
                tops.size, lefts[0] < lefts[1] && lefts[1] < lefts[2],
                images.every(r => r.top >= heading.bottom && r.height > 50)].join('|');
      })()
      """) as? String
      XCTAssertEqual(result, "true|1|true|true", markdown)
    }
  }

  @MainActor
  func testSplitBackgroundTakesOneHalf() async throws {
    let webView = try await loadedWebView("## Text\n\n![bg right](data:image/gif;base64,R0lGODlhAQABAAAAACw=)")
    let result = try await webView.evaluateJavaScript("""
    (() => {
      const slide = document.querySelector('.mdp-slide').getBoundingClientRect();
      const bg = document.querySelector('.mdp-slide-bg').getBoundingClientRect();
      const body = document.querySelector('.mdp-slide-body').getBoundingClientRect();
      return [Math.round((bg.left - slide.left) / slide.width * 100),
              Math.round(bg.width / slide.width * 100),
              body.right <= bg.left + 1].join('|');
    })()
    """) as? String
    XCTAssertEqual(result, "50|50|true")
  }

  @MainActor
  func testPresenterViewShowsCurrentSlideWithNotesAndTheNextSlide() async throws {
    let webView = try await loadedWebView(
      "# One\n\n???\n\nFirst notes\n\n---\n\n## Two\n\n???\n\nSecond notes\n\n---\n\n## Three",
      width: 1200, height: 700)
    let result = try await webView.evaluateJavaScript("""
    (() => {
      document.documentElement.setAttribute('data-mdp-slides-presenter', '');
      MdPreviewSlides.show(1, 0);
      const shown = Array.from(document.querySelectorAll('.mdp-slide-frame'))
        .filter(frame => frame.offsetParent !== null).map(frame => frame.dataset.slide);
      const notes = Array.from(document.querySelectorAll('.mdp-slide-notes'))
        .filter(n => n.offsetParent !== null).map(n => n.textContent.trim());
      const current = document.querySelector('[data-mdp-current] .mdp-slide').getBoundingClientRect();
      const next = document.querySelector('[data-mdp-next] .mdp-slide').getBoundingClientRect();
      return [shown.join(','), notes.join(','), current.width > next.width, next.left > current.right].join('|');
    })()
    """) as? String
    XCTAssertEqual(result, "1,2|Second notes|true|true")
  }
}
