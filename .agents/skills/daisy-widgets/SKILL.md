---
name: daisy-widgets
description: Write and fix dashboards, KPI pages, status reports and metric summaries as ordinary Markdown documents for Daisy — `stat` tiles, `chart` blocks (bar, stacked and horizontal bar, line, pie, donut), `progress` bars and rings, inline `{{sparkline: …}}` trend lines, `{{progress: 7/12}}` bars and `{{badge: …}}` labels, `<!-- card … -->` panels, and `<!-- columns -->` layouts, with the shared `color` key (default, accent, success, info, warning, danger or a hex). Use this whenever the user wants a dashboard, scorecard, metrics page, project status, OKR or release tracker, weekly report, or any chart or KPI in a Markdown file for Daisy — even if they only say "make a dashboard from these numbers". For slide decks use the daisy-slides skill instead; the same blocks work on slides.
---

# Daisy widgets

Daisy is a macOS Markdown app. In any Markdown file, three fenced blocks become widgets — `stat` tiles, `chart` charts and `progress` bars — and three shortcodes, written as inline code, draw inline widgets: `` `{{sparkline: …}}` ``, `` `{{progress: …}}` `` and `` `{{badge: …}}` ``. `<!-- card -->` frames blocks as a panel, and `<!-- columns -->` puts them side by side. Read mode, Quick Look and PDF export draw them; every other Markdown viewer shows the blocks and shortcodes as plain text, so the file stays readable anywhere. No frontmatter flag is needed.

The exact rules are in `references/widgets-guide.md` (widgets, charts, colors), `references/cards-guide.md` and `references/columns-guide.md` — Daisy's own docs. Read the relevant section when you need a rule this file only summarizes.

## Workflow

1. **Decide what the page answers.** Lead with 3–5 headline numbers (a `stat` row), then the charts that explain them, then status and next steps. Group related blocks with headings.
2. **Write it** with the syntax below. Every value is written in the file: there are no data files, formulas or fetches, so put the numbers straight into the blocks.
3. **Lint it:** `python3 scripts/check_widgets.py doc.md` (path relative to this skill). A block Daisy can't read stays plain code *silently*; the linter finds the missing key, the bad color, the unquoted badge text, the card that never closes. Fix every error.
4. **Tell the user** to open the file in Daisy (Read mode, ⌘E toggles editing).

## Widgets

Each block is `key: value` lines; a line of `---` separates items in a `stat` or `progress` block.

````markdown
```stat
label: Revenue
value: $48.2k
delta: +12%
trend: up
note: vs last month
---
label: Churn
value: 2.1%
delta: -0.4%
trend: down
good: down
color: success
```

```progress
label: Features
value: 9
max: 12
striped: true
---
label: Blockers
value: 2
max: 10
color: danger
```

Status `{{badge: "Build passing" color=success}}` `{{badge: "Docs behind" color=warning}}`

| Service | Requests | Status |
| --- | --- | --- |
| API | `{{sparkline: 120, 132, 128, 150, 171}}` | `{{badge: Healthy color=success}}` |
````

- **`stat`** — `label` and `value` required; `color` (the value), `delta`, `trend` (`up`/`down`/`flat`, colors the delta; ignored without a `delta`), `good: down` for metrics where down is good, `note`, `link` (an arrow to a URL, file or `#heading`). Tiles in one block share a row.
- **`progress`** — `label`, `value` (≥ 0), `max` (> 0); `color` (default accent), `striped: true` for work still moving (bars only). One row per bar: label, bar, `value / max`. `shape: ring` **on the first item** turns the whole block into rings side by side (percent in the middle, label under): the gauge for a KPI card. `text` changes the number shown, as a template: `{value} / {max}` (a bar's default), `{percent}` (a ring's default), `${value}k of ${max}k`, plain words, or `none`; keep ring text to ~6 characters.
- **Shortcodes** — inline code `{{name: arguments}}`, the colon right after the name: the main value first, then `key=value` options, separated by spaces. Quote a value with spaces (`"In review"`); a value ending in a comma continues (`3, 5, 2`). Options a widget doesn't take and extra values are **ignored**, so `{{badge: In review}}` shows only "In".
- **`{{sparkline: 3,5,2,8 color=… type=bar}}`** — two or more numbers as a text-height trend line, or bars from zero with `type=bar` (good for counts per day or week); `color` (default accent). Ideal in table cells, one per row.
- **`{{progress: 7/12 color=… striped=true text="{percent}"}}`** — a small bar from a fraction or a percentage (`58%`), bar only unless `text=` adds the same template as the block; for a table cell or a sentence. The ```` ```progress ```` block stays for labelled bars and rings.
- **`{{badge: "text" color=…}}`** — a status pill; `color` (grey without one). Several badges are several shortcodes on one line. There is no ```` ```badge ```` block any more: it shows as plain code.

## Colors

One key, `color`, everywhere: a stat's value, a progress bar's fill, a sparkline's line, a badge's text and tint, a card's border or bar (in a shortcode it's `color=success`). A chart's `colors` takes a comma list of the same. Values: `default` or `neutral` (the widget's normal look), `accent`, `success`, `info`, `warning`, `danger`, or a hex (`#6366F1`, `#fff`). Say what it *means*; each widget puts the color in the right place and keeps text readable in light and dark mode. Prefer names over hex: names follow the theme and dark mode, a hex is the same everywhere.

## Charts

````markdown
```chart
type: bar
title: Sales (k$)
colors: accent, success
legend:
  position: right
| Month | 2025 | 2026 |
| ----- | ---- | ---- |
| Jan   | 12   | 15   |
| Feb   | 18   | 21   |
```
````

- `type`: `bar`, `line`, `pie` or `donut` (required). Options come first, then a Markdown table: first column the labels, every other column a series of plain numbers (`1,200` and `-4` fine; no `$` or `%` — put units in the title or header).
- Bars: `stacked: true`, `direction: horizontal`. Any chart: `title`, `height: 240` (px, 80–1200; a pie's or donut's diameter), `values: false`, `grid: false`, `colors`.
- Groups of indented lines: `legend:` with `position` (`top`/`bottom`/`left`/`right`) and `visible`; `x-axis:` / `y-axis:` with `visible: false`. The one-line `legend: right` / `legend: none` also works.
- A `pie` or `donut` takes exactly one number column, all zero or more. A donut shows the total in the middle.
- A chart is drawn at the width it is shown at, half as tall (at least 200px); set `height` to keep a row of charts even.

## Cards and columns

```markdown
<!-- columns -->
<!-- card style=accent color=success -->
### Revenue
Up 12% on Pro upgrades
<!-- end-card -->

<!-- column -->
<!-- card style=accent edge=top color=danger -->
### Support SLA
68% against 90%
<!-- end-card -->

<!-- end-columns -->
```

- A row of gauges: one `progress` block with `shape: ring` inside a card with `align=center`, or one ring per card in columns.
- Card options, `key=value` in the opening comment: `style` (`plain`, `outline`, `filled`, `accent`), `color`, `tint=true`, `padding` (`compact`, `normal`, `roomy`), `align=center`, `edge=top` (accent bar across the top). There is no CSS.
- A card alone in a column fills the column's height, so a row of cards lines up. `align=center padding=compact` around a ring progress block makes a gauge.
- Columns: `<!-- columns -->`, `<!-- column -->` between parts, `<!-- end-columns -->`; 2–4 equal columns, stacked on a narrow window.

## Traps that render silently wrong

- **A typo leaves the block or shortcode as code**, not an error: an unknown color (`red`, `ok`, `positive`), a missing `label`/`value`, a shortcode without its colon (`{{badge Done}}`) or with an unclosed quote, a non-number in a chart cell, an option line after the table. Run the linter.
- **Badges are shortcodes now:** a ```` ```badge ```` block shows as plain code; write `{{badge: "Docs behind" color=warning}}`.
- **A card must close** (`<!-- end-card -->`) in the same column it opened; columns can't go inside a card, and cards don't nest.
- **Markers inside a list** (indented under a bullet) are ignored; keep them at the top level.
- **Units in chart cells** (`$12`, `12%`) make the chart plain.

## Writing good widget pages

- Headline numbers first; each with a `delta` and the right `good:` direction, so green always means good.
- One question per chart, said in its `title` or the heading above it.
- Use color for meaning, sparingly: `success`/`warning`/`danger` for status, `accent` for emphasis, `default` for everything else.
- Keep a row of cards or charts the same height (`height`, similar content) so it reads as a grid.
