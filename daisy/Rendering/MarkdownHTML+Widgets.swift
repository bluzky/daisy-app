//
//  MarkdownHTML+Widgets.swift
//  daisy
//
//  Widgets in an ordinary document. In any document, three fenced
//  blocks become widgets in the page:
//
//      ```stat      label / value / color / delta / trend / good / note / link
//      ```chart     type / title / legend / values / stacked / direction /
//                   height / grid / colors / x-axis / y-axis; legend, x-axis and
//                   y-axis may be groups of indented `key: value` lines,
//                   then a Markdown table
//      ```progress  shape (first item) / label / value / max / color / text /
//                   striped
//
//  Each block is `key: value` lines; a line of `---` separates items. A chart
//  ends with its table and is drawn by `MdChart`
//  (`MarkdownHTML+WidgetChart.swift`).
//
//  Four widgets are inline shortcodes, written as inline code:
//
//      `{{sparkline: 3,5,2,8 color=success}}`   numbers / color / type (line, bar)
//      `{{badge: "In review" color=warning}}`   text / color
//      `{{shape: 1 kind=circle size=lg}}`       1-3 characters / kind / style /
//                                               color / size
//      `{{progress: 7/12 color=success}}`       7/12 or 58% / color / striped /
//                                               text
//
//  `progress` is both a block and a shortcode.
//
//  Arguments are separated by spaces, positional values first, then
//  `key=value`; `"…"` or `'…'` quote a value with spaces, and a value ending
//  in a comma continues into the next one (`3, 5, 2`). Unknown keys and extra
//  positional values are ignored; broken quoting, a missing main value or a
//  bad value for a known key leave the code as it is.
//
//  The formatter stamps `data-md-widget` on those fences and shortcodes.
//  The page script draws the widgets from them and leaves any it cannot
//  read as the plain code it already is, so other viewers, and a typo,
//  show the source. The extension loads only when a stamp is present.
//
//  Colors come from the `--widget-*` custom properties in
//  `widgetStylesheet`. Widgets only ever carry classes, so a theme
//  restyles every widget by setting the properties.
//

import Foundation

nonisolated enum WidgetDocument {

    /// Fence languages that become widgets.
    static let widgetLanguages: Set<String> = ["stat", "chart", "progress"]

    /// Widgets written inline as a shortcode, `` `{{name: arguments}}` ``.
    /// The page script has one inline builder per name.
    static let inlineWidgets: Set<String> = ["sparkline", "badge", "progress", "shape"]

    /// Attribute the formatter stamps on a widget fence's `<pre>` and on a
    /// shortcode's `<code>`.
    static let stampAttribute = "data-md-widget"

    /// Attribute naming the widget on a shortcode's `<code>`.
    static let inlineAttribute = "data-md-inline"

    /// The widget a code span names when its whole text is a shortcode:
    /// `{{name: arguments}}`, the colon right after the name and required.
    /// Nil for any other code, a template's `{{ user.name }}` included. The
    /// arguments are read by the page script, which leaves the code as it is
    /// when they don't parse.
    static func inlineWidgetName(in code: String) -> String? {
        guard code.hasPrefix("{{"), code.hasSuffix("}}"),
              let match = code.wholeMatch(of: #/\{\{\s*([a-z][a-z0-9-]*):(?s:.*)\}\}/#)
        else { return nil }
        let name = String(match.1)
        return inlineWidgets.contains(name) ? name : nil
    }
}

/// The widget palette: semantic colors every widget reads. Two built-in
/// palettes of standard colors, light and dark; a slide deck's theme can
/// override a color. Stats, progress bars, badges and cards pick one with
/// `color:` by its name (`ColorName`), or take a checked hex instead.
nonisolated enum WidgetColor: String, CaseIterable, Sendable {
    /// `default` is grey; a widget's `color: default` is its normal look.
    case neutral = "default"
    case accent, success, info, warning, danger
    case series1, series2, series3, series4, series5, series6, series7, series8

    static let seriesCount = 8

    /// The names `color:` accepts, in the order the docs list them.
    static let named: [WidgetColor] = [.neutral, .accent, .success, .info, .warning, .danger]

    /// Another name `color:` accepts for `default`.
    static let neutralAlias = "neutral"

    /// The palette color a `color:` name means (`neutral` is `default`), or
    /// nil for anything else. Expects a lowercased name.
    static func named(_ name: String) -> WidgetColor? {
        if name == neutralAlias { return .neutral }
        return named.first { $0.rawValue == name }
    }

    /// The chart series colors, in order.
    static let series: [WidgetColor] = [.series1, .series2, .series3, .series4,
                                           .series5, .series6, .series7, .series8]

    /// `--widget-accent`, `--widget-series-1`, …
    var cssProperty: String {
        if let index = Self.series.firstIndex(of: self) { return "--widget-series-\(index + 1)" }
        return "--widget-\(rawValue)"
    }

    /// The slide theme `colors:` key: `widget_accent`, `widget_series_1`, …
    var slideThemeKey: String {
        if let index = Self.series.firstIndex(of: self) { return "widget_series_\(index + 1)" }
        return "widget_\(rawValue)"
    }

    /// The CSS value a widget uses.
    var cssValue: String { "var(\(cssProperty))" }

    /// Built-in default ("#RRGGBB") in the light or the dark palette.
    func defaultHex(dark: Bool) -> String {
        let pair: (String, String) = switch self {
        // Apple's system colors, one set shared by every widget: the status
        // colors are the same hues as the chart series. Stat deltas, drawn as
        // text, darken them in the light palette (`--widget-text-mix`).
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

    /// One palette's declarations, for the widget stylesheet.
    static func defaultDeclarations(dark: Bool) -> String {
        allCases.map { "\($0.cssProperty): \($0.defaultHex(dark: dark));" }.joined(separator: " ")
    }
}

nonisolated extension MarkdownHTML {

    /// Draws the widgets. Always on, with no reading preference to
    /// toggle; it activates only when a widget fence is stamped. The
    /// script and styles ship in every vendor-loading mode, Quick Look's
    /// `.inline` included, because the script is small and the widgets are
    /// the content.
    struct WidgetsExtension: MarkdownRenderExtension {
        let id = "widgets"
        let descriptor = RenderExtensionDescriptor(
            titleKey: "Widgets",
            descriptionKey: nil,
            defaultEnabled: true,
            userToggleable: false
        )
        let order = 230

        func isActive(in context: RenderContext) -> Bool {
            context.html.contains(WidgetDocument.stampAttribute)
        }

        func assets(mode _: VendorLoading) -> RenderAssets {
            // The chart library loads first: the widget script's `chart`
            // builder calls it.
            RenderAssets(
                css: MarkdownHTML.widgetStylesheet + "\n" + MarkdownHTML.widgetChartStylesheet,
                bodyJS: MarkdownHTML.widgetChartScript + "\n" + MarkdownHTML.widgetScript,
                scriptAssetIDs: [id]
            )
        }
    }

    static let widgetStylesheet = """
    /* Widget palette (WidgetColor): semantic colors, one light and one
       dark palette; a slide theme can override them. The stat tile fill
       (`--widget-card`) is the code block background's value. Text,
       surface and border follow the page theme. `--widget-text-mix` is
       how much of a palette color text keeps when mixed with black: the
       bright colors are too light for text on a light page, fine on a dark
       one. A badge is its color as text on a pale tint of the same color. */
    :root {
        \(WidgetColor.defaultDeclarations(dark: false))
        --widget-text-mix: 65%;
        --widget-card: #f9f9f9;
        --widget-text: var(--secondary, #6e6e73);
        --widget-surface: var(--aside-bg, #f5f5f7);
        --widget-border: var(--grid, #d2d2d7);
        /* The empty part of a progress bar or ring: a tint of the text, so it
           shows on the page, in a card and on a slide, light or dark. */
        --widget-track: color-mix(in srgb, currentColor 12%, transparent);
    }
    :root[data-mdp-color-scheme="dark"] {
        \(WidgetColor.defaultDeclarations(dark: true))
        --widget-text-mix: 100%;
        --widget-card: #262626;
    }
    @media (prefers-color-scheme: dark) {
        :root:not([data-mdp-color-scheme="light"]) {
            \(WidgetColor.defaultDeclarations(dark: true))
            --widget-text-mix: 100%;
            --widget-card: #262626;
        }
    }
    .md-widget-stats, .md-widget-progress, .md-widget-rings, .md-widget-badge, .md-widget-spark, .md-widget-iprogress, .md-widget-shape {
        -webkit-print-color-adjust: exact;
        print-color-adjust: exact;
    }

    /* Stat tiles */
    .md-widget-stats {
        display: flex;
        flex-wrap: wrap;
        gap: 12px;
        margin: 1em 0;
    }
    .md-widget-stat {
        flex: 1 1 160px;
        min-width: 0;
        padding: 14px 16px;
        border: 1px solid var(--widget-border);
        border-radius: 10px;
        background: var(--widget-card);
    }
    .md-widget-stat-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 8px;
    }
    .md-widget-label {
        font-size: 0.95em;
        overflow-wrap: anywhere;
    }
    .md-widget-link {
        display: inline-flex;
        flex: 0 0 auto;
        color: var(--widget-text);
        border-radius: 4px;
    }
    .md-widget-link:hover { color: var(--link, currentColor); }
    .md-widget-link svg {
        width: 18px;
        height: 18px;
        fill: none;
        stroke: currentColor;
        stroke-width: 1.8;
        stroke-linecap: round;
        stroke-linejoin: round;
    }
    .md-widget-stat-main {
        display: flex;
        flex-wrap: wrap;
        align-items: baseline;
        gap: 4px 12px;
        margin-top: 6px;
    }
    .md-widget-value {
        color: var(--md-widget-ink, inherit);
        font-size: 1.5em;
        font-weight: 600;
        line-height: 1.2;
        font-variant-numeric: tabular-nums;
        overflow-wrap: anywhere;
    }
    .md-widget-delta {
        /* Pushed to the right edge, on the value's line or, when the tile is
           too narrow, on the next one. */
        margin-left: auto;
        font-size: 0.85em;
        font-variant-numeric: tabular-nums;
        white-space: nowrap;
    }
    .md-widget-note {
        margin-top: 2px;
        font-size: 0.8em;
        color: var(--widget-text);
    }
    .md-widget-delta.md-widget-good { color: color-mix(in srgb, \(WidgetColor.success.cssValue) var(--widget-text-mix), black); }
    .md-widget-delta.md-widget-bad { color: color-mix(in srgb, \(WidgetColor.danger.cssValue) var(--widget-text-mix), black); }
    .md-widget-delta.md-widget-flat { color: color-mix(in srgb, \(WidgetColor.neutral.cssValue) var(--widget-text-mix), black); }

    /* `color:` on a stat, progress bar or badge. A palette name is a class
       (`md-widget-c-success`) and a hex a pair of custom properties set by the
       widget script (`md-widget-c-custom`), never a style the block writes.
       `--md-widget-color` is the color for a fill; `--md-widget-ink` the same
       color for text, a palette one darkened on a light page so it stays
       readable, a hex as written. `default` sets nothing: the widget keeps
       its normal look. */
    \(WidgetColor.named.map { "." + "md-widget-c-\($0.rawValue) { --md-widget-color: \($0.cssValue); --md-widget-ink: color-mix(in srgb, \($0.cssValue) var(--widget-text-mix), black); }" }.joined(separator: "\n    "))

    /* Progress */
    /* One row per bar: label | bar | value. The rows share the block's grid
       (`display: contents`), so labels, bars and values line up; a long
       label wraps within 40% of the width. */
    .md-widget-progress {
        display: grid;
        grid-template-columns: fit-content(40%) minmax(60px, 1fr) max-content;
        align-items: center;
        gap: 10px 12px;
        margin: 1em 0;
        font-size: 0.9em;
    }
    .md-widget-progress-item { display: contents; }
    .md-widget-progress-value {
        color: var(--widget-text);
        font-variant-numeric: tabular-nums;
        text-align: right;
    }
    .md-widget-track {
        height: 12px;
        border-radius: 6px;
        background: var(--widget-track);
        overflow: hidden;
    }
    .md-widget-fill {
        height: 100%;
        border-radius: 6px;
        background: var(--md-widget-color, \(WidgetColor.accent.cssValue));
    }
    /* Rings (`shape: ring`): one per item, side by side and wrapping. The arc
       is the share, drawn with the circle's dash pattern from 12 o'clock; the
       text sits in the middle and shrinks for longer text. Sizes are in em,
       so a ring scales with slide text. */
    .md-widget-rings {
        display: flex;
        flex-wrap: wrap;
        gap: 1em 1.75em;
        margin: 1em 0;
    }
    .md-card-align-center .md-widget-rings { justify-content: center; }
    .md-widget-ring {
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 0.4em;
        width: 7.5em;
        text-align: center;
    }
    .md-widget-ring-meter {
        position: relative;
        width: 6.5em;
        height: 6.5em;
    }
    .md-widget-ring-meter svg { display: block; width: 100%; height: 100%; }
    .md-widget-ring-track {
        fill: none;
        stroke: var(--widget-track);
        stroke-width: 10;
    }
    .md-widget-ring-arc {
        fill: none;
        stroke: var(--md-widget-color, \(WidgetColor.accent.cssValue));
        stroke-width: 10;
        stroke-linecap: round;
    }
    .md-widget-ring-text {
        position: absolute;
        top: 50%;
        left: 0;
        right: 0;
        transform: translateY(-50%);
        padding: 0 0.9em;
        font-size: 1.3em;
        font-weight: 600;
        line-height: 1.2;
        font-variant-numeric: tabular-nums;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
    }
    .md-widget-ring-text-long { font-size: 1.05em; }
    .md-widget-ring-text-xlong { font-size: 0.85em; }
    .md-widget-ring-label {
        font-size: 0.9em;
        line-height: 1.3;
        overflow-wrap: anywhere;
    }
    /* `striped: true`: diagonal stripes over the fill, moving only while the
       bar is on screen (`md-widget-moving`, set by the widget script). Still
       for Reduce Motion and in print and PDF; every frame looks alike, so a
       still capture never shows a half-drawn state. */
    .md-widget-fill-striped {
        background-image: linear-gradient(45deg,
            rgb(255 255 255 / 28%) 25%, transparent 25%,
            transparent 50%, rgb(255 255 255 / 28%) 50%,
            rgb(255 255 255 / 28%) 75%, transparent 75%, transparent);
        background-size: 16px 16px;
    }
    .md-widget-fill-striped.md-widget-moving {
        animation: md-widget-stripes 1s linear infinite;
    }
    @keyframes md-widget-stripes {
        from { background-position: 0 0; }
        to { background-position: 16px 0; }
    }
    @media (prefers-reduced-motion: reduce) {
        .md-widget-fill-striped.md-widget-moving { animation: none; }
    }
    @media print {
        .md-widget-fill-striped.md-widget-moving { animation: none; }
    }

    /* Badges (`{{badge: …}}`), inline in the text */
    .md-widget-badge {
        display: inline-block;
        padding: 0 0.7em;
        border-radius: 999px;
        font-size: 0.85em;
        font-weight: 600;
        line-height: 1.6;
        white-space: nowrap;
        /* Text in the color, darkened on a light page like other colored
           text (a hex too, so a light one stays readable), on a pale tint
           of it. Grey without a color. */
        --md-widget-badge-color: var(--md-widget-color, \(WidgetColor.neutral.cssValue));
        color: color-mix(in srgb, var(--md-widget-badge-color) var(--widget-text-mix), black);
        background: color-mix(in srgb, var(--md-widget-badge-color) 18%, transparent);
    }

    /* Shapes (`{{shape: 1}}`): a circle or rounded square with up to three
       characters in the middle, centered on the line. Sized in em, so a
       shape follows its text: a heading's or a slide's is bigger. `filled`
       is the color with white text (dark text on `warning`); `tint` is a badge's look; `outline` a ring in
       the color. Without a color it is the accent. */
    .md-widget-shape {
        --md-widget-shape-color: var(--md-widget-color, \(WidgetColor.accent.cssValue));
        display: inline-flex;
        align-items: center;
        justify-content: center;
        box-sizing: border-box;
        width: 1.75em;
        height: 1.75em;
        vertical-align: middle;
        border-radius: 50%;
        font-size: 0.9em;
        font-weight: 600;
        line-height: 1;
        font-variant-numeric: tabular-nums;
        white-space: nowrap;
        color: #fff;
        background: var(--md-widget-shape-color);
    }
    /* Warning is too light for white text. */
    .md-widget-shape.md-widget-c-warning:not(.md-widget-shape-tint, .md-widget-shape-outline) { color: #1d1d1f; }
    .md-widget-shape-square { border-radius: 0.3em; }
    .md-widget-shape-tint,
    .md-widget-shape-outline {
        color: color-mix(in srgb, var(--md-widget-shape-color) var(--widget-text-mix), black);
    }
    .md-widget-shape-tint { background: color-mix(in srgb, var(--md-widget-shape-color) 18%, transparent); }
    .md-widget-shape-outline {
        background: transparent;
        border: 0.1em solid var(--md-widget-shape-color);
    }
    .md-widget-shape-sm { font-size: 0.7em; }
    .md-widget-shape-lg { font-size: 1.25em; }
    .md-widget-shape-xl { font-size: 2em; }
    /* Two or three characters step down to fit the shape. */
    .md-widget-shape-2 > span { font-size: 0.8em; }
    .md-widget-shape-3 > span { font-size: 0.6em; letter-spacing: -0.02em; }
    .md-widget-shape-unit { font-size: 0.65em; margin-left: 0.04em; }

    /* Sparklines (`{{sparkline: …}}`): a line the height of the text, on its
       baseline. The stroke keeps its width however the line is scaled. A
       palette color is the darker text shade on a light page (`--md-widget-ink`)
       so a thin line stays visible; without a color it is the accent. */
    .md-widget-spark {
        display: inline-block;
        width: 4.5em;
        height: 1em;
        vertical-align: -0.15em;
    }
    .md-widget-spark svg { display: block; width: 100%; height: 100%; overflow: visible; }
    .md-widget-spark polyline {
        fill: none;
        stroke: var(--md-widget-ink, color-mix(in srgb, \(WidgetColor.accent.cssValue) var(--widget-text-mix), black));
        stroke-width: 1.5;
        stroke-linecap: round;
        stroke-linejoin: round;
        vector-effect: non-scaling-stroke;
    }
    /* `type=bar`: filled bars in the fill shade, like a progress bar. */
    .md-widget-spark rect {
        fill: var(--md-widget-color, \(WidgetColor.accent.cssValue));
    }
    /* Inline progress (`{{progress: 7/12}}`): a bar half the text's height,
       centered on the line, with optional text after it. */
    /* Inline, so the text after the bar keeps the line's baseline. */
    .md-widget-iprogress { white-space: nowrap; }
    .md-widget-iprogress-track {
        display: inline-block;
        width: 5em;
        height: 0.55em;
        vertical-align: middle;
        border-radius: 0.275em;
        background: var(--widget-track);
        overflow: hidden;
    }
    .md-widget-iprogress .md-widget-fill { display: block; border-radius: 0.275em; }
    .md-widget-iprogress .md-widget-fill-striped { background-size: 0.55em 0.55em; }
    .md-widget-iprogress-text {
        margin-left: 0.4em;
        font-size: 0.9em;
        color: var(--widget-text);
        font-variant-numeric: tabular-nums;
        white-space: nowrap;
    }
    /* The values as text, for find, copy and VoiceOver; not shown. */
    .md-widget-sr {
        position: absolute;
        width: 1px;
        height: 1px;
        overflow: hidden;
        clip-path: inset(50%);
        white-space: nowrap;
    }
    """

    /// The palette names `color:` accepts, as a JavaScript array literal.
    static var colorNamesLiteral: String {
        "[" + WidgetColor.named.map { "'\($0.rawValue)'" }.joined(separator: ", ") + "]"
    }

    /// `ExternalLinkPolicy.blockedSchemes` as a JavaScript array literal: a
    /// stat link is built after the page sanitizer ran, so it checks itself.
    static var blockedSchemesLiteral: String {
        "[" + ExternalLinkPolicy.blockedSchemes.map { "'\($0)'" }.joined(separator: ", ") + "]"
    }

    /// Reads every `pre[data-md-widget]` and `code[data-md-inline]` and
    /// replaces it with its widget. One that does not parse is left alone. Text reaches the page only
    /// through `textContent` and attributes, never `innerHTML`, and colors
    /// only through classes or checked hex custom properties, so a value
    /// cannot inject markup or styles.
    static let widgetScript = #"""
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
      const NEUTRAL_ALIAS = '\#(WidgetColor.neutralAlias)';
      const HEX = /^#(?:[0-9a-f]{3}|[0-9a-f]{6})$/i;
      function readColor(text) {
        if (text == null) return { name: 'default' };
        const value = String(text).trim().toLowerCase();
        if (value === NEUTRAL_ALIAS) return { name: 'default' };
        if (COLOR_NAMES.includes(value)) return { name: value };
        if (HEX.test(value)) return { hex: value };
        return null;
      }
      function paint(node, color) {
        if (color.name === 'default') return;
        if (color.name) {
          node.classList.add('md-widget-c-' + color.name);
          return;
        }
        node.classList.add('md-widget-c-custom');
        node.style.setProperty('--md-widget-color', color.hex);
        node.style.setProperty('--md-widget-ink', color.hex);
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
        const wrap = el('div', 'md-widget-stats');
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

          const tile = el('div', 'md-widget-stat');
          const head = el('div', 'md-widget-stat-head');
          head.append(el('div', 'md-widget-label', item.label));
          if (href) {
            const link = el('a', 'md-widget-link');
            link.setAttribute('href', href);
            link.setAttribute('title', href);
            link.setAttribute('aria-label', item.label);
            link.append(arrowIcon());
            head.append(link);
          }
          const main = el('div', 'md-widget-stat-main');
          const valueNode = el('div', 'md-widget-value', item.value);
          paint(valueNode, color);
          main.append(valueNode);
          // `trend` only decorates a delta: without one it is ignored.
          if (item.delta) {
            let sentiment = 'flat';
            if (trend && trend !== 'flat') {
              sentiment = (trend === 'up') === (good === 'up') ? 'good' : 'bad';
            }
            const arrow = TREND_ARROWS[trend] || '';
            main.append(el('div', 'md-widget-delta md-widget-' + sentiment, arrow + item.delta));
          }
          tile.append(head, main);
          if (item.note) tile.append(el('div', 'md-widget-note', item.note));
          wrap.append(tile);
        }
        return wrap;
      }

      // One item per bar or ring: `label`, `value` (zero or more) and `max`
      // (above zero); a value above its maximum shows a full bar or ring.
      // `shape: bar | ring` on the first item sets the whole block's shape.
      // `color` colors the bar or the arc. `text` is what shows beside the
      // bar or inside the ring: a template with `{value}`, `{max}` and
      // `{percent}`, or `none`; by default `{value} / {max}` for a bar and
      // `{percent}` for a ring. `striped: true` adds moving stripes to a bar,
      // except a full one; a ring takes no stripes.
      const SHAPES = ['bar', 'ring'];
      function progressText(template, value, max) {
        const percent = formatter.format(Math.round(Math.min(value / max, 1) * 100)) + '%';
        return template.replace(/\{(value|max|percent)\}/g, (_, key) =>
          key === 'value' ? formatter.format(value) : key === 'max' ? formatter.format(max) : percent);
      }
      function meterAttributes(node, item, value, max, custom) {
        node.setAttribute('role', 'progressbar');
        node.setAttribute('aria-label', item.label);
        node.setAttribute('aria-valuemin', '0');
        node.setAttribute('aria-valuemax', String(max));
        node.setAttribute('aria-valuenow', String(value));
        if (custom) node.setAttribute('aria-valuetext', custom);
      }
      // A ring: the track, and an arc from 12 o'clock as long as the share,
      // drawn with the circle's dash pattern; the text sits in the middle.
      function ringItem(item, share, color, shown, custom, value, max) {
        const SVGNS = 'http://www.w3.org/2000/svg';
        const node = el('div', 'md-widget-ring');
        const meter = el('div', 'md-widget-ring-meter');
        meterAttributes(meter, item, value, max, custom);
        const svg = document.createElementNS(SVGNS, 'svg');
        svg.setAttribute('viewBox', '0 0 100 100');
        svg.setAttribute('aria-hidden', 'true');
        const circle = cls => {
          const c = document.createElementNS(SVGNS, 'circle');
          c.setAttribute('cx', '50');
          c.setAttribute('cy', '50');
          c.setAttribute('r', '42');
          c.setAttribute('class', cls);
          svg.append(c);
          return c;
        };
        circle('md-widget-ring-track');
        if (share > 0) {
          const arc = circle('md-widget-ring-arc');
          arc.setAttribute('pathLength', '100');
          arc.setAttribute('stroke-dasharray', (share * 100) + ' 100');
          arc.setAttribute('transform', 'rotate(-90 50 50)');
          paint(arc, color);
        }
        const size = shown.length > 6 ? ' md-widget-ring-text-xlong' : shown.length > 4 ? ' md-widget-ring-text-long' : '';
        meter.append(svg, el('div', 'md-widget-ring-text' + size, shown));
        node.append(meter, el('div', 'md-widget-ring-label', item.label));
        return node;
      }
      function progress(source) {
        const items = parse(source);
        if (!items) return null;
        const shape = (items[0].shape || 'bar').toLowerCase();
        if (!SHAPES.includes(shape) || items.slice(1).some(item => 'shape' in item)) return null;
        const ring = shape === 'ring';
        const list = el('div', ring ? 'md-widget-rings' : 'md-widget-progress');
        for (const item of items) {
          const value = num(item.value || '');
          const max = num(item.max || '');
          if (!item.label || value == null || max == null || value < 0 || max <= 0) return null;
          const color = readColor(item.color);
          if (!color) return null;
          const striped = (item.striped || 'false').toLowerCase();
          if (!['true', 'false'].includes(striped) || (ring && striped === 'true')) return null;
          const template = item.text != null ? item.text : (ring ? '{percent}' : '{value} / {max}');
          const shown = template.trim().toLowerCase() === 'none' ? '' : progressText(template, value, max);
          const custom = item.text != null ? shown : null;
          const share = Math.min(value / max, 1);
          if (ring) {
            list.append(ringItem(item, share, color, shown, custom, value, max));
            continue;
          }
          const row = el('div', 'md-widget-progress-item');
          const track = el('div', 'md-widget-track');
          meterAttributes(track, item, value, max, custom);
          const fill = el('div', 'md-widget-fill'
            + (striped === 'true' && value < max ? ' md-widget-fill-striped' : ''));
          paint(fill, color);
          fill.style.width = (share * 100) + '%';
          track.append(fill);
          // An empty value cell keeps the block's columns lined up.
          row.append(el('span', 'md-widget-progress-label', item.label), track,
                     el('span', 'md-widget-progress-value', shown));
          list.append(row);
        }
        return list;
      }

      // Shortcode arguments: `{{name: arguments}}` in inline code. Separated
      // by spaces; `"…"` or `'…'` quote a value with spaces (no escapes); a
      // value ending in an unquoted comma continues into the next, so
      // `3, 5, 2` is one value. `key=value` is an option, anything else a
      // positional value. Null for an unclosed quote or an empty, malformed
      // or repeated key; a builder ignores what it doesn't take.
      const SHORTCODE = /^\{\{\s*[a-z][a-z0-9-]*:([\s\S]*)\}\}$/;
      const OPTION_KEY = /^[a-z][a-z0-9-]*$/;
      function tokenize(text) {
        const positional = [];
        const options = {};
        let i = 0;
        while (i < text.length) {
          while (i < text.length && /\s/.test(text[i])) i++;
          if (i >= text.length) break;
          let token = '', keyEnd = -1, quotedYet = false, trailingComma = false;
          for (;;) {
            if (i >= text.length || /\s/.test(text[i])) {
              if (!trailingComma) break;
              // A value ending in a comma continues past the spaces.
              while (i < text.length && /\s/.test(text[i])) i++;
              if (i >= text.length) break;
            }
            const ch = text[i];
            if (ch === '"' || ch === "'") {
              const end = text.indexOf(ch, i + 1);
              if (end < 0) return null;
              token += text.slice(i + 1, end);
              quotedYet = true;
              trailingComma = false;
              i = end + 1;
              continue;
            }
            if (ch === '=' && keyEnd < 0 && !quotedYet) keyEnd = token.length;
            token += ch;
            trailingComma = ch === ',';
            i++;
          }
          if (keyEnd < 0) { positional.push(token); continue; }
          const key = token.slice(0, keyEnd);
          if (!OPTION_KEY.test(key) || key in options) return null;
          options[key] = token.slice(keyEnd + 1);
        }
        return { positional, options };
      }

      // `{{badge: text color=…}}`: the text in its color on a tinted pill,
      // grey without a color.
      function badge(args) {
        const text = args.positional[0];
        const color = readColor(args.options.color);
        if (!text || !text.trim() || !color) return null;
        const node = el('span', 'md-widget-badge', text);
        paint(node, color);
        return node;
      }

      // `{{sparkline: 3,5,2,8 color=… type=line|bar}}`: two or more numbers,
      // in order. A line is scaled between the lowest and the highest, flat
      // across the middle when they are all the same. Bars grow from zero
      // (down for a negative number), one per number, at least a sliver tall
      // so a zero still shows. The values stay as hidden text for find, copy
      // and VoiceOver.
      const SPARK_WIDTH = 100, SPARK_HEIGHT = 20, SPARK_PAD = 2;
      const SPARK_TYPES = ['line', 'bar'];
      const round = n => Math.round(n * 100) / 100;
      function sparkline(args) {
        const list = args.positional[0];
        if (!list) return null;
        const values = list.split(',').map(part => {
          const t = part.trim();
          return NUMBER.test(t) ? Number(t) : null;
        });
        if (values.length < 2 || values.some(value => value === null)) return null;
        const color = readColor(args.options.color);
        if (!color) return null;
        const type = args.options.type == null ? 'line' : args.options.type.toLowerCase();
        if (!SPARK_TYPES.includes(type)) return null;
        const min = Math.min(...values), max = Math.max(...values);
        const inner = SPARK_HEIGHT - 2 * SPARK_PAD;
        const SVGNS = 'http://www.w3.org/2000/svg';
        const svg = document.createElementNS(SVGNS, 'svg');
        svg.setAttribute('viewBox', '0 0 ' + SPARK_WIDTH + ' ' + SPARK_HEIGHT);
        svg.setAttribute('preserveAspectRatio', 'none');
        svg.setAttribute('aria-hidden', 'true');
        if (type === 'bar') {
          // The scale always includes zero, so bars are comparable.
          const lo = Math.min(0, min), hi = Math.max(0, max), span = hi - lo;
          const y = value => span ? SPARK_PAD + (hi - value) / span * inner : SPARK_HEIGHT - SPARK_PAD;
          const zero = y(0);
          const slot = SPARK_WIDTH / values.length, width = slot * 0.7;
          values.forEach((value, index) => {
            const height = Math.max(Math.abs(y(value) - zero), 1);
            const bar = document.createElementNS(SVGNS, 'rect');
            bar.setAttribute('x', round(index * slot + (slot - width) / 2));
            bar.setAttribute('y', round(value < 0 ? zero : zero - height));
            bar.setAttribute('width', round(width));
            bar.setAttribute('height', round(height));
            svg.append(bar);
          });
        } else {
          const points = values.map((value, index) => {
            const x = index / (values.length - 1) * SPARK_WIDTH;
            const y = max === min
              ? SPARK_HEIGHT / 2
              : SPARK_PAD + (1 - (value - min) / (max - min)) * inner;
            return round(x) + ',' + round(y);
          });
          const line = document.createElementNS(SVGNS, 'polyline');
          line.setAttribute('points', points.join(' '));
          svg.append(line);
        }
        const node = el('span', 'md-widget-spark md-widget-spark-' + type);
        paint(node, color);
        node.append(svg, el('span', 'md-widget-sr', 'Sparkline: ' + values.map(v => formatter.format(v)).join(', ')));
        return node;
      }

      // `{{progress: 7/12 color=… striped=true text=…}}` or
      // `{{progress: 58%}}`: a text-height bar, nothing beside it unless
      // `text` (the block's template: `{value}`, `{max}`, `{percent}`) adds
      // some. A value above the maximum shows a full bar. Without `text` the
      // value stays as hidden text for find, copy and VoiceOver.
      const FRACTION = /^([^/]+)\/([^/]+)$/;
      function inlineProgress(args) {
        const written = (args.positional[0] || '').trim();
        let value = null, max = null;
        const fraction = FRACTION.exec(written);
        if (fraction) {
          value = num(fraction[1]);
          max = num(fraction[2]);
        } else if (written.endsWith('%')) {
          value = num(written.slice(0, -1));
          max = 100;
        }
        if (value == null || max == null || value < 0 || max <= 0) return null;
        const color = readColor(args.options.color);
        if (!color) return null;
        const striped = (args.options.striped || 'false').toLowerCase();
        if (!['true', 'false'].includes(striped)) return null;
        const template = args.options.text;
        const shown = template == null || template.trim().toLowerCase() === 'none'
          ? '' : progressText(template, value, max);
        const node = el('span', 'md-widget-iprogress');
        const track = el('span', 'md-widget-iprogress-track');
        track.setAttribute('role', 'progressbar');
        track.setAttribute('aria-valuemin', '0');
        track.setAttribute('aria-valuemax', String(max));
        track.setAttribute('aria-valuenow', String(value));
        if (shown) track.setAttribute('aria-valuetext', shown);
        const fill = el('span', 'md-widget-fill'
          + (striped === 'true' && value < max ? ' md-widget-fill-striped' : ''));
        paint(fill, color);
        fill.style.width = (Math.min(value / max, 1) * 100) + '%';
        track.append(fill);
        node.append(track);
        node.append(shown
          ? el('span', 'md-widget-iprogress-text', shown)
          : el('span', 'md-widget-sr', 'Progress: ' + progressText('{value} / {max}', value, max)));
        return node;
      }

      // `{{shape: 1 kind=circle style=filled color=… size=md}}`: one to three
      // characters (a step number, a letter, `98%`) in a circle or a rounded
      // square. More characters, or a kind, style or size outside its list,
      // leave the code as it is.
      const SHAPE_KINDS = ['circle', 'square'];
      const SHAPE_STYLES = ['filled', 'tint', 'outline'];
      const SHAPE_SIZES = ['sm', 'md', 'lg', 'xl'];
      function shape(args) {
        const text = (args.positional[0] || '').trim();
        const length = Array.from(text).length;
        if (length < 1 || length > 3) return null;
        const kind = (args.options.kind || 'circle').toLowerCase();
        const style = (args.options.style || 'filled').toLowerCase();
        const size = (args.options.size || 'md').toLowerCase();
        if (!SHAPE_KINDS.includes(kind) || !SHAPE_STYLES.includes(style)
            || !SHAPE_SIZES.includes(size)) return null;
        const color = readColor(args.options.color);
        if (!color) return null;
        const node = el('span', 'md-widget-shape');
        if (kind !== 'circle') node.classList.add('md-widget-shape-' + kind);
        if (style !== 'filled') node.classList.add('md-widget-shape-' + style);
        if (size !== 'md') node.classList.add('md-widget-shape-' + size);
        if (length > 1) node.classList.add('md-widget-shape-' + length);
        // A trailing `%` is drawn smaller, as on a gauge, so `98%` fits.
        const label = el('span');
        if (length > 1 && text.endsWith('%')) {
          label.append(text.slice(0, -1), el('span', 'md-widget-shape-unit', '%'));
        } else {
          label.textContent = text;
        }
        node.append(label);
        paint(node, color);
        return node;
      }

      const INLINE = { sparkline, badge, progress: inlineProgress, shape };

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
            || (color.name === 'default' ? null : 'var(--widget-' + color.name + ')'));
        }
        const data = table(rows);
        if (!data) return null;
        return MdChart.render({
          type, title: options.title || '', legend, values: values === 'true',
          stacked: stacked === 'true', direction, height, grid: grid === 'true', xAxis, yAxis, colors,
          labels: data.labels, series: data.series
        });
      }

      const BUILDERS = { stat, chart, progress };

      // Striped fills move only while on screen, so an open document doesn't
      // keep repainting bars nobody can see.
      const motion = 'IntersectionObserver' in window
        ? new IntersectionObserver(entries => {
            for (const entry of entries) {
              if (!entry.target.isConnected) { motion.unobserve(entry.target); continue; }
              entry.target.classList.toggle('md-widget-moving', entry.isIntersecting);
            }
          })
        : null;

      function upgrade(root) {
        const scope = root && root.querySelectorAll ? root : document;
        for (const pre of scope.querySelectorAll('pre[data-md-widget]')) {
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
          for (const fill of node.querySelectorAll('.md-widget-fill-striped')) {
            if (motion) motion.observe(fill); else fill.classList.add('md-widget-moving');
          }
        }
        for (const code of scope.querySelectorAll('code[data-md-inline]')) {
          const build = INLINE[code.getAttribute('data-md-inline')];
          const match = build && SHORTCODE.exec(code.textContent);
          if (!match) continue;
          let node = null;
          try {
            const args = tokenize(match[1]);
            node = args && build(args);
          } catch (e) { node = null; }
          if (!node) continue;
          code.replaceWith(node);
          for (const fill of node.querySelectorAll('.md-widget-fill-striped')) {
            if (motion) motion.observe(fill); else fill.classList.add('md-widget-moving');
          }
        }
      }

      window.MdPreview?.registerExtension({ id: 'widgets', render(root) { upgrade(root); } });
    })();
    </script>
    """#
}
