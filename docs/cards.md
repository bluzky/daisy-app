# Cards

Frame blocks as one panel with HTML comments, each on its own line:

```markdown
<!-- card -->
### Revenue

Up 12% on last month.
<!-- end-card -->
```

Type `/card` to insert the two lines around the current line. The comments are invisible in other Markdown viewers, which show the blocks as usual.

A card holds any blocks: text, lists, tables, images, code, and [widgets](widgets.md) and charts. Put a heading inside it for a title.

## Options

Options go in the opening comment as `key=value` pairs, separated by spaces:

```markdown
<!-- card style=accent color=success padding=compact -->
```

Each part of a card's look is its own option. `style` is a shortcut that sets several of them at once.

| Option | Values | What it does |
| --- | --- | --- |
| `fill` | `none`, `surface` (default), `soft`, `tint`, `solid` | The background. `surface` is the theme's code-block background. `soft` and `tint` mix a little (8%) or more (14%) of the color into it, so they stay readable in light and dark mode. `solid` is the color itself, with white text (dark text on `warning`). |
| `border` | `none`, `thin` (default), `thick` | The outline. It takes the color when there is one, unless the card has a `bar`. |
| `bar` | `none` (default), `left`, `top` | A thick bar in the color down the left side or across the top. With a bar, the border keeps the theme's separator color. |
| `color` | `default` (or `neutral`), `accent`, `success`, `info`, `warning`, `danger`, or a hex color (`#6366F1`, `#fff`) | The one color the card uses for its bar, border and fill: the same [colors](widgets.md#colors) as every widget, which follow light and dark mode and the theme. `default` is the accent. A hex color stays the same in both modes. |
| `shape` | `rounded` (default), `square`, `pill`, `circle` | The card's outline. `square` has square corners and `pill` fully round ends. `circle` is a circle at most 14em across, centered, with its content centered in it; it keeps its shape instead of filling its column's height, so keep its content short, such as a number and a word. |
| `padding` | `none`, `compact`, `normal` (default), `roomy` | Space inside the card. A `pill` or `circle` keeps its own padding. |
| `align` | `start` (default), `center` | Centers the card's content, for example a single number or a gauge. |
| `style` | `plain` (default), `outline`, `filled`, `accent`, `solid`, `none` | A preset; see below. |

### Style presets

| `style` | Same as | Looks like |
| --- | --- | --- |
| `plain` | `fill=surface border=thin` | The theme's code-block background with a thin border. |
| `outline` | `fill=none border=thin` | A border only. |
| `filled` | `fill=tint border=none` | A tinted background, no border. |
| `accent` | `fill=surface border=thin bar=left` | A plain card with a colored bar down the left side. |
| `solid` | `fill=solid border=none` | The color itself, with white text. |
| `none` | `fill=none border=none` | Nothing visible: groups blocks, with the card's padding and alignment. |

An option written beside `style` overrides the preset, wherever it stands in the comment: `style=accent bar=top` puts the bar across the top, and `style=solid border=thick` adds a border to a solid card. Without `style`, a card starts from `plain`.

```markdown
<!-- card style=accent bar=top color=success -->
<!-- card style=solid color=info shape=pill -->
<!-- card style=none align=center -->
<!-- card fill=soft bar=top border=none color=warning -->
```

Values may be quoted (`color="#6366F1"`). There is no way to write CSS in a card: a value outside these lists, an unknown option, or one given twice leaves the card's blocks plain.

### Solid cards

On a `solid` card, headings, links (underlined), list markers, quotes, rules, table lines and inline code take the card's text color instead of the theme's, so they stay readable. A [`shape`](widgets.md#shapes) inside one is drawn in the text color so it doesn't vanish into the card. Other widgets, such as stat tiles, charts and progress bars, keep their own colors; put them in a `fill=soft` or `tint` card instead. For a light hex color, use `tint`: a solid card's text is white.

## Rules

- `<!-- card … -->` opens a card and `<!-- end-card -->` closes it. Both are required, and a card holds at least one block.
- A card with no closing comment, no blocks, or an invalid option is left as plain content, so a typo never frames the rest of the document.
- Cards do not nest. An opener inside an open card drops the outer card; the inner one still frames if it is well formed.
- A card can go inside a [column](columns.md), and a card alone in a column fills its height, so a row of cards lines up. Columns cannot go inside a card, and a card cannot span a column break.
- Only top-level comments count, or comments directly inside a column. A comment inside a list, quote or another block is ignored.
- Read mode, Quick Look and PDF export draw cards, and a card is not split across printed pages. The editor shows the comment lines. DOCX export lists the blocks one after another.

## Cards on slides

The same comments work in a [slide deck](slides.md#cards), in the slide body or inside a column. A card must open and close within one column, or within the part of the slide above or below the columns.

## Example: circles

```markdown
<!-- columns -->
<!-- card shape=circle style=filled color=success -->
### 48k
Users
<!-- end-card -->

<!-- column -->
<!-- card shape=circle style=outline color=info -->
### 98%
Uptime
<!-- end-card -->

<!-- end-columns -->
```

For a small numbered marker in a line of text, use the [`shape` shortcode](widgets.md#shapes) instead.

## Example: a row of cards

```markdown
<!-- columns -->
<!-- card style=accent color=success -->
### Revenue
$48.2k, up 12%
<!-- end-card -->

<!-- column -->
<!-- card style=accent color=danger -->
### Churn
2.1%, down 0.4%
<!-- end-card -->

<!-- end-columns -->
```
