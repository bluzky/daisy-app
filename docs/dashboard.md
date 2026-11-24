# Dashboard

Turn a Markdown file into a dashboard with four kinds of fenced block: `stat` tiles, `chart` bar, line, pie and donut charts, `progress` bars and `badge` labels. They work in any Markdown file; there is nothing to turn on. A block with a missing or invalid field stays a plain code block. Every value is written in the file: there are no data files, no network fetches and no formulas. See [`samples/dashboard.md`](../samples/dashboard.md) for a complete example.

Each block is a few `key: value` lines. Where a block holds several items, a line of `---` separates them. A chart adds a Markdown table after its `key: value` lines; see [Charts](#charts).

## Stat tiles

````markdown
```stat
label: Revenue
value: $48.2k
delta: +12%
trend: up
note: vs last month
link: #sales-by-month
---
label: Churn
value: 2.1%
delta: -0.4%
trend: down
good: down
```
````

| Key | Required | What it does |
| --- | --- | --- |
| `label` | yes | The tile's title, top left. |
| `value` | yes | The big number. Written as you want it shown: `$48.2k`, `3,204`, `2.1%`. |
| `delta` | no | The change, on the value's line at the tile's right edge. |
| `trend` | no | `up`, `down` or `flat`: the arrow before the delta, and its color. Ignored without a `delta`. |
| `good` | no | `down` for a metric where down is good, such as churn. The default is `up`. |
| `note` | no | A small line under the value. |
| `link` | no | An arrow in the tile's top right corner that opens like any Markdown link: a web address, a relative file (`reports/q3.md`) or a heading in the same file (`#sales-by-month`). |

- All the tiles in one block share a row and wrap on a narrow window.
- Color follows `trend` and `good`: a move in the good direction is green, the other red, and `flat` grey. So `trend: down` with `good: down` is green.
- A tile needs only `label` and `value`. A `delta` without a `trend` shows grey with no arrow. A `trend` without a `delta` is ignored.
- A `javascript:`, `data:` or `file:` link leaves the block plain.

## Progress

````markdown
```progress
label: Features
value: 7
max: 12
---
label: Tests passing
value: 182
max: 190
color: positive
```
````

`label`, `value` and `max` are required. `value` is zero or more and `max` above zero; a value above its maximum shows a full bar. Each bar is one row: its label, the bar, then `value / max`. The bars in one block stack, with their labels, bars and values lined up.

`color` is optional and names a palette color: `accent` (the default), `positive`, `negative`, `warning` or `neutral`. Any other value, a hex code included, leaves the block plain.

`striped: true` draws moving diagonal stripes over a bar's fill, to mark work still in progress. The stripes move only while the bar is on screen, stand still when macOS Reduce Motion is on and in print and PDF, and a full bar has none. Any value other than `true` or `false` leaves the block plain.

## Badges

````markdown
```badge
text: Build passing
status: ok
---
text: Docs outdated
status: warn
```
````

`text` and `status` are required. `status` is `ok` (green), `warn` (amber) or `fail` (red). Badges in one block sit side by side.

## Charts

A `chart` block draws a bar, line, pie or donut chart from a Markdown table written inside it:

````markdown
```chart
type: bar
title: Sales by month
legend: right
| Month | 2025 | 2026 |
| ----- | ---- | ---- |
| Jan   | 12   | 15   |
| Feb   | 18   | 21   |
| Mar   | 15   | 24   |
```

```chart
type: pie
title: Revenue mix
| Plan       | Share |
| ---------- | ----- |
| Free       | 40    |
| Pro        | 45    |
| Enterprise | 15    |
```
````

| Key | Required | What it does |
| --- | --- | --- |
| `type` | yes | `bar`, `line`, `pie` or `donut`. A donut is a pie with a hole, and shows the total in the middle (hidden with `values: false`). |
| `title` | no | A heading above the chart. |
| `legend` | no | Where the legend goes: `top`, `bottom`, `left` or `right`, or `none` to hide it. The default is `bottom`. On a narrow window a `left` or `right` legend moves below the chart. It can also be a group: `position` (`top`, `bottom`, `left` or `right`) and `visible` (`true` or `false`), each on an indented line under `legend:`. |
| `values` | no | `false` to stop drawing each value on the chart. Values are drawn by default. |
| `stacked` | no | Bar charts only. `true` draws each row as one bar with its series stacked; positives stack up from zero and negatives down. Each segment shows its value when it fits, and the row's total sits at the end of the bar. The default is `false`, one bar per series side by side. |
| `direction` | no | Bar charts only. `horizontal` lays the bars sideways with the row labels on the left; the default is `vertical`. |
| `height` | no | The chart's height in pixels, from 80 to 1200 (`height: 240` or `height: 240px`). For a pie or donut it is the diameter. Without it, bar and line charts are half as tall as they are wide (at least 200px), a horizontal bar chart grows with its rows, and a pie or donut is up to 320px. |
| `colors` | no | Up to eight hex colors (`#RGB` or `#RRGGBB`), separated by commas, for the series in order, or a pie's or donut's slices: `colors: #4F46E5, #22C55E, #F59E0B`. Series past the list keep the palette colors. Unlike the palette, these colors are the same in light and dark mode. Anything that isn't a hex color leaves the block plain. |
| `grid` | no | `false` hides the grid lines of a bar or line chart; the zero line and the axis numbers stay. The default is `true`. |
| `x-axis`, `y-axis` | no | Groups with `visible: false` on an indented line, to hide the labels along the bottom (`x-axis`) or up the left side (`y-axis`) of a bar or line chart and give their room to the plot. The axes are named as drawn, so on a horizontal bar chart `x-axis` holds the values and `y-axis` the rows. The zero line and grid lines stay; use `grid: false` for those. |

Line, pie and donut charts ignore `stacked` and `direction`, and pie and donut charts have no axes. A group's lines are indented under its key; an indented line anywhere else, or any value other than the ones listed, leaves the block plain.

````markdown
```chart
type: line
title: Signups per week
legend:
  position: right
  visible: true
y-axis:
  visible: false
| Week | Organic | Paid |
| ---- | ------- | ---- |
| W1   | 120     | 40   |
| W2   | 135     | 52   |
```
````

````markdown
```chart
type: bar
title: Tickets by team
stacked: true
direction: horizontal
| Team     | Open | Closed |
| -------- | ---- | ------ |
| Platform | 12   | 30     |
| Mobile   | 8    | 22     |
```
````

The `key: value` lines come first and the table last. In the table:

- The first column holds the labels: the groups of bars, the points of a line, or the slices of a pie or donut.
- Every other column is a series, named by its header. A bar chart draws one bar per series in each group; a line chart draws one line per series.
- Every cell after the first column is a plain number. `1,200` and `-4` are fine; `$12` and `12%` are not, so put units in the title or the column header.
- A `pie` or `donut` takes exactly one number column, every value zero or more. A slice too small for its label (under about 5%) shows no value.

Vertical bar and line charts are as wide as their column and half as tall (at least 200px), with an axis that always includes zero. A horizontal bar chart is as wide as the column and grows taller with each row. A pie or donut is at most 320px wide. A chart is drawn at the width it is shown at and redrawn when that changes, so values and axis labels keep the same size in a narrow column, a wide window or on a slide, however many bars there are.

Mermaid's [`xychart-beta` and `pie`](https://mermaid.js.org) still work in any document and also render on GitHub, but they keep Mermaid's own colors rather than the dashboard palette below.

## Colors

Every widget draws with one shared palette of semantic colors, in a light and a dark version that follow the page's appearance. A progress bar can pick a palette color by name, and a chart can replace its series colors with `colors` (hex values only); nothing else in a block sets a color.

| Color | Used for | Light | Dark |
| --- | --- | --- | --- |
| Accent (`--dashboard-accent`) | Progress bars (default) | `#007AFF` blue | `#0A84FF` |
| Positive (`--dashboard-positive`) | Good deltas, `ok` badges, `color: positive` bars | `#34C759` green | `#30D158` |
| Negative (`--dashboard-negative`) | Bad deltas, `fail` badges, `color: negative` bars | `#FF3B30` red | `#FF453A` |
| Warning (`--dashboard-warning`) | `warn` badges, `color: warning` bars | `#FF9500` orange | `#FF9F0A` |
| Neutral (`--dashboard-neutral`) | Flat deltas, `color: neutral` bars | `#8E8E93` grey | `#98989D` |
| Series 1–8 (`--dashboard-series-1` … `-8`) | Chart series and pie slices, in order; a ninth starts again at the first | Apple's system blue, orange, teal, purple, green, pink, yellow, grey | their dark-mode versions |

These are Apple's standard system colors, one set for every widget: the `warn` badge is the same orange as a chart's second series. Badges are white text on their color. A stat's delta, drawn as text, is the color darkened on a light page so it stays readable, and the color itself on a dark one.

Text, the progress track and the stat tile's outline follow the page's own theme colors; a stat tile's fill (`--dashboard-card`) is the theme's code block background, in every app theme and slide theme.

Every app theme, and Quick Look, uses these two palettes; there is no setting for them. A slide deck's theme can change them on its slides with the `colors:` keys `dashboard_accent`, `dashboard_positive`, `dashboard_negative`, `dashboard_warning`, `dashboard_neutral` and `dashboard_series_1` … `dashboard_series_8` (see [Slides](slides.md#themes)).

## Invalid blocks and other viewers

A block with a missing required key, an unknown value (`status: purple`, `trend: sideways`, `type: radar`), a value that should be a number but isn't, a line that is not `key: value`, or a chart table with a missing separator row or a row of the wrong length is left as the plain code block it is in the file. The rest of the document still renders. Other Markdown viewers show every block that way.

## Where it renders

Read mode, Quick Look, PDF export and [slides](slides.md) (a deck draws widgets inside its slides) draw the widgets. The editor shows the blocks as text, and DOCX export writes each block as the code block it is.
