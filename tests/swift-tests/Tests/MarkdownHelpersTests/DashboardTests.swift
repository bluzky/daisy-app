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
        XCTAssertEqual(rendered.articleHTML.components(separatedBy: "data-md-dashboard").count - 1, 3,
                       "stat, progress, badge")
        XCTAssertTrue(rendered.scriptAssetIDs.contains("dashboard"))
    }

    func testAC_1_1_FlagOffValuesAndOtherFencesAreNotStamped() {
        let off = MarkdownHTML.render(markdown: "---\ndashboard: false\n---\n\n" + widgets)
        XCTAssertFalse(off.articleHTML.contains("data-md-dashboard"))
        let other = MarkdownHTML.render(markdown: dashboard("```swift\nlet x = 1\n```"))
        XCTAssertFalse(other.articleHTML.contains("data-md-dashboard"))
    }

    func testAChartFenceIsNotAWidget() {
        let html = MarkdownHTML.render(markdown: dashboard("```chart\ntype: bar\n| A | N |\n| - | - |\n| x | 3 |\n```")).articleHTML
        XCTAssertFalse(html.contains("data-md-dashboard"), "charts are Mermaid's job")
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
    private func load(_ markdown: String, mode: MarkdownHTML.VendorLoading = .inline) async throws -> WKWebView {
        let rendered = MarkdownHTML.render(markdown: markdown, vendorLoading: mode)
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
        XCTAssertEqual(colors, ["rgb(1, 2, 3)", "rgb(4, 5, 6)", "rgb(4, 5, 6)"])
    }

    @MainActor
    func testAC_1_2_WidgetsDrawInLazyMode() async throws {
        let webView = try await load(dashboard(widgets), mode: .lazy)
        let tiles = try await eval(webView, "document.querySelectorAll('.md-dash-stat').length") as? Int
        XCTAssertEqual(tiles, 2)
    }

    // MARK: Charts are Mermaid's (docs/dashboard.md recommends these)

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
