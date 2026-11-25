# Cards

Frame blocks as one panel with HTML comments, each on its own line:

```markdown
<!-- card -->
### Revenue

Up 12% on last month.
<!-- end-card -->
```

Type `/card` to insert the two lines around the current line. The comments are invisible in other Markdown viewers, which show the blocks as usual.

A card holds any blocks: text, lists, tables, images, code, and [dashboard](dashboard.md) widgets and charts. Put a heading inside it for a title.

## Options

Options go in the opening comment as `key=value` pairs, separated by spaces:

```markdown
<!-- card style=accent color=success padding=compact -->
```

| Option | Values | What it does |
| --- | --- | --- |
| `style` | `plain` (default), `outline`, `filled`, `accent` | `plain` is the theme's code-block background with a thin border. `outline` is the border only. `filled` is a background tinted with the color and no border. `accent` adds a bar in the color down the left side, or across the top with `edge=top`. |
| `color` | `default`, `accent`, `success`, `info`, `warning`, `danger`, or a hex color (`#6366F1`, `#fff`) | The color of the border, the accent bar or the tint: the same [colors](dashboard.md#colors) as every dashboard widget, which follow light and dark mode and the theme. `default` is the card's normal look, the accent. A hex color stays the same in both modes. |
| `tint` | `true`, `false` (default) | Mixes a little of the color into the background. The tint is mixed into the theme's background, so it stays readable in light and dark mode. |
| `padding` | `compact`, `normal` (default), `roomy` | Space inside the card. |
| `align` | `start` (default), `center` | Centers the card's content, for example a single number or a gauge. |
| `edge` | `left` (default), `top` | Where an `accent` card's bar sits: down the left side or across the top. Other styles have no bar and ignore it. |

Values may be quoted (`color="#6366F1"`). There is no way to write CSS in a card: a value outside these lists, an unknown option, or one given twice leaves the card's blocks plain.

## Rules

- `<!-- card … -->` opens a card and `<!-- end-card -->` closes it. Both are required, and a card holds at least one block.
- A card with no closing comment, no blocks, or an invalid option is left as plain content, so a typo never frames the rest of the document.
- Cards do not nest. An opener inside an open card drops the outer card; the inner one still frames if it is well formed.
- A card can go inside a [column](columns.md), and a card alone in a column fills its height, so a row of cards lines up. Columns cannot go inside a card, and a card cannot span a column break.
- Only top-level comments count, or comments directly inside a column. A comment inside a list, quote or another block is ignored.
- Read mode, Quick Look and PDF export draw cards, and a card is not split across printed pages. The editor shows the comment lines. DOCX export lists the blocks one after another.

## Cards on slides

The same comments work in a [slide deck](slides.md#cards), in the slide body or inside a column. A card must open and close within one column, or within the part of the slide above or below the columns.

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
