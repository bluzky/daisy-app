//
//  MarkdownHTML+Dashboard.swift
//  daisy
//
//  Dashboard widgets in an ordinary document. A document asks for them with
//  `dashboard: true` in its frontmatter; four fenced blocks then become
//  widgets in the page:
//
//      ```stat      label / value / delta / trend / good / note / link
//      ```chart     type / title / legend / values, then a Markdown table
//      ```progress  label / value / max
//      ```badge     text / status (ok, warn, fail)
//
//  Each block is `key: value` lines; a line of `---` separates items. A chart
//  ends with its table and is drawn by `MdChart`
//  (`MarkdownHTML+DashboardChart.swift`).
//
//  The formatter only stamps `data-md-dashboard` on those fences while the
//  flag is on. The page script draws the widgets from the stamped blocks and
//  leaves any block it cannot read as the plain code block it already is, so
//  other viewers, and a typo, show the source. Extensions never see the
//  frontmatter, which is why the stamp carries the opt-in.
//
//  Colors come from the `--dashboard-*` custom properties in
//  `dashboardStylesheet`. Widgets only ever carry classes, so a theme
//  restyles every widget by setting the properties.
//

import Foundation

nonisolated enum DashboardDocument {

    /// Fence languages that become widgets.
    static let widgetLanguages: Set<String> = ["stat", "chart", "progress", "badge"]

    /// Attribute the formatter stamps on a widget fence's `<pre>`.
    static let stampAttribute = "data-md-dashboard"

    static func isDashboard(frontmatter raw: String?, format: MarkdownFrontmatter.Format?) -> Bool {
        guard let raw, let format else { return false }
        return MarkdownFrontmatter.parse(raw, format: format).contains { entry in
            entry.key.lowercased() == "dashboard"
                && entry.value.trimmingCharacters(in: .whitespaces).lowercased() == "true"
        }
    }
}

/// The dashboard palette: semantic colors every widget reads. Two built-in
/// palettes of standard colors, light and dark; Customize Theme and a slide
/// deck's theme can override a color. Blocks never name a color.
nonisolated enum DashboardColor: String, CaseIterable, Sendable {
    case accent, positive, negative, warning, neutral
    case series1, series2, series3, series4, series5, series6, series7, series8

    static let seriesCount = 8

    /// The chart series colors, in order.
    static let series: [DashboardColor] = [.series1, .series2, .series3, .series4,
                                           .series5, .series6, .series7, .series8]

    /// `--dashboard-accent`, `--dashboard-series-1`, …
    var cssProperty: String {
        if let index = Self.series.firstIndex(of: self) { return "--dashboard-series-\(index + 1)" }
        return "--dashboard-\(rawValue)"
    }

    /// The slide theme `colors:` key: `dashboard_accent`, `dashboard_series_1`, …
    var slideThemeKey: String {
        if let index = Self.series.firstIndex(of: self) { return "dashboard_series_\(index + 1)" }
        return "dashboard_\(rawValue)"
    }

    /// The CSS value a widget uses.
    var cssValue: String { "var(\(cssProperty))" }

    /// Built-in default ("#RRGGBB") in the light or the dark palette.
    func defaultHex(dark: Bool) -> String {
        let pair: (String, String) = switch self {
        // Apple's system colors, one set shared by every widget: the status
        // colors are the same hues as the chart series. Stat deltas, drawn as
        // text, darken them in the light palette (`--dashboard-text-mix`).
        case .accent, .series1: ("#007AFF", "#0A84FF")
        case .positive: ("#34C759", "#30D158")
        case .negative: ("#FF3B30", "#FF453A")
        case .warning: ("#FF9500", "#FF9F0A")
        case .neutral: ("#8E8E93", "#98989D")
        case .series2: ("#FF9500", "#FF9F0A")
        case .series3: ("#30B0C7", "#40C8E0")
        case .series4: ("#AF52DE", "#BF5AF2")
        case .series5: ("#34C759", "#30D158")
        case .series6: ("#FF2D55", "#FF375F")
        case .series7: ("#FFCC00", "#FFD60A")
        case .series8: ("#8E8E93", "#98989D")
        }
        return dark ? pair.1 : pair.0
    }

    /// One palette's declarations, for the dashboard stylesheet.
    static func defaultDeclarations(dark: Bool) -> String {
        allCases.map { "\($0.cssProperty): \($0.defaultHex(dark: dark));" }.joined(separator: " ")
    }
}

nonisolated extension MarkdownHTML {

    /// Draws the dashboard widgets. Always on: a document asks for them with
    /// its frontmatter, so there is no reading preference to toggle. The
    /// script and styles ship in every vendor-loading mode, Quick Look's
    /// `.inline` included, because the script is small and the widgets are
    /// the content.
    struct DashboardExtension: MarkdownRenderExtension {
        let id = "dashboard"
        let descriptor = RenderExtensionDescriptor(
            titleKey: "Dashboard",
            descriptionKey: nil,
            defaultEnabled: true,
            userToggleable: false
        )
        let order = 230

        func isActive(in context: RenderContext) -> Bool {
            context.html.contains(DashboardDocument.stampAttribute)
        }

        func assets(mode _: VendorLoading) -> RenderAssets {
            // The chart library loads first: the widget script's `chart`
            // builder calls it.
            RenderAssets(
                css: MarkdownHTML.dashboardStylesheet + "\n" + MarkdownHTML.dashboardChartStylesheet,
                bodyJS: MarkdownHTML.dashboardChartScript + "\n" + MarkdownHTML.dashboardScript,
                scriptAssetIDs: [id]
            )
        }
    }

    static let dashboardStylesheet = """
    /* Dashboard palette (DashboardColor): semantic colors, one light and one
       dark palette; a slide theme can override them. The stat tile fill
       (`--dashboard-card`) is the code block background's value. Text,
       surface and border follow the page theme. `--dashboard-text-mix` is
       how much of a palette color text keeps when mixed with black: the
       bright colors are too light for text on a light page, fine on a dark
       one. Badges are white text on their status color. */
    :root {
        \(DashboardColor.defaultDeclarations(dark: false))
        --dashboard-text-mix: 65%;
        --dashboard-card: #f9f9f9;
        --dashboard-text: var(--secondary, #6e6e73);
        --dashboard-surface: var(--aside-bg, #f5f5f7);
        --dashboard-border: var(--grid, #d2d2d7);
    }
    :root[data-mdp-color-scheme="dark"] {
        \(DashboardColor.defaultDeclarations(dark: true))
        --dashboard-text-mix: 100%;
        --dashboard-card: #262626;
    }
    @media (prefers-color-scheme: dark) {
        :root:not([data-mdp-color-scheme="light"]) {
            \(DashboardColor.defaultDeclarations(dark: true))
            --dashboard-text-mix: 100%;
            --dashboard-card: #262626;
        }
    }
    .md-dash-stats, .md-dash-progress, .md-dash-badges {
        -webkit-print-color-adjust: exact;
        print-color-adjust: exact;
    }

    /* Stat tiles */
    .md-dash-stats {
        display: flex;
        flex-wrap: wrap;
        gap: 12px;
        margin: 1em 0;
    }
    .md-dash-stat {
        flex: 1 1 160px;
        min-width: 0;
        padding: 14px 16px;
        border: 1px solid var(--dashboard-border);
        border-radius: 10px;
        background: var(--dashboard-card);
    }
    .md-dash-stat-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
    }
    .md-dash-label {
        font-size: 0.95em;
        overflow-wrap: anywhere;
    }
    .md-dash-link {
        display: inline-flex;
        flex: 0 0 auto;
        color: var(--dashboard-text);
        border-radius: 4px;
    }
    .md-dash-link:hover { color: var(--link, currentColor); }
    .md-dash-link svg {
        width: 18px;
        height: 18px;
        fill: none;
        stroke: currentColor;
        stroke-width: 1.8;
        stroke-linecap: round;
        stroke-linejoin: round;
    }
    .md-dash-stat-main {
        display: flex;
        flex-wrap: wrap;
        align-items: baseline;
        gap: 4px 12px;
        margin-top: 6px;
    }
    .md-dash-value {
        font-size: 1.5em;
        font-weight: 600;
        line-height: 1.2;
        font-variant-numeric: tabular-nums;
        overflow-wrap: anywhere;
    }
    .md-dash-delta {
        /* Pushed to the right edge, on the value's line or, when the tile is
           too narrow, on the next one. */
        margin-left: auto;
        font-size: 0.85em;
        font-variant-numeric: tabular-nums;
        white-space: nowrap;
    }
    .md-dash-note {
        margin-top: 2px;
        font-size: 0.8em;
        color: var(--dashboard-text);
    }
    .md-dash-delta.md-dash-good { color: color-mix(in srgb, var(--dashboard-positive) var(--dashboard-text-mix), black); }
    .md-dash-delta.md-dash-bad { color: color-mix(in srgb, var(--dashboard-negative) var(--dashboard-text-mix), black); }
    .md-dash-delta.md-dash-flat { color: color-mix(in srgb, var(--dashboard-neutral) var(--dashboard-text-mix), black); }

    /* Progress */
    .md-dash-progress {
        display: grid;
        gap: 10px;
        margin: 1em 0;
    }
    .md-dash-progress-head {
        display: flex;
        justify-content: space-between;
        gap: 12px;
        font-size: 0.9em;
        font-variant-numeric: tabular-nums;
    }
    .md-dash-progress-head span:last-child { color: var(--dashboard-text); }
    .md-dash-track {
        height: 8px;
        margin-top: 4px;
        border-radius: 4px;
        background: var(--dashboard-surface);
        overflow: hidden;
    }
    .md-dash-fill {
        height: 100%;
        border-radius: 4px;
        background: \(DashboardColor.accent.cssValue);
    }

    /* Badges */
    .md-dash-badges {
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
        margin: 1em 0;
    }
    .md-dash-badge {
        display: inline-block;
        padding: 2px 10px;
        border-radius: 999px;
        font-size: 0.85em;
        font-weight: 600;
        color: #fff;
    }
    .md-dash-badge.md-dash-ok { background: var(--dashboard-positive); }
    .md-dash-badge.md-dash-warn { background: var(--dashboard-warning); }
    .md-dash-badge.md-dash-fail { background: var(--dashboard-negative); }
    """

    /// `ExternalLinkPolicy.blockedSchemes` as a JavaScript array literal: a
    /// stat link is built after the page sanitizer ran, so it checks itself.
    static var blockedSchemesLiteral: String {
        "[" + ExternalLinkPolicy.blockedSchemes.map { "'\($0)'" }.joined(separator: ", ") + "]"
    }

    /// Reads every `pre[data-md-dashboard]` and replaces it with its widget.
    /// A block that does not parse is left alone. Text reaches the page only
    /// through `textContent` and attributes, never `innerHTML`, and colors
    /// only through classes, so a value cannot inject markup or styles.
    static let dashboardScript = #"""
    <script>
    (function() {
      const KEY = /^([A-Za-z][A-Za-z0-9_-]*)\s*:\s*(.*)$/;
      const NUMBER = /^[-+]?(\d+\.?\d*|\.\d+)$/;
      const formatter = new Intl.NumberFormat(undefined, { maximumFractionDigits: 2 });

      function el(tag, cls, text) {
        const node = document.createElement(tag);
        if (cls) node.className = cls;
        if (text != null) node.textContent = text;
        return node;
      }
      function num(text) {
        const t = String(text).replace(/,/g, '').trim();
        return NUMBER.test(t) ? Number(t) : null;
      }

      // `key: value` lines, items split by a line of dashes. Anything else
      // makes the block invalid.
      function parse(source) {
        const items = [{}];
        for (const raw of source.split('\n')) {
          const line = raw.trim();
          if (!line) continue;
          if (/^-{3,}$/.test(line)) {
            if (Object.keys(items[items.length - 1]).length) items.push({});
            continue;
          }
          const match = KEY.exec(line);
          if (!match) return null;
          const key = match[1].toLowerCase();
          const item = items[items.length - 1];
          if (key in item) return null;
          item[key] = match[2].trim();
        }
        if (!Object.keys(items[items.length - 1]).length) items.pop();
        return items.length ? items : null;
      }

      // A link opens like any Markdown link: a URL, a relative file or a
      // `#heading`. Schemes the page never follows make the block invalid.
      const BLOCKED_SCHEMES = \#(blockedSchemesLiteral);
      function safeLink(text) {
        const href = text.trim();
        if (!href || /\s/.test(href)) return null;
        const scheme = /^([a-z][a-z0-9+.-]*):/i.exec(href);
        if (scheme && BLOCKED_SCHEMES.includes(scheme[1].toLowerCase())) return null;
        return href;
      }

      const TREND_ARROWS = { up: '▲ ', down: '▼ ', flat: '▬ ' };
      function arrowIcon() {
        const SVGNS = 'http://www.w3.org/2000/svg';
        const icon = document.createElementNS(SVGNS, 'svg');
        icon.setAttribute('viewBox', '0 0 24 24');
        icon.setAttribute('aria-hidden', 'true');
        const path = document.createElementNS(SVGNS, 'path');
        path.setAttribute('d', 'M5 12h14M13 6l6 6-6 6');
        icon.append(path);
        return icon;
      }

      function stat(source) {
        const items = parse(source);
        if (!items) return null;
        const wrap = el('div', 'md-dash-stats');
        for (const item of items) {
          if (!item.label || !item.value) return null;
          const trend = item.trend ? item.trend.toLowerCase() : '';
          if (trend && !['up', 'down', 'flat'].includes(trend)) return null;
          const good = item.good ? item.good.toLowerCase() : 'up';
          if (!['up', 'down'].includes(good)) return null;
          const href = item.link != null ? safeLink(item.link) : null;
          if (item.link != null && !href) return null;

          const tile = el('div', 'md-dash-stat');
          const head = el('div', 'md-dash-stat-head');
          head.append(el('div', 'md-dash-label', item.label));
          if (href) {
            const link = el('a', 'md-dash-link');
            link.setAttribute('href', href);
            link.setAttribute('title', href);
            link.setAttribute('aria-label', item.label);
            link.append(arrowIcon());
            head.append(link);
          }
          const main = el('div', 'md-dash-stat-main');
          main.append(el('div', 'md-dash-value', item.value));
          // `trend` only decorates a delta: without one it is ignored.
          if (item.delta) {
            let sentiment = 'flat';
            if (trend && trend !== 'flat') {
              sentiment = (trend === 'up') === (good === 'up') ? 'good' : 'bad';
            }
            const arrow = TREND_ARROWS[trend] || '';
            main.append(el('div', 'md-dash-delta md-dash-' + sentiment, arrow + item.delta));
          }
          tile.append(head, main);
          if (item.note) tile.append(el('div', 'md-dash-note', item.note));
          wrap.append(tile);
        }
        return wrap;
      }

      // One bar per item: `label`, `value` (zero or more) and `max` (above
      // zero). A value above its maximum shows a full bar.
      function progress(source) {
        const items = parse(source);
        if (!items) return null;
        const list = el('div', 'md-dash-progress');
        for (const item of items) {
          const value = num(item.value || '');
          const max = num(item.max || '');
          if (!item.label || value == null || max == null || value < 0 || max <= 0) return null;
          const row = el('div', 'md-dash-progress-item');
          const head = el('div', 'md-dash-progress-head');
          head.append(el('span', null, item.label),
                      el('span', null, formatter.format(value) + ' / ' + formatter.format(max)));
          const track = el('div', 'md-dash-track');
          track.setAttribute('role', 'progressbar');
          track.setAttribute('aria-label', item.label);
          track.setAttribute('aria-valuemin', '0');
          track.setAttribute('aria-valuemax', String(max));
          track.setAttribute('aria-valuenow', String(value));
          const fill = el('div', 'md-dash-fill');
          fill.style.width = (Math.min(value / max, 1) * 100) + '%';
          track.append(fill);
          row.append(head, track);
          list.append(row);
        }
        return list;
      }

      function badge(source) {
        const items = parse(source);
        if (!items) return null;
        const wrap = el('div', 'md-dash-badges');
        for (const item of items) {
          const status = (item.status || '').toLowerCase();
          if (!item.text || !['ok', 'warn', 'fail'].includes(status)) return null;
          wrap.append(el('span', 'md-dash-badge md-dash-' + status, item.text));
        }
        return wrap;
      }

      // A chart: `key: value` options, then a Markdown table whose first
      // column holds the labels and every other column a series of numbers.
      // `MdChart` draws it; any type registered there is accepted.
      const LEGENDS = ['top', 'bottom', 'left', 'right', 'none'];
      function cells(line) {
        let row = line.trim();
        if (row.startsWith('|')) row = row.slice(1);
        if (row.endsWith('|')) row = row.slice(0, -1);
        return row.split('|').map(cell => cell.trim());
      }
      function table(rows) {
        if (rows.length < 3) return null;
        const header = cells(rows[0]);
        const rule = cells(rows[1]);
        if (header.length < 2 || rule.length !== header.length) return null;
        if (!rule.every(cell => /^:?-+:?$/.test(cell))) return null;
        const labels = [];
        const series = header.slice(1).map(name => ({ name, values: [] }));
        for (const row of rows.slice(2)) {
          const values = cells(row);
          if (values.length !== header.length) return null;
          labels.push(values[0]);
          for (let i = 1; i < values.length; i++) {
            const value = num(values[i]);
            if (value == null) return null;
            series[i - 1].values.push(value);
          }
        }
        return { labels, series };
      }
      function chart(source) {
        if (!window.MdChart) return null;
        const options = {};
        const rows = [];
        for (const raw of source.split('\n')) {
          const line = raw.trim();
          if (!line) continue;
          if (line.startsWith('|')) { rows.push(line); continue; }
          if (rows.length) return null;
          const match = KEY.exec(line);
          if (!match) return null;
          const key = match[1].toLowerCase();
          if (key in options) return null;
          options[key] = match[2].trim();
        }
        const type = (options.type || '').toLowerCase();
        const legend = (options.legend || 'bottom').toLowerCase();
        const values = (options.values || 'true').toLowerCase();
        if (!MdChart.has(type) || !LEGENDS.includes(legend) || !['true', 'false'].includes(values)) return null;
        const data = table(rows);
        if (!data) return null;
        return MdChart.render({
          type, title: options.title || '', legend, values: values === 'true',
          labels: data.labels, series: data.series
        });
      }

      const BUILDERS = { stat, chart, progress, badge };

      function upgrade(root) {
        const scope = root && root.querySelectorAll ? root : document;
        for (const pre of scope.querySelectorAll('pre[data-md-dashboard]')) {
          const code = pre.querySelector('code');
          const match = code && /(?:^|\s)language-([a-z]+)(?:\s|$)/.exec(code.className);
          const build = match && BUILDERS[match[1]];
          if (!build) continue;
          let node = null;
          try { node = build(code.textContent); } catch (e) { node = null; }
          if (!node) continue;
          for (const attribute of Array.from(pre.attributes)) {
            if (attribute.name.indexOf('data-source') === 0) node.setAttribute(attribute.name, attribute.value);
          }
          // The page wraps every code block in a header with wrap and copy
          // buttons; the widget replaces that frame, not just the `pre`.
          const frame = pre.parentElement && pre.parentElement.classList.contains('md-code-wrap')
            ? pre.parentElement : pre;
          frame.replaceWith(node);
        }
      }

      window.MdPreview?.registerExtension({ id: 'dashboard', render(root) { upgrade(root); } });
    })();
    </script>
    """#
}
