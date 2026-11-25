import Foundation
import WebKit
import XCTest

@testable import MarkdownHelpers

/// Inline widget shortcodes, `` `{{name: arguments}}` ``
/// (docs/features/markdown-shortcodes.md, #73). AC IDs are that spec's.
final class ShortcodeTests: XCTestCase {

    // MARK: Formatter (BR-1)

    func testOnlyAKnownNameWithItsColonIsStamped() {
        XCTAssertEqual(WidgetDocument.inlineWidgetName(in: "{{sparkline: 1,2}}"), "sparkline")
        XCTAssertEqual(WidgetDocument.inlineWidgetName(in: "{{ badge:Done}}"), "badge")
        XCTAssertEqual(WidgetDocument.inlineWidgetName(in: "{{badge:}}"), "badge")
        for code in ["{{sparkline 1,2}}", "{{sparkline : 1,2}}", "{{sparklien: 1,2}}", "{{ user.name }}",
                     "{{#if x}}", "{{.Name}}", "{{ ok ? 'a' : 'b' }}", "x {{badge: A}}", "{{badge: A}} x",
                     "{{stat: A}}"] {
            XCTAssertNil(WidgetDocument.inlineWidgetName(in: code), code)
        }
    }

    func testAShortcodeKeepsItsTextAndLoadsTheScript() {
        let rendered = MarkdownHTML.render(markdown: "Trend `{{sparkline: 1,2,3}}` and `{{ user.name }}`")
        XCTAssertTrue(rendered.articleHTML.contains(
            "<code data-md-widget=\"\" data-md-inline=\"sparkline\">{{sparkline: 1,2,3}}</code>"))
        XCTAssertTrue(rendered.articleHTML.contains("<code>{{ user.name }}</code>"))
        XCTAssertTrue(rendered.scriptAssetIDs.contains("widgets"))
    }

    func testAShortcodeInAFootnoteStaysCode() {
        let html = MarkdownHTML.render(markdown: "Text[^1]\n\n[^1]: See `{{sparkline: 1,2}}`").articleHTML
        XCTAssertEqual(html.components(separatedBy: "data-md-inline").count - 1, 0)
    }

    func testABadgeFenceIsNoLongerStamped() {
        let html = MarkdownHTML.render(markdown: "```badge\ntext: Shipped\n```").articleHTML
        XCTAssertFalse(html.contains("data-md-widget"))
    }

    // MARK: The page script

    @MainActor
    private func load(_ markdown: String, mode: MarkdownHTML.VendorLoading = .inline,
                      forcesSlides: Bool = false) async throws -> WKWebView {
        let rendered = MarkdownHTML.render(markdown: markdown, vendorLoading: mode,
                                           colorScheme: .light, forcesSlides: forcesSlides)
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 700))
        webView.loadHTMLString(rendered.html, baseURL: nil)
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if !webView.isLoading { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        try await Task.sleep(for: .milliseconds(200))
        return webView
    }

    @MainActor
    private func eval(_ webView: WKWebView, _ script: String) async throws -> Any? {
        try await webView.evaluateJavaScript(script)
    }

    /// The y of each point of the first sparkline, as drawn.
    private let pointsProbe = """
    Array.from(document.querySelector('.md-widget-spark polyline').points, p => Math.round(p.y * 100) / 100)
    """

    @MainActor
    func testAC_1_1_SparklineInATableCellReplacesTheCodeAtTextHeight() async throws {
        let webView = try await load("""
        | Service | Trend |
        | --- | --- |
        | API | `{{sparkline: 3,5,2,8,6}}` |
        """)
        let result = try await eval(webView, """
        (() => {
          const cell = document.querySelectorAll('td')[1];
          const spark = cell.querySelector('.md-widget-spark');
          return [!!spark, cell.querySelectorAll('code').length,
                  spark.querySelector('polyline').points.length,
                  Math.round(spark.getBoundingClientRect().height),
                  Math.round(parseFloat(getComputedStyle(cell).fontSize))];
        })()
        """) as? [Any]
        XCTAssertEqual(result?[0] as? Bool, true)
        XCTAssertEqual(result?[1] as? Int, 0, "the code is replaced")
        XCTAssertEqual(result?[2] as? Int, 5)
        XCTAssertEqual(result?[3] as? Int, result?[4] as? Int, "as tall as the cell's text")
        let ys = try await eval(webView, pointsProbe) as? [Double]
        // 20 units tall with 2 of padding: the lowest (2) at 18, the highest (8) at 2.
        XCTAssertEqual(ys, [15.33, 10, 18, 2, 7.33], "scaled between the lowest and the highest")
    }

    @MainActor
    func testAC_1_2_QuotedValuesAndAColor() async throws {
        let webView = try await load("`{{sparkline: \"3,5,2,8\" color=success}}` `{{sparkline: 1,2 color=#FF00FF}}`")
        let result = try await eval(webView, """
        (() => {
          const sparks = document.querySelectorAll('.md-widget-spark');
          return [sparks.length, sparks[0].className, sparks[0].querySelector('polyline').points.length,
                  getComputedStyle(sparks[1].querySelector('polyline')).stroke];
        })()
        """) as? [Any]
        XCTAssertEqual(result?[0] as? Int, 2)
        XCTAssertEqual(result?[1] as? String, "md-widget-spark md-widget-spark-line md-widget-c-success")
        XCTAssertEqual(result?[2] as? Int, 4)
        XCTAssertEqual(result?[3] as? String, "rgb(255, 0, 255)", "a hex colors the line exactly")
    }

    @MainActor
    func testAC_1_3_InvalidShortcodesStayInlineCode() async throws {
        for markdown in [
            "`{{sparklien: 1,2}}`",
            "`{{sparkline 1,2}}`",
            "`{{sparkline: 1,2 color=\"red}}`",
            "`{{sparkline: 1,2 color=purple}}`",
            "`{{ user.name }}`",
            "`{{sparkline: 1,2 color=a color=b}}`",
            "`{{sparkline: 1,x,3}}`",
            "`{{sparkline: 1,2 type=area}}`",
            "`{{sparkline:}}`",
            "`{{badge: \"\"}}`",
        ] {
            let webView = try await load(markdown + "\n\nAfter")
            let result = try await eval(webView, """
            [document.querySelectorAll('code').length,
             document.querySelectorAll('.md-widget-spark, .md-widget-badge').length,
             document.querySelectorAll('p')[1].textContent]
            """) as? [Any]
            XCTAssertEqual(result?[0] as? Int, 1, markdown)
            XCTAssertEqual(result?[1] as? Int, 0, markdown)
            XCTAssertEqual(result?[2] as? String, "After", "the rest renders: \(markdown)")
        }
    }

    @MainActor
    func testAC_1_4_ShortcodesDrawInQuickLookLazyModeAndOnSlides() async throws {
        let markdown = "Trend `{{sparkline: 1,3,2}}` `{{badge: Live color=success}}`"
        for mode in [MarkdownHTML.VendorLoading.inline, .lazy] {
            let webView = try await load(markdown, mode: mode)
            let drawn = try await eval(webView, "document.querySelectorAll('.md-widget-spark, .md-widget-badge').length") as? Int
            XCTAssertEqual(drawn, 2, "\(mode)")
        }
        let slide = try await load(markdown, forcesSlides: true)
        let onSlide = try await eval(slide, "document.querySelectorAll('.md-widget-spark, .md-widget-badge').length") as? Int
        XCTAssertEqual(onSlide, 2, "on a slide")
    }

    @MainActor
    func testAC_1_5_BadgeIsInlineAndABadgeBlockStaysCode() async throws {
        let webView = try await load("""
        | Item | Status |
        | --- | --- |
        | Spec | `{{badge: "In review" color=warning}}` |

        ```badge
        text: Shipped
        ```
        """)
        let result = try await eval(webView, """
        (() => {
          const badge = document.querySelector('td .md-widget-badge');
          return [badge.textContent, badge.className, document.querySelectorAll('.md-widget-badge').length,
                  document.querySelector('pre code').textContent.trim()];
        })()
        """) as? [Any]
        XCTAssertEqual(result?[0] as? String, "In review")
        XCTAssertEqual(result?[1] as? String, "md-widget-badge md-widget-c-warning")
        XCTAssertEqual(result?[2] as? Int, 1, "the badge block is not drawn")
        XCTAssertEqual(result?[3] as? String, "text: Shipped")
    }

    // MARK: Shapes

    @MainActor
    func testShapesDrawTheirTextInTheirKindStyleAndSize() async throws {
        let webView = try await load("""
        `{{shape: 1}}` `{{shape: AB kind=square style=tint color=success size=xl}}` \
        `{{shape: 98% style=outline color=#ff00ff size=sm}}` `{{shape: '★'}}`
        """)
        let result = try await eval(webView, """
        Array.from(document.querySelectorAll('.md-widget-shape'), s => {
          const box = s.getBoundingClientRect();
          return [s.textContent, s.className, Math.round(box.width) === Math.round(box.height)];
        })
        """) as? [[Any]]
        XCTAssertEqual(result?.map { $0[0] as? String }, ["1", "AB", "98%", "★"])
        XCTAssertEqual(result?.map { $0[1] as? String }, [
            "md-widget-shape",
            "md-widget-shape md-widget-shape-square md-widget-shape-tint md-widget-shape-xl md-widget-shape-2 md-widget-c-success",
            "md-widget-shape md-widget-shape-outline md-widget-shape-sm md-widget-shape-3 md-widget-c-custom",
            "md-widget-shape",
        ])
        XCTAssertEqual(result?.map { $0[2] as? Bool }, [true, true, true, true], "a shape is as tall as it is wide")
        let border = try await eval(webView,
            "getComputedStyle(document.querySelectorAll('.md-widget-shape')[2]).borderTopColor") as? String
        XCTAssertEqual(border, "rgb(255, 0, 255)", "a hex colors the outline exactly")
    }

    @MainActor
    func testInvalidShapesStayInlineCode() async throws {
        for markdown in [
            "`{{shape:}}`",
            "`{{shape: 1234}}`",
            "`{{shape: 1 kind=hexagon}}`",
            "`{{shape: 1 style=glow}}`",
            "`{{shape: 1 size=huge}}`",
            "`{{shape: 1 color=purple}}`",
        ] {
            let webView = try await load(markdown)
            let result = try await eval(webView, """
            [document.querySelectorAll('code').length, document.querySelectorAll('.md-widget-shape').length]
            """) as? [Int]
            XCTAssertEqual(result, [1, 0], markdown)
        }
    }

    @MainActor
    func testAC_1_6_UnsupportedArgumentsAreIgnored() async throws {
        let webView = try await load("`{{sparkline: 1,4,2 size=big}}` `{{badge: In review}}`")
        let result = try await eval(webView, """
        [document.querySelector('.md-widget-spark polyline').points.length,
         document.querySelector('.md-widget-badge').textContent,
         document.querySelectorAll('code').length]
        """) as? [Any]
        XCTAssertEqual(result?[0] as? Int, 3)
        XCTAssertEqual(result?[1] as? String, "In", "an extra positional value is ignored")
        XCTAssertEqual(result?[2] as? Int, 0)
    }

    // MARK: Arguments (BR-2)

    @MainActor
    func testAValueEndingInACommaContinuesIntoTheNext() async throws {
        let webView = try await load("`{{sparkline: 3, 5, 2, 8 color=info}}`")
        let result = try await eval(webView, """
        [document.querySelector('.md-widget-spark polyline').points.length,
         document.querySelector('.md-widget-spark').className]
        """) as? [Any]
        XCTAssertEqual(result?[0] as? Int, 4)
        XCTAssertEqual(result?[1] as? String, "md-widget-spark md-widget-spark-line md-widget-c-info")
    }

    @MainActor
    func testEitherQuoteHoldsTheOther() async throws {
        let webView = try await load("`{{badge: 'Say \"hi\"'}}` `{{badge: \"It's\" color='success'}}`")
        let texts = try await eval(webView,
            "Array.from(document.querySelectorAll('.md-widget-badge'), b => b.textContent + '|' + b.className)") as? [String]
        XCTAssertEqual(texts, ["Say \"hi\"|md-widget-badge", "It's|md-widget-badge md-widget-c-success"])
    }

    @MainActor
    func testBadgeTextNeverBecomesMarkup() async throws {
        let webView = try await load("`{{badge: \"<img src=x onerror=alert(1)>\"}}`")
        let result = try await eval(webView, """
        [document.querySelectorAll('.md-widget-badge img').length, document.querySelector('.md-widget-badge').textContent]
        """) as? [Any]
        XCTAssertEqual(result?[0] as? Int, 0)
        XCTAssertEqual(result?[1] as? String, "<img src=x onerror=alert(1)>")
    }

    // MARK: Sparkline (BR-5)

    @MainActor
    func testEqualValuesDrawAFlatLineAcrossTheMiddle() async throws {
        let webView = try await load("`{{sparkline: 0,0,0}}`")
        let ys = try await eval(webView, pointsProbe) as? [Double]
        XCTAssertEqual(ys, [10, 10, 10])
    }

    @MainActor
    func testAC_1_7_BarSparklineDrawsOneBarPerNumberFromZero() async throws {
        let webView = try await load("`{{sparkline: 4,8,0,-4 type=bar color=success}}`")
        let result = try await eval(webView, """
        (() => {
          const spark = document.querySelector('.md-widget-spark');
          const bars = Array.from(spark.querySelectorAll('rect'), r =>
            [r.y.baseVal.value, r.height.baseVal.value].map(n => Math.round(n * 100) / 100).join('/'));
          return [spark.className, spark.querySelectorAll('polyline').length, bars.join(' '),
                  getComputedStyle(spark.querySelector('rect')).fill];
        })()
        """) as? [Any]
        XCTAssertEqual(result?[0] as? String, "md-widget-spark md-widget-spark-bar md-widget-c-success")
        XCTAssertEqual(result?[1] as? Int, 0, "no line")
        // Scale -4…8 over 16 units from y 2: zero at 12.67. A zero is a 1-unit
        // sliver; a negative bar hangs below zero.
        XCTAssertEqual(result?[2] as? String, "7.33/5.33 2/10.67 11.67/1 12.67/5.33")
        XCTAssertEqual(result?[3] as? String, "rgb(52, 199, 89)", "bars take the fill shade")
    }

    @MainActor
    func testBarsOfPositiveNumbersStandOnTheBottom() async throws {
        let webView = try await load("`{{sparkline: 2,4 type=BAR}}` `{{sparkline: 0,0 type=bar}}`")
        let bars = try await eval(webView, """
        Array.from(document.querySelectorAll('.md-widget-spark'), s => Array.from(s.querySelectorAll('rect'),
          r => Math.round((r.y.baseVal.value + r.height.baseVal.value) * 100) / 100).join(','))
        """) as? [String]
        XCTAssertEqual(bars, ["18,18", "18,18"], "every bar ends at the bottom; all zeros are slivers there")
    }

    // MARK: Progress (BR-9)

    @MainActor
    func testAC_1_8_InlineProgressIsABarFromAFractionOrAPercent() async throws {
        let webView = try await load("""
        | Feature | Done |
        | --- | --- |
        | Sync | `{{progress: 7/12 color=success}}` |
        | Search | `{{progress: 58%}}` |
        | Import | `{{progress: 15/10}}` |
        """)
        let result = try await eval(webView, """
        Array.from(document.querySelectorAll('td .md-widget-iprogress'), node => {
          const track = node.querySelector('.md-widget-iprogress-track');
          const fill = node.querySelector('.md-widget-fill');
          return [Math.round(fill.getBoundingClientRect().width / track.getBoundingClientRect().width * 100),
                  fill.className, track.getAttribute('aria-valuenow') + '/' + track.getAttribute('aria-valuemax'),
                  node.textContent].join('|');
        })
        """) as? [String]
        XCTAssertEqual(result, [
            "58|md-widget-fill md-widget-c-success|7/12|Progress: 7 / 12",
            "58|md-widget-fill|58/100|Progress: 58 / 100",
            "100|md-widget-fill|15/10|Progress: 15 / 10",
        ], "bar only, the value as hidden text; above the maximum is a full bar")
        let shown = try await eval(webView,
            "getComputedStyle(document.querySelector('.md-widget-iprogress .md-widget-sr')).clipPath") as? String
        XCTAssertEqual(shown, "inset(50%)", "the value text is not shown")
    }

    @MainActor
    func testInlineProgressTextAndStripes() async throws {
        let webView = try await load(
            "`{{progress: 3/4 text=\"{percent} done\" striped=true}}` `{{progress: 4/4 striped=true}}`")
        let result = try await eval(webView, """
        Array.from(document.querySelectorAll('.md-widget-iprogress'), node =>
          [node.querySelector('.md-widget-iprogress-text')?.textContent ?? '',
           node.querySelector('.md-widget-iprogress-track').getAttribute('aria-valuetext') ?? '',
           node.querySelectorAll('.md-widget-fill-striped').length].join('|'))
        """) as? [String]
        XCTAssertEqual(result, ["75% done|75% done|1", "||0"], "text after the bar; a full bar has no stripes")
    }

    @MainActor
    func testInvalidInlineProgressStaysCode() async throws {
        for markdown in ["`{{progress: 7}}`", "`{{progress: 7/0}}`", "`{{progress: -1/4}}`",
                         "`{{progress: x%}}`", "`{{progress: 1/2 striped=yes}}`"] {
            let webView = try await load(markdown)
            let code = try await eval(webView, "document.querySelectorAll('code').length") as? Int
            XCTAssertEqual(code, 1, markdown)
        }
    }

    @MainActor
    func testAProgressBlockStillDraws() async throws {
        let webView = try await load("```progress\nlabel: A\nvalue: 1\nmax: 2\n```\n\nInline `{{progress: 1/2}}`")
        let result = try await eval(webView, """
        [document.querySelectorAll('.md-widget-progress').length, document.querySelectorAll('.md-widget-iprogress').length]
        """) as? [Int]
        XCTAssertEqual(result, [1, 1])
    }

    @MainActor
    func testOneNumberIsNotASparkline() async throws {
        let webView = try await load("`{{sparkline: 5}}`")
        let drawn = try await eval(webView, "document.querySelectorAll('.md-widget-spark').length") as? Int
        XCTAssertEqual(drawn, 0)
    }

    @MainActor
    func testTheValuesStayAsTextForFindCopyAndVoiceOver() async throws {
        let webView = try await load("Signups `{{sparkline: 3,5,2.5,8}}` this week")
        let result = try await eval(webView, """
        [document.querySelector('p').textContent,
         document.querySelector('.md-widget-spark svg').getAttribute('aria-hidden'),
         Math.round(document.querySelector('.md-widget-sr').getBoundingClientRect().width)]
        """) as? [Any]
        XCTAssertEqual(result?[0] as? String, "Signups Sparkline: 3, 5, 2.5, 8 this week")
        XCTAssertEqual(result?[1] as? String, "true")
        XCTAssertEqual(result?[2] as? Int, 1, "not shown")
    }

    // MARK: One list of names

    @MainActor
    func testEveryInlineWidgetHasABuilder() async throws {
        for name in WidgetDocument.inlineWidgets.sorted() {
            let argument = name == "progress" ? "1/2" : "1,2"
            let webView = try await load("`{{\(name): \(argument)}}`")
            let code = try await eval(webView, "document.querySelectorAll('code').length") as? Int
            XCTAssertEqual(code, 0, "`\(name)` has no inline builder in the page script")
        }
    }

    /// The skills' checkers mirror the page; their widget sets must match.
    func testTheSkillCheckersKnowTheSameWidgets() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for skill in ["daisy-widgets", "daisy-slides"] {
            let url = root.appendingPathComponent(".agents/skills/\(skill)/scripts/check_deck.py")
            let source = try String(contentsOf: url, encoding: .utf8)
            func names(_ variable: String) -> Set<String>? {
                guard let line = source.split(separator: "\n").first(where: { $0.hasPrefix(variable + " = {") })
                else { return nil }
                return Set(line.matches(of: #/"([a-z-]+)"/#).map { String($0.1) })
            }
            XCTAssertEqual(names("WIDGETS"), WidgetDocument.widgetLanguages, skill)
            XCTAssertEqual(names("INLINE_WIDGETS"), WidgetDocument.inlineWidgets, skill)
        }
    }
}
