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

  func testDimDarkensTheBackground() {
    XCTAssertEqual(slide("![bg dim](a.jpg)").background, .init(source: "a.jpg", dims: true))
    XCTAssertEqual(slide("![bg right dim fit](a.jpg)").background,
                   .init(source: "a.jpg", position: .right, fits: true, dims: true))
    let html = slidesHTML("# Title\n\n![bg dim](a.jpg)")
    XCTAssertTrue(html.contains("mdp-slide--bg-full mdp-slide--bg-dim"))
    XCTAssertTrue(html.contains("<div class=\"mdp-slide-bg mdp-slide-bg--full mdp-slide-bg--dim\">"))
  }

  func testBlurSoftensTheBackground() {
    XCTAssertEqual(slide("![bg blur](a.jpg)").background, .init(source: "a.jpg", blurs: true))
    XCTAssertEqual(slide("![bg dim blur](a.jpg)").background, .init(source: "a.jpg", dims: true, blurs: true))
    let html = slidesHTML("# Title\n\n![bg left blur](a.jpg)")
    XCTAssertTrue(html.contains("<div class=\"mdp-slide-bg mdp-slide-bg--left mdp-slide-bg--blur\">"))
    XCTAssertFalse(html.contains("mdp-slide--bg-dim"), "blur alone leaves the text color alone")
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

  func testOneCommentCanHoldSeveralDirectivesOnePerLine() {
    let styled = slide("""
    <!--
    layout: title
    _class: invert center

    color: "#FFF"
    -->

    ## Heading

    - a
    """)
    XCTAssertEqual(styled.layout, .title)
    XCTAssertEqual(styled.classes, ["invert", "center"])
    XCTAssertEqual(styled.color, "#fff")
  }

  func testMultiLineCommentMixesSpaceColumnAndStep() {
    let slide = slide("""
    ## A

    left

    <!--
    column
    space: 2
    -->

    right
    """)
    XCTAssertEqual(slide.columns.count, 2)
    XCTAssertEqual(slide.spaces.values.first, 2)
  }

  func testQuotesAroundAValueAreRemoved() {
    XCTAssertEqual(slide("<!-- _color: 'navy' -->\n\n## A").color, "navy")
    XCTAssertEqual(SlideDeck.directives(inComment: " a: \"x\" \n\n b \n").map(\.key), ["a", "b"])
  }

  func testAnOrdinaryCommentChangesNothing() {
    let plain = slide("<!--\nTODO: tighten this slide\nask Linh\n-->\n\n## A")
    XCTAssertEqual(plain.layout, .section)
    XCTAssertTrue(plain.classes.isEmpty)
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

  // MARK: - Columns

  private func columnTexts(_ markdown: String) -> (header: [String], columns: [[String]]) {
    let slide = slide(markdown)
    let text = { (range: Range<Int>) in
      slide.blocks[range].map { $0.format().trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    return (text(slide.columnHeader), slide.columns.map(text))
  }

  func testColumnBreaksSplitTheSlideBelowItsHeading() {
    let split = columnTexts("## Title\n\nleft\n\n<!-- column -->\n\nright")
    XCTAssertEqual(split.header, ["## Title"])
    XCTAssertEqual(split.columns, [["left"], ["right"]])
    XCTAssertEqual(slide("## Title\n\nleft\n\n<!-- column -->\n\nright").layout, .columns)
  }

  func testABreakRightAfterTheHeadingOrAtTheEndAddsNoEmptyColumn() {
    let split = columnTexts("""
    ## Title

    <!-- column -->

    left

    <!-- column -->

    right

    <!-- column -->
    """)
    XCTAssertEqual(split.columns, [["left"], ["right"]])
  }

  func testColumnsWithoutAHeading() {
    let split = columnTexts("one\n\n<!-- column -->\n\ntwo\n\n<!-- column -->\n\nthree")
    XCTAssertEqual(split.header, [])
    XCTAssertEqual(split.columns, [["one"], ["two"], ["three"]])
  }

  func testOneColumnIsNoColumns() {
    let slide = slide("## Title\n\n<!-- column -->\n\n- a\n- b")
    XCTAssertTrue(slide.columns.isEmpty)
    XCTAssertEqual(slide.layout, .titleContent)
  }

  func testColumnsStopAtFour() {
    let markdown = (1...6).map { "c\($0)" }.joined(separator: "\n\n<!-- column -->\n\n")
    let split = columnTexts(markdown)
    XCTAssertEqual(split.columns, [["c1"], ["c2"], ["c3"], ["c4", "c5", "c6"]])
  }

  func testEndColumnsPutsTheRestBelowTheColumns() {
    let slide = slide("""
    ## Title

    left

    <!-- column -->

    right

    <!-- end-columns -->

    > [!note] Note
    > Below both.

    After that.
    """)
    XCTAssertEqual(slide.columns.count, 2)
    XCTAssertEqual(slide.columns.map(\.count), [1, 1])
    XCTAssertEqual(slide.columnFooter.count, 2)
    XCTAssertTrue(slide.blocks[slide.columnFooter.lowerBound] is BlockQuote)
  }

  func testEndColumnsBeforeAnyBreakOrTwiceIsIgnored() {
    let early = slide("a\n\n<!-- end-columns -->\n\nb\n\n<!-- column -->\n\nc")
    XCTAssertEqual(early.columns.map(\.count), [2, 1])
    XCTAssertTrue(early.columnFooter.isEmpty)
    let twice = slide("a\n\n<!-- column -->\n\nb\n\n<!-- end-columns -->\n\nc\n\n<!-- end-columns -->\n\nd")
    XCTAssertEqual(twice.columnFooter.count, 2)
  }

  func testBreaksAfterEndColumnsAreIgnored() {
    let slide = slide("a\n\n<!-- column -->\n\nb\n\n<!-- end-columns -->\n\nc\n\n<!-- column -->\n\nd")
    XCTAssertEqual(slide.columns.count, 2)
    XCTAssertEqual(slide.columnFooter.count, 2)
  }

  func testEndColumnsWithOneColumnIsNoColumns() {
    let slide = slide("## T\n\n<!-- column -->\n\na\n\n<!-- end-columns -->\n\nb")
    XCTAssertTrue(slide.columns.isEmpty)
    XCTAssertTrue(slide.columnFooter.isEmpty)
    XCTAssertFalse(slidesHTML("## T\n\n<!-- column -->\n\na\n\n<!-- end-columns -->\n\nb").contains("mdp-slide-columns"))
  }

  func testColumnBreakInsideAListIsIgnored() {
    XCTAssertTrue(slide("- a\n\n  <!-- column -->\n\n- b").columns.isEmpty)
  }

  func testLayoutDirectiveStillWinsOverColumns() {
    XCTAssertEqual(slide("<!-- layout: title-content -->\n\na\n\n<!-- column -->\n\nb").layout,
                   .titleContent)
  }

  func testColumnsRenderInsideTheSlideBody() {
    let html = slidesHTML("## Title\n\n- a <!-- step -->\n\n<!-- column -->\n\n<!-- step -->\nright")
    XCTAssertTrue(html.contains("mdp-slide--columns"))
    XCTAssertTrue(html.contains(
      "<div class=\"mdp-slide-body\">\n<h2"), html)
    XCTAssertTrue(html.contains("<div class=\"mdp-slide-columns\">\n<div class=\"mdp-slide-column\">\n<ul"))
    XCTAssertTrue(html.contains("</div>\n<div class=\"mdp-slide-column\">\n<div class=\"mdp-step\" data-step=\"2\"><p"))
    XCTAssertEqual(html.components(separatedBy: "class=\"mdp-slide-column\"").count - 1, 2)
  }

  // MARK: - Space

  func testSpaceDirectiveAddsEmptyLines() {
    let slide = slide("## A\n\nfirst\n\n<!-- space -->\n\nsecond\n\n<!-- space: 3 -->\n\nthird")
    XCTAssertEqual(slide.spaces, [2: 1, 4: 3])
    XCTAssertEqual(slide.blocks.count, 6)
  }

  func testSpaceIsCappedAndInvalidCountsAreIgnored() {
    XCTAssertEqual(slide("a\n\n<!-- space: 40 -->\n\nb").spaces.values.first, SlideDeck.maximumSpaceLines)
    XCTAssertTrue(slide("a\n\n<!-- space: 0 -->\n\nb").spaces.isEmpty)
    XCTAssertTrue(slide("a\n\n<!-- space: lots -->\n\nb").spaces.isEmpty)
  }

  func testSpaceDoesNotChangeTheLayoutOrTakeAStep() {
    XCTAssertEqual(slide("<!-- space: 2 -->\n\n## Section").layout, .section)
    let stepped = slide("<!-- step -->\n<!-- space -->\n\nRevealed")
    XCTAssertEqual(stepped.blockSteps, [1: 1])
  }

  func testSpaceRendersAsASpacer() {
    let html = slidesHTML("first\n\n<!-- space: 2 -->\n\nsecond")
    XCTAssertTrue(html.contains("<div class=\"mdp-slide-space mdp-slide-space-2\" aria-hidden=\"true\"></div>"))
    XCTAssertFalse(html.contains("<!-- space"))
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
  func testTallImagesInColumnsFitSideBySide() async throws {
    // A 400 × 1200 image: three times taller than wide.
    let tall = "data:image/svg+xml;base64," + Data(
      "<svg xmlns='http://www.w3.org/2000/svg' width='400' height='1200'><rect width='400' height='1200' fill='teal'/></svg>".utf8
    ).base64EncodedString()
    let webView = try await loadedWebView("""
    ## A gallery

    ![a](\(tall))

    <!-- column -->

    ![b](\(tall))

    <!-- column -->

    ![c](\(tall))
    """, width: 1280, height: 720)
    var result: String?
    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline {
      result = try await webView.evaluateJavaScript("""
      (() => {
        const images = Array.from(document.querySelectorAll('.mdp-slide-column img'));
        if (!images.every(img => img.complete && img.naturalHeight)) return null;
        const slide = document.querySelector('.mdp-slide').getBoundingClientRect();
        const boxes = images.map(img => img.getBoundingClientRect());
        const columns = Array.from(document.querySelectorAll('.mdp-slide-column')).map(c => c.getBoundingClientRect());
        return [boxes.length,
                new Set(boxes.map(r => Math.round(r.top))).size,
                boxes.every(r => r.bottom <= slide.bottom + 1 && r.height > 100),
                boxes.every((r, i) => Math.abs((r.left + r.right) / 2 - (columns[i].left + columns[i].right) / 2) < 2),
                boxes.every(r => Math.abs(r.height / r.width - 3) < 0.05)].join('|');
      })()
      """) as? String
      if result != nil { break }
      try await Task.sleep(for: .milliseconds(100))
    }
    XCTAssertEqual(result, "3|1|true|true|true")
  }

  @MainActor
  func testColumnsSitSideBySideAtEqualWidthsBelowTheHeading() async throws {
    let webView = try await loadedWebView("""
    ## Before and after

    - Slow builds
    - Manual releases

    <!-- column -->

    - Cached builds

    <!-- column -->

    A third column
    """)
    let result = try await webView.evaluateJavaScript("""
    (() => {
      const heading = document.querySelector('.mdp-slide-body h2').getBoundingClientRect();
      const columns = Array.from(document.querySelectorAll('.mdp-slide-column')).map(c => c.getBoundingClientRect());
      const body = getComputedStyle(document.querySelector('.mdp-slide')).fontSize;
      const item = getComputedStyle(document.querySelector('.mdp-slide-column li')).fontSize;
      return [columns.length,
              new Set(columns.map(r => Math.round(r.top))).size,
              new Set(columns.map(r => Math.round(r.width))).size,
              columns[0].right < columns[1].left && columns[1].right < columns[2].left,
              columns.every(r => r.top >= heading.bottom),
              body === item].join('|');
    })()
    """) as? String
    XCTAssertEqual(result, "3|1|1|true|true|true")
  }

  @MainActor
  func testBlocksAfterEndColumnsSpanTheSlideRightBelowTheColumns() async throws {
    let webView = try await loadedWebView("""
    ## Campaigns

    - Upgrade before the peak

    <!-- column -->

    - Scale via IaC
    - Agreed takeover trigger

    <!-- end-columns -->

    > [!note]
    > Running a real peak is the strongest evidence.
    """)
    let result = try await webView.evaluateJavaScript("""
    (() => {
      const body = document.querySelector('.mdp-slide-body').getBoundingClientRect();
      const columns = document.querySelector('.mdp-slide-columns').getBoundingClientRect();
      const note = document.querySelector('.mdp-slide-body > .markdown-alert').getBoundingClientRect();
      const lastItem = Array.from(document.querySelectorAll('.mdp-slide-column li')).pop().getBoundingClientRect();
      return [Math.abs(note.width - body.width) < 2,
              note.top >= columns.bottom,
              note.top - lastItem.bottom < body.height * 0.2].join('|');
    })()
    """) as? String
    XCTAssertEqual(result, "true|true|true")
  }

  @MainActor
  func testTallDiagramsFitTheSlideInTheBodyAndInAColumn() async throws {
    let flow = (0..<12).map { "  N\($0)[Step \($0)] --> N\($0 + 1)[Step \($0 + 1)]" }.joined(separator: "\n")
    let markdown = """
    ## Full width

    ```mermaid
    flowchart TD
    \(flow)
    ```

    Text below.

    ---

    ## In a column

    - A point

    <!-- column -->

    ```mermaid
    flowchart TD
    \(flow)
    ```
    """
    // Mermaid ships inline here; the lazy page loads it from the app bundle.
    let rendered = MarkdownHTML.render(markdown: markdown, vendorLoading: .inline, forcesSlides: true)
    let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1280, height: 720))
    webView.loadHTMLString(rendered.html, baseURL: nil)
    var fits: String?
    let deadline = Date().addingTimeInterval(15)
    while Date() < deadline {
      try await Task.sleep(for: .milliseconds(200))
      fits = try? await webView.evaluateJavaScript("""
      (() => {
        const svgs = document.querySelectorAll('.mdp-slide svg');
        const figures = Array.from(document.querySelectorAll('.mdp-slide .mermaid-figure'));
        // Laid out once Mermaid has given each figure the diagram's shape.
        if (svgs.length < 2 || !figures.every(f => f.style.getPropertyValue('--mm-aspect'))) return null;
        return Array.from(svgs).map(svg => {
          const slide = svg.closest('.mdp-slide').getBoundingClientRect();
          const box = svg.getBoundingClientRect();
          return box.height > 50 && box.bottom <= slide.bottom + 1;
        }).join('|');
      })()
      """) as? String
      if fits != nil { break }
    }
    XCTAssertEqual(fits, "true|true")
  }

  @MainActor
  func testSpaceAddsLinesAtTheSlidesLineHeight() async throws {
    var gaps: [Double] = []
    var line = 0.0
    for spacer in ["", "<!-- space -->", "<!-- space: 2 -->"] {
      let webView = try await loadedWebView("first\n\n\(spacer)\n\nsecond", width: 1280, height: 720)
      let measured = try await webView.evaluateJavaScript("""
      (() => { const ps = document.querySelectorAll('.mdp-slide-body p');
        const font = parseFloat(getComputedStyle(document.querySelector('.mdp-slide')).fontSize);
        return [ps[1].getBoundingClientRect().top - ps[0].getBoundingClientRect().bottom, font * 1.4]; })()
      """) as? [Double]
      let values = try XCTUnwrap(measured)
      gaps.append(values[0])
      line = values[1]
    }
    XCTAssertEqual(gaps[1] - gaps[0], line, accuracy: 1)
    XCTAssertEqual(gaps[2] - gaps[0], line * 2, accuracy: 1)
  }

  @MainActor
  func testATallImageInTheBodyFitsBelowTheText() async throws {
    let tall = "data:image/svg+xml;base64," + Data(
      "<svg xmlns='http://www.w3.org/2000/svg' width='400' height='1200'><rect width='400' height='1200' fill='teal'/></svg>".utf8
    ).base64EncodedString()
    let webView = try await loadedWebView("## Diagram\n\nSome text above.\n\n![tall](\(tall))", width: 1280, height: 720)
    var result: String?
    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline {
      result = try await webView.evaluateJavaScript("""
      (() => {
        const img = document.querySelector('.mdp-slide-body img');
        if (!img.complete || !img.naturalHeight) return null;
        const slide = document.querySelector('.mdp-slide').getBoundingClientRect();
        const box = img.getBoundingClientRect();
        return [box.bottom <= slide.bottom + 1, box.height > 100, Math.abs(box.height / box.width - 3) < 0.05].join('|');
      })()
      """) as? String
      if result != nil { break }
      try await Task.sleep(for: .milliseconds(100))
    }
    XCTAssertEqual(result, "true|true|true")
  }

  @MainActor
  func testDimmedFullBackgroundDarkensTheImageAndLightensTheText() async throws {
    let white = "data:image/svg+xml;base64," + Data(
      "<svg xmlns='http://www.w3.org/2000/svg' width='16' height='9'><rect width='16' height='9' fill='white'/></svg>".utf8
    ).base64EncodedString()
    let webView = try await loadedWebView("# Launch\n\nAt nine\n\n![bg dim](\(white))")
    let result = try await webView.evaluateJavaScript("""
    (() => {
      const veil = getComputedStyle(document.querySelector('.mdp-slide-bg'), '::after');
      const slide = document.querySelector('.mdp-slide');
      const veilBox = document.querySelector('.mdp-slide-bg').getBoundingClientRect();
      const box = slide.getBoundingClientRect();
      return [veil.backgroundColor,
              getComputedStyle(slide.querySelector('h1')).color,
              Math.round(veilBox.width) === Math.round(box.width),
              document.elementFromPoint(box.left + box.width / 2, box.top + box.height / 2).closest('.mdp-slide-body') !== null
                || getComputedStyle(slide.querySelector('.mdp-slide-body')).position === 'relative'].join('|');
    })()
    """) as? String
    XCTAssertEqual(result, "rgba(0, 0, 0, 0.6)|rgb(255, 255, 255)|true|true")
  }

  @MainActor
  func testBlurredBackgroundStaysInsideItsBox() async throws {
    let webView = try await loadedWebView("## Text\n\n![bg right blur](data:image/gif;base64,R0lGODlhAQABAAAAACw=)")
    let result = try await webView.evaluateJavaScript("""
    (() => {
      const box = document.querySelector('.mdp-slide-bg');
      const img = box.querySelector('img');
      return [getComputedStyle(img).filter.startsWith('blur('),
              getComputedStyle(box).overflow,
              getComputedStyle(document.querySelector('.mdp-slide h2')).color !== 'rgb(255, 255, 255)'].join('|');
    })()
    """) as? String
    XCTAssertEqual(result, "true|hidden|true")
  }

  @MainActor
  func testBackgroundImageCoversItsBoxWhateverItsShape() async throws {
    let wide = "data:image/svg+xml;base64," + Data(
      "<svg xmlns='http://www.w3.org/2000/svg' width='1600' height='400'><rect width='1600' height='400' fill='teal'/></svg>".utf8
    ).base64EncodedString()
    for keywords in ["bg", "bg right", "bg left blur"] {
      let webView = try await loadedWebView("## Text\n\n![\(keywords)](\(wide))")
      var result: String?
      let deadline = Date().addingTimeInterval(5)
      while Date() < deadline {
        result = try await webView.evaluateJavaScript("""
        (() => {
          const box = document.querySelector('.mdp-slide-bg');
          const img = box.querySelector('img');
          if (!img.complete || !img.naturalWidth) return null;
          const b = box.getBoundingClientRect(), i = img.getBoundingClientRect();
          return [i.left <= b.left + 1, i.top <= b.top + 1, i.right >= b.right - 1, i.bottom >= b.bottom - 1,
                  getComputedStyle(img).objectFit].join('|');
        })()
        """) as? String
        if result != nil { break }
        try await Task.sleep(for: .milliseconds(100))
      }
      XCTAssertEqual(result, "true|true|true|true|cover", keywords)
    }
  }

  @MainActor
  func testColorDirectiveWinsOverDimmedText() async throws {
    let webView = try await loadedWebView("<!-- color: #ff0000 -->\n\n# Launch\n\n![bg dim](data:image/gif;base64,R0lGODlhAQABAAAAACw=)")
    let color = try await webView.evaluateJavaScript(
      "getComputedStyle(document.querySelector('.mdp-slide h1')).color") as? String
    XCTAssertEqual(color, "rgb(255, 0, 0)")
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
