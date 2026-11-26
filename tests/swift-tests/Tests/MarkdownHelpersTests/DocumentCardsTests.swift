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
        let style = try XCTUnwrap(CardStyle(options: " style=accent color=#6366F1 fill=soft padding=compact align=center"))
        XCTAssertEqual(style.classes,
                       "md-card md-card-fill-soft md-card-bar-left md-card-colored md-card-pad-compact md-card-align-center")
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
        XCTAssertEqual(CardStyle(options: "shape=circle style=filled")?.classes,
                       "md-card md-card-fill-tint md-card-border-none md-card-shape-circle")
        XCTAssertEqual(CardStyle(options: "shape=pill")?.classes, "md-card md-card-shape-pill")
        XCTAssertEqual(CardStyle(options: "shape=square")?.classes, "md-card md-card-shape-square")
        XCTAssertEqual(CardStyle(options: "shape=rounded")?.classes, "md-card", "rounded is the default")
        XCTAssertEqual(CardStyle(options: "padding=none")?.classes, "md-card md-card-pad-none")
        XCTAssertEqual(CardStyle(options: "style=solid color=warning ink=light")?.classes,
                       "md-card md-card-fill-solid md-card-border-none md-card-colored md-card-color-warning md-card-ink-light")
        XCTAssertEqual(CardStyle(options: "ink=dark")?.ink, .dark)
    }

    func testStylePresetsSetFillBorderAndBar() {
        let expected: [String: String] = [
            "plain": "md-card",
            "outline": "md-card md-card-fill-none",
            "filled": "md-card md-card-fill-tint md-card-border-none",
            "accent": "md-card md-card-bar-left",
            "solid": "md-card md-card-fill-solid md-card-border-none",
            "none": "md-card md-card-fill-none md-card-border-none",
        ]
        for (preset, classes) in expected {
            XCTAssertEqual(CardStyle(options: "style=\(preset)")?.classes, classes, preset)
        }
        XCTAssertEqual(Set(expected.keys), Set(CardStyle.Preset.allCases.map(\.rawValue)))
    }

    func testOptionsBesideAPresetOverrideIt() {
        XCTAssertEqual(CardStyle(options: "style=accent bar=top")?.classes, "md-card md-card-bar-top")
        XCTAssertEqual(CardStyle(options: "bar=top style=accent")?.classes, "md-card md-card-bar-top",
                       "wherever the option stands")
        XCTAssertEqual(CardStyle(options: "style=solid border=thick")?.classes,
                       "md-card md-card-fill-solid md-card-border-thick")
        XCTAssertEqual(CardStyle(options: "style=accent bar=none fill=none")?.classes, "md-card md-card-fill-none")
        XCTAssertEqual(CardStyle(options: "fill=soft bar=top border=none")?.classes,
                       "md-card md-card-fill-soft md-card-border-none md-card-bar-top", "no preset needed")
    }

    /// The skills' checker mirrors the parser; their option names must match.
    func testTheSkillCheckerKnowsTheSameCardOptions() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent(".agents/skills/daisy-slides/scripts/check_deck.py"),
                                encoding: .utf8)
        let block = try XCTUnwrap(source.firstRange(of: #/CARD_OPTIONS = \{(?s:.*?)\n\}/#))
        let keys = Set(source[block].matches(of: #/\n    "([a-z]+)":/#).map { String($0.1) })
        XCTAssertEqual(keys, CardStyle.optionNames)
    }

    func testInvalidOptionsAreRejected() {
        for options in [
            "style=fancy", "color=red", "color=#12345", "color=#fff;background:url(x)",
            "fill=yes", "border=dotted", "bar=bottom", "padding=huge", "align=right", "size=big",
            "shape=hexagon", "style", "style=", "style=accent style=plain", "style=\"accent",
            "tint=true", "edge=top", "fill=soft fill=tint", "ink=grey", "ink=",
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
        XCTAssertTrue(out.contains("<div class=\"md-card md-card-fill-tint md-card-border-none md-card-colored md-card-color-warning\">"))
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
        XCTAssertTrue(out.contains("<div class=\"md-card md-card-bar-left\">"))
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

        <!-- card style=accent bar=top color=#00ff00 -->
        Top bar
        <!-- end-card -->

        <!-- card style=none -->
        Bare
        <!-- end-card -->

        <!-- card style=solid color=#0000ff -->
        ### Solid
        [A link](https://example.com)
        <!-- end-card -->

        <!-- card border=thick color=#ff0000 -->
        Thick
        <!-- end-card -->

        <!-- card style=solid color=warning ink=light -->
        ### Light on warning
        <!-- end-card -->

        <!-- card ink=dark -->
        ### Dark on the surface
        <!-- end-card -->
        """)
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 900))
        webView.loadHTMLString(rendered.html, baseURL: nil)
        let deadline = Date().addingTimeInterval(10)
        while webView.isLoading && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        let result = try await webView.evaluateJavaScript("""
        (() => {
          const [plain, accent, outline, top, bare, solid, thick, light, darkInk] = Array.from(document.querySelectorAll('.md-card'));
          const css = el => getComputedStyle(el);
          return [css(plain).backgroundColor !== 'rgba(0, 0, 0, 0)',
                  css(accent).borderLeftColor, css(accent).borderLeftWidth !== css(accent).borderTopWidth,
                  css(outline).backgroundColor,
                  Math.round(plain.getBoundingClientRect().height) === Math.round(accent.getBoundingClientRect().height),
                  css(top).borderTopColor, css(top).borderTopWidth !== css(top).borderLeftWidth,
                  css(bare).backgroundColor, css(bare).borderTopWidth,
                  css(solid).backgroundColor, css(solid.querySelector('h3')).color, css(solid.querySelector('a')).color,
                  css(thick).borderTopColor, parseFloat(css(thick).borderTopWidth) > 1,
                  css(accent).borderTopColor !== 'rgb(255, 0, 0)',
                  css(light.querySelector('h3')).color, css(darkInk.querySelector('h3')).color, css(darkInk).color];
        })()
        """) as? [Any]
        XCTAssertEqual(result?[0] as? Bool, true, "a plain card has a fill")
        XCTAssertEqual(result?[1] as? String, "rgb(255, 0, 0)", "the accent bar takes the color")
        XCTAssertEqual(result?[2] as? Bool, true, "the accent bar is thicker than the border")
        XCTAssertEqual(result?[3] as? String, "rgba(0, 0, 0, 0)", "an outline card has no fill")
        XCTAssertEqual(result?[4] as? Bool, true, "cards in a row of columns line up")
        XCTAssertEqual(result?[5] as? String, "rgb(0, 255, 0)", "bar=top moves the bar to the top")
        XCTAssertEqual(result?[6] as? Bool, true, "the top bar is thicker than the side border")
        XCTAssertEqual(result?[7] as? String, "rgba(0, 0, 0, 0)", "style=none has no fill")
        XCTAssertEqual(result?[8] as? String, "0px", "style=none has no border")
        XCTAssertEqual(result?[9] as? String, "rgb(0, 0, 255)", "a solid card is its color")
        XCTAssertEqual(result?[10] as? String, "rgb(255, 255, 255)", "a heading on a solid card is white")
        XCTAssertEqual(result?[11] as? String, "rgb(255, 255, 255)", "so is a link")
        XCTAssertEqual(result?[12] as? String, "rgb(255, 0, 0)", "without a bar, the border takes the color")
        XCTAssertEqual(result?[13] as? Bool, true, "border=thick is thicker than a thin border")
        XCTAssertEqual(result?[14] as? Bool, true, "with a bar, the border keeps the theme's separator color")
        XCTAssertEqual(result?[15] as? String, "rgb(255, 255, 255)", "ink=light wins over warning's dark text")
        XCTAssertEqual(result?[16] as? String, "rgb(29, 29, 31)", "ink=dark sets a heading's color on any card")
        XCTAssertEqual(result?[17] as? String, "rgb(29, 29, 31)", "and the card's text")
    }
}
