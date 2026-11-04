import Foundation
import Markdown
import WebKit
import XCTest

@testable import MarkdownHelpers

final class SlideDeckTests: XCTestCase {
  private func deck(_ markdown: String) -> SlideDeck {
    SlideDeck(document: Document(parsing: markdown))
  }

  private func layouts(_ markdown: String) -> [SlideDeck.Layout] {
    deck(markdown).slides.map(\.layout)
  }

  private func slidesHTML(_ markdown: String) -> String {
    MarkdownHTML.render(markdown: markdown, forcesSlides: true).articleHTML
  }

  // MARK: - Splitting

  func testTopLevelThematicBreaksSplitSlides() {
    XCTAssertEqual(deck("# One\n\n---\n\n## Two\n\n***\n\n## Three\n\n___\n\nfour").slides.count, 4)
  }

  func testSetextHeadingIsNotASlideBreak() {
    let slides = deck("Title\n---\n\ntext").slides
    XCTAssertEqual(slides.count, 1)
    XCTAssertTrue(slides[0].blocks.first is Heading)
  }

  func testBreaksInsideListsQuotesAndFencesDoNotSplit() {
    let markdown = """
    - item

      ---

    > quote
    >
    > ---

    ```
    ---
    ```
    """
    XCTAssertEqual(deck(markdown).slides.count, 1)
  }

  func testLeadingAndTrailingBreaksAddNoEmptySlides() {
    XCTAssertEqual(deck("---\n\n# One\n\n---\n\n## Two\n\n---\n").slides.count, 2)
  }

  func testBreaksBetweenBreaksKeepABlankSlide() {
    XCTAssertEqual(layouts("# One\n\n---\n\n---\n\n## Two"), [.title, .blank, .section])
  }

  func testFrontmatterFencesNeverSplitSlides() {
    let markdown = "---\nslides: true\n---\n\n# One\n\n---\n\n## Two"
    XCTAssertEqual(MarkdownHTML.slideCount(markdown: markdown), 2)
  }

  func testSlideCountMatchesRenderedSlides() {
    let markdown = """
    ---
    slides: true
    ---

    # Deck

    $$
    x
    $$

    ---

    Text[^1]

    [^1]: A note.

    ---

    ## End
    """
    let html = MarkdownHTML.render(markdown: markdown).articleHTML
    XCTAssertEqual(MarkdownHTML.slideCount(markdown: markdown), 3)
    XCTAssertEqual(html.components(separatedBy: "class=\"mdp-slide-frame\"").count - 1, 3)
  }

  // MARK: - Notes

  func testNotesMarkerAloneStartsNotes() {
    let slide = deck("## Title\n\n???\n\nSay hello.\n\n- point").slides[0]
    XCTAssertEqual(slide.blocks.count, 1)
    XCTAssertNil(slide.notesLead)
    XCTAssertEqual(slide.notes.count, 2)
  }

  func testNotesMarkerFollowedByTextOnTheNextLine() {
    let slide = deck("## Title\n\n???\nSay hello.").slides[0]
    XCTAssertNotNil(slide.notesLead)
    XCTAssertTrue(slide.notes.isEmpty)
    let html = slidesHTML("## Title\n\n???\nSay hello.")
    XCTAssertTrue(html.contains("<aside class=\"mdp-slide-notes\">"))
    XCTAssertTrue(html.contains(">Say hello.</p>"))
    XCTAssertFalse(html.contains("???"))
  }

  func testNotesEndAtTheNextSlide() {
    let slides = deck("## A\n\n???\n\nnote\n\n---\n\n## B").slides
    XCTAssertEqual(slides.count, 2)
    XCTAssertFalse(slides[1].hasNotes)
    XCTAssertEqual(slides[1].layout, .section)
  }

  func testMarkerWithTextOnTheSameLineOrInAListIsContent() {
    XCTAssertFalse(deck("??? not notes").slides[0].hasNotes)
    XCTAssertFalse(deck("- ???").slides[0].hasNotes)
  }

  func testSecondMarkerInNotesIsNoteText() {
    let slide = deck("## A\n\n???\n\none\n\n???\n\ntwo").slides[0]
    XCTAssertEqual(slide.notes.count, 3)
  }

  func testSlideWithOnlyNotesIsBlank() {
    XCTAssertEqual(layouts("# A\n\n---\n\n???\n\nnotes only"), [.title, .blank])
  }

  // MARK: - Layout inference

  func testLayoutRules() {
    let cases: [(String, SlideDeck.Layout)] = [
      ("# Title", .title),
      ("# Title\n\nA subtitle", .title),
      ("# Title\n\n" + String(repeating: "a", count: 250), .titleContent),
      ("# Title\n\n- one item", .titleContent),
      ("## Section", .section),
      ("> A quote", .quote),
      ("> [!tip] A callout", .titleContent),
      ("```swift\nlet a = 1\n```", .code),
      ("## Code\n\n```mermaid\ngraph TD\n```", .code),
      ("## Code\n\n```swift\nx\n```\n\nand a paragraph", .titleContent),
      ("MdPreviewMathBlock0Token", .math),
      ("## Heading\n\n![a](a.png)", .titleImage),
      ("## Heading\n\n![a](a.png) ![b](b.png)", .titleContent),
      ("## Heading\n\n![a](a.png) ![b](b.png) ![c](c.png)", .titleContent),
      ("![a](a.png)\n\n![b](b.png)\n![c](c.png)", .titleContent),
      ("## Heading\n\nSome text", .titleContent),
      ("Just text", .titleContent),
      ("<!-- a comment -->", .blank),
      ("<!-- a comment -->\n\n## Section", .section),
    ]
    for (markdown, expected) in cases {
      XCTAssertEqual(SlideDeck.layout(of: Array(Document(parsing: markdown).children)),
                     expected, markdown)
    }
  }

  // MARK: - Turning it on

  func testFrontmatterTurnsSlidesOn() {
    XCTAssertTrue(SlideDeck.isDeck(markdown: "---\nslides: true\n---\n# A"))
    XCTAssertTrue(SlideDeck.isDeck(markdown: "---\nmarp: true\n---\n# A"))
    XCTAssertTrue(SlideDeck.isDeck(markdown: "+++\nslides = true\n+++\n# A"))
    XCTAssertFalse(SlideDeck.isDeck(markdown: "---\nslides: false\n---\n# A"))
    XCTAssertFalse(SlideDeck.isDeck(markdown: "# A\n\n---\n\n# B"))
  }

  func testOrdinaryDocumentsKeepRulesAndFrontmatter() {
    let html = MarkdownHTML.render(markdown: "---\ntitle: Notes\n---\n\n# A\n\n---\n\n# B").articleHTML
    XCTAssertFalse(html.contains("mdp-deck"))
    XCTAssertTrue(html.contains("<hr"))
    XCTAssertTrue(html.contains("md-frontmatter"))
  }

  func testDeckRendersSectionsWithoutFrontmatterOrRules() throws {
    let rendered = MarkdownHTML.render(
      markdown: "---\nslides: true\n---\n\n# A\n\n---\n\n## B",
      vendorLoading: .lazy
    )
    let html = rendered.articleHTML
    XCTAssertTrue(html.hasPrefix("<div class=\"mdp-deck\">"))
    XCTAssertTrue(html.contains("<div class=\"mdp-slide mdp-slide--title\">"))
    XCTAssertTrue(html.contains("<div class=\"mdp-slide mdp-slide--section\">"))
    XCTAssertTrue(html.contains("data-slide=\"1\""))
    XCTAssertFalse(html.contains("<hr"))
    XCTAssertFalse(html.contains("md-frontmatter"))
    XCTAssertFalse(html.contains("md-source-blank-line"))
    XCTAssertFalse(html.contains(MarkdownHTML.slideFootnotesToken))
    XCTAssertTrue(rendered.scriptAssetIDs.contains("slides"))
  }

  func testSlidesKeepSourceLinesOfTheFile() {
    let html = slidesHTML("---\nslides: true\n---\n\n# A\n\n---\n\n## B")
    XCTAssertTrue(html.contains("<h1 data-source-line=\"5\""), html)
    XCTAssertTrue(html.contains("<h2 data-source-line=\"9\""), html)
  }

  func testSlidesScriptLoadsInEveryHost() throws {
    let slides = try XCTUnwrap(MarkdownHTML.renderExtensions.first { $0.id == "slides" })
    XCTAssertFalse(slides.descriptor.userToggleable)
    for mode in [MarkdownHTML.VendorLoading.lazy, .inline] {
      XCTAssertTrue(slides.assets(mode: mode).bodyJS.contains("MdPreviewSlides"))
      XCTAssertTrue(slides.assets(mode: mode).css.contains(".mdp-slide"))
    }
  }

  // MARK: - Footnotes

  func testFootnotesAppearOnEverySlideThatReferencesThem() {
    let html = slidesHTML("""
    ## One

    First[^a] and second[^b].

    ---

    ## Two

    Again[^a].

    ---

    ## Three

    None.

    [^a]: Alpha.
    [^b]: Beta.
    [^c]: Unused.
    """)
    let slides: [String] = Array(html.components(separatedBy: "class=\"mdp-slide-frame\"").dropFirst())
    XCTAssertEqual(slides.count, 3)
    XCTAssertTrue(slides[0].contains("<li value=\"1\">"))
    XCTAssertTrue(slides[0].contains("<li value=\"2\">"))
    XCTAssertTrue(slides[1].contains("<li value=\"1\">"))
    XCTAssertFalse(slides[1].contains("<li value=\"2\">"))
    XCTAssertFalse(slides[2].contains("mdp-slide-footnotes"))
    XCTAssertFalse(html.contains("Unused"))
    XCTAssertFalse(html.contains("role=\"doc-endnotes\""))
    XCTAssertTrue(slides[1].contains("<sup class=\"footnote-ref\">"))
  }

  func testNoteFootnotesStayInTheNotes() {
    let html = slidesHTML("## One\n\nText.\n\n???\n\nSee[^n].\n\n[^n]: Source.")
    guard let notesStart = html.range(of: "<aside class=\"mdp-slide-notes\">") else {
      return XCTFail("no notes in \(html)")
    }
    XCTAssertFalse(html[..<notesStart.lowerBound].contains("mdp-slide-footnotes"))
    XCTAssertTrue(html[notesStart.upperBound...].contains("mdp-slide-footnotes"))
  }

  // MARK: - Page

  @MainActor
  private func loadedWebView(_ markdown: String, width: CGFloat = 900, height: CGFloat = 600)
    async throws -> WKWebView {
    let rendered = MarkdownHTML.render(markdown: markdown, vendorLoading: .lazy, forcesSlides: true)
    let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: width, height: height))
    webView.loadHTMLString(rendered.html, baseURL: nil)
    let deadline = Date().addingTimeInterval(10)
    while webView.isLoading && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
    return webView
  }

  @MainActor
  func testSlidesKeepTheirAspectRatioInReadMode() async throws {
    let webView = try await loadedWebView("# One\n\n---\n\n## Two")
    let ratio = try await webView.evaluateJavaScript("""
    (() => { const r = document.querySelector('.mdp-slide').getBoundingClientRect();
             return r.width / r.height; })()
    """) as? Double
    XCTAssertEqual(try XCTUnwrap(ratio), 16.0 / 9.0, accuracy: 0.01)
  }

  @MainActor
  func testPresentingShowsOnlyTheCurrentSlideFittedToTheWindow() async throws {
    let webView = try await loadedWebView("# One\n\n---\n\n## Two\n\n???\n\nnotes", width: 1000, height: 400)
    let result = try await webView.evaluateJavaScript("""
    (() => {
      document.documentElement.setAttribute('data-mdp-slides-presenting', '');
      MdPreviewSlides.show(1);
      const shown = Array.from(document.querySelectorAll('.mdp-slide-frame'))
        .filter(frame => frame.offsetParent !== null).map(frame => frame.dataset.slide);
      const slide = document.querySelector('[data-mdp-current] .mdp-slide').getBoundingClientRect();
      const notes = document.querySelector('.mdp-slide-notes').offsetParent !== null;
      return [shown.join(','), Math.round(slide.height), notes, MdPreviewSlides.count(), MdPreviewSlides.show(9)].join('|');
    })()
    """) as? String
    XCTAssertEqual(result, "1|400|false|2|1")
  }
}
