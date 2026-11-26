import AppKit
import WebKit
import XCTest
@testable import MarkdownHelpers

/// Widget previews in the editor with the real widget script on the real
/// editor page (docs/features/editor-widget-previews.md). The editor's rules
/// are covered with a stub in `scripts/editor-bundle/smoke/widget-previews.mjs`;
/// these catch a page, script-order or validity mistake the stub can't.
@MainActor
final class EditorWidgetPreviewTests: XCTestCase {
    private func editor(_ markdown: String, themeCSS: String = "") throws -> WebViewLayoutHarness {
        let script = try TestVendor.script("daisy/Vendor/CodeMirror/mdedit.min.js")
        let html = EditorHTML.render(markdown: markdown, editorJavaScript: script, configuration: .init(
            themeOverrideCSS: themeCSS,
            extensionCSS: MarkdownHTML.editorExtensionCSS(),
            extensionBodyHTML: MarkdownHTML.editorExtensionBodyHTML()
        ))
        return WebViewLayoutHarness(html: html, width: 650, isEditor: true, height: 900)
    }

    func testAC_1_1_and_AC_2_1_statBlockAndBadgeAreDrawnByTheReadModeScript() async throws {
        let harness = try editor("""
        Intro

        ```stat
        label: Revenue
        value: 12,400
        ```

        Status `{{badge: "In review" color=warning}}` today
        """)
        defer { harness.close() }
        _ = try await harness.layout(texts: [], imageCount: 0)
        let result = try await harness.webView.evaluateJavaScript("""
            (() => {
                const stat = document.querySelector('.cm-md-widget-preview .md-widget-stats');
                const badge = document.querySelector('.cm-md-widget-inline .md-widget-badge');
                return [!!stat, stat ? stat.textContent.includes('12,400') : false,
                        !!badge, badge ? badge.textContent : '',
                        document.querySelector('.cm-content').textContent.includes('label: Revenue')];
            })()
            """) as? [Any]
        XCTAssertEqual(result?[0] as? Bool, true, "stat tile drawn")
        XCTAssertEqual(result?[1] as? Bool, true, "stat tile shows its value")
        XCTAssertEqual(result?[2] as? Bool, true, "badge drawn")
        XCTAssertEqual(result?[3] as? String, "In review")
        XCTAssertEqual(result?[4] as? Bool, false, "stat source hidden")
    }

    /// Heading and list lines hang their marker with a negative text-indent;
    /// an inline-block badge or shape must not inherit it (BR-5).
    func testShortcodeTextStaysInsideItsPillInHeadingsAndLists() async throws {
        let harness = try editor("""
        ## `{{shape: 5 style=tint color=danger}}` Review owed

        - innoup #2987 sync · 57d old `{{badge: "idle 0d"}}`
        """)
        defer { harness.close() }
        _ = try await harness.layout(texts: [], imageCount: 0)
        let result = try await harness.webView.evaluateJavaScript("""
            ['.md-widget-shape', '.md-widget-badge'].map(selector => {
                const pill = document.querySelector('.cm-md-widget-inline ' + selector);
                if (!pill) return selector + ' missing';
                const range = document.createRange();
                range.selectNodeContents(pill);
                const text = range.getBoundingClientRect();
                const box = pill.getBoundingClientRect();
                return text.left >= box.left - 0.5 && text.right <= box.right + 0.5
                    ? 'inside' : selector + ' text ' + text.left + '…' + text.right + ' box ' + box.left + '…' + box.right;
            })
            """) as? [String]
        XCTAssertEqual(result, ["inside", "inside"])
    }

    /// CodeMirror's vertical motion steps over block widgets, which only a
    /// page with layout can show.
    func testAC_1_2_arrowKeysMoveIntoADrawnChartFromAboveAndBelow() async throws {
        let harness = try editor("""
        Above

        ```chart
        type: bar
        | Month | Sales |
        | --- | --- |
        | Jan | 10 |
        ```

        Below
        """)
        defer { harness.close() }
        _ = try await harness.layout(texts: [], imageCount: 0)
        let result = try await harness.webView.callAsyncJavaScript("""
            const content = document.querySelector('.cm-content');
            const view = content.cmTile.view;
            const settle = async () => {
                for (let i = 0; i < 12; i++) { window.__layoutTestFrame(); await Promise.resolve(); }
            };
            const results = [];
            // The blank lines next to the block: one key press from its source.
            for (const [line, key, expected] of [[2, 'ArrowDown', 'type: bar'], [9, 'ArrowUp', '| Jan | 10 |']]) {
                view.focus();
                view.dispatch({ selection: { anchor: view.state.doc.line(line).from }, userEvent: 'select' });
                await settle();
                if (!document.querySelector('.cm-md-widget-preview')) return 'not drawn before ' + key;
                content.dispatchEvent(new KeyboardEvent('keydown', { key, code: key, bubbles: true, cancelable: true }));
                await settle();
                const at = view.state.doc.lineAt(view.state.selection.main.head).text;
                const drawn = !!document.querySelector('.cm-md-widget-preview');
                results.push(at === expected && !drawn ? 'pass' : key + ' at "' + at + '" drawn=' + drawn);
            }
            return results.join(', ');
            """, arguments: [:], in: nil, contentWorld: .page) as? String
        XCTAssertEqual(result, "pass, pass")
    }

    /// An unclosed block's last line is source even when it ends like a
    /// fence. Only a quote or list lets text follow an unclosed block.
    func testArrowUpEntersAnUnclosedBlockOnItsLastLine() async throws {
        let harness = try editor("Above\n\n> ```stat\n> value: 1\n> label: A ```\n\nBelow")
        defer { harness.close() }
        _ = try await harness.layout(texts: [], imageCount: 0)
        let result = try await harness.webView.callAsyncJavaScript("""
            const content = document.querySelector('.cm-content');
            const view = content.cmTile.view;
            if (!document.querySelector('.cm-md-widget-preview')) return 'not drawn';
            view.focus();
            view.dispatch({ selection: { anchor: view.state.doc.line(6).from }, userEvent: 'select' });
            for (let i = 0; i < 12; i++) { window.__layoutTestFrame(); await Promise.resolve(); }
            content.dispatchEvent(new KeyboardEvent('keydown',
                { key: 'ArrowUp', code: 'ArrowUp', bubbles: true, cancelable: true }));
            return view.state.doc.lineAt(view.state.selection.main.head).text;
            """, arguments: [:], in: nil, contentWorld: .page) as? String
        XCTAssertEqual(result, "> label: A ```")
    }

    /// Read mode sizes every box as border-box; a stat tile's flex basis
    /// depends on it (BR-5).
    func testStatTilesAreSizedAsInReadMode() async throws {
        let harness = try editor("Intro\n\n```stat\nlabel: A\nvalue: 1\n```\n")
        defer { harness.close() }
        _ = try await harness.layout(texts: [], imageCount: 0)
        let result = try await harness.webView.evaluateJavaScript("""
            getComputedStyle(document.querySelector('.cm-md-widget-preview .md-widget-stat')).boxSizing
            """) as? String
        XCTAssertEqual(result, "border-box")
    }

    func testAC_1_3_invalidProgressBlockStaysCode() async throws {
        let harness = try editor("Intro\n\n```progress\nvalue: 3\ncolor: purple\n```\n\nAfter")
        defer { harness.close() }
        _ = try await harness.layout(texts: [], imageCount: 0)
        let result = try await harness.webView.evaluateJavaScript("""
            [document.querySelector('.cm-md-widget-preview, .md-widget-progress') == null,
             document.querySelector('.cm-content').textContent.includes('color: purple')]
            """) as? [Bool]
        XCTAssertEqual(result, [true, true])
    }

    func testClickingAStatLinkDoesNotNavigateAndRevealsSource() async throws {
        let markdown = "Intro\n\n```stat\nlabel: Docs\nvalue: 3\nlink: https://example.com\n```\n\nAfter"
        let harness = try editor(markdown)
        defer { harness.close() }
        _ = try await harness.layout(texts: [], imageCount: 0)
        let result = try await harness.webView.callAsyncJavaScript("""
            const before = location.href;
            const link = document.querySelector('.cm-md-widget-preview a');
            if (!link) return 'no link';
            const click = new MouseEvent('click', { bubbles: true, cancelable: true });
            link.dispatchEvent(click);
            if (!click.defaultPrevented) return 'click not prevented';
            link.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, cancelable: true, button: 0, detail: 1 }));
            document.dispatchEvent(new MouseEvent('mouseup', { bubbles: true }));
            for (let i = 0; i < 12; i++) { window.__layoutTestFrame(); await Promise.resolve(); }
            if (location.href !== before) return 'navigated';
            return document.querySelector('.cm-md-widget-preview') == null ? 'pass' : 'still drawn';
            """, arguments: [:], in: nil, contentWorld: .page) as? String
        XCTAssertEqual(result, "pass")
    }

    func testAC_2_4_sparklineInTableCellIsDrawnAndEditingShowsSource() async throws {
        let harness = try editor("| Item | Trend |\n| --- | --- |\n| Sales | `{{sparkline: 3,5,2,8}}` |\n")
        defer { harness.close() }
        _ = try await harness.layout(texts: [], imageCount: 0)
        let result = try await harness.webView.callAsyncJavaScript("""
            const cell = document.querySelector('.cm-md-table-cell[data-table-row="1"][data-table-column="1"]');
            const widget = cell && cell.querySelector('.cm-md-widget-inline .md-widget-spark');
            if (!widget) return 'not drawn';
            if (widget.closest('[contenteditable="false"]') == null) return 'widget editable';
            const box = widget.getBoundingClientRect();
            const at = { bubbles: true, cancelable: true, button: 0, detail: 1,
                         clientX: box.left + box.width / 2, clientY: box.top + box.height / 2 };
            widget.dispatchEvent(new MouseEvent('mousedown', at));
            document.dispatchEvent(new MouseEvent('mouseup', at));
            for (let i = 0; i < 12; i++) { window.__layoutTestFrame(); await Promise.resolve(); }
            if (document.activeElement !== cell) return 'cell not focused';
            return cell.textContent === '`{{sparkline: 3,5,2,8}}`' ? 'pass' : 'source not shown: ' + cell.textContent;
            """, arguments: [:], in: nil, contentWorld: .page) as? String
        XCTAssertEqual(result, "pass")
    }

    func testAC_2_4_arrowKeyIntoTheSparklineCellShowsSource() async throws {
        let harness = try editor("| Item | Trend |\n| --- | --- |\n| Sales | `{{sparkline: 3,5,2,8}}` |\n")
        defer { harness.close() }
        _ = try await harness.layout(texts: [], imageCount: 0)
        let result = try await harness.webView.callAsyncJavaScript("""
            const at = column => document.querySelector(
                '.cm-md-table-cell[data-table-row="1"][data-table-column="' + column + '"]');
            const settle = async () => {
                for (let i = 0; i < 12; i++) { window.__layoutTestFrame(); await Promise.resolve(); }
            };
            if (!at(1)?.querySelector('.md-widget-spark')) return 'not drawn';
            const first = at(0);
            first.focus();
            await settle();
            const selection = window.getSelection();
            selection.selectAllChildren(first);
            selection.collapseToEnd();
            first.dispatchEvent(new KeyboardEvent('keydown',
                { key: 'ArrowRight', code: 'ArrowRight', bubbles: true, cancelable: true }));
            await settle();
            const cell = at(1);
            if (document.activeElement !== cell) return 'cell not focused';
            return cell.textContent === '`{{sparkline: 3,5,2,8}}`' ? 'pass' : 'source not shown: ' + cell.textContent;
            """, arguments: [:], in: nil, contentWorld: .page) as? String
        XCTAssertEqual(result, "pass")
    }

    /// AC-1.6's screenshots show the look; this checks the rule that makes it
    /// possible: a theme's dark widget colour beats the widget stylesheet's
    /// dark default on the editor page, as it does in Read mode.
    func testThemeWidgetColorsWinOverWidgetDefaultsInLightAndDark() async throws {
        var colors = ThemeColorsSetting()
        colors.setHex("#112233", .widgetAccent, .light)
        colors.setHex("#445566", .widgetAccent, .dark)
        colors.setHex("#eeeeee", .codeBlockBackground, .light)
        colors.setHex("#222222", .codeBlockBackground, .dark)
        for (dark, accent, card) in [(false, "#112233", "#eeeeee"), (true, "#445566", "#222222")] {
            let harness = try editor("`{{badge: Done color=accent}}`", themeCSS: colors.editorOverrideCSS)
            defer { harness.close() }
            harness.webView.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            _ = try await harness.layout(texts: [], imageCount: 0)
            let values = try await harness.webView.evaluateJavaScript("""
                ['--widget-accent', '--widget-card'].map(name =>
                    getComputedStyle(document.documentElement).getPropertyValue(name).trim())
                """) as? [String]
            XCTAssertEqual(values, [accent, card], "dark=\(dark)")
        }
    }
}
