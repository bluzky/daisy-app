import Foundation
import WebKit
import XCTest

@testable import MarkdownHelpers

final class WidgetTests: XCTestCase {

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

    Build `{{badge: Passing color=success}}`

    ```chart
    type: bar
    | Month | Sales |
    | ----- | ----- |
    | Jan   | 12    |
    | Feb   | 18    |
    ```
    """

    // MARK: Always on

    func testEveryWidgetFenceIsStampedWithoutFrontmatter() {
        let rendered = MarkdownHTML.render(markdown: widgets)
        XCTAssertEqual(rendered.articleHTML.components(separatedBy: "data-md-widget").count - 1, 4,
                       "stat, progress, the badge shortcode, chart")
        XCTAssertTrue(rendered.scriptAssetIDs.contains("widgets"))
    }

    func testOtherFencesAreNotStampedAndDoNotLoadTheScript() {
        let other = MarkdownHTML.render(markdown: "```swift\nlet x = 1\n```")
        XCTAssertFalse(other.articleHTML.contains("data-md-widget"))
        XCTAssertFalse(other.html.contains("id: 'widgets'"), "the script loads only when a widget is stamped")
        XCTAssertFalse(other.scriptAssetIDs.contains("widgets"))
    }

    func testFrontmatterNoLongerTurnsWidgetsOff() {
        let rendered = MarkdownHTML.render(markdown: "---\ndashboard: false\n---\n\n```stat\nlabel: A\nvalue: 1\n```")
        XCTAssertTrue(rendered.articleHTML.contains("data-md-widget"))
    }

    func testAC_5_1_StampedFencesKeepTheirPlainText() {
        let html = MarkdownHTML.render(markdown: "```stat\nlabel: A\nvalue: 1\n```").articleHTML
        XCTAssertTrue(html.contains("label: A"))
        XCTAssertFalse(html.contains("hljs"))
    }

    // MARK: Quick Look parity (BR-8)

    func testAC_5_2_ScriptAndStylesShipInEveryVendorLoadingMode() {
        for mode in [MarkdownHTML.VendorLoading.inline, .lazy] {
            let html = MarkdownHTML.render(markdown: widgets, vendorLoading: mode).html
            XCTAssertTrue(html.contains(".md-widget-stat"), "styles missing in \(mode)")
            XCTAssertTrue(html.contains("id: 'widgets'"), "script missing in \(mode)")
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
        let webView = try await load(markdown)
        return try await eval(webView, "document.querySelectorAll('\(selector)').length") as? Int
    }

    // MARK: Stat (BR-2, BR-9, BR-12)

    @MainActor
    func testAC_2_1_And_2_2_StatBlockDrawsOneRowOfTiles() async throws {
        let webView = try await load(widgets)
        let tiles = try await eval(webView, "document.querySelectorAll('.md-widget-stats .md-widget-stat').length") as? Int
        XCTAssertEqual(tiles, 2)
        let rows = try await eval(webView, "document.querySelectorAll('.md-widget-stats').length") as? Int
        XCTAssertEqual(rows, 1)
        let first = try await eval(webView, "document.querySelector('.md-widget-stat .md-widget-value').textContent") as? String
        XCTAssertEqual(first, "$48.2k")
    }

    @MainActor
    func testAC_2_3_And_2_4_DeltaColorFollowsTrendAndGood() async throws {
        let webView = try await load(widgets)
        let classes = try await eval(webView, "Array.from(document.querySelectorAll('.md-widget-delta')).map(n => n.className)") as? [String]
        XCTAssertEqual(classes, ["md-widget-delta md-widget-good", "md-widget-delta md-widget-good"])
        let text = try await eval(webView, "document.querySelectorAll('.md-widget-delta')[0].textContent") as? String
        XCTAssertTrue(try XCTUnwrap(text).contains("\u{25B2}"))

        let swapped = try await load("```stat\nlabel: Churn\nvalue: 3%\ndelta: +1%\ntrend: up\ngood: down\n```")
        let bad = try await eval(swapped, "document.querySelector('.md-widget-delta').className") as? String
        XCTAssertEqual(bad, "md-widget-delta md-widget-bad")
    }

    @MainActor
    func testAC_2_3_DeltaAndTrendAreOptionalAndATrendNeedsADelta() async throws {
        let webView = try await load("""
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
        """)
        let result = try await eval(webView, """
        Array.from(document.querySelectorAll('.md-widget-stat')).map(tile => {
          const delta = tile.querySelector('.md-widget-delta');
          return delta ? delta.className + '|' + delta.textContent : '';
        })
        """) as? [String]
        XCTAssertEqual(result, ["", "", "md-widget-delta md-widget-flat|+4%"])
    }

    @MainActor
    func testAC_2_5_StatShowsDeltaRightAlignedOnTheValueLineAndAnOptionalNote() async throws {
        let webView = try await load("```stat\nlabel: Leads\nvalue: 2,947\ndelta: 21%\ntrend: up\nnote: Accurate growth\n```")
        let layout = try await eval(webView, """
        (() => {
          const tile = document.querySelector('.md-widget-stat');
          const main = tile.querySelector('.md-widget-stat-main').getBoundingClientRect();
          const value = tile.querySelector('.md-widget-value').getBoundingClientRect();
          const delta = tile.querySelector('.md-widget-delta').getBoundingClientRect();
          const sameLine = delta.top < value.bottom && delta.bottom > value.top;
          const atRightEdge = Math.abs(delta.right - main.right) <= 1;
          return [sameLine && atRightEdge ? 1 : 0, tile.querySelector('.md-widget-note').textContent];
        })()
        """) as? [Any]
        XCTAssertEqual(layout?[0] as? Int, 1, "delta is on the value's line, at the right edge")
        XCTAssertEqual(layout?[1] as? String, "Accurate growth")
        let notes = try await count("```stat\nlabel: A\nvalue: 1\n```", ".md-widget-note")
        XCTAssertEqual(notes, 0)
    }

    @MainActor
    func testAC_2_6_StatLinkIsAnOrdinaryLinkWithAnArrow() async throws {
        let webView = try await load("```stat\nlabel: Leads\nvalue: 9\nlink: #sales-by-month\n---\nlabel: Docs\nvalue: 1\nlink: https://example.com/a\n```")
        let links = try await eval(webView, "Array.from(document.querySelectorAll('.md-widget-stat a.md-widget-link')).map(a => a.getAttribute('href') + '|' + (a.querySelector('svg') ? 'arrow' : ''))") as? [String]
        XCTAssertEqual(links, ["#sales-by-month|arrow", "https://example.com/a|arrow"])
        let none = try await count("```stat\nlabel: A\nvalue: 1\n```", ".md-widget-link")
        XCTAssertEqual(none, 0, "no link, no arrow")
    }

    @MainActor
    func testAC_2_6_ABlockedLinkSchemeLeavesTheBlockPlain() async throws {
        for href in ["javascript:alert(1)", "JavaScript:alert(1)", "data:text/html,x", "file:///etc/hosts"] {
            let drawn = try await count("```stat\nlabel: A\nvalue: 1\nlink: \(href)\n```", ".md-widget-stat")
            XCTAssertEqual(drawn, 0, href)
        }
    }

    // MARK: Progress (BR-4)

    @MainActor
    func testAC_4_1_ProgressFillMatchesTheShare() async throws {
        let webView = try await load(widgets)
        let width = try await eval(webView, "document.querySelector('.md-widget-fill').style.width") as? String
        XCTAssertEqual(Double(try XCTUnwrap(width).dropLast()) ?? 0, 7.0 / 12.0 * 100, accuracy: 0.001)
        let valueNow = try await eval(webView, "document.querySelector('[role=progressbar]').getAttribute('aria-valuenow')") as? String
        XCTAssertEqual(valueNow, "7")
        let row = try await eval(webView, """
        (() => {
          const item = document.querySelector('.md-widget-progress-item');
          const [label, track, value] = Array.from(item.children);
          const top = el => Math.round(el.getBoundingClientRect().top + el.getBoundingClientRect().height / 2);
          return [item.textContent,
                  track.getAttribute('role'),
                  label.getBoundingClientRect().right <= track.getBoundingClientRect().left,
                  track.getBoundingClientRect().right <= value.getBoundingClientRect().left,
                  Math.abs(top(label) - top(track)) <= 1 && Math.abs(top(value) - top(track)) <= 1];
        })()
        """) as? [Any]
        XCTAssertEqual(row?[0] as? String, "Release7 / 12")
        XCTAssertEqual(row?[1] as? String, "progressbar")
        XCTAssertEqual(row?[2] as? Bool, true, "label left of the bar")
        XCTAssertEqual(row?[3] as? Bool, true, "value right of the bar")
        XCTAssertEqual(row?[4] as? Bool, true, "label, bar and value on one row")
    }

    @MainActor
    func testAC_4_1_EachProgressItemIsOneBarAndAFullBarCapsAtTheMaximum() async throws {
        let webView = try await load("```progress\nlabel: A\nvalue: 3\nmax: 4\n---\nlabel: B\nvalue: 9\nmax: 4\n```")
        let widths = try await eval(webView, "Array.from(document.querySelectorAll('.md-widget-fill')).map(f => f.style.width)") as? [String]
        XCTAssertEqual(widths, ["75%", "100%"])
    }

    @MainActor
    func testProgressColorPicksAPaletteColorAndDefaultsToAccent() async throws {
        let webView = try await load("```progress\nlabel: A\nvalue: 1\nmax: 4\n---\nlabel: B\nvalue: 1\nmax: 4\ncolor: Warning\n```")
        let result = try await eval(webView, """
        Array.from(document.querySelectorAll('.md-widget-fill')).map(fill => {
          const probe = document.createElement('div');
          probe.style.color = getComputedStyle(document.documentElement)
            .getPropertyValue(fill.classList.contains('md-widget-c-warning') ? '--widget-warning' : '--widget-accent');
          document.body.append(probe);
          const expected = getComputedStyle(probe).color;
          probe.remove();
          return fill.className + '|' + (getComputedStyle(fill).backgroundColor === expected);
        })
        """) as? [String]
        XCTAssertEqual(result, ["md-widget-fill|true",
                                "md-widget-fill md-widget-c-warning|true"])
    }

    @MainActor
    func testStripedProgressMovesOnScreenButNotWhenFull() async throws {
        let webView = try await load("```progress\nlabel: A\nvalue: 3\nmax: 4\nstriped: true\n---\nlabel: B\nvalue: 4\nmax: 4\nstriped: true\n---\nlabel: C\nvalue: 1\nmax: 4\n```")
        // The observer reports after layout; give it a frame.
        try await Task.sleep(nanoseconds: 300_000_000)
        let result = try await eval(webView, """
        Array.from(document.querySelectorAll('.md-widget-fill')).map(fill => [
          fill.classList.contains('md-widget-fill-striped'),
          fill.classList.contains('md-widget-moving'),
          getComputedStyle(fill).backgroundImage !== 'none',
          getComputedStyle(fill).animationName
        ].join('|'))
        """) as? [String]
        XCTAssertEqual(result, ["true|true|true|md-widget-stripes",
                                "false|false|false|none",
                                "false|false|false|none"])
    }

    @MainActor
    func testRingShapeDrawsOneRingPerItemWithThePercentInside() async throws {
        let webView = try await load("""
        ```progress
        shape: ring
        label: Revenue
        value: 48
        max: 52
        color: success
        ---
        label: Empty
        value: 0
        max: 10
        ---
        label: Over
        value: 12
        max: 10
        ```
        """)
        let result = try await eval(webView, """
        (() => {
          const rings = Array.from(document.querySelectorAll('.md-widget-ring'));
          return [document.querySelectorAll('.md-widget-progress').length,
                  rings.map(r => r.querySelector('.md-widget-ring-text').textContent).join(','),
                  rings.map(r => r.querySelector('.md-widget-ring-label').textContent).join(','),
                  rings.map(r => { const a = r.querySelector('.md-widget-ring-arc'); return a ? a.getAttribute('stroke-dasharray') : 'none'; }).join(','),
                  rings[0].querySelector('.md-widget-ring-arc').classList.contains('md-widget-c-success'),
                  rings[0].querySelector('[role=progressbar]').getAttribute('aria-valuenow'),
                  rings[0].getBoundingClientRect().top === rings[1].getBoundingClientRect().top];
        })()
        """) as? [Any]
        XCTAssertEqual(result?[0] as? Int, 0, "rings replace the bar rows")
        XCTAssertEqual(result?[1] as? String, "92%,0%,100%", "the percent is rounded and capped at 100%")
        XCTAssertEqual(result?[2] as? String, "Revenue,Empty,Over")
        XCTAssertEqual(result?[3] as? String, "92.3076923076923 100,none,100 100", "no arc at zero, a full arc above max")
        XCTAssertEqual(result?[4] as? Bool, true, "the arc takes the color")
        XCTAssertEqual(result?[5] as? String, "48")
        XCTAssertEqual(result?[6] as? Bool, true, "rings sit side by side")
    }

    @MainActor
    func testTextIsATemplateOnBarsAndRings() async throws {
        let webView = try await load("""
        ```progress
        label: Default
        value: 1200
        max: 1500
        ---
        label: Template
        value: 48
        max: 52
        text: ${value}k of ${max}k
        ---
        label: Literal
        value: 1
        max: 2
        text: On track
        ---
        label: Hidden
        value: 1
        max: 2
        text: none
        ---
        label: Typo
        value: 1
        max: 2
        text: {total}
        ```

        ```progress
        shape: ring
        label: Fraction
        value: 3
        max: 4
        text: {value}/{max}
        ```
        """)
        let result = try await eval(webView, """
        [Array.from(document.querySelectorAll('.md-widget-progress-value')).map(v => v.textContent),
         document.querySelector('.md-widget-ring-text').textContent,
         document.querySelectorAll('.md-widget-track')[1].getAttribute('aria-valuetext'),
         document.querySelectorAll('.md-widget-track')[0].hasAttribute('aria-valuetext')]
        """) as? [Any]
        XCTAssertEqual(result?[0] as? [String], ["1,200 / 1,500", "$48k of $52k", "On track", "", "{total}"],
                       "default, placeholders, literal text, none, and an unknown placeholder kept as typed")
        XCTAssertEqual(result?[1] as? String, "3/4")
        XCTAssertEqual(result?[2] as? String, "$48k of $52k", "custom text is what a screen reader hears")
        XCTAssertEqual(result?[3] as? Bool, false)
    }

    @MainActor
    func testProgressLabelIsOptional() async throws {
        let bars = try await load("```progress\nvalue: 3\nmax: 4\n---\nvalue: 1\nmax: 4\n```")
        let result = try await eval(bars, """
        (() => { const list = document.querySelector('.md-widget-progress');
          return [list.classList.contains('md-widget-progress-unlabelled'),
                  list.querySelectorAll('.md-widget-progress-label').length,
                  list.querySelectorAll('.md-widget-fill').length,
                  list.querySelector('.md-widget-track').hasAttribute('aria-label')] })()
        """) as? [Any]
        XCTAssertEqual(result?[0] as? Bool, true, "no label column")
        XCTAssertEqual(result?[1] as? Int, 0)
        XCTAssertEqual(result?[2] as? Int, 2, "both bars drawn")
        XCTAssertEqual(result?[3] as? Bool, false)

        let mixed = try await load("```progress\nlabel: A\nvalue: 3\nmax: 4\n---\nvalue: 1\nmax: 4\n```")
        let labels = try await eval(mixed, "Array.from(document.querySelectorAll('.md-widget-progress-label')).map(l => l.textContent)") as? [String]
        XCTAssertEqual(labels, ["A", ""], "an empty cell keeps the bars lined up")

        let rings = try await load("```progress\nshape: ring\nvalue: 20\nmax: 100\n```")
        let ring = try await eval(rings, "[document.querySelectorAll('.md-widget-ring').length, document.querySelectorAll('.md-widget-ring-label').length]") as? [Int]
        XCTAssertEqual(ring, [1, 0], "a ring without its name")
    }

    @MainActor
    func testAC_4_1_InvalidProgressStaysPlain() async throws {
        for block in [
            "```progress\nlabel: A\nvalue: 3\n```",
            "```progress\nlabel: A\nvalue: 3\nmax: 0\n```",
            "```progress\nlabel: A\nvalue: -1\nmax: 4\n```",
            "```progress\nlabel: A\nvalue: many\nmax: 4\n```",
            "```progress\nlabel: A\nvalue: 1\nmax: 4\ncolor: #ff00\n```",
            "```progress\nlabel: A\nvalue: 1\nmax: 4\ncolor: purple\n```",
            "```progress\nlabel: A\nvalue: 1\nmax: 4\ncolor: positive\n```",
            "```progress\nlabel: A\nvalue: 1\nmax: 4\nstriped: yes\n```",
            "```progress\nshape: circle\nlabel: A\nvalue: 1\nmax: 4\n```",
            "```progress\nlabel: A\nvalue: 1\nmax: 4\n---\nshape: ring\nlabel: B\nvalue: 1\nmax: 4\n```",
            "```progress\nshape: ring\nlabel: A\nvalue: 1\nmax: 4\nstriped: true\n```",
        ] {
            let drawn = try await count(block, ".md-widget-progress")
            XCTAssertEqual(drawn, 0, block)
        }
    }

    // MARK: Badge (BR-5)

    @MainActor
    func testAC_4_2_BadgeShowsItsColorClass() async throws {
        let webView = try await load("`{{badge: Down color=danger}}` `{{badge: Plain}}`")
        let classes = try await eval(webView, "Array.from(document.querySelectorAll('.md-widget-badge')).map(b => b.className)") as? [String]
        XCTAssertEqual(classes, ["md-widget-badge md-widget-c-danger", "md-widget-badge"], "without a color a badge is grey")
    }

    @MainActor
    func testColorIsOneKeyAcrossStatProgressAndBadge() async throws {
        let webView = try await load("""
        ```stat
        label: Churn
        value: 2.1%
        color: danger
        ---
        label: Custom
        value: 9
        color: #FF00FF
        ---
        label: Plain
        value: 1
        color: default
        ```

        `{{badge: Light color=#ffee00}}` `{{badge: Dark color=#112233}}`
        """, colorScheme: .light)
        let result = try await eval(webView, """
        (() => {
          const values = Array.from(document.querySelectorAll('.md-widget-value'));
          const badges = Array.from(document.querySelectorAll('.md-widget-badge'));
          const label = getComputedStyle(document.querySelector('.md-widget-label')).color;
          return [values[0].className,
                  getComputedStyle(values[1]).color,
                  getComputedStyle(values[2]).color === getComputedStyle(values[2].closest('.md-widget-stat')).color,
                  getComputedStyle(badges[0]).backgroundColor, getComputedStyle(badges[0]).color,
                  getComputedStyle(badges[1]).color];
        })()
        """) as? [Any]
        XCTAssertEqual(result?[0] as? String, "md-widget-value md-widget-c-danger", "a palette name is a class")
        XCTAssertEqual(result?[1] as? String, "rgb(255, 0, 255)", "a hex colors the value exactly")
        XCTAssertEqual(result?[2] as? Bool, true, "`default` keeps the tile's text color")
        XCTAssertEqual(result?[3] as? String, "color(srgb 1 0.933333 0 / 0.18)", "a badge sits on a tint of its color")
        XCTAssertEqual(result?[4] as? String, "color(srgb 0.65 0.606667 0)", "a light hex badge's text is darkened on a light page")
        XCTAssertEqual(result?[5] as? String, "color(srgb 0.043333 0.086667 0.13)")
    }

    @MainActor
    func testNeutralIsAnotherNameForDefault() async throws {
        let webView = try await load("""
        ```stat
        label: A
        value: 1
        color: neutral
        ```

        `{{badge: Plain}}` `{{badge: Neutral color=neutral}}` `{{badge: Default color=default}}`
        """, colorScheme: .light)
        let result = try await eval(webView, """
        (() => {
          const badges = Array.from(document.querySelectorAll('.md-widget-badge'))
            .map(b => getComputedStyle(b).backgroundColor + ' ' + getComputedStyle(b).color);
          return [document.querySelectorAll('.md-widget-stat').length, badges.length, new Set(badges).size];
        })()
        """) as? [Int]
        XCTAssertEqual(result, [1, 3, 1], "`neutral` draws like `default` and like no color")
    }

    @MainActor
    func testInvalidColorsLeaveTheBlockPlain() async throws {
        for block in [
            "```stat\nlabel: A\nvalue: 1\ncolor: red\n```",
            "`{{badge: A color=ok}}`",
            "`{{badge: A color=#12345}}`",
        ] {
            let webView = try await load(block)
            let plain = try await eval(webView, "document.querySelectorAll('[data-md-widget]').length") as? Int
            XCTAssertEqual(plain, 1, block)
        }
    }

    // MARK: Robustness

    @MainActor
    func testAC_5_3_OnlyTheInvalidBlockStaysPlain() async throws {
        let webView = try await load("```stat\nlabel: Fine\nvalue: 1\ncolor: success\n```\n\n```stat\nlabel: Broken\nvalue: 2\ncolor: purple\n```")
        let drawn = try await eval(webView, "document.querySelectorAll('.md-widget-stat').length") as? Int
        let plain = try await eval(webView, "document.querySelectorAll('pre[data-md-widget]').length") as? Int
        XCTAssertEqual(drawn, 1)
        XCTAssertEqual(plain, 1)
    }

    @MainActor
    func testAWidgetReplacesTheCodeBlockFrameWithItsButtons() async throws {
        let webView = try await load(widgets)
        let frames = try await eval(webView, "document.querySelectorAll('.md-code-wrap').length") as? Int
        XCTAssertEqual(frames, 0, "valid widgets must not keep the code header, buttons or background")
        let buttons = try await eval(webView, "document.querySelectorAll('.md-code-action').length") as? Int
        XCTAssertEqual(buttons, 0)
        let invalid = try await count("```stat\nlabel: Broken\n```", ".md-code-wrap")
        XCTAssertEqual(invalid, 1, "an invalid block keeps its code frame")
    }

    @MainActor
    func testAuthorTextNeverBecomesMarkup() async throws {
        let webView = try await load("```stat\nlabel: <img src=x onerror=alert(1)>\nvalue: <b>9</b>\n```")
        let injected = try await eval(webView, "document.querySelectorAll('.md-widget-stat img, .md-widget-stat b').length") as? Int
        XCTAssertEqual(injected, 0)
        let label = try await eval(webView, "document.querySelector('.md-widget-label').textContent") as? String
        XCTAssertEqual(label, "<img src=x onerror=alert(1)>")
    }

    @MainActor
    func testAC_5_4_WidgetColorsComeFromTheWidgetPalette() async throws {
        let webView = try await load(widgets, colorScheme: .light)
        let colors = try await eval(webView, """
        (() => {
          const root = document.documentElement.style;
          root.setProperty('--widget-accent', 'rgb(1, 2, 3)');
          root.setProperty('--widget-success', 'rgb(4, 5, 6)');
          return [getComputedStyle(document.querySelector('.md-widget-fill')).backgroundColor,
                  getComputedStyle(document.querySelector('.md-widget-badge')).backgroundColor,
                  getComputedStyle(document.querySelector('.md-widget-delta')).color];
        })()
        """) as? [String]
        // The badge tint is the success color at 18%; the delta, drawn as text, is
        // that color mixed 65% with black in the light palette.
        XCTAssertEqual(colors, ["rgb(1, 2, 3)", "color(srgb 0.015686 0.019608 0.023529 / 0.18)",
                                "color(srgb 0.010196 0.012745 0.015294)"])
    }

    @MainActor
    func testAC_1_2_WidgetsDrawInLazyMode() async throws {
        let webView = try await load(widgets, mode: .lazy)
        let tiles = try await eval(webView, "document.querySelectorAll('.md-widget-stat').length") as? Int
        XCTAssertEqual(tiles, 2)
    }

    // MARK: Chart (BR-3, BR-10, BR-13)

    private func chart(_ type: String, _ options: String, _ table: String) -> String {
        "```chart\ntype: \(type)\n\(options)\(table)\n```"
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

    private let stackable = """
    | Team | Open | Closed |
    | ---- | ---- | ------ |
    | A    | 10   | 30     |
    | B    | 5    | -2     |
    """

    @MainActor
    func testStackedBarsShareOneBarPerRowAndShowTotals() async throws {
        let webView = try await load(chart("bar", "stacked: true\n", stackable))
        let result = try await eval(webView, """
        (() => {
          const bars = Array.from(document.querySelectorAll('.md-chart-bar'))
            .map(r => ({ x: +r.getAttribute('x'), y: +r.getAttribute('y'),
                         w: +r.getAttribute('width'), h: +r.getAttribute('height') }));
          const [a1, b1, a2, b2] = bars;
          return [bars.length,
                  a1.x === a2.x && b1.x === b2.x,
                  Math.abs(a2.y + a2.h - a1.y) < 0.01,
                  b2.y >= b1.y + b1.h - 0.01,
                  Array.from(document.querySelectorAll('.md-chart-inside-value')).map(t => t.textContent).join(','),
                  Array.from(document.querySelectorAll('.md-chart-values .md-chart-value:not(.md-chart-inside-value)'))
                    .map(t => t.textContent).join(',')];
        })()
        """) as? [Any]
        XCTAssertEqual(result?[0] as? Int, 4)
        XCTAssertEqual(result?[1] as? Bool, true, "a row's series share one bar")
        XCTAssertEqual(result?[2] as? Bool, true, "a positive segment stacks on the one below it")
        XCTAssertEqual(result?[3] as? Bool, true, "a negative segment hangs below zero")
        XCTAssertEqual(result?[4] as? String, "10,5,30")
        XCTAssertEqual(result?[5] as? String, "40,3", "each row's total at the end of its bar")
    }

    @MainActor
    func testHorizontalBarsPutRowsDownTheLeft() async throws {
        let webView = try await load(chart("bar", "direction: horizontal\n", stackable))
        let result = try await eval(webView, """
        (() => {
          const bars = Array.from(document.querySelectorAll('.md-chart-bar'))
            .map(r => ({ x: +r.getAttribute('x'), y: +r.getAttribute('y'),
                         w: +r.getAttribute('width'), h: +r.getAttribute('height') }));
          const label = Array.from(document.querySelectorAll('.md-chart-axes text')).find(t => t.textContent === 'B');
          return [bars.length,
                  bars[2].w > bars[0].w,
                  bars[1].y > bars[0].y,
                  label.getAttribute('text-anchor'),
                  +label.getAttribute('x') < bars[0].x];
        })()
        """) as? [Any]
        XCTAssertEqual(result?[0] as? Int, 4)
        XCTAssertEqual(result?[1] as? Bool, true, "a bar's length is its value (30 > 10)")
        XCTAssertEqual(result?[2] as? Bool, true, "rows run top to bottom")
        XCTAssertEqual(result?[3] as? String, "end")
        XCTAssertEqual(result?[4] as? Bool, true, "row labels sit left of the bars")
    }

    @MainActor
    func testStackedAndDirectionAreIgnoredByLineCharts() async throws {
        let webView = try await load(chart("line", "stacked: true\ndirection: horizontal\n", twoSeries))
        let lines = try await eval(webView, "document.querySelectorAll('.md-chart-line').length") as? Int
        XCTAssertEqual(lines, 2)
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
    func testChartsDrawAtTheirShownWidthSoTextKeepsItsSize() async throws {
        let line = chart("line", twoSeries)
        let webView = try await load("<!-- columns -->\n\n\(line)\n\n<!-- column -->\n\n\(line)\n\n<!-- end-columns -->\n\n\(line)")
        // The resize observer redraws after layout.
        try await Task.sleep(nanoseconds: 400_000_000)
        let result = try await eval(webView, """
        Array.from(document.querySelectorAll('.md-chart-plot')).map(plot =>
          Math.abs(plot.viewBox.baseVal.width - plot.getBoundingClientRect().width) <= 1)
        """) as? [Bool]
        XCTAssertEqual(result, [true, true, true], "one viewBox unit is one CSS pixel")
        let widths = try await eval(webView, """
        Array.from(document.querySelectorAll('.md-chart-plot')).map(plot => Math.round(plot.getBoundingClientRect().width))
        """) as? [Int]
        XCTAssertLessThan(widths?[0] ?? 0, widths?[2] ?? 0, "a column chart is narrower than a full-width one")
    }

    @MainActor
    func testHeightSetsTheChartHeightAndGridFalseKeepsOnlyTheZeroLine() async throws {
        let webView = try await load(chart("bar", "height: 180px\ngrid: false\n", twoSeries)
                                     + "\n\n" + chart("donut", "height: 160\n", shares))
        try await Task.sleep(nanoseconds: 400_000_000)
        let result = try await eval(webView, """
        (() => {
          const [bar, donut] = Array.from(document.querySelectorAll('.md-chart-plot'));
          return [Math.round(bar.getBoundingClientRect().height),
                  bar.querySelectorAll('.md-chart-grid').length,
                  bar.querySelectorAll('.md-chart-zero').length,
                  bar.querySelectorAll('.md-chart-axes text').length > 4,
                  Math.round(donut.getBoundingClientRect().width),
                  Math.round(donut.getBoundingClientRect().height)];
        })()
        """) as? [Any]
        XCTAssertEqual(result?[0] as? Int, 180)
        XCTAssertEqual(result?[1] as? Int, 1, "only the zero line is left")
        XCTAssertEqual(result?[2] as? Int, 1)
        XCTAssertEqual(result?[3] as? Bool, true, "the axis numbers stay")
        XCTAssertEqual(result?[4] as? Int, 160, "a donut's height is its diameter")
        XCTAssertEqual(result?[5] as? Int, 160)
    }

    @MainActor
    func testNestedLegendSetsPositionAndVisibility() async throws {
        let right = try await load(chart("bar", "legend:\n  position: right\n  visible: true\n", twoSeries))
        let side = try await eval(right, "document.querySelector('.md-chart').classList.contains('md-chart-legend-right')") as? Bool
        XCTAssertEqual(side, true)
        let hidden = try await load(chart("bar", "legend:\n  position: right\n  visible: false\n", twoSeries))
        let legends = try await eval(hidden, "document.querySelectorAll('.md-chart-legend').length") as? Int
        XCTAssertEqual(legends, 0)
        let shorthand = try await load(chart("bar", "legend: none\n", twoSeries))
        let none = try await eval(shorthand, "document.querySelectorAll('.md-chart-legend').length") as? Int
        XCTAssertEqual(none, 0, "the one-line form still works")
    }

    @MainActor
    func testHiddenAxesDropTheirLabelsButKeepTheZeroLine() async throws {
        let axisTexts = "Array.from(document.querySelectorAll('.md-chart-axes text')).map(t => t.textContent)"
        let both = try await load(chart("bar", "x-axis:\n  visible: false\ny-axis:\n  visible: false\n", twoSeries))
        let none = try await eval(both, axisTexts) as? [String]
        XCTAssertEqual(none, [])
        let zero = try await eval(both, "document.querySelectorAll('.md-chart-zero').length") as? Int
        XCTAssertEqual(zero, 1)

        // Vertical: x is the rows along the bottom; y the values up the left.
        let noX = try await load(chart("bar", "x-axis:\n  visible: false\n", twoSeries))
        let yOnly = try await eval(noX, axisTexts) as? [String]
        XCTAssertFalse(yOnly?.contains("Jan") ?? true)
        XCTAssertTrue(yOnly?.contains("0") ?? false)

        // Horizontal: y is the rows up the left.
        let noY = try await load(chart("bar", "direction: horizontal\ny-axis:\n  visible: false\n", twoSeries))
        let xOnly = try await eval(noY, axisTexts) as? [String]
        XCTAssertFalse(xOnly?.contains("Jan") ?? true)
        XCTAssertTrue(xOnly?.contains("0") ?? false)
    }

    @MainActor
    func testColorsReplaceTheSeriesColorsInOrder() async throws {
        let webView = try await load(chart("bar", "colors: #ff0000, #0F0\n", twoSeries)
                                     + "\n\n" + chart("donut", "colors: #0000ff\n", shares))
        let result = try await eval(webView, """
        [getComputedStyle(document.querySelector('.md-chart-bar.md-chart-s1')).fill,
         getComputedStyle(document.querySelector('.md-chart-bar.md-chart-s2')).fill,
         getComputedStyle(document.querySelector('.md-chart-swatch.md-chart-s1')).backgroundColor,
         getComputedStyle(document.querySelector('.md-chart-type-donut .md-chart-slice.md-chart-s1')).fill,
         getComputedStyle(document.querySelector('.md-chart-type-donut .md-chart-slice.md-chart-s2')).fill !== 'rgb(0, 0, 255)']
        """) as? [Any]
        XCTAssertEqual(result?[0] as? String, "rgb(255, 0, 0)")
        XCTAssertEqual(result?[1] as? String, "rgb(0, 255, 0)")
        XCTAssertEqual(result?[2] as? String, "rgb(255, 0, 0)", "the legend swatch matches")
        XCTAssertEqual(result?[3] as? String, "rgb(0, 0, 255)", "a donut's first slice")
        XCTAssertEqual(result?[4] as? Bool, true, "slices past the list keep the palette")
    }

    @MainActor
    func testLineRunsFromTheLeftEdgeToTheRightEdge() async throws {
        let webView = try await load(chart("line", twoSeries))
        let result = try await eval(webView, """
        (() => {
          const grid = document.querySelector('.md-chart-grid');
          const dots = Array.from(document.querySelectorAll('.md-chart-dot.md-chart-s1'));
          const label = Array.from(document.querySelectorAll('.md-chart-axes text')).find(t => t.textContent === 'Jan');
          return [+dots[0].getAttribute('cx') === +grid.getAttribute('x1'),
                  +dots[dots.length - 1].getAttribute('cx') === +grid.getAttribute('x2'),
                  +label.getAttribute('x') === +dots[0].getAttribute('cx')];
        })()
        """) as? [Bool]
        XCTAssertEqual(result, [true, true, true], "first point on the left edge, last on the right, labels under the points")
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
    func testDonutDrawsARingOfSlicesWithTheTotalInTheMiddle() async throws {
        let webView = try await load(chart("donut", shares))
        let result = try await eval(webView, """
        [document.querySelectorAll('.md-chart-type-donut path.md-chart-slice').length,
         Array.from(document.querySelectorAll('path.md-chart-slice')).every(p => !p.getAttribute('d').startsWith('M150,150')),
         Array.from(document.querySelectorAll('.md-chart-pie-value')).map(t => t.textContent).join(','),
         document.querySelector('.md-chart-donut-total').textContent,
         Array.from(document.querySelectorAll('.md-chart-legend li')).map(li => li.textContent).join(',')]
        """) as? [Any]
        XCTAssertEqual(result?[0] as? Int, 3)
        XCTAssertEqual(result?[1] as? Bool, true, "slices leave the middle open")
        XCTAssertEqual(result?[2] as? String, "40,57")
        XCTAssertEqual(result?[3] as? String, "100")
        XCTAssertEqual(result?[4] as? String, "Free,Pro,Team")

        let hidden = try await load(chart("donut", "values: false\n", shares))
        let total = try await eval(hidden, "document.querySelectorAll('.md-chart-donut-total').length") as? Int
        XCTAssertEqual(total, 0, "values: false hides the total too")
    }

    @MainActor
    func testAC_3_3_InvalidChartsStayPlain() async throws {
        let blocks = [
            "```chart\n| A | N |\n| - | - |\n| x | 3 |\n```",
            chart("radar", "| A | N |\n| - | - |\n| x | 3 |"),
            chart("bar", "| A | N |\n| - | - |\n| x | lots |"),
            chart("bar", "| A | N |\n| - | - |\n| x | 3 | 4 |"),
            chart("bar", "| A | N |\n| - | - |"),
            chart("bar", "legend: middle\n", "| A | N |\n| - | - |\n| x | 3 |"),
            chart("bar", "values: maybe\n", "| A | N |\n| - | - |\n| x | 3 |"),
            chart("bar", "stacked: yes\n", "| A | N |\n| - | - |\n| x | 3 |"),
            chart("bar", "height: tall\n", "| A | N |\n| - | - |\n| x | 3 |"),
            chart("bar", "height: 20\n", "| A | N |\n| - | - |\n| x | 3 |"),
            chart("bar", "grid: off\n", "| A | N |\n| - | - |\n| x | 3 |"),
            chart("bar", "colors: red\n", "| A | N |\n| - | - |\n| x | 3 |"),
            chart("bar", "colors: #12345, #fff\n", "| A | N |\n| - | - |\n| x | 3 |"),
            chart("bar", "colors: #111, #222, #333, #444, #555, #666, #777, #888, #999\n", "| A | N |\n| - | - |\n| x | 3 |"),
            chart("bar", "colors: #fff;background:url(x)\n", "| A | N |\n| - | - |\n| x | 3 |"),
            chart("bar", "  position: left\n", "| A | N |\n| - | - |\n| x | 3 |"),
            chart("bar", "legend:\n  visible: maybe\n", "| A | N |\n| - | - |\n| x | 3 |"),
            chart("bar", "legend:\n  position: none\n", "| A | N |\n| - | - |\n| x | 3 |"),
            chart("bar", "x-axis: false\n", "| A | N |\n| - | - |\n| x | 3 |"),
            chart("bar", "y-axis:\n  visible: no\n", "| A | N |\n| - | - |\n| x | 3 |"),
            chart("bar", "direction: sideways\n", "| A | N |\n| - | - |\n| x | 3 |"),
            chart("bar", "| A | N |\n| - | - |\n| x | 3 |\ntitle: late"),
            chart("pie", twoSeries),
            chart("donut", twoSeries),
            chart("pie", "| A | N |\n| - | - |\n| x | 3 |\n| y | -1 |"),
            "```chart\ntype: bar\n```",
        ]
        for markdown in blocks {
            let webView = try await load(markdown)
            let drawn = try await eval(webView, "document.querySelectorAll('.md-chart').length") as? Int
            let plain = try await eval(webView, "document.querySelectorAll('pre[data-md-widget]').length") as? Int
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
        XCTAssertEqual(size, "10px", "value labels keep a fixed size")

        let hidden = try await load(chart("line", "values: false\n", twoSeries))
        let none = try await eval(hidden, "document.querySelectorAll('.md-chart-value').length") as? Int
        XCTAssertEqual(none, 0)
    }

    @MainActor
    func testANewChartTypeRegisteredWithMdChartIsAccepted() async throws {
        let webView = try await load(widgets)
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

    /// Computed colors of: a progress fill, a good delta, a `success` badge,
    /// a `warning` badge, chart series 1 and chart series 2.
    private let paletteProbe = """
    [getComputedStyle(document.querySelector('.md-widget-fill')).backgroundColor,
     getComputedStyle(document.querySelector('.md-widget-delta.md-widget-good')).color,
     getComputedStyle(document.querySelector('.md-widget-badge.md-widget-c-success')).backgroundColor,
     getComputedStyle(document.querySelector('.md-widget-badge.md-widget-c-warning')).backgroundColor,
     getComputedStyle(document.querySelector('.md-chart-bar.md-chart-s1')).fill,
     getComputedStyle(document.querySelector('.md-chart-bar.md-chart-s2')).fill]
    """

    private var paletteDocument: String {
        widgets + "\n\n`{{badge: Hm color=warning}}`\n\n```chart\ntype: bar\n| A | X | Y |\n| - | - | - |\n| a | 1 | 2 |\n```"
    }

    @MainActor
    func testAC_6_1_WidgetsUseTheLightOrDarkPalette() async throws {
        let light = try await load(paletteDocument, colorScheme: .light)
        let colors = try await eval(light, paletteProbe) as? [String]
        // One set of Apple colors: the warning badge tints series 2's orange
        // and the ok badge series 5's green; the good delta and the ok
        // badge's text are that green darkened for text.
        XCTAssertEqual(colors, ["rgb(0, 122, 255)", "color(srgb 0.132549 0.507255 0.226863)",
                                "color(srgb 0.203922 0.780392 0.34902 / 0.18)", "color(srgb 1 0.584314 0 / 0.18)",
                                "rgb(0, 122, 255)", "rgb(255, 149, 0)"])
        let badgeText = try await eval(light, "getComputedStyle(document.querySelector('.md-widget-badge')).color") as? String
        XCTAssertEqual(badgeText, "color(srgb 0.132549 0.507255 0.226863)")
        let dark = try await load(paletteDocument, colorScheme: .dark)
        let darkColors = try await eval(dark, paletteProbe) as? [String]
        // Dark: delta text keeps the full color.
        XCTAssertEqual(darkColors, ["rgb(10, 132, 255)", "color(srgb 0.188235 0.819608 0.345098)",
                                    "color(srgb 0.188235 0.819608 0.345098 / 0.18)", "color(srgb 1 0.623529 0.039216 / 0.18)",
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
            let rendered = MarkdownHTML.render(markdown: "```stat\nlabel: A\nvalue: 1\n```",
                                               vendorLoading: .inline, colorScheme: scheme,
                                               themeOverrides: overrides)
            let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 700))
            webView.loadHTMLString(rendered.html, baseURL: nil)
            while webView.isLoading { try await Task.sleep(for: .milliseconds(50)) }
            try await Task.sleep(for: .milliseconds(200))
            let fill = try await eval(webView, "getComputedStyle(document.querySelector('.md-widget-stat')).backgroundColor") as? String
            XCTAssertEqual(fill, expected, "\(scheme)")
        }
        // Built-in presets: every preset's code background reaches the tiles.
        for preset in ThemePreset.builtIn {
            guard let css = preset.setting.markdownThemeOverrides?.css,
                  let code = preset.setting.hexValue(.codeBlockBackground, .light) else { continue }
            XCTAssertTrue(css.contains(":root { --widget-card: \(code); }"), preset.name)
        }
        // Slide theme: its code background, or the deck's light/dark default.
        let deck = Theme(file: Theme.File(id: "t", css: "/* @theme\nappearance: light\n*/ :root { --code-bg: #102030; }"),
                         base: nil)!
        XCTAssertTrue(deck.slideCSS.contains("--code-bg: #102030; --widget-card: #102030;"))
        let dark = Theme(id: "d", name: "D", appearance: .dark)
        XCTAssertTrue(dark.slideCSS.contains("--widget-card: #262626;"))
    }

    func testAC_6_5_ASlideThemeSetsTheWidgetPalette() {
        let theme = Theme(file: Theme.File(id: "t", css: """
        /* @theme
        appearance: light
        */
        :root { --widget-accent: #123456; --widget-series-4: #abcdef; --widget-bogus: #000000; }
        """), base: nil)!
        XCTAssertTrue(theme.slideCSS.contains("--widget-accent: #123456;"))
        XCTAssertTrue(theme.slideCSS.contains("--widget-series-4: #abcdef;"))
        XCTAssertFalse(theme.slideCSS.contains("bogus"))
        // A deck's `theme_overrides:` keep their YAML keys.
        var deck = Theme(id: "o", name: "O", appearance: .light)
        deck.applyOverrides(SlideYAML.parse("colors:\n  widget_accent: \"#654321\""))
        XCTAssertTrue(deck.slideCSS.contains("--widget-accent: #654321;"))
    }

    // MARK: Mermaid still renders beside widgets

    @MainActor
    func testTheMermaidChartsTheDocsRecommendRender() async throws {
        let markdown = """
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
        """
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

    // MARK: Theme widget colors (unified CSS themes, BR-10)

    @MainActor
    func testAC_2_6_accentWidgetColorFromThemeInPageAndSlides() async throws {
        let css = "/* @theme\nname: Brand\nappearance: light\n*/ :root { --widget-accent: #123456; }"
        let catalog = Theme.catalog(builtIns: BuiltInThemes.files, user: [Theme.File(id: "brand", css: css)])
        let brand = try XCTUnwrap(catalog["brand"])
        let overrides = ThemeLibrary.look(for: brand).colors.markdownThemeOverrides
        XCTAssertTrue(try XCTUnwrap(overrides).css.contains(":root { --widget-accent: #123456; }"))

        let rendered = MarkdownHTML.render(markdown: "Text\n", vendorLoading: .lazy, colorScheme: .light,
                                           themeOverrides: overrides)
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 700))
        webView.loadHTMLString(rendered.html, baseURL: nil)
        let deadline = Date().addingTimeInterval(10)
        while webView.isLoading && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        let value = try await webView.evaluateJavaScript(
            "getComputedStyle(document.documentElement).getPropertyValue('--widget-accent').trim()") as? String
        XCTAssertEqual(value?.lowercased(), "#123456", "The page's --widget-accent, which every widget reads")

        let deck = Theme.forDeck(SlideDeckSettings(markdown: "---\nslides: true\ntheme: brand\n---\n"), in: catalog)
        XCTAssertTrue(deck.slideCSS.contains("--widget-accent: #123456"))
    }
}
