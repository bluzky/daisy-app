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
//        size: { width: 600, height: 300 },
//        validate(spec) { return true; },  // false leaves the block plain
//        draw(svg, spec, kit) { ... },     // adds SVG to the plot
//      });
//
//  `MdChart.render(spec)` builds the figure: title, legend in its position,
//  the SVG root, accessibility, and the value labels layer. A spec is
//  `{ type, title, legend, values, labels: [string],
//  series: [{ name, values: [number] }] }`. The `chart` block parser in
//  `dashboardScript` accepts any registered type, so a new type needs only a
//  `register` call. `bar`, `line` and `pie` are registered the same way.
//
//  Colors are classes only (`md-chart-s1` … `s8`), mapped to the theme's
//  dashboard series colors (`DashboardColor.series`). Text reaches the SVG
//  through `textContent`, never markup.
//

import Foundation

nonisolated extension MarkdownHTML {

    /// Number of series colors before they repeat.
    static let dashboardChartSeriesColors = DashboardColor.seriesCount

    private static var dashboardChartSeriesCSS: String {
        DashboardColor.series.enumerated().map { offset, color in
            let index = offset + 1
            return """
            .md-chart-plot .md-chart-s\(index) { fill: \(color.cssValue); }
            .md-chart-plot .md-chart-line.md-chart-s\(index) { fill: none; stroke: \(color.cssValue); }
            .md-chart-swatch.md-chart-s\(index) { background: \(color.cssValue); }
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
    .md-chart-type-pie .md-chart-plot { max-width: 320px; }
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
        font-size: 12px;
        font-variant-numeric: tabular-nums;
    }
    /* Values on a slice: white, with a soft dark outline drawn under the fill
       (paint-order) so they stay readable on the light slices (yellow,
       green, teal) too. */
    .md-chart-plot .md-chart-pie-value {
        fill: #fff;
        stroke: rgb(0 0 0 / 45%);
        stroke-width: 3px;
        stroke-linejoin: round;
        paint-order: stroke;
        font-weight: 600;
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

    /// Defines `window.MdChart` with the `bar`, `line` and `pie` types. Loaded
    /// before `dashboardScript`, whose `chart` builder calls it.
    static let dashboardChartScript = #"""
    <script>
    (function() {
      if (window.MdChart) return;
      const SVGNS = 'http://www.w3.org/2000/svg';
      const SERIES_COLORS = \#(dashboardChartSeriesColors);
      const types = Object.create(null);
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
      // band per row with its label underneath.
      const MARGIN = { top: 20, right: 12, bottom: 30, left: 48 };
      function cartesian(plot, spec, size) {
        const range = scale(spec.series.flatMap(series => series.values));
        const left = MARGIN.left;
        const right = size.width - MARGIN.right;
        const top = MARGIN.top;
        const bottom = size.height - MARGIN.bottom;
        const band = (right - left) / spec.labels.length;
        const y = value => bottom - (value - range.min) / (range.max - range.min) * (bottom - top);
        const axes = svg('g', { class: 'md-chart-axes' }, plot);
        const ticks = Math.round((range.max - range.min) / range.step);
        for (let i = 0; i <= ticks; i++) {
          const value = Number((range.min + i * range.step).toPrecision(12));
          const at = y(value);
          svg('line', {
            x1: left, x2: right, y1: at, y2: at,
            class: value === 0 ? 'md-chart-grid md-chart-zero' : 'md-chart-grid'
          }, axes);
          text(axes, left - 8, at + 4, format(value), 'md-chart-axis', 'end');
        }
        spec.labels.forEach((label, i) => {
          text(axes, left + band * (i + 0.5), bottom + 18, label, 'md-chart-axis');
        });
        return { y, band, left, x: i => left + band * (i + 0.5) };
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

      function render(spec) {
        const renderer = has(spec.type) ? types[spec.type.toLowerCase()] : null;
        if (!renderer || !spec.labels.length || !spec.series.length) return null;
        if (renderer.validate && !renderer.validate(spec)) return null;
        const size = renderer.size || { width: 600, height: 300 };
        const position = spec.legend || 'bottom';

        const figure = el('figure', 'md-chart md-chart-type-' + spec.type.toLowerCase() + ' md-chart-legend-' + position);
        if (spec.title) figure.append(el('figcaption', 'md-chart-title', spec.title));
        const body = el('div', 'md-chart-body');
        const plot = svg('svg', {
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
          cartesian: () => cartesian(plot, spec, size),
          value(x, y, number, cls) {
            if (spec.values) text(valueLayer, x, y, format(number), cls || 'md-chart-value');
          }
        };
        renderer.draw(plot, spec, kit);
        plot.append(valueLayer);

        if (position !== 'none') {
          body.append(legend(renderer.legend === 'rows' ? spec.labels : spec.series.map(series => series.name)));
        }
        body.append(plot);
        figure.append(body);
        return figure;
      }

      register('bar', {
        legend: 'series',
        draw(plot, spec, kit) {
          const axes = kit.cartesian();
          const group = axes.band * 0.72;
          const width = group / spec.series.length;
          const zero = axes.y(0);
          spec.series.forEach((series, s) => {
            series.values.forEach((value, i) => {
              const x = axes.left + axes.band * i + (axes.band - group) / 2 + width * s;
              const top = Math.min(axes.y(value), zero);
              const height = Math.abs(axes.y(value) - zero);
              kit.svg('rect', {
                x: x + 1, y: top, width: Math.max(width - 2, 1), height, rx: 2,
                class: 'md-chart-bar ' + kit.seriesClass(s)
              }, plot);
              kit.value(x + width / 2, value < 0 ? top + height + 14 : top - 5, value);
            });
          });
        }
      });

      register('line', {
        legend: 'series',
        draw(plot, spec, kit) {
          const axes = kit.cartesian();
          spec.series.forEach((series, s) => {
            const cls = kit.seriesClass(s);
            const points = series.values.map((value, i) => [axes.x(i), axes.y(value)]);
            kit.svg('polyline', {
              points: points.map(point => point.join(',')).join(' '),
              class: 'md-chart-line ' + cls
            }, plot);
            points.forEach(([x, y], i) => {
              kit.svg('circle', { cx: x, cy: y, r: 3.5, class: 'md-chart-dot ' + cls }, plot);
              kit.value(x, y - 9, series.values[i]);
            });
          });
        }
      });

      // One number column; slices clockwise from 12 o'clock. A slice under
      // 5% of the total is too small for its label.
      register('pie', {
        legend: 'rows',
        size: { width: 300, height: 300 },
        validate(spec) {
          if (spec.series.length !== 1) return false;
          const values = spec.series[0].values;
          return values.every(value => value >= 0) && values.reduce((a, b) => a + b, 0) > 0;
        },
        draw(plot, spec, kit) {
          const values = spec.series[0].values;
          const total = values.reduce((a, b) => a + b, 0);
          const cx = kit.width / 2;
          const cy = kit.height / 2;
          const r = Math.min(cx, cy) - 10;
          const point = (angle, radius) => [cx + radius * Math.cos(angle), cy + radius * Math.sin(angle)];
          let angle = -Math.PI / 2;
          values.forEach((value, i) => {
            const share = value / total;
            const cls = 'md-chart-slice ' + kit.seriesClass(i);
            const end = angle + share * 2 * Math.PI;
            if (share >= 1) {
              kit.svg('circle', { cx, cy, r, class: cls }, plot);
            } else if (share > 0) {
              const [x1, y1] = point(angle, r);
              const [x2, y2] = point(end, r);
              kit.svg('path', {
                d: 'M' + cx + ',' + cy + ' L' + x1 + ',' + y1 +
                   ' A' + r + ',' + r + ' 0 ' + (share > 0.5 ? 1 : 0) + ' 1 ' + x2 + ',' + y2 + ' Z',
                class: cls
              }, plot);
            }
            if (share >= 0.05) {
              const [x, y] = point((angle + end) / 2, r * 0.62);
              kit.value(x, y + 4, value, 'md-chart-value md-chart-pie-value');
            }
            angle = end;
          });
        }
      });

      window.MdChart = Object.freeze({ register, has, render });
    })();
    </script>
    """#
}
