import Foundation
import WebKit
import XCTest

@testable import MarkdownHelpers

final class DashboardTests: XCTestCase {

    private let widgets = """
    ```stat
    label: Revenue
    value: $48.2k
    delta: +12%
    trend: up
    ---
    label: Churn
    value: 2.1%
    delta: -0.4%
    trend: down
    good: down
    ```

    ```progress
    label: Release
    value: 7
    max: 12
    ```

    ```badge
    text: Passing
    status: ok
    ```

    ```chart
    type: bar
    | Month | Sales |
    | ----- | ----- |
    | Jan   | 12    |
    | Feb   | 18    |
    ```
    """

    private func dashboard(_ body: String) -> String {
        "---\ndashboard: true\n---\n\n" + body
    }

    // MARK: Opt-in (BR-1)

    func testAC_1_1_WithoutTheFlagWidgetFencesAreOrdinaryCodeBlocks() {
        let rendered = MarkdownHTML.render(markdown: widgets)
        XCTAssertFalse(rendered.articleHTML.contains("data-md-dashboard"))
        XCTAssertFalse(rendered.html.contains("id: 'dashboard'"), "the script loads only when a widget is stamped")
        XCTAssertFalse(rendered.scriptAssetIDs.contains("dashboard"))
        XCTAssertTrue(rendered.articleHTML.contains("language-stat"))
    }

    func testAC_1_2_WithTheFlagEveryWidgetFenceIsStamped() {
        let rendered = MarkdownHTML.render(markdown: dashboard(widgets))
        XCTAssertEqual(rendered.articleHTML.components(separatedBy: "data-md-dashboard").count - 1, 4,
                       "stat, progress, badge, chart")
        XCTAssertTrue(rendered.scriptAssetIDs.contains("dashboard"))
    }

    func testAC_1_1_FlagOffValuesAndOtherFencesAreNotStamped() {
        let off = MarkdownHTML.render(markdown: "---\ndashboard: false\n---\n\n" + widgets)
        XCTAssertFalse(off.articleHTML.contains("data-md-dashboard"))
        let other = MarkdownHTML.render(markdown: dashboard("```swift\nlet x = 1\n```"))
        XCTAssertFalse(other.articleHTML.contains("data-md-dashboard"))
    }

    func testAC_1_2_DashboardFlagWorksInTomlFrontmatter() {
        let rendered = MarkdownHTML.render(markdown: "+++\ndashboard = true\n+++\n\n```badge\ntext: A\nstatus: ok\n```")
        XCTAssertTrue(rendered.articleHTML.contains("data-md-dashboard"))
    }

    func testAC_5_1_StampedFencesKeepTheirPlainText() {
        let html = MarkdownHTML.render(markdown: dashboard("```stat\nlabel: A\nvalue: 1\n```")).articleHTML
        XCTAssertTrue(html.contains("label: A"))
        XCTAssertFalse(html.contains("hljs"))
    }

    // MARK: Quick Look parity (BR-8)

    func testAC_5_2_ScriptAndStylesShipInEveryVendorLoadingMode() {
        for mode in [MarkdownHTML.VendorLoading.inline, .lazy] {
            let html = MarkdownHTML.render(markdown: dashboard(widgets), vendorLoading: mode).html
            XCTAssertTrue(html.contains(".md-dash-stat"), "styles missing in \(mode)")
            XCTAssertTrue(html.contains("id: 'dashboard'"), "script missing in \(mode)")
        }
    }

    // MARK: The page script

    @MainActor
    private func load(_ markdown: String, mode: MarkdownHTML.VendorLoading = .inline,
                      colorScheme: MarkdownHTML.ColorScheme? = nil) async throws -> WKWebView {
        let rendered = MarkdownHTML.render(markdown: markdown, vendorLoading: mode,
                                           colorScheme: colorScheme)
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

    @MainActor
    private func count(_ markdown: String, _ selector: String) async throws -> Int? {
        let webView = try await load(dashboard(markdown))
        return try await eval(webView, "document.querySelectorAll('\(selector)').length") as? Int
    }

    // MARK: Stat (BR-2, BR-9, BR-12)

    @MainActor
    func testAC_2_1_And_2_2_StatBlockDrawsOneRowOfTiles() async throws {
        let webView = try await load(dashboard(widgets))
        let tiles = try await eval(webView, "document.querySelectorAll('.md-dash-stats .md-dash-stat').length") as? Int
        XCTAssertEqual(tiles, 2)
        let rows = try await eval(webView, "document.querySelectorAll('.md-dash-stats').length") as? Int
        XCTAssertEqual(rows, 1)
        let first = try await eval(webView, "document.querySelector('.md-dash-stat .md-dash-value').textContent") as? String
        XCTAssertEqual(first, "$48.2k")
    }

    @MainActor
    func testAC_2_3_And_2_4_DeltaColorFollowsTrendAndGood() async throws {
        let webView = try await load(dashboard(widgets))
        let classes = try await eval(webView, "Array.from(document.querySelectorAll('.md-dash-delta')).map(n => n.className)") as? [String]
        XCTAssertEqual(classes, ["md-dash-delta md-dash-good", "md-dash-delta md-dash-good"])
        let text = try await eval(webView, "document.querySelectorAll('.md-dash-delta')[0].textContent") as? String
        XCTAssertTrue(try XCTUnwrap(text).contains("\u{25B2}"))

        let swapped = try await load(dashboard("```stat\nlabel: Churn\nvalue: 3%\ndelta: +1%\ntrend: up\ngood: down\n```"))
        let bad = try await eval(swapped, "document.querySelector('.md-dash-delta').className") as? String
        XCTAssertEqual(bad, "md-dash-delta md-dash-bad")
    }

    @MainActor
    func testAC_2_3_DeltaAndTrendAreOptionalAndATrendNeedsADelta() async throws {
        let webView = try await load(dashboard("""
        ```stat
        label: Plain
        value: 1
        ---
        label: Trend only
        value: 2
        trend: up
        ---
        label: Delta only
        value: 3
        delta: +4%
        ```
        """))
        let result = try await eval(webView, """
        Array.from(document.querySelectorAll('.md-dash-stat')).map(tile => {
          const delta = tile.querySelector('.md-dash-delta');
          return delta ? delta.className + '|' + delta.textContent : '';
        })
        """) as? [String]
        XCTAssertEqual(result, ["", "", "md-dash-delta md-dash-flat|+4%"])
    }

    @MainActor
    func testAC_2_5_StatShowsDeltaRightAlignedOnTheValueLineAndAnOptionalNote() async throws {
        let webView = try await load(dashboard("```stat\nlabel: Leads\nvalue: 2,947\ndelta: 21%\ntrend: up\nnote: Accurate growth\n```"))
        let layout = try await eval(webView, """
        (() => {
          const tile = document.querySelector('.md-dash-stat');
          const main = tile.querySelector('.md-dash-stat-main').getBoundingClientRect();
          const value = tile.querySelector('.md-dash-value').getBoundingClientRect();
          const delta = tile.querySelector('.md-dash-delta').getBoundingClientRect();
          const sameLine = delta.top < value.bottom && delta.bottom > value.top;
          const atRightEdge = Math.abs(delta.right - main.right) <= 1;
          return [sameLine && atRightEdge ? 1 : 0, tile.querySelector('.md-dash-note').textContent];
        })()
        """) as? [Any]
        XCTAssertEqual(layout?[0] as? Int, 1, "delta is on the value's line, at the right edge")
        XCTAssertEqual(layout?[1] as? String, "Accurate growth")
        let notes = try await count("```stat\nlabel: A\nvalue: 1\n```", ".md-dash-note")
        XCTAssertEqual(notes, 0)
    }

    @MainActor
    func testAC_2_6_StatLinkIsAnOrdinaryLinkWithAnArrow() async throws {
        let webView = try await load(dashboard("```stat\nlabel: Leads\nvalue: 9\nlink: #sales-by-month\n---\nlabel: Docs\nvalue: 1\nlink: https://example.com/a\n```"))
        let links = try await eval(webView, "Array.from(document.querySelectorAll('.md-dash-stat a.md-dash-link')).map(a => a.getAttribute('href') + '|' + (a.querySelector('svg') ? 'arrow' : ''))") as? [String]
        XCTAssertEqual(links, ["#sales-by-month|arrow", "https://example.com/a|arrow"])
        let none = try await count("```stat\nlabel: A\nvalue: 1\n```", ".md-dash-link")
        XCTAssertEqual(none, 0, "no link, no arrow")
    }

    @MainActor
    func testAC_2_6_ABlockedLinkSchemeLeavesTheBlockPlain() async throws {
        for href in ["javascript:alert(1)", "JavaScript:alert(1)", "data:text/html,x", "file:///etc/hosts"] {
            let drawn = try await count("```stat\nlabel: A\nvalue: 1\nlink: \(href)\n```", ".md-dash-stat")
            XCTAssertEqual(drawn, 0, href)
        }
    }

    // MARK: Progress (BR-4)

    @MainActor
    func testAC_4_1_ProgressFillMatchesTheShare() async throws {
        let webView = try await load(dashboard(widgets))
        let width = try await eval(webView, "document.querySelector('.md-dash-fill').style.width") as? String
        XCTAssertEqual(Double(try XCTUnwrap(width).dropLast()) ?? 0, 7.0 / 12.0 * 100, accuracy: 0.001)
        let valueNow = try await eval(webView, "document.querySelector('[role=progressbar]').getAttribute('aria-valuenow')") as? String
        XCTAssertEqual(valueNow, "7")
        let head = try await eval(webView, "document.querySelector('.md-dash-progress-head').textContent") as? String
        XCTAssertEqual(head, "Release7 / 12")
    }

    @MainActor
    func testAC_4_1_EachProgressItemIsOneBarAndAFullBarCapsAtTheMaximum() async throws {
        let webView = try await load(dashboard("```progress\nlabel: A\nvalue: 3\nmax: 4\n---\nlabel: B\nvalue: 9\nmax: 4\n```"))
        let widths = try await eval(webView, "Array.from(document.querySelectorAll('.md-dash-fill')).map(f => f.style.width)") as? [String]
        XCTAssertEqual(widths, ["75%", "100%"])
    }

    @MainActor
    func testAC_4_1_InvalidProgressStaysPlain() async throws {
        for block in [
            "```progress\nlabel: A\nvalue: 3\n```",
            "```progress\nlabel: A\nvalue: 3\nmax: 0\n```",
            "```progress\nlabel: A\nvalue: -1\nmax: 4\n```",
            "```progress\nlabel: A\nvalue: many\nmax: 4\n```",
            "```progress\nvalue: 1\nmax: 4\n```",
        ] {
            let drawn = try await count(block, ".md-dash-progress")
            XCTAssertEqual(drawn, 0, block)
        }
    }

    // MARK: Badge (BR-5)

    @MainActor
    func testAC_4_2_BadgeShowsItsStatusColorClass() async throws {
        let webView = try await load(dashboard("```badge\ntext: Down\nstatus: fail\n```"))
        let cls = try await eval(webView, "document.querySelector('.md-dash-badge').className") as? String
        XCTAssertEqual(cls, "md-dash-badge md-dash-fail")
    }

    // MARK: Robustness

    @MainActor
    func testAC_5_3_OnlyTheInvalidBlockStaysPlain() async throws {
        let webView = try await load(dashboard("```badge\ntext: Fine\nstatus: ok\n```\n\n```badge\ntext: Broken\nstatus: purple\n```"))
        let drawn = try await eval(webView, "document.querySelectorAll('.md-dash-badge').length") as? Int
        let plain = try await eval(webView, "document.querySelectorAll('pre[data-md-dashboard]').length") as? Int
        XCTAssertEqual(drawn, 1)
        XCTAssertEqual(plain, 1)
    }

    @MainActor
    func testAWidgetReplacesTheCodeBlockFrameWithItsButtons() async throws {
        let webView = try await load(dashboard(widgets))
        let frames = try await eval(webView, "document.querySelectorAll('.md-code-wrap').length") as? Int
        XCTAssertEqual(frames, 0, "valid widgets must not keep the code header, buttons or background")
        let buttons = try await eval(webView, "document.querySelectorAll('.md-code-action').length") as? Int
        XCTAssertEqual(buttons, 0)
        let invalid = try await count("```stat\nlabel: Broken\n```", ".md-code-wrap")
        XCTAssertEqual(invalid, 1, "an invalid block keeps its code frame")
    }

    @MainActor
    func testAuthorTextNeverBecomesMarkup() async throws {
        let webView = try await load(dashboard("```stat\nlabel: <img src=x onerror=alert(1)>\nvalue: <b>9</b>\n```"))
        let injected = try await eval(webView, "document.querySelectorAll('.md-dash-stat img, .md-dash-stat b').length") as? Int
        XCTAssertEqual(injected, 0)
        let label = try await eval(webView, "document.querySelector('.md-dash-label').textContent") as? String
        XCTAssertEqual(label, "<img src=x onerror=alert(1)>")
    }

    @MainActor
    func testAC_5_4_WidgetColorsComeFromTheDashboardPalette() async throws {
        let webView = try await load(dashboard(widgets))
        let colors = try await eval(webView, """
        (() => {
          const root = document.documentElement.style;
          root.setProperty('--dashboard-accent', 'rgb(1, 2, 3)');
          root.setProperty('--dashboard-positive', 'rgb(4, 5, 6)');
          return [getComputedStyle(document.querySelector('.md-dash-fill')).backgroundColor,
                  getComputedStyle(document.querySelector('.md-dash-badge')).backgroundColor,
                  getComputedStyle(document.querySelector('.md-dash-delta')).color];
        })()
        """) as? [String]
        // The badge fill is the positive color; the delta, drawn as text, is
        // that color mixed 65% with black in the light palette.
        XCTAssertEqual(colors, ["rgb(1, 2, 3)", "rgb(4, 5, 6)", "color(srgb 0.010196 0.012745 0.015294)"])
    }

    @MainActor
    func testAC_1_2_WidgetsDrawInLazyMode() async throws {
        let webView = try await load(dashboard(widgets), mode: .lazy)
        let tiles = try await eval(webView, "document.querySelectorAll('.md-dash-stat').length") as? Int
        XCTAssertEqual(tiles, 2)
    }

    // MARK: Chart (BR-3, BR-10, BR-13)

    private func chart(_ type: String, _ options: String, _ table: String) -> String {
        dashboard("```chart\ntype: \(type)\n\(options)\(table)\n```")
    }

    private func chart(_ type: String, _ table: String) -> String {
        chart(type, "", table)
    }

    private let twoSeries = """
    | Month | 2025 | 2026 |
    | ----- | ---- | ---- |
    | Jan   | 12   | 15   |
    | Feb   | 18   | -4   |
    | Mar   | 1,200 | 24  |
    """

    private let shares = """
    | Plan | Users |
    | :--- | ----: |
    | Free | 40 |
    | Pro  | 57 |
    | Team | 3  |
    """

    @MainActor
    func testAC_3_1_BarChartDrawsOneBarPerSeriesForEachRow() async throws {
        let webView = try await load(chart("bar", twoSeries))
        let result = try await eval(webView, """
        [document.querySelectorAll('.md-chart-type-bar .md-chart-bar').length,
         document.querySelectorAll('.md-chart-bar.md-chart-s1').length,
         document.querySelectorAll('.md-chart-bar.md-chart-s2').length,
         getComputedStyle(document.querySelector('.md-chart-bar.md-chart-s1')).fill !==
           getComputedStyle(document.querySelector('.md-chart-bar.md-chart-s2')).fill,
         Array.from(document.querySelectorAll('.md-chart-axes text')).some(t => t.textContent === 'Mar')]
        """) as? [Any]
        XCTAssertEqual(result?[0] as? Int, 6)
        XCTAssertEqual(result?[1] as? Int, 3)
        XCTAssertEqual(result?[2] as? Int, 3)
        XCTAssertEqual(result?[3] as? Bool, true, "each series has its own color")
        XCTAssertEqual(result?[4] as? Bool, true, "row labels under the groups")
    }

    @MainActor
    func testAC_3_1_LineChartDrawsOneLinePerSeries() async throws {
        let webView = try await load(chart("line", twoSeries))
        let result = try await eval(webView, """
        [document.querySelectorAll('.md-chart-line').length,
         document.querySelectorAll('.md-chart-dot').length,
         document.querySelector('.md-chart-line.md-chart-s1').getAttribute('points').split(' ').length]
        """) as? [Int]
        XCTAssertEqual(result, [2, 6, 3])
    }

    @MainActor
    func testAC_3_2_PieChartDrawsOneSlicePerRowSizedByShare() async throws {
        let webView = try await load(chart("pie", shares))
        let result = try await eval(webView, """
        [document.querySelectorAll('.md-chart-slice').length,
         Array.from(document.querySelectorAll('.md-chart-legend li')).map(li => li.textContent).join(','),
         Array.from(document.querySelectorAll('.md-chart-pie-value')).map(t => t.textContent).join(',')]
        """) as? [Any]
        XCTAssertEqual(result?[0] as? Int, 3)
        XCTAssertEqual(result?[1] as? String, "Free,Pro,Team", "a pie's legend names its rows")
        XCTAssertEqual(result?[2] as? String, "40,57", "a slice under 5% has no label")
        // The largest slice (57%) is the only arc drawn the long way round.
        let arcs = try await eval(webView, """
        Array.from(document.querySelectorAll('path.md-chart-slice')).map(p => / 0 1 1 /.test(p.getAttribute('d')))
        """) as? [Bool]
        XCTAssertEqual(arcs, [false, true, false])
    }

    @MainActor
    func testAC_3_3_InvalidChartsStayPlain() async throws {
        let blocks = [
            dashboard("```chart\n| A | N |\n| - | - |\n| x | 3 |\n```"),
            chart("radar", "| A | N |\n| - | - |\n| x | 3 |"),
            chart("bar", "| A | N |\n| - | - |\n| x | lots |"),
            chart("bar", "| A | N |\n| - | - |\n| x | 3 | 4 |"),
            chart("bar", "| A | N |\n| - | - |"),
            chart("bar", "legend: middle\n", "| A | N |\n| - | - |\n| x | 3 |"),
            chart("bar", "values: maybe\n", "| A | N |\n| - | - |\n| x | 3 |"),
            chart("bar", "| A | N |\n| - | - |\n| x | 3 |\ntitle: late"),
            chart("pie", twoSeries),
            chart("pie", "| A | N |\n| - | - |\n| x | 3 |\n| y | -1 |"),
            dashboard("```chart\ntype: bar\n```"),
        ]
        for markdown in blocks {
            let webView = try await load(markdown)
            let drawn = try await eval(webView, "document.querySelectorAll('.md-chart').length") as? Int
            let plain = try await eval(webView, "document.querySelectorAll('pre[data-md-dashboard]').length") as? Int
            XCTAssertEqual(drawn, 0, markdown)
            XCTAssertEqual(plain, 1, markdown)
        }
    }

    @MainActor
    func testAC_3_4_LegendSitsOnTheChosenSide() async throws {
        let positions = ["top": "above", "bottom": "below", "left": "beside-left", "right": "beside-right", "": "below"]
        for (position, expected) in positions {
            let options = position.isEmpty ? "" : "legend: \(position)\n"
            let webView = try await load(chart("bar", options, twoSeries))
            let side = try await eval(webView, """
            (() => {
              const legend = document.querySelector('.md-chart-legend').getBoundingClientRect();
              const plot = document.querySelector('.md-chart-plot').getBoundingClientRect();
              if (legend.bottom <= plot.top) return 'above';
              if (legend.top >= plot.bottom) return 'below';
              if (legend.right <= plot.left) return 'beside-left';
              if (legend.left >= plot.right) return 'beside-right';
              return 'overlap';
            })()
            """) as? String
            XCTAssertEqual(side, expected, "legend: \(position)")
            // Top and bottom legends are one row; side legends a column.
            // No list bullet from the page's `ul` styles.
            let layout = try await eval(webView, """
            (() => {
              const items = Array.from(document.querySelectorAll('.md-chart-legend li'));
              const [a, b] = items.map(li => li.getBoundingClientRect());
              const sameRow = Math.abs(a.top - b.top) < 1 && b.left > a.right;
              const bullet = getComputedStyle(items[0], '::before').content;
              return [sameRow, bullet];
            })()
            """) as? [Any]
            let inRow = position == "left" || position == "right" ? false : true
            XCTAssertEqual(layout?[0] as? Bool, inRow, "legend: \(position) entries in a row")
            XCTAssertEqual(layout?[1] as? String, "none", "legend: \(position) has no bullets")
        }
        let hidden = try await load(chart("bar", "legend: none\n", twoSeries))
        let legends = try await eval(hidden, "document.querySelectorAll('.md-chart-legend').length") as? Int
        XCTAssertEqual(legends, 0)
    }

    @MainActor
    func testAC_3_5_ValuesAreDrawnUnlessTurnedOff() async throws {
        let shown = try await load(chart("bar", twoSeries))
        let labels = try await eval(shown, "Array.from(document.querySelectorAll('.md-chart-value')).map(t => t.textContent)") as? [String]
        XCTAssertEqual(labels?.count, 6)
        XCTAssertTrue(labels?.contains("-4") ?? false)
        let size = try await eval(shown, "getComputedStyle(document.querySelector('.md-chart-value')).fontSize") as? String
        XCTAssertEqual(size, "12px", "value labels keep a fixed size")

        let hidden = try await load(chart("line", "values: false\n", twoSeries))
        let none = try await eval(hidden, "document.querySelectorAll('.md-chart-value').length") as? Int
        XCTAssertEqual(none, 0)
    }

    @MainActor
    func testANewChartTypeRegisteredWithMdChartIsAccepted() async throws {
        let webView = try await load(dashboard(widgets))
        let drawn = try await eval(webView, """
        (() => {
          MdChart.register('dots', {
            draw(svg, spec, kit) {
              spec.series[0].values.forEach((v, i) => kit.svg('circle', { cx: 20 * i + 10, cy: 10, r: 4, class: 'probe' }, svg));
            }
          });
          const figure = MdChart.render({ type: 'dots', title: 'T', legend: 'none', values: true,
                                          labels: ['a', 'b'], series: [{ name: 'n', values: [1, 2] }] });
          return [MdChart.has('dots'), figure.querySelectorAll('.probe').length, MdChart.has('radar')];
        })()
        """) as? [Any]
        XCTAssertEqual(drawn?[0] as? Bool, true)
        XCTAssertEqual(drawn?[1] as? Int, 2)
        XCTAssertEqual(drawn?[2] as? Bool, false)
    }

    @MainActor
    func testAuthorTextInAChartNeverBecomesMarkup() async throws {
        let webView = try await load(chart("bar", "title: <b>T</b>\n", "| A | <i>N</i> |\n| - | - |\n| <img src=x> | 3 |"))
        let injected = try await eval(webView, "document.querySelectorAll('.md-chart b, .md-chart i, .md-chart img').length") as? Int
        XCTAssertEqual(injected, 0)
        let title = try await eval(webView, "document.querySelector('.md-chart-title').textContent") as? String
        XCTAssertEqual(title, "<b>T</b>")
    }

    // MARK: Palette and theming (BR-11, BR-15)

    /// Computed colors of: a progress fill, a good delta, an `ok` badge, a
    /// `warn` badge, chart series 1 and chart series 2.
    private let paletteProbe = """
    [getComputedStyle(document.querySelector('.md-dash-fill')).backgroundColor,
     getComputedStyle(document.querySelector('.md-dash-delta.md-dash-good')).color,
     getComputedStyle(document.querySelector('.md-dash-badge.md-dash-ok')).backgroundColor,
     getComputedStyle(document.querySelector('.md-dash-badge.md-dash-warn')).backgroundColor,
     getComputedStyle(document.querySelector('.md-chart-bar.md-chart-s1')).fill,
     getComputedStyle(document.querySelector('.md-chart-bar.md-chart-s2')).fill]
    """

    private var paletteDocument: String {
        dashboard(widgets + "\n\n```badge\ntext: Hm\nstatus: warn\n```\n\n```chart\ntype: bar\n| A | X | Y |\n| - | - | - |\n| a | 1 | 2 |\n```")
    }

    @MainActor
    func testAC_6_1_WidgetsUseTheLightOrDarkPalette() async throws {
        let light = try await load(paletteDocument, colorScheme: .light)
        let colors = try await eval(light, paletteProbe) as? [String]
        // One set of Apple colors: the warning badge is series 2's orange and
        // the ok badge series 5's green; the good delta is that green
        // darkened for text.
        XCTAssertEqual(colors, ["rgb(0, 122, 255)", "color(srgb 0.132549 0.507255 0.226863)",
                                "rgb(52, 199, 89)", "rgb(255, 149, 0)",
                                "rgb(0, 122, 255)", "rgb(255, 149, 0)"])
        let badgeText = try await eval(light, "getComputedStyle(document.querySelector('.md-dash-badge')).color") as? String
        XCTAssertEqual(badgeText, "rgb(255, 255, 255)")
        let dark = try await load(paletteDocument, colorScheme: .dark)
        let darkColors = try await eval(dark, paletteProbe) as? [String]
        // Dark: delta text keeps the full color.
        XCTAssertEqual(darkColors, ["rgb(10, 132, 255)", "color(srgb 0.188235 0.819608 0.345098)",
                                    "rgb(48, 209, 88)", "rgb(255, 159, 10)",
                                    "rgb(10, 132, 255)", "rgb(255, 159, 10)"])
    }

    @MainActor
    func testEveryThemeFillsStatTilesWithItsCodeBackground() async throws {
        // App theme: a theme's code background (a preset or Customize Theme).
        var overrides = MarkdownHTML.ThemeOverrides()
        overrides.lightCodeBackground = "#E3E1E1"
        overrides.darkCodeBackground = "#37312A"
        for (scheme, expected) in [(MarkdownHTML.ColorScheme.light, "rgb(227, 225, 225)"),
                                   (.dark, "rgb(55, 49, 42)")] {
            let rendered = MarkdownHTML.render(markdown: dashboard("```stat\nlabel: A\nvalue: 1\n```"),
                                               vendorLoading: .inline, colorScheme: scheme,
                                               themeOverrides: overrides)
            let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 700))
            webView.loadHTMLString(rendered.html, baseURL: nil)
            while webView.isLoading { try await Task.sleep(for: .milliseconds(50)) }
            try await Task.sleep(for: .milliseconds(200))
            let fill = try await eval(webView, "getComputedStyle(document.querySelector('.md-dash-stat')).backgroundColor") as? String
            XCTAssertEqual(fill, expected, "\(scheme)")
        }
        // Built-in presets: every preset's code background reaches the tiles.
        for preset in ThemePreset.builtIn {
            guard let css = preset.setting.markdownThemeOverrides?.css,
                  let code = preset.setting.hexValue(.codeBlockBackground, .light) else { continue }
            XCTAssertTrue(css.contains(":root { --dashboard-card: \(code); }"), preset.name)
        }
        // Slide theme: its code background, or the deck's light/dark default.
        let deck = SlideTheme(id: "t", values: SlideYAML.parse("colors:\n  code_background: \"#102030\""))
        XCTAssertTrue(deck.css.contains("--code-bg: #102030; --dashboard-card: #102030;"))
        let dark = SlideTheme(id: "d", values: SlideYAML.parse("appearance: dark"))
        XCTAssertTrue(dark.css.contains("--dashboard-card: #262626;"))
    }

    func testAC_6_5_ASlideThemeSetsTheDashboardPalette() {
        let theme = SlideTheme(id: "t", values: SlideYAML.parse("""
        colors:
          dashboard_accent: "#123456"
          dashboard_series_4: "#abcdef"
          dashboard_bogus: "#000000"
        """))
        XCTAssertTrue(theme.css.contains("--dashboard-accent: #123456;"))
        XCTAssertTrue(theme.css.contains("--dashboard-series-4: #abcdef;"))
        XCTAssertFalse(theme.css.contains("bogus"))
    }

    // MARK: Mermaid still renders in a dashboard

    @MainActor
    func testTheMermaidChartsTheDocsRecommendRender() async throws {
        let markdown = dashboard("""
        ```mermaid
        xychart-beta
            x-axis [Jan, Feb, Mar, Apr]
            y-axis "Sales" 0 --> 30
            bar [12, 18, 15, 24]
            line [7, 9, 8, 11]
        ```

        ```mermaid
        pie title Revenue mix
            "Free" : 40
            "Pro" : 45
            "Enterprise" : 15
        ```
        """)
        let webView = try await load(markdown)
        let deadline = Date().addingTimeInterval(20)
        var drawn = 0
        while Date() < deadline {
            drawn = try await eval(webView, "document.querySelectorAll('.mermaid svg').length") as? Int ?? 0
            if drawn == 2 { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(drawn, 2, "both Mermaid charts render")
        let errors = try await eval(webView, "document.querySelectorAll('.mermaid .error-icon, .mermaid [aria-roledescription=\"error\"]').length") as? Int
        XCTAssertEqual(errors, 0)
    }
}
