//
//  MarkdownHTML+Dashboard.swift
//  daisy
//
//  Dashboard widgets in an ordinary document. In any document, four fenced
//  blocks become widgets in the page:
//
//      ```stat      label / value / color / delta / trend / good / note / link
//      ```chart     type / title / legend / values / stacked / direction /
//                   height / grid / colors / x-axis / y-axis; legend, x-axis and
//                   y-axis may be groups of indented `key: value` lines,
//                   then a Markdown table
//      ```progress  label / value / max / color / striped
//      ```badge     text / color
//
//  Each block is `key: value` lines; a line of `---` separates items. A chart
//  ends with its table and is drawn by `MdChart`
//  (`MarkdownHTML+DashboardChart.swift`).
//
//  The formatter stamps `data-md-dashboard` on those fences. The page script
//  draws the widgets from the stamped blocks and leaves any block it cannot
//  read as the plain code block it already is, so other viewers, and a typo,
//  show the source. The extension loads only when a stamp is present.
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
}

/// The dashboard palette: semantic colors every widget reads. Two built-in
/// palettes of standard colors, light and dark; a slide deck's theme can
/// override a color. Stats, progress bars, badges and cards pick one with
/// `color:` by its name (`ColorName`), or take a checked hex instead.
nonisolated enum DashboardColor: String, CaseIterable, Sendable {
    /// `default` is grey; a widget's `color: default` is its normal look.
    case neutral = "default"
    case accent, success, info, warning, danger
    case series1, series2, series3, series4, series5, series6, series7, series8

    static let seriesCount = 8

    /// The names `color:` accepts, in the order the docs list them.
    static let named: [DashboardColor] = [.neutral, .accent, .success, .info, .warning, .danger]

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
        case .success: ("#34C759", "#30D158")
        case .info: ("#30B0C7", "#40C8E0")
        case .warning: ("#FF9500", "#FF9F0A")
        case .danger: ("#FF3B30", "#FF453A")
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

    /// Draws the dashboard widgets. Always on, with no reading preference to
    /// toggle; it activates only when a widget fence is stamped. The
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
       one. Badges are white text on their color, dark on a light hex. */
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
        color: var(--md-dash-ink, inherit);
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
    .md-dash-delta.md-dash-good { color: color-mix(in srgb, \(DashboardColor.success.cssValue) var(--dashboard-text-mix), black); }
    .md-dash-delta.md-dash-bad { color: color-mix(in srgb, \(DashboardColor.danger.cssValue) var(--dashboard-text-mix), black); }
    .md-dash-delta.md-dash-flat { color: color-mix(in srgb, \(DashboardColor.neutral.cssValue) var(--dashboard-text-mix), black); }

    /* `color:` on a stat, progress bar or badge. A palette name is a class
       (`md-dash-c-success`) and a hex a pair of custom properties set by the
       widget script (`md-dash-c-custom`), never a style the block writes.
       `--md-dash-color` is the color for a fill; `--md-dash-ink` the same
       color for text, a palette one darkened on a light page so it stays
       readable, a hex as written. `default` sets nothing: the widget keeps
       its normal look. */
    \(DashboardColor.named.map { "." + "md-dash-c-\($0.rawValue) { --md-dash-color: \($0.cssValue); --md-dash-ink: color-mix(in srgb, \($0.cssValue) var(--dashboard-text-mix), black); }" }.joined(separator: "\n    "))

    /* Progress */
    /* One row per bar: label | bar | value. The rows share the block's grid
       (`display: contents`), so labels, bars and values line up; a long
       label wraps within 40% of the width. */
    .md-dash-progress {
        display: grid;
        grid-template-columns: fit-content(40%) minmax(60px, 1fr) max-content;
        align-items: center;
        gap: 10px 12px;
        margin: 1em 0;
        font-size: 0.9em;
    }
    .md-dash-progress-item { display: contents; }
    .md-dash-progress-value {
        color: var(--dashboard-text);
        font-variant-numeric: tabular-nums;
        text-align: right;
    }
    .md-dash-track {
        height: 12px;
        border-radius: 6px;
        background: var(--dashboard-surface);
        overflow: hidden;
    }
    .md-dash-fill {
        height: 100%;
        border-radius: 6px;
        background: var(--md-dash-color, \(DashboardColor.accent.cssValue));
    }
    /* `striped: true`: diagonal stripes over the fill, moving only while the
       bar is on screen (`md-dash-moving`, set by the widget script). Still
       for Reduce Motion and in print and PDF; every frame looks alike, so a
       still capture never shows a half-drawn state. */
    .md-dash-fill-striped {
        background-image: linear-gradient(45deg,
            rgb(255 255 255 / 28%) 25%, transparent 25%,
            transparent 50%, rgb(255 255 255 / 28%) 50%,
            rgb(255 255 255 / 28%) 75%, transparent 75%, transparent);
        background-size: 16px 16px;
    }
    .md-dash-fill-striped.md-dash-moving {
        animation: md-dash-stripes 1s linear infinite;
    }
    @keyframes md-dash-stripes {
        from { background-position: 0 0; }
        to { background-position: 16px 0; }
    }
    @media (prefers-reduced-motion: reduce) {
        .md-dash-fill-striped.md-dash-moving { animation: none; }
    }
    @media print {
        .md-dash-fill-striped.md-dash-moving { animation: none; }
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
        background: var(--md-dash-color, \(DashboardColor.neutral.cssValue));
    }
    /* A light hex fill takes dark text. */
    .md-dash-badge.md-dash-on-light { color: #1d1d1f; }
    """

    /// The palette names `color:` accepts, as a JavaScript array literal.
    static var colorNamesLiteral: String {
        "[" + DashboardColor.named.map { "'\($0.rawValue)'" }.joined(separator: ", ") + "]"
    }

    /// `ExternalLinkPolicy.blockedSchemes` as a JavaScript array literal: a
    /// stat link is built after the page sanitizer ran, so it checks itself.
    static var blockedSchemesLiteral: String {
        "[" + ExternalLinkPolicy.blockedSchemes.map { "'\($0)'" }.joined(separator: ", ") + "]"
    }

    /// Reads every `pre[data-md-dashboard]` and replaces it with its widget.
    /// A block that does not parse is left alone. Text reaches the page only
    /// through `textContent` and attributes, never `innerHTML`, and colors
    /// only through classes or checked hex custom properties, so a value
    /// cannot inject markup or styles.
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

      // `color:` on a stat, progress bar or badge: a palette name or a hex.
      // `readColor` returns null for anything else, which leaves the block
      // plain. `paint` colors a node by class, or for a hex by custom
      // properties set here, never by a style the block writes; `default`
      // keeps the widget's normal look.
      const COLOR_NAMES = \#(colorNamesLiteral);
      const HEX = /^#(?:[0-9a-f]{3}|[0-9a-f]{6})$/i;
      function readColor(text) {
        if (text == null) return { name: 'default' };
        const value = String(text).trim().toLowerCase();
        if (COLOR_NAMES.includes(value)) return { name: value };
        if (HEX.test(value)) return { hex: value };
        return null;
      }
      function paint(node, color) {
        if (color.name === 'default') return;
        if (color.name) {
          node.classList.add('md-dash-c-' + color.name);
          return;
        }
        node.classList.add('md-dash-c-custom');
        node.style.setProperty('--md-dash-color', color.hex);
        node.style.setProperty('--md-dash-ink', color.hex);
      }
      // Whether a hex is light enough to need dark text on it.
      function isLight(hex) {
        let h = hex.slice(1);
        if (h.length === 3) h = h.split('').map(c => c + c).join('');
        const [r, g, b] = [0, 2, 4].map(i => parseInt(h.slice(i, i + 2), 16));
        return (0.299 * r + 0.587 * g + 0.114 * b) / 255 > 0.62;
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
          // `color` colors the value.
          const color = readColor(item.color);
          if (!color) return null;

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
          const valueNode = el('div', 'md-dash-value', item.value);
          paint(valueNode, color);
          main.append(valueNode);
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
      // zero). A value above its maximum shows a full bar. An optional
      // `color` colors the bar; the default is the accent.
      // `striped: true` adds moving stripes, except on a full bar.
      function progress(source) {
        const items = parse(source);
        if (!items) return null;
        const list = el('div', 'md-dash-progress');
        for (const item of items) {
          const value = num(item.value || '');
          const max = num(item.max || '');
          if (!item.label || value == null || max == null || value < 0 || max <= 0) return null;
          const color = readColor(item.color);
          if (!color) return null;
          const striped = (item.striped || 'false').toLowerCase();
          if (!['true', 'false'].includes(striped)) return null;
          const row = el('div', 'md-dash-progress-item');
          const track = el('div', 'md-dash-track');
          track.setAttribute('role', 'progressbar');
          track.setAttribute('aria-label', item.label);
          track.setAttribute('aria-valuemin', '0');
          track.setAttribute('aria-valuemax', String(max));
          track.setAttribute('aria-valuenow', String(value));
          const fill = el('div', 'md-dash-fill'
            + (striped === 'true' && value < max ? ' md-dash-fill-striped' : ''));
          paint(fill, color);
          fill.style.width = (Math.min(value / max, 1) * 100) + '%';
          track.append(fill);
          row.append(el('span', 'md-dash-progress-label', item.label), track,
                     el('span', 'md-dash-progress-value', formatter.format(value) + ' / ' + formatter.format(max)));
          list.append(row);
        }
        return list;
      }

      // `text`, and an optional `color` for the badge's fill: grey by
      // default; a light hex takes dark text.
      function badge(source) {
        const items = parse(source);
        if (!items) return null;
        const wrap = el('div', 'md-dash-badges');
        for (const item of items) {
          const color = readColor(item.color);
          if (!item.text || !color) return null;
          const node = el('span', 'md-dash-badge', item.text);
          paint(node, color);
          if (color.hex && isLight(color.hex)) node.classList.add('md-dash-on-light');
          wrap.append(node);
        }
        return wrap;
      }

      // A chart: `key: value` options, then a Markdown table whose first
      // column holds the labels and every other column a series of numbers.
      // `MdChart` draws it; any type registered there is accepted.
      const LEGENDS = ['top', 'bottom', 'left', 'right', 'none'];
      const POSITIONS = ['top', 'bottom', 'left', 'right'];
      const GROUPS = ['legend', 'x-axis', 'y-axis'];
      function flag(text, fallback) {
        const value = (text == null ? fallback : text).toLowerCase();
        return value === 'true' ? true : value === 'false' ? false : null;
      }
      // `legend: right` or `legend: none`, or a group with `position` and
      // `visible`. Returns the position, 'none', or null when invalid.
      function legendPosition(option) {
        if (option == null) return 'bottom';
        if (typeof option === 'string') {
          const value = option.toLowerCase();
          return LEGENDS.includes(value) ? value : null;
        }
        const position = (option.position || 'bottom').toLowerCase();
        const visible = flag(option.visible, 'true');
        if (!POSITIONS.includes(position) || visible == null) return null;
        return visible ? position : 'none';
      }
      // `x-axis:` / `y-axis:` groups with `visible`. Null when invalid.
      function axisOptions(option) {
        if (option == null) return { visible: true };
        if (typeof option === 'string') return null;
        const visible = flag(option.visible, 'true');
        return visible == null ? null : { visible };
      }
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
        // A group key with no value (`legend:`) takes the indented
        // `key: value` lines under it.
        let group = null;
        for (const raw of source.split('\n')) {
          const line = raw.trim();
          if (!line) continue;
          if (line.startsWith('|')) { rows.push(line); continue; }
          if (rows.length) return null;
          const match = KEY.exec(line);
          if (!match) return null;
          const key = match[1].toLowerCase();
          const value = match[2].trim();
          if (/^\s/.test(raw)) {
            if (!group || key in group) return null;
            group[key] = value;
            continue;
          }
          if (key in options) return null;
          group = null;
          if (!value && GROUPS.includes(key)) group = options[key] = {};
          else options[key] = value;
        }
        const type = (options.type || '').toLowerCase();
        const legend = legendPosition(options.legend);
        const xAxis = axisOptions(options['x-axis']);
        const yAxis = axisOptions(options['y-axis']);
        if (!legend || !xAxis || !yAxis) return null;
        const values = (options.values || 'true').toLowerCase();
        // `stacked` and `direction` shape a bar chart; other types ignore them.
        const stacked = (options.stacked || 'false').toLowerCase();
        const direction = (options.direction || 'vertical').toLowerCase();
        if (!MdChart.has(type) || !['true', 'false'].includes(values)) return null;
        if (!['true', 'false'].includes(stacked) || !['vertical', 'horizontal'].includes(direction)) return null;
        // `height` in CSS pixels; `grid: false` hides the grid lines.
        const grid = (options.grid || 'true').toLowerCase();
        if (!['true', 'false'].includes(grid)) return null;
        let height = null;
        if (options.height != null) {
          height = num(options.height.replace(/px$/i, ''));
          if (height == null || height < 80 || height > 1200) return null;
        }
        // `colors`: up to eight palette names or `#RGB` / `#RRGGBB`, comma-
        // separated, for the series (or a pie's slices) in order; the rest
        // keep the series palette.
        let colors = null;
        if (options.colors != null) {
          const read = options.colors.split(',').map(readColor);
          if (read.length > 8 || read.some(color => !color)) return null;
          // A palette name becomes its variable; `default` keeps the series color.
          colors = read.map(color => color.hex
            || (color.name === 'default' ? null : 'var(--dashboard-' + color.name + ')'));
        }
        const data = table(rows);
        if (!data) return null;
        return MdChart.render({
          type, title: options.title || '', legend, values: values === 'true',
          stacked: stacked === 'true', direction, height, grid: grid === 'true', xAxis, yAxis, colors,
          labels: data.labels, series: data.series
        });
      }

      const BUILDERS = { stat, chart, progress, badge };

      // Striped fills move only while on screen, so an open document doesn't
      // keep repainting bars nobody can see.
      const motion = 'IntersectionObserver' in window
        ? new IntersectionObserver(entries => {
            for (const entry of entries) {
              if (!entry.target.isConnected) { motion.unobserve(entry.target); continue; }
              entry.target.classList.toggle('md-dash-moving', entry.isIntersecting);
            }
          })
        : null;

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
          for (const fill of node.querySelectorAll('.md-dash-fill-striped')) {
            if (motion) motion.observe(fill); else fill.classList.add('md-dash-moving');
          }
        }
      }

      window.MdPreview?.registerExtension({ id: 'dashboard', render(root) { upgrade(root); } });
    })();
    </script>
    """#
}
