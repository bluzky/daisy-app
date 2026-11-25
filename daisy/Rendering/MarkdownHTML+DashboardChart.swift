//
//  MarkdownHTML+DashboardChart.swift
//  daisy
//
//  MdChart: the small SVG chart library behind the dashboard `chart` block.
//
//  A chart type is a renderer registered by name:
//
//      MdChart.register('bar', {
//        legend: 'series',              // legend names the series, or 'rows'
//        size(spec, width) { ... },     // optional; { width, height } at the shown width
//        validate(spec) { return true; },  // false leaves the block plain
//        draw(svg, spec, kit) { ... },     // adds SVG to the plot
//      });
//
//  `MdChart.render(spec)` builds the figure: title, legend in its position,
//  the SVG root, accessibility, and the value labels layer. A spec is
//  `{ type, title, legend, values, stacked, direction, labels: [string],
//  series: [{ name, values: [number] }] }`; `stacked` and `direction`
//  (`vertical` or `horizontal`) are read by `bar` only. `height` (CSS px)
//  and `grid` (false hides grid lines) apply to every type that has them;
//  `xAxis` and `yAxis` (`{ visible }`) hide the bottom and left labels. `size` may also be a
//  function of the spec. The `chart` block parser in
//  `dashboardScript` accepts any registered type, so a new type needs only a
//  `register` call. `bar`, `line`, `pie` and `donut` are registered the same way.
//
//  Colors are classes only (`md-chart-s1` … `s8`), mapped to the theme's
//  dashboard series colors (`DashboardColor.series`). A spec's `colors`
//  (checked hex or `var(--dashboard-name)`, at most eight; null keeps the
//  series color) override them as
//  `--md-chart-color-N` custom properties on the figure, never as markup.
//  Text reaches the SVG through `textContent`, never markup.
//

import Foundation

nonisolated extension MarkdownHTML {

    /// Number of series colors before they repeat.
    static let dashboardChartSeriesColors = DashboardColor.seriesCount

    private static var dashboardChartSeriesCSS: String {
        DashboardColor.series.enumerated().map { offset, color in
            let index = offset + 1
            // A chart's own `colors` set `--md-chart-color-N` on its figure.
            let value = "var(--md-chart-color-\(index), \(color.cssValue))"
            return """
            .md-chart-plot .md-chart-s\(index) { fill: \(value); }
            .md-chart-plot .md-chart-line.md-chart-s\(index) { fill: none; stroke: \(value); }
            .md-chart-swatch.md-chart-s\(index) { background: \(value); }
            """
        }.joined(separator: "\n")
    }

    /// Chart layout. The series colors are part of the dashboard palette,
    /// defined in `dashboardStylesheet`.
    static let dashboardChartStylesheet = """
    .md-chart {
        margin: 1em 0;
        container-type: inline-size;
        -webkit-print-color-adjust: exact;
        print-color-adjust: exact;
    }
    .md-chart-title {
        margin-bottom: 8px;
        font-weight: 600;
    }
    .md-chart-body {
        display: flex;
        align-items: center;
        gap: 10px 20px;
    }
    .md-chart-legend-top .md-chart-body { flex-direction: column; }
    .md-chart-legend-bottom .md-chart-body { flex-direction: column-reverse; }
    .md-chart-legend-left .md-chart-body { flex-direction: row; }
    .md-chart-legend-right .md-chart-body { flex-direction: row-reverse; }
    .md-chart-plot {
        display: block;
        flex: 1 1 auto;
        width: 100%;
        min-width: 0;
        height: auto;
        overflow: visible;
    }
    /* A `height` on a pie or donut overrides this cap inline. */
    .md-chart-type-pie .md-chart-plot,
    .md-chart-type-donut .md-chart-plot { max-width: 320px; }
    /* `.md-chart` raises these above the page's list rules
       (`article.markdown-body ul` is a column flexbox, and `ul > li` draws a
       bullet). Top and bottom legends are a centered row that wraps. */
    .md-chart .md-chart-legend {
        display: flex;
        flex-direction: row;
        flex-wrap: wrap;
        justify-content: center;
        gap: 4px 14px;
        margin: 0;
        padding: 0;
        list-style: none;
        font-size: 0.85em;
    }
    .md-chart-legend-left .md-chart-legend,
    .md-chart-legend-right .md-chart-legend {
        flex: 0 0 auto;
        flex-direction: column;
        max-width: 40%;
    }
    .md-chart .md-chart-legend li {
        display: flex;
        align-items: center;
        gap: 6px;
        margin: 0;
        padding: 0;
    }
    .md-chart .md-chart-legend li::before { content: none; }
    .md-chart-swatch {
        flex: none;
        width: 10px;
        height: 10px;
        border-radius: 2px;
    }
    /* A side legend moves under the chart when there is no room beside it. */
    @container (max-width: 420px) {
        .md-chart-legend-left .md-chart-body,
        .md-chart-legend-right .md-chart-body { flex-direction: column-reverse; }
        .md-chart-legend-left .md-chart-legend,
        .md-chart-legend-right .md-chart-legend { flex-direction: row; max-width: none; }
    }
    .md-chart-plot text { font-family: inherit; }
    .md-chart-axis {
        fill: var(--dashboard-text);
        font-size: 12px;
    }
    .md-chart-grid {
        stroke: var(--dashboard-border);
        stroke-width: 1;
    }
    .md-chart-zero { stroke: var(--dashboard-text); }
    .md-chart-value {
        fill: currentColor;
        font-size: 10px;
        font-variant-numeric: tabular-nums;
    }
    /* Values on a slice: white, with a soft dark outline drawn under the fill
       (paint-order) so they stay readable on the light slices (yellow,
       green, teal) too. */
    .md-chart-plot .md-chart-pie-value,
    .md-chart-plot .md-chart-inside-value {
        fill: #fff;
        stroke: rgb(0 0 0 / 45%);
        stroke-width: 3px;
        stroke-linejoin: round;
        paint-order: stroke;
        font-weight: 600;
    }
    .md-chart-donut-total {
        fill: currentColor;
        font-size: 30px;
        font-weight: 600;
        font-variant-numeric: tabular-nums;
    }
    .md-chart-plot .md-chart-line {
        stroke-width: 2.5;
        stroke-linejoin: round;
        stroke-linecap: round;
    }
    .md-chart-slice {
        stroke: Canvas;
        stroke-width: 1.5;
    }
    \(dashboardChartSeriesCSS)
    """

    /// Defines `window.MdChart` with the `bar`, `line`, `pie` and `donut` types. Loaded
    /// before `dashboardScript`, whose `chart` builder calls it.
    static let dashboardChartScript = #"""
    <script>
    (function() {
      if (window.MdChart) return;
      const SVGNS = 'http://www.w3.org/2000/svg';
      const SERIES_COLORS = \#(dashboardChartSeriesColors);
      const types = Object.create(null);
      const HEX = /^#(?:[0-9a-f]{3}|[0-9a-f]{6})$/i;
      const PALETTE_VAR = /^var\(--dashboard-[a-z]+\)$/;
      const formatter = new Intl.NumberFormat(undefined, { maximumFractionDigits: 2 });

      function el(tag, cls, text) {
        const node = document.createElement(tag);
        if (cls) node.className = cls;
        if (text != null) node.textContent = text;
        return node;
      }
      function svg(tag, attrs, parent) {
        const node = document.createElementNS(SVGNS, tag);
        for (const name in attrs) {
          if (attrs[name] != null) node.setAttribute(name, String(attrs[name]));
        }
        if (parent) parent.append(node);
        return node;
      }
      function text(parent, x, y, content, cls, anchor) {
        const node = svg('text', { x, y, class: cls, 'text-anchor': anchor || 'middle' }, parent);
        node.textContent = content;
        return node;
      }
      function format(value) { return formatter.format(value); }
      function seriesClass(index) { return 'md-chart-s' + ((index % SERIES_COLORS) + 1); }

      // A scale from the data, always including 0, in round steps.
      function scale(values) {
        let min = Math.min(0, ...values);
        let max = Math.max(0, ...values);
        if (min === max) max = min + 1;
        const raw = (max - min) / 4;
        const power = Math.pow(10, Math.floor(Math.log10(raw)));
        const fraction = raw / power;
        const step = (fraction <= 1 ? 1 : fraction <= 2 ? 2 : fraction <= 5 ? 5 : 10) * power;
        return { min: Math.floor(min / step) * step, max: Math.ceil(max / step) * step, step };
      }

      // Axes shared by bar and line: grid lines with tick labels, and one
      // band per row with its label. Vertical (the default) puts the values
      // up the left and the rows along the bottom; horizontal puts the rows
      // down the left, sized to their labels, and the values along the bottom.
      // `options.values` sets the range, for a stack's totals.
      // `options.edges` places rows on points running from the left edge to
      // the right edge instead of in bands, for a line.
      const MARGIN = { top: 20, right: 12, bottom: 30, left: 48 };
      function cartesian(plot, spec, size, options) {
        const horizontal = !!(options && options.horizontal);
        const range = scale(options && options.values
          ? options.values
          : spec.series.flatMap(series => series.values));
        // A hidden axis (`x-axis` along the bottom, `y-axis` up the left, as
        // drawn) gives its labels' room back to the plot.
        const showX = !spec.xAxis || spec.xAxis.visible !== false;
        const showY = !spec.yAxis || spec.yAxis.visible !== false;
        const longest = Math.max(...spec.labels.map(label => label.length));
        const left = !showY ? 12
          : horizontal ? Math.min(200, Math.max(MARGIN.left, 12 + longest * 7)) : MARGIN.left;
        // Room for a value label past the longest horizontal bar.
        const edges = !horizontal && !!(options && options.edges);
        // An edge layout keeps room on the right for the last row's centered label.
        const right = size.width - (horizontal ? 36 : edges ? 24 : MARGIN.right);
        const top = MARGIN.top;
        const bottom = size.height - (showX ? MARGIN.bottom : 12);
        const fraction = value => (value - range.min) / (range.max - range.min);
        const at = horizontal
          ? value => left + fraction(value) * (right - left)
          : value => bottom - fraction(value) * (bottom - top);
        const band = (horizontal ? bottom - top : right - left) / spec.labels.length;
        const bandStart = i => (horizontal ? top : left) + band * i;
        // A lone point sits in the middle.
        const point = i => spec.labels.length > 1
          ? left + (right - left) * i / (spec.labels.length - 1)
          : (left + right) / 2;
        const rowX = i => edges ? point(i) : bandStart(i) + band / 2;
        const axes = svg('g', { class: 'md-chart-axes' }, plot);
        const ticks = Math.round((range.max - range.min) / range.step);
        for (let i = 0; i <= ticks; i++) {
          const value = Number((range.min + i * range.step).toPrecision(12));
          const p = at(value);
          const cls = value === 0 ? 'md-chart-grid md-chart-zero' : 'md-chart-grid';
          // `grid: false` keeps the zero line and the tick labels.
          const line = value === 0 || spec.grid !== false;
          if (horizontal) {
            if (line) svg('line', { x1: p, x2: p, y1: top, y2: bottom, class: cls }, axes);
            if (showX) text(axes, p, bottom + 18, format(value), 'md-chart-axis');
          } else {
            if (line) svg('line', { x1: left, x2: right, y1: p, y2: p, class: cls }, axes);
            if (showY) text(axes, left - 8, p + 4, format(value), 'md-chart-axis', 'end');
          }
        }
        spec.labels.forEach((label, i) => {
          if (horizontal) { if (showY) text(axes, left - 8, bandStart(i) + band / 2 + 4, label, 'md-chart-axis', 'end'); }
          else if (showX) text(axes, rowX(i), bottom + 18, label, 'md-chart-axis');
        });
        return { value: at, y: at, band, left, bandStart, x: rowX };
      }

      function legend(names) {
        const list = el('ul', 'md-chart-legend');
        names.forEach((name, i) => {
          const item = el('li');
          item.append(el('span', 'md-chart-swatch ' + seriesClass(i)), el('span', null, name));
          list.append(item);
        });
        return list;
      }

      function register(type, renderer) {
        if (typeof type !== 'string' || !renderer || typeof renderer.draw !== 'function') {
          throw new TypeError('MdChart.register(type, { draw }) needs a name and a draw function');
        }
        types[type.toLowerCase()] = renderer;
      }

      function has(type) { return typeof type === 'string' && type.toLowerCase() in types; }

      // A chart is drawn at the width it is shown at, so one viewBox unit is
      // one CSS pixel and text keeps its real size in a narrow column or a
      // wide window. Before the plot is laid out it draws at DEFAULT_WIDTH;
      // the observer redraws it once its width is known, and on every resize.
      const DEFAULT_WIDTH = 600;
      const MIN_WIDTH = 160;
      const redraws = new WeakMap();
      const resizes = 'ResizeObserver' in window
        ? new ResizeObserver(entries => {
            for (const entry of entries) {
              const plot = entry.target;
              if (!plot.isConnected) { resizes.unobserve(plot); continue; }
              const redraw = redraws.get(plot);
              if (redraw) redraw(entry.contentRect.width);
            }
          })
        : null;

      // The size a renderer asks for at `width`: a function of the spec and
      // the width, a fixed size, or the default half-as-tall-as-wide.
      function sizeFor(renderer, spec, width) {
        if (typeof renderer.size === 'function') return renderer.size(spec, width);
        if (renderer.size) return renderer.size;
        return { width, height: spec.height || Math.max(200, Math.round(width / 2)) };
      }

      function render(spec) {
        const renderer = has(spec.type) ? types[spec.type.toLowerCase()] : null;
        if (!renderer || !spec.labels.length || !spec.series.length) return null;
        if (renderer.validate && !renderer.validate(spec)) return null;
        const position = spec.legend || 'bottom';

        const figure = el('figure', 'md-chart md-chart-type-' + spec.type.toLowerCase() + ' md-chart-legend-' + position);
        (spec.colors || []).forEach((color, i) => {
          if (i < SERIES_COLORS && color && (HEX.test(color) || PALETTE_VAR.test(color))) {
            figure.style.setProperty('--md-chart-color-' + (i + 1), color);
          }
        });
        if (spec.title) figure.append(el('figcaption', 'md-chart-title', spec.title));
        const body = el('div', 'md-chart-body');
        if (position !== 'none') {
          body.append(legend(renderer.legend === 'rows' ? spec.labels : spec.series.map(series => series.name)));
        }

        let plot = null;
        let drawnWidth = 0;
        function draw(width) {
          width = Math.max(MIN_WIDTH, Math.round(width));
          if (plot && Math.abs(width - drawnWidth) < 1) return;
          drawnWidth = width;
          const size = sizeFor(renderer, spec, width);
          const next = svg('svg', {
            class: 'md-chart-plot',
            viewBox: '0 0 ' + size.width + ' ' + size.height,
            role: 'img',
            'aria-label': spec.title || spec.type + ' chart'
          });
          // Value labels sit on their own layer, above every shape.
          const valueLayer = svg('g', { class: 'md-chart-values' });
          const kit = {
            width: size.width,
            height: size.height,
            svg,
            text,
            format,
            seriesClass,
            scale,
            cartesian: options => cartesian(next, spec, size, options),
            value(x, y, number, cls, anchor) {
              if (spec.values) text(valueLayer, x, y, format(number), cls || 'md-chart-value', anchor);
            }
          };
          renderer.draw(next, spec, kit);
          next.append(valueLayer);
          // A round chart's `height` is its diameter, so it caps the width too.
          if (renderer.round && spec.height) next.style.maxWidth = spec.height + 'px';
          if (plot) {
            if (resizes) resizes.unobserve(plot);
            plot.replaceWith(next);
          } else {
            body.append(next);
          }
          plot = next;
          redraws.set(plot, draw);
          if (resizes) resizes.observe(plot);
        }
        draw(DEFAULT_WIDTH);
        figure.append(body);
        return figure;
      }

      // `direction: horizontal` lays the bars sideways, one band per row, as
      // tall as the rows need. `stacked` puts a row's series in one bar:
      // positives stack up from zero and negatives down, each segment shows
      // its value inside when it fits, and the row's total sits at the end.
      const BAR_ROW = 14;
      register('bar', {
        legend: 'series',
        size(spec, width) {
          if (spec.height) return { width, height: spec.height };
          if (spec.direction !== 'horizontal') return { width, height: Math.max(200, Math.round(width / 2)) };
          const perBand = spec.stacked ? 1 : spec.series.length;
          const band = Math.max(28, perBand * BAR_ROW + 12);
          return { width, height: MARGIN.top + MARGIN.bottom + spec.labels.length * band };
        },
        draw(plot, spec, kit) {
          const horizontal = spec.direction === 'horizontal';
          const stacked = !!spec.stacked && spec.series.length > 1;
          const positive = spec.labels.map(() => 0);
          const negative = spec.labels.map(() => 0);
          if (stacked) {
            for (const series of spec.series) {
              series.values.forEach((value, i) => {
                if (value < 0) negative[i] += value; else positive[i] += value;
              });
            }
          }
          const axes = kit.cartesian({
            horizontal,
            values: stacked ? positive.concat(negative) : null
          });
          const group = axes.band * 0.72;
          const thickness = group / (stacked ? 1 : spec.series.length);
          const zero = axes.value(0);
          const ends = spec.labels.map(() => ({ up: 0, down: 0 }));
          // Draws a bar from `from` to `to` (values) across `[across, across + thickness]`.
          function bar(from, to, across, cls) {
            const a = axes.value(from);
            const b = axes.value(to);
            const start = Math.min(a, b);
            const length = Math.abs(b - a);
            const breadth = Math.max(thickness - 2, 1);
            kit.svg('rect', horizontal
              ? { x: start, y: across + 1, width: length, height: breadth, class: cls }
              : { x: across + 1, y: start, width: breadth, height: length, class: cls }, plot);
            return { start, length, middle: across + thickness / 2 };
          }
          // A value label just past the end of a bar, on its side of zero.
          function outside(shape, value, number) {
            if (horizontal) {
              const below = value < 0;
              kit.value(below ? shape.start - 5 : shape.start + shape.length + 5, shape.middle + 4,
                        number, null, below ? 'end' : 'start');
            } else {
              kit.value(shape.middle, value < 0 ? shape.start + shape.length + 14 : shape.start - 5, number);
            }
          }
          spec.series.forEach((series, s) => {
            const cls = 'md-chart-bar ' + kit.seriesClass(s);
            series.values.forEach((value, i) => {
              const across = axes.bandStart(i) + (axes.band - group) / 2 + (stacked ? 0 : thickness * s);
              if (!stacked) {
                outside(bar(0, value, across, cls), value, value);
                return;
              }
              const end = ends[i];
              const from = value < 0 ? end.down : end.up;
              const to = from + value;
              if (value < 0) end.down = to; else end.up = to;
              const shape = bar(from, to, across, cls);
              // Inside a segment only when the number fits in it.
              const room = horizontal ? 6 * kit.format(value).length + 8 : 14;
              if (value !== 0 && shape.length >= room) {
                const center = shape.start + shape.length / 2;
                if (horizontal) kit.value(center, shape.middle + 4, value, 'md-chart-value md-chart-inside-value');
                else kit.value(shape.middle, center + 4, value, 'md-chart-value md-chart-inside-value');
              }
            });
          });
          if (stacked) {
            spec.labels.forEach((_, i) => {
              const across = axes.bandStart(i) + (axes.band - group) / 2;
              const total = positive[i] + negative[i];
              // The total sits past the longer side of the stack.
              const towardNegative = positive[i] === 0 && negative[i] < 0;
              const far = towardNegative ? negative[i] : positive[i];
              const a = axes.value(far);
              const shape = { start: Math.min(a, zero), length: Math.abs(a - zero), middle: across + thickness / 2 };
              outside(shape, towardNegative ? -1 : 1, total);
            });
          }
        }
      });

      register('line', {
        legend: 'series',
        draw(plot, spec, kit) {
          const axes = kit.cartesian({ edges: true });
          spec.series.forEach((series, s) => {
            const cls = kit.seriesClass(s);
            const points = series.values.map((value, i) => [axes.x(i), axes.y(value)]);
            kit.svg('polyline', {
              points: points.map(point => point.join(',')).join(' '),
              class: 'md-chart-line ' + cls
            }, plot);
            // The end points' values lean inward, clear of the axis labels.
            const last = points.length - 1;
            points.forEach(([x, y], i) => {
              kit.svg('circle', { cx: x, cy: y, r: 3.5, class: 'md-chart-dot ' + cls }, plot);
              const anchor = last > 0 && i === 0 ? 'start' : last > 0 && i === last ? 'end' : 'middle';
              const dx = anchor === 'start' ? -2 : anchor === 'end' ? 2 : 0;
              kit.value(x + dx, y - 9, series.values[i], null, anchor);
            });
          });
        }
      });

      // One number column; slices clockwise from 12 o'clock. A slice under
      // 5% of the total is too small for its label. A donut is a pie with a
      // hole (`hole` is its share of the radius) and the total in the middle.
      function validateShares(spec) {
        if (spec.series.length !== 1) return false;
        const values = spec.series[0].values;
        return values.every(value => value >= 0) && values.reduce((a, b) => a + b, 0) > 0;
      }
      function drawSlices(plot, spec, kit, hole) {
        const values = spec.series[0].values;
        const total = values.reduce((a, b) => a + b, 0);
        const cx = kit.width / 2;
        const cy = kit.height / 2;
        const r = Math.min(cx, cy) - 10;
        const inner = r * hole;
        const point = (angle, radius) => [cx + radius * Math.cos(angle), cy + radius * Math.sin(angle)];
        // A full ring: the outer circle less the inner one.
        const ring = (outer, inside) =>
          'M' + (cx - outer) + ',' + cy + ' a' + outer + ',' + outer + ' 0 1 0 ' + (2 * outer) + ',0' +
          ' a' + outer + ',' + outer + ' 0 1 0 ' + (-2 * outer) + ',0 Z' +
          (inside > 0
            ? ' M' + (cx - inside) + ',' + cy + ' a' + inside + ',' + inside + ' 0 1 0 ' + (2 * inside) + ',0' +
              ' a' + inside + ',' + inside + ' 0 1 0 ' + (-2 * inside) + ',0 Z'
            : '');
        let angle = -Math.PI / 2;
        values.forEach((value, i) => {
          const share = value / total;
          const cls = 'md-chart-slice ' + kit.seriesClass(i);
          const end = angle + share * 2 * Math.PI;
          const large = share > 0.5 ? 1 : 0;
          if (share >= 1) {
            kit.svg('path', { d: ring(r, inner), 'fill-rule': 'evenodd', class: cls }, plot);
          } else if (share > 0) {
            const [x1, y1] = point(angle, r);
            const [x2, y2] = point(end, r);
            let d = 'M' + x1 + ',' + y1 + ' A' + r + ',' + r + ' 0 ' + large + ' 1 ' + x2 + ',' + y2;
            if (inner > 0) {
              const [x3, y3] = point(end, inner);
              const [x4, y4] = point(angle, inner);
              d += ' L' + x3 + ',' + y3 + ' A' + inner + ',' + inner + ' 0 ' + large + ' 0 ' + x4 + ',' + y4 + ' Z';
            } else {
              d = 'M' + cx + ',' + cy + ' L' + x1 + ',' + y1 + d.slice(d.indexOf(' A')) + ' Z';
            }
            kit.svg('path', { d, class: cls }, plot);
          }
          if (share >= 0.05) {
            const [x, y] = point((angle + end) / 2, inner > 0 ? (r + inner) / 2 : r * 0.62);
            kit.value(x, y + 4, value, 'md-chart-value md-chart-pie-value');
          }
          angle = end;
        });
        if (inner > 0) kit.value(cx, cy + 10, total, 'md-chart-donut-total');
      }

      register('pie', {
        legend: 'rows',
        round: true,
        size: (spec, width) => { const side = Math.min(width, spec.height || 320); return { width: side, height: side }; },
        validate: validateShares,
        draw(plot, spec, kit) { drawSlices(plot, spec, kit, 0); }
      });

      register('donut', {
        legend: 'rows',
        round: true,
        size: (spec, width) => { const side = Math.min(width, spec.height || 320); return { width: side, height: side }; },
        validate: validateShares,
        draw(plot, spec, kit) { drawSlices(plot, spec, kit, 0.58); }
      });

      window.MdChart = Object.freeze({ register, has, render });
    })();
    </script>
    """#
}
