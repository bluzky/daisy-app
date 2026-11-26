# Widgets

Draw widgets in any Markdown document with three kinds of fenced block — `stat` tiles, `chart` bar, line, pie and donut charts, and `progress` bars and rings — and four inline [shortcodes](#shortcodes), `sparkline`, `badge`, `progress` and `shape`, that sit in a sentence or a table cell. They work in any Markdown file; there is nothing to turn on. A block or shortcode with a missing or invalid field stays plain code. Every value is written in the file: there are no data files, no network fetches and no formulas. See [`samples/widgets.md`](../samples/widgets.md) for a complete example.

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
color: success
```
````

| Key | Required | What it does |
| --- | --- | --- |
| `label` | yes | The tile's title, top left. |
| `value` | yes | The big number. Written as you want it shown: `$48.2k`, `3,204`, `2.1%`. |
| `color` | no | The big number's [color](#colors): `success`, `danger`, … or a hex. The default is the theme's text color. With a look option below, the tile's fill, border and bar take it too. |
| `delta` | no | The change, on the value's line at the tile's right edge. |
| `trend` | no | `up`, `down` or `flat`: the arrow before the delta, and its color. Ignored without a `delta`. |
| `good` | no | `down` for a metric where down is good, such as churn. The default is `up`. |
| `note` | no | A small line under the value. |
| `link` | no | An arrow in the tile's top right corner that opens like any Markdown link: a web address, a relative file (`reports/q3.md`) or a heading in the same file (`#sales-by-month`). |
| `style` | no | `plain` (default), `outline`, `filled`, `accent` or `solid`: the same presets as a [card's](cards.md#style-presets). |
| `fill` | no | `none`, `surface` (default), `soft`, `tint` or `solid`, as on a card. |
| `border` | no | `none`, `thin` (default) or `thick`. |
| `bar` | no | `none` (default), `left` or `top`: a bar in the color down the left side or across the top. |
| `ink` | no | `light` or `dark`: the tile's text color, white or near-black. |
| `padding` | no | `compact`, `normal` (default) or `roomy`. |

- All the tiles in one block share a row and wrap on a narrow window.
- Color follows `trend` and `good`: a move in the good direction is green, the other red, and `flat` grey. So `trend: down` with `good: down` is green.
- A tile needs only `label` and `value`. A `delta` without a `trend` shows grey with no arrow. A `trend` without a `delta` is ignored.
- A `javascript:`, `data:` or `file:` link leaves the block plain.

### A tile's look

`style`, `fill`, `border`, `bar`, `ink` and `padding` work as they do on a [card](cards.md#options), one tile at a time. An option written beside `style` overrides the preset: `style: accent` with `bar: top` puts the bar across the top. A tile has no `shape`: it keeps its rounded corners.

````markdown
```stat
label: Revenue
value: $48.2k
style: accent
color: success
---
label: Uptime
value: 99.98%
style: solid
color: info
---
label: Incidents
value: 3
fill: soft
bar: top
border: none
color: warning
```
````

- With any of these options, the tile's `color` also goes to its border, bar and fill. Without a `color`, the bar and a `soft`, `tint` or `solid` fill are the accent and the border stays the theme's, as on a card. A tile with only `color` keeps its normal outline, with the color on its value alone.
- On a `solid` tile, or one with `ink`, the label, value, delta and note all take the text color, so nothing vanishes into the fill; the delta keeps its arrow but not its green or red. A solid tile's text is white, or dark on `warning`; for a light hex color, add `ink: dark`.
- A value outside its list leaves the block plain.

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
color: success
```
````

`value` and `max` are required; `label` is optional. `value` is zero or more and `max` above zero; a value above its maximum shows a full bar. Each bar is one row: its label, the bar, then `value / max`. A bar without a label leaves its label cell empty; when no bar in the block has one, the bars take the whole width. The bars in one block stack, with their labels, bars and values lined up.

| Key | Required | What it does |
| --- | --- | --- |
| `label` | no | The bar's or ring's name. Without it, a ring shows no name under it. |
| `value`, `max` | yes | How far along: `value` zero or more, `max` above zero. |
| `shape` | no | `bar` (the default) or `ring`, on the **first item only**; it sets the whole block. `shape` on a later item leaves the block plain. |
| `color` | no | The bar's or the ring's arc [color](#colors); the default is the accent. |
| `text` | no | What shows beside the bar or inside the ring (see below). |
| `striped` | no | `true` for moving stripes on a bar. A ring takes none: `striped: true` on a ring leaves the block plain. |

### Rings

`shape: ring` draws each item as a ring instead of a bar: an arc from 12 o'clock as long as the share, the percentage in the middle and the label under it. The rings in one block sit side by side and wrap; in a card with `align=center` they are centered. A ring scales with the text, so it fits a slide or a column the same way.

````markdown
```progress
shape: ring
label: Revenue target
value: 48
max: 52
color: success
---
label: Onboarding
value: 81
max: 100
```
````

### The text

`text` sets what shows beside a bar or inside a ring. It is a template: `{value}` and `{max}` are the numbers as written in the block (with thousands separators), and `{percent}` is the share, rounded, with its `%` sign (`100%` at most).

| You want | Write | Shows for 48 of 52 |
| --- | --- | --- |
| Value and max | `text: {value} / {max}` | `48 / 52` — a bar's default |
| Percentage | `text: {percent}` | `92%` — a ring's default |
| Your own words, with numbers | `text: ${value}k of ${max}k` | `$48k of $52k` |
| Your own words | `text: On track` | `On track` |
| Nothing | `text: none` | — |

Anything that isn't one of the three placeholders shows as typed, so a typo such as `{total}` is visible rather than lost. A ring's text shrinks to fit and is cut off when it is much longer than about 6 characters. Screen readers read the `text` when you set one, and the value otherwise.

`striped: true` draws moving diagonal stripes over a bar's fill, to mark work still in progress. The stripes move only while the bar is on screen, stand still when macOS Reduce Motion is on and in print and PDF, and a full bar has none. Any value other than `true` or `false` leaves the block plain.

## Shortcodes

A shortcode is a widget written inline, as inline code: `` `{{name: arguments}}` ``. It sits in a sentence, a list item or a table cell, where a fenced block can't.

```markdown
| Service | Trend | Status |
| --- | --- | --- |
| API | `{{sparkline: 120,132,128,150,171}}` | `{{badge: Healthy color=success}}` |
| Search | `{{sparkline: 80, 78, 64, 58 color=warning}}` | `{{badge: "Slow queries" color=warning}}` |
```

- The colon right after the name is required: `{{badge Done}}`, an unknown name, or template code such as `{{ user.name }}` stays ordinary inline code.
- Arguments are separated by spaces: the widget's main value first, then `key=value` options.
- Wrap a value with spaces in `"…"` or `'…'` (`"In review"`); use one kind of quote to hold the other (`'Say "hi"'`). There are no backslash escapes.
- A value ending in a comma continues into the next, so `3, 5, 2, 8` is one list.
- An option a widget doesn't take, or an extra value, is ignored: `{{badge: In review}}` shows only "In", so quote text with spaces.
- An unclosed quote, a repeated option, a missing main value or a bad value (`color=purple`) leaves the shortcode as the inline code it is.

### Sparklines

`` `{{sparkline: 3,5,2,8,6 color=success}}` `` draws two or more numbers, in order, as a small line the height of the text, scaled between the lowest and the highest; when every number is the same, the line is flat across the middle. `type=bar` draws one bar per number instead, growing from zero (down for a negative number); a zero shows as a thin sliver. `type` is `line` (the default) or `bar`; anything else leaves the shortcode as code. `color` is optional ([colors](#colors)); without it the line or bars are the accent color. Find, copy and VoiceOver get the values as text (`Sparkline: 3, 5, 2, 8, 6`).

### Progress

`` `{{progress: 7/12}}` `` or `` `{{progress: 58%}}` `` draws a small progress bar, half the text's height, for a table cell or a sentence. Write the value as a fraction (`7/12`, value 0 or more and maximum above 0) or a percentage; a value above the maximum shows a full bar. By default only the bar is drawn (screen readers and copy get "Progress: 7 / 12"); `text=` adds text after it, with the same `{value}`, `{max}` and `{percent}` template as the [block](#progress) (`text="{percent}"`, `text="7 of 12 done"`). `color` sets the fill (accent without one) and `striped=true` adds the moving stripes. The block form, with labels and rings, is unchanged.

### Badges

`` `{{badge: "Build passing" color=success}}` `` shows its text in a color on a pale tint of that color. `color` is optional ([colors](#colors)); without it a badge is grey. On a light page the text is darkened so it stays readable, a hex color too. Several badges side by side are several shortcodes on one line. A fenced ```` ```badge ```` block is no longer drawn; it shows as a plain code block.

```markdown
`{{badge: Shipped style=solid color=success}}` `{{badge: Draft style=outline}}` `{{badge: v2 kind=rounded size=sm}}`
```

| Option | Values | What it does |
| --- | --- | --- |
| `color` | [colors](#colors) | The badge's color; grey without one. |
| `style` | `tint` (default), `solid`, `outline` | The same looks as a [shape](#shapes)'s: the text in the color on a pale tint, the color with white text (dark on `warning`), or a ring in the color. |
| `kind` | `pill` (default), `rounded`, `square` | Round ends, small rounded corners, or sharp corners. |
| `size` | `sm`, `md` (default), `lg` | A badge scales with the text around it; `size` makes it smaller or bigger than that. |
| `ink` | `light`, `dark` | The text color, white or near-black, instead of the automatic one. Use `ink=dark` on a solid badge in a light hex color. |

A value outside its list leaves the badge as code. In a card with `style=solid`, a badge is redrawn in the card's text color so it stays visible.

### Shapes

`` `{{shape: 1}}` `` draws a few characters (a step number, a letter, `98%`) in the middle of a marker, centered on the line. Use it to number steps on a slide, or to mark items in a list, a table or a card heading.

```markdown
`{{shape: 1}}` Import · `{{shape: 2}}` Style · `{{shape: 3 color=success}}` Present

`{{shape: A kind=rounded style=tint size=lg}}` `{{shape: 98% style=outline color=info size=xl}}`

`{{shape: 1 kind=hexagon}}` `{{shape: ! kind=diamond color=warning}}` `{{shape: v2.1 kind=pill style=tint}}`
```

| Option | Values | What it does |
| --- | --- | --- |
| `kind` | `circle` (default), `rounded`, `square`, `pill`, `hexagon`, `diamond` | The outline. `rounded` is a square with rounded corners and `square` one with sharp corners, as on a [card](cards.md). A `pill` has round ends and grows with its text. A `hexagon` (point up) and a `diamond` are drawn as shapes of their own, in every style. |
| `style` | `solid` (default), `tint`, `outline` | The same names as a card's styles. `solid` is the color with white text, or dark text on `warning`; with a light hex color, add `ink=dark`. `tint` is a badge's look: the text in the color on a pale tint of it. `outline` is a ring in the color around text in the color. |
| `color` | [colors](#colors) | The shape's color; the accent without one. |
| `size` | `sm`, `md` (default), `lg`, `xl` | A shape scales with the text around it, so one in a heading or on a slide is bigger; `size` makes it smaller or bigger than that. |
| `ink` | `light`, `dark` | The text color, white or near-black, instead of the automatic one. It wins everywhere, also on `warning` and inside a solid card. Use `ink=dark` on a solid shape in a light hex color. |

- Every kind but `pill` is as tall as it is wide and takes one to three characters; two or three are drawn smaller to fit, a little smaller again in a hexagon or a diamond, and a trailing `%` smaller still, as on a gauge.
- A `pill` takes up to twelve characters, such as a version or a short label, and keeps the text size.
- More characters, no text, or a `kind`, `style` or `size` outside its list leaves the shortcode as code. `style=filled` is now `style=solid`.
- In a card with `style=solid`, a shape is redrawn in the card's text color so it stays visible.
- For a step's title next to its number, write both on one line or put the shape at the top of a [column](columns.md).

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
| `colors` | no | Up to eight [colors](#colors), separated by commas, for the series in order, or a pie's or donut's slices: `colors: success, danger, #6366F1`. `default`, and series past the list, keep the chart's own series colors. |
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

Mermaid's [`xychart-beta` and `pie`](https://mermaid.js.org) still work in any document and also render on GitHub, but they keep Mermaid's own colors rather than the widget palette below.

## Colors

Every widget draws with one shared palette of semantic colors, in a light and a dark version that follow the page's appearance.

One key, `color`, picks a color on a stat (its value, and with a look option its tile), a progress bar (its fill), a sparkline (its line), a badge (its text and tint) and a [card](cards.md); a chart's `colors` takes a list of the same values. Each takes a name from the table below or a hex color (`#RGB` or `#RRGGBB`), and each widget puts it where it belongs: you say *what it means*, not "text" or "background". `default` is the widget's normal look. Anything else, such as `red` or `#12345`, leaves the block plain. A hex color stays the same in light and dark mode; the names follow it.

| Name | Used for | Light | Dark |
| --- | --- | --- | --- |
| `default` or `neutral` (`--widget-default`) | Badges without a color, flat deltas | `#8E8E93` grey | `#98989D` |
| `accent` (`--widget-accent`) | Progress bars, sparklines and cards without a color | `#007AFF` blue | `#0A84FF` |
| `success` (`--widget-success`) | Good deltas | `#34C759` green | `#30D158` |
| `info` (`--widget-info`) | | `#30B0C7` teal | `#40C8E0` |
| `warning` (`--widget-warning`) | | `#FF9500` orange | `#FF9F0A` |
| `danger` (`--widget-danger`) | Bad deltas | `#FF3B30` red | `#FF453A` |
| Series 1–8 (`--widget-series-1` … `-8`) | Chart series and pie slices, in order; a ninth starts again at the first | Apple's system blue, orange, teal, purple, green, pink, yellow, grey | their dark-mode versions |

These are Apple's standard system colors, one set for every widget: a `warning` badge is the same orange as a chart's second series. Badges are their color as text on a pale tint of it. Text and lines in a named color, a stat's value or delta and a sparkline, are darkened on a light page so they stay readable, and are the color itself on a dark one; a hex color is used as written.

Text, the progress track (a light tint of the text color) and the stat tile's outline follow the page's own theme colors; a stat tile's fill (`--widget-card`) is the theme's code block background, in every theme.

The built-in themes, and Quick Look, use these two palettes; there is no setting for them. A theme file can change them: as the reading theme (**View → Theme**) for every document, or as a deck's `theme:` on its slides. A theme file sets `--widget-default`, `--widget-accent`, `--widget-success`, `--widget-info`, `--widget-warning`, `--widget-danger` and `--widget-series-1` … `--widget-series-8`. A deck's `theme_overrides:` uses the `colors:` keys `widget_default`, `widget_accent`, … `widget_series_8`. See [Slides](slides.md#themes).

## Invalid blocks and other viewers

A block with a missing required key, an unknown value (`color: purple`, `trend: sideways`, `type: radar`), a value that should be a number but isn't, a line that is not `key: value`, or a chart table with a missing separator row or a row of the wrong length is left as the plain code block it is in the file. The rest of the document still renders. Other Markdown viewers show every block that way, and every shortcode as inline code.

## Where it renders

Read mode, Quick Look, PDF export and [slides](slides.md) (a deck draws widgets inside its slides) draw the widgets. The editor shows the blocks and shortcodes as text, and DOCX export writes each as the code it is. A shortcode in a footnote stays inline code.
