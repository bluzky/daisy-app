import WebKit
import XCTest
@testable import MarkdownHelpers

final class DocumentCardsTests: XCTestCase {

    private func html(_ markdown: String) -> String {
        MarkdownHTML.render(markdown: markdown).articleHTML
    }

    private func slides(_ markdown: String) -> String {
        MarkdownHTML.render(markdown: markdown, forcesSlides: true).articleHTML
    }

    private func cardCount(_ out: String) -> Int {
        out.components(separatedBy: "<div class=\"md-card").count - 1
    }

    // MARK: Options

    func testOptionsParseIntoClassesAndAColorProperty() throws {
        let style = try XCTUnwrap(CardStyle(options: " style=accent color=#6366F1 tint=true padding=compact align=center"))
        XCTAssertEqual(style.classes,
                       "md-card md-card-accent md-card-colored md-card-tint md-card-pad-compact md-card-align-center")
        XCTAssertEqual(style.colorAttribute, " data-md-card-color=\"#6366f1\"", "a hex color rides in a data attribute")
        let palette = CardStyle(options: "color=success")
        XCTAssertEqual(palette?.classes, "md-card md-card-colored md-card-color-success", "a palette color is a class")
        XCTAssertEqual(palette?.colorAttribute, "")
        XCTAssertEqual(CardStyle(options: "color='#fff'")?.color, "#fff", "a value may be quoted")
        XCTAssertEqual(CardStyle().classes, "md-card")
        XCTAssertEqual(CardStyle().colorAttribute, "")
        XCTAssertEqual(CardStyle(options: "color=default")?.classes, "md-card", "`default` is the card's normal look")
        XCTAssertEqual(CardStyle(options: "color=neutral")?.classes, "md-card", "`neutral` is `default`")
        XCTAssertNil(CardStyle(options: "color=positive"), "the old names are gone")
        XCTAssertFalse(style.openingTag.contains("style="), "the page drops style attributes")
        XCTAssertEqual(CardStyle(options: "style=accent edge=top")?.classes, "md-card md-card-accent md-card-edge-top")
        XCTAssertEqual(CardStyle(options: "style=accent edge=left")?.classes, "md-card md-card-accent", "left is the default")
        XCTAssertEqual(CardStyle(options: "style=filled edge=top")?.classes, "md-card md-card-filled", "only an accent card has a bar")
    }

    func testInvalidOptionsAreRejected() {
        for options in [
            "style=fancy", "color=red", "color=#12345", "color=#fff;background:url(x)",
            "tint=yes", "padding=huge", "align=right", "edge=bottom", "size=big", "style", "style=",
            "style=accent style=plain", "style=\"accent",
        ] {
            XCTAssertNil(CardStyle(options: options), options)
        }
    }

    func testMarkersNeedTheirOwnWord() {
        XCTAssertEqual(DocumentCards.marker(ofComment: " card "), .open(CardStyle()))
        XCTAssertEqual(DocumentCards.marker(ofComment: "END-CARD"), .end)
        XCTAssertNil(DocumentCards.marker(ofComment: "cards"))
        XCTAssertNil(DocumentCards.marker(ofComment: "card: style=accent"))
        XCTAssertEqual(DocumentCards.marker(ofComment: "card style=nope"), .open(nil))
    }

    // MARK: Documents

    func testACardFramesItsBlocks() {
        let out = html("Before\n\n<!-- card style=filled color=warning -->\n### Title\n\nBody text\n\n<!-- end-card -->\n\nAfter")
        XCTAssertTrue(out.contains("<div class=\"md-card md-card-filled md-card-colored md-card-color-warning\">"))
        let open = out.range(of: "<div class=\"md-card")!.lowerBound
        XCTAssertLessThan(out.range(of: "Before")!.upperBound, open)
        XCTAssertGreaterThan(out.range(of: "Body text")!.lowerBound, open)
        let close = out.range(of: "</div>", range: out.range(of: "Body text")!.upperBound..<out.endIndex)!.lowerBound
        XCTAssertGreaterThan(out.range(of: "After")!.lowerBound, close, "content after the card stays outside it")
    }

    func testBlocksInACardKeepTheirSourceLines() {
        let out = html("<!-- card -->\nInside\n\n<!-- end-card -->")
        XCTAssertTrue(out.contains("data-source-start=\"2\""))
    }

    func testMalformedCardsStayPlain() {
        for markdown in [
            "<!-- card -->\nNo end",
            "<!-- card -->\n<!-- end-card -->",
            "<!-- card style=fancy -->\nText\n\n<!-- end-card -->",
            "<!-- card -->\n<!-- columns -->\nL\n\n<!-- column -->\nR\n\n<!-- end-columns -->\n<!-- end-card -->",
            "- item\n\n  <!-- card -->\n  Inside\n\n  <!-- end-card -->",
        ] {
            XCTAssertEqual(cardCount(html(markdown)), 0, markdown)
        }
        XCTAssertTrue(html("<!-- card -->\nNo end").contains("No end"), "the blocks still show")
    }

    func testAnOpenerInsideACardDropsTheOuterOne() {
        let out = html("<!-- card -->\nA\n\n<!-- card -->\nB\n\n<!-- end-card -->\n\n<!-- end-card -->")
        XCTAssertEqual(cardCount(out), 1, "only the inner, well-formed card frames")
        let open = out.range(of: "<div class=\"md-card")!.lowerBound
        XCTAssertLessThan(out.range(of: ">A<")!.lowerBound, open, "A stays outside")
    }

    func testCardsInsideColumns() {
        let out = html("""
        <!-- columns -->
        <!-- card color=success -->
        Left
        <!-- end-card -->

        <!-- column -->
        <!-- card -->
        Right
        <!-- end-card -->

        <!-- end-columns -->
        """)
        XCTAssertTrue(out.contains("<div class=\"md-columns\" data-columns=\"2\">"))
        XCTAssertEqual(cardCount(out), 2)
        XCTAssertTrue(out.contains("<div class=\"md-column\">\n<div class=\"md-card md-card-colored md-card-color-success\">"))
    }

    func testACardCannotSpanAColumnBreak() {
        let out = html("<!-- columns -->\n<!-- card -->\nLeft\n\n<!-- column -->\nRight\n<!-- end-card -->\n\n<!-- end-columns -->")
        XCTAssertEqual(cardCount(out), 0)
        XCTAssertTrue(out.contains("md-columns"), "the columns still lay out")
    }

    // MARK: Slides

    func testSlidesFrameCardsInTheBodyAndInColumns() {
        let out = slides("""
        ## Metrics

        <!-- card style=accent -->
        Top

        <!-- end-card -->

        ---

        ## Split

        <!-- card color=#ff0000 -->
        Left

        <!-- end-card -->
        <!-- column -->
        Right
        """)
        XCTAssertEqual(cardCount(out), 2)
        XCTAssertTrue(out.contains("<div class=\"md-card md-card-accent\">"))
        XCTAssertTrue(out.contains("<div class=\"mdp-slide-column\">\n<div class=\"md-card md-card-colored\" data-md-card-color=\"#ff0000\">"))
    }

    func testSlideCardsFollowTheSameRules() {
        for markdown in [
            "## A\n\n<!-- card -->\nNo end",
            "## A\n\n<!-- card style=fancy -->\nText\n\n<!-- end-card -->",
            "## A\n\n<!-- card -->\n<!-- end-card -->",
            "## A\n\n<!-- card -->\nLeft\n\n<!-- column -->\nRight\n\n<!-- end-card -->",
        ] {
            XCTAssertEqual(cardCount(slides(markdown)), 0, markdown)
        }
    }

    // MARK: Styles

    @MainActor
    func testCardStylesComeFromTheThemeAndTheColor() async throws {
        let rendered = MarkdownHTML.render(markdown: """
        <!-- columns -->
        <!-- card -->
        Short
        <!-- end-card -->

        <!-- column -->
        <!-- card style=accent color=#ff0000 -->
        Tall

        Taller

        Tallest
        <!-- end-card -->

        <!-- end-columns -->

        <!-- card style=outline -->
        Outline
        <!-- end-card -->

        <!-- card style=accent edge=top color=#00ff00 -->
        Top bar
        <!-- end-card -->
        """)
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 600))
        webView.loadHTMLString(rendered.html, baseURL: nil)
        let deadline = Date().addingTimeInterval(10)
        while webView.isLoading && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        let result = try await webView.evaluateJavaScript("""
        (() => {
          const [plain, accent, outline, top] = Array.from(document.querySelectorAll('.md-card'));
          const css = el => getComputedStyle(el);
          return [css(plain).backgroundColor !== 'rgba(0, 0, 0, 0)',
                  css(accent).borderLeftColor, css(accent).borderLeftWidth !== css(accent).borderTopWidth,
                  css(outline).backgroundColor,
                  Math.round(plain.getBoundingClientRect().height) === Math.round(accent.getBoundingClientRect().height),
                  css(top).borderTopColor, css(top).borderTopWidth !== css(top).borderLeftWidth];
        })()
        """) as? [Any]
        XCTAssertEqual(result?[0] as? Bool, true, "a plain card has a fill")
        XCTAssertEqual(result?[1] as? String, "rgb(255, 0, 0)", "the accent bar takes the color")
        XCTAssertEqual(result?[2] as? Bool, true, "the accent bar is thicker than the border")
        XCTAssertEqual(result?[3] as? String, "rgba(0, 0, 0, 0)", "an outline card has no fill")
        XCTAssertEqual(result?[4] as? Bool, true, "cards in a row of columns line up")
        XCTAssertEqual(result?[5] as? String, "rgb(0, 255, 0)", "edge=top moves the bar to the top")
        XCTAssertEqual(result?[6] as? Bool, true, "the top bar is thicker than the side border")
    }
}
