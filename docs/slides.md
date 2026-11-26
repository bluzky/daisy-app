# Slides

A Markdown file can be a slide deck. Read Mode shows it as a strip of 16:9 slides with each slide's speaker notes under it, **View → Present** (<kbd>⌥⌘P</kbd>) shows it full screen, and PDF export prints one slide per page. Everything Daisy renders works on a slide: headings, lists, tables, code, callouts, math, Mermaid, tasks and footnotes.

```markdown
---
slides: true
---

# Quarterly review
Daisy team

---

## What shipped

- Tasks sidebar
- Query blocks <!-- step -->

???
Mention the query block guide.
```

See [`samples/slides.md`](../samples/slides.md) for a deck that uses every feature below.

- [Turning a file into a deck](#turning-a-file-into-a-deck)
- [Deck settings](#deck-settings)
- [Themes](#themes)
- [Slides](#slides-1)
- [Speaker notes](#speaker-notes)
- [Layouts](#layouts)
- [Directives](#directives)
- [Backgrounds](#backgrounds)
- [Image sizes](#image-sizes)
- [Step-by-step reveals](#step-by-step-reveals)
- [Columns](#columns)
- [Empty lines](#empty-lines)
- [Captions](#captions)
- [Footnotes](#footnotes)
- [Widgets](#widgets)
- [Editing a deck](#editing-a-deck)
- [Presenting](#presenting)
- [Export](#export)
- [Syntax summary](#syntax-summary)

## Turning a file into a deck

Add `slides: true` to the frontmatter. TOML frontmatter (`slides = true`) works too. Marp's `marp: true` is not read.

```markdown
---
slides: true
---
```

A deck's frontmatter configures the deck and is not shown. Without it, a file reads as an ordinary document, where `---` is a horizontal rule. **View → Present** shows any Markdown file as slides, with or without the frontmatter, without changing the file.

## Deck settings

The frontmatter can also set:

```markdown
---
slides: true
theme: midnight-navy
aspect: 4:3
paginate: true
header: Daisy
footer: "{title} | {date} | {slide_number}/{total}"
title: Quarterly review
author: Linh
date: 4 Nov 2026
---
```

| Key | Effect |
| --- | --- |
| `theme` | The deck's look; see [Themes](#themes). |
| `theme_overrides` | Changes single theme colors or fonts for this deck. |
| `aspect` | Slide shape: `16:9` (default), `16:10` or `4:3`. Presenting and PDF pages follow it. |
| `font_size` | The base text size: a percentage of the default (`120%`) or pixels on a 1280 px wide slide (`36`). Everything on the slide scales with it. Kept between `50%` and `200%`. |
| `paginate` | `true` shows the slide number in the bottom-right corner. |
| `header`, `footer` | A line of small text at the top or bottom of every slide. |
| `title`, `author`, `date` | Fill `{title}`, `{author}` and `{date}` in the header and footer. |

In `header` and `footer`, `{title}` is the `title` setting, or the first H1 in the deck; `{date}` is the `date` setting, or today's date; `{slide_number}` and `{total}` count slides from 1. A `|` splits the text into left, center and right parts: `"{title} | | {slide_number}/{total}"` puts the title on the left and the count on the right. Quote a value that contains `{`, `|` or `#`.

A slide can change these for itself:

| Directive | Effect on its slide |
| --- | --- |
| `<!-- _font_size: 120% -->` | This slide's base text size, same values as `font_size`. |
| `<!-- _paginate: false -->` | Hides the slide number (`true` shows it when the deck doesn't). |
| `<!-- _header: text -->`, `<!-- _footer: text -->` | Replaces the header or footer; an empty value (`<!-- _footer: "" -->`) hides it. |

## Themes

`theme:` in the frontmatter picks the deck's look, by id; case doesn't matter. Without it, with `theme: default`, or with a name Daisy doesn't know, slides follow the reading theme.

Every reading theme can be named, and a few themes are made for slides:

| Theme | Look |
| --- | --- |
| `original`, `quiet`, `paper`, `calm`, `focus`, `ember`, `dusk`, `midnight` | The reading themes of the same names: their colors and fonts on the slides. |
| `pitch` | A reading theme too. White slides, blue headings; title and section slides on solid blue; table headers in white on blue. |
| `paper-warm` | Warm off-white, brown headings, serif type. |
| `midnight-navy` | Dark blue slides; title and section slides on a brighter blue. |

Values a theme doesn't set still come from the reading theme. Code on a slide follows the theme: a dark-only theme gets dark-mode code colors even in a light window, and the other way round; a theme that follows the system follows the window.

> **Renamed slide themes.** The slide themes `paper` and `midnight` are now `paper-warm` and `midnight-navy`. `paper` and `midnight` mean the reading themes. The `light` and `dark` slide themes are gone, and so is the reading theme `bold`, so a deck that names them uses the reading theme.

### Your own themes

A theme is a CSS file in `~/.config/daisy/themes/`. Its file name without `.css` is its id. A file with a built-in theme's id is ignored, and so is a file that doesn't say `light`, `dark` or `system` (itself or through `extends`).

The same file works as a deck's `theme:` and as the reading theme. **View → Theme** lists the built-in themes, then yours; choosing one restyles the reading view and the editor in every window. **View → Theme → Open Themes Folder** opens (and creates) the folder.

As the reading theme:

- A light-only or dark-only theme locks the app's appearance to match; a `system` theme sets it to Automatic.
- Customize is unavailable and the page uses the default spacing: change the theme by editing its file.
- If the file is deleted or no longer valid, the reading theme goes back to Original.

```css
/* @theme
name: My Brand
appearance: light
extends: pitch
footer: "{title} | | {slide_number}/{total}"
*/
:root {
  --bg: #FFFFFF;
  --text: #1A1A1A;
  --heading: #0057B8;
  --link: #0057B8;
  --bold: #B8003F;
  --code-bg: #F5F7FA;
  --slide-title-bg: #0057B8;
  --slide-title-text: #FFFFFF;
  --font-heading: Georgia, serif;
  --font-body: Inter, sans-serif;
  --font-code: JetBrains Mono, monospace;
}
```

The `@theme` comment holds the theme's settings:

| Key | Meaning |
| --- | --- |
| `name` | The name shown for the theme. |
| `appearance` | `light`, `dark` or `system` (has a light and a dark palette). Required, unless the theme it `extends` has one. |
| `extends` | Starts from a built-in theme or another of your themes; set only what differs. |
| `header`, `footer` | A template like the frontmatter's. The deck's own `header` and `footer` win. |

`:root { … }` holds the theme's values; a `system` theme puts its dark values in `@media (prefers-color-scheme: dark) { :root { … } }`. In dark, a value only `:root` sets comes from the reading theme's dark colors instead.

| Value | Meaning |
| --- | --- |
| `--bg`, `--text` | Slide background and body text. |
| `--heading`, `--heading-1` … `--heading-6` | All headings, or one level. |
| `--link` | Links and list bullets. |
| `--bold` | Bold text. |
| `--code-bg` | Code block background, also the stat tile fill. |
| `--table-header-bg`, `--table-header-text` | Background and text of a table's header row. |
| `--table-border`, `--table-stripe` | A table's lines, and the shaded rows of a `striped` table. |
| `--table-style` | `lines` (default: a rule above and below each row), `grid` (borders between all cells), `striped` (every other row shaded) or `minimal` (only a rule under the header). |
| `--widget-default`, `--widget-accent`, `--widget-success`, `--widget-info`, `--widget-warning`, `--widget-danger`, `--widget-series-1` … `--widget-series-8` | The [widget palette](widgets.md#colors): cards, badges, shapes, stat tiles, progress bars and charts. |
| `--font-body`, `--font-heading`, `--font-code` | Font lists for body text, headings and code. |
| `--body-weight` | `400` or `600` (heavier body text). |
| `--slide-title-bg`, `--slide-title-text` | Background and text of title and section slides. Slides only. |
| `--slide-font-size` | The base text size, like the frontmatter's `font_size`, which wins over it. Slides only. |

Everything else applies to the reading view and the editor too, except that the editor draws a deck's widgets with the reading theme's `--widget-*` colors. `header` and `footer` are slides only. If a theme sets no heading or code font, headings use the body font and code keeps the default monospace.

Colors are hex values (`#rgb`, `#rgba`, `#rrggbb` or `#rrggbbaa`); color names aren't accepted. Fonts are lists of names. Any other rule, value or property is ignored, so a theme can't break the page. Theme files are read each time a deck renders: after editing one, edit or reopen the deck to see it. An edit to the reading theme's file shows when you switch back to Daisy or open **View → Theme**. Quick Look decks use the built-in themes only, and Quick Look ignores your reading theme's colors.

#### Themes from earlier versions

YAML slide themes in `~/.config/daisy/slide-themes/` are no longer read. The files stay on disk.

To keep one, write it as a CSS file in `~/.config/daisy/themes/`. Add an `@theme` comment with `name`, `appearance` and `extends`. Then turn each YAML key into a value:

| YAML key | CSS value |
| --- | --- |
| `colors.background`, `text`, `heading`, `bold` | `--bg`, `--text`, `--heading`, `--bold` |
| `colors.accent` | `--link` |
| `colors.code_background` | `--code-bg` |
| `colors.primary`, `title_text` | `--slide-title-bg`, `--slide-title-text` |
| `colors.table_header`, `table_header_text`, `table_border`, `table_stripe` | `--table-header-bg`, `--table-header-text`, `--table-border`, `--table-stripe` |
| `colors.widget_accent`, `widget_series_1`, … | `--widget-accent`, `--widget-series-1`, … |
| `fonts.body`, `title`, `code`, `size` | `--font-body`, `--font-heading`, `--font-code`, `--slide-font-size` |
| `table.style` | `--table-style` |

Write colors as hex. For the old `pitch`, `paper` and `midnight`, use `extends: pitch`, `paper-warm` or `midnight-navy`. For the old `light` and `dark`, set the colors yourself.

### Changing a theme for one deck

```markdown
---
slides: true
theme: pitch
theme_overrides:
  colors:
    heading: "#C00000"
---
```

`theme_overrides` takes YAML keys, as theme files did before:

| Key | Sets |
| --- | --- |
| `colors.background`, `text`, `heading`, `bold`, `code_background` | `--bg`, `--text`, `--heading`, `--bold`, `--code-bg` |
| `colors.accent` | `--link` (`primary` is used when there is no `accent`) |
| `colors.primary`, `title_text` | `--slide-title-bg`, `--slide-title-text` |
| `colors.table_header`, `table_header_text`, `table_border`, `table_stripe` | The table colors |
| `colors.widget_accent`, `widget_series_1`, … | The widget palette |
| `fonts.body`, `title`, `code`, `size` | `--font-body`, `--font-heading`, `--font-code`, `--slide-font-size` |
| `table.style` | `--table-style` |
| `appearance` | `light` or `dark` |
| `header`, `footer` | The theme's header and footer |

Colors are hex, as in theme files.

## Slides

A line with only `---` starts the next slide. `***` and `___` work too.

```markdown
# First slide

---

## Second slide
```

Only a `---` at the top level of the file counts. These are not slide breaks:

- `---` directly under a line of text, which makes that text a heading (`Title` followed by `---`);
- `---` inside a list, a quote or a code block;
- the frontmatter's own `---` lines.

A `---` at the very start or end of the file adds no empty slide. Two `---` in a row make a blank slide. For a horizontal rule inside a slide, write `<hr>`.

## Speaker notes

A paragraph whose first line is `???` starts the slide's notes. Everything after it, up to the next `---`, is notes.

```markdown
## Results

- Revenue up 12%

???
Pause here for questions.
Mention the Q3 dip.
```

- The notes text can start on the line right after `???`, or after a blank line.
- `???` with other text on the same line, or inside a list, is ordinary text.
- Notes are Markdown: lists, links and code work.
- Read Mode shows notes under each slide. The presenter view shows the current slide's notes. They never appear on the presented slide or in a PDF.
- Directives written in the notes are ignored.

## Layouts

Each slide gets a layout from its content. The first matching rule wins:

| Content | Layout | Look |
| --- | --- | --- |
| `<!-- layout: name -->` | that layout | |
| Two or more columns from `<!-- column -->` | `columns` | equal columns below the heading |
| `![bg left]` or `![bg right]` | `split` | image on one half, text centered vertically on the other |
| `![bg]` and nothing else | `full-bleed` | the image fills the slide |
| An H1 alone, or with one paragraph of up to 200 characters | `title` | centered, large title, muted subtitle |
| An H2 alone | `section` | centered, large heading |
| A quote alone (not a callout) | `quote` | centered, large italic |
| One code block or Mermaid diagram, with an optional heading | `code` | |
| Display math, with an optional heading | `math` | centered, larger formula |
| A heading and one image | `title-image` | the image fills the space below the heading |
| Anything else | `title-content` | top left, the usual slide |
| Nothing | `blank` | |

HTML comments don't count as content, and a background image is ignored by every rule except `split` and `full-bleed`: `# Title` with `![bg](photo.jpg)` is a `title` slide with a background.

Long content is not shrunk to fit: anything that doesn't fit on the slide is cut off. A tall Mermaid diagram or image is the exception; it shrinks to the space left on the slide.

## Directives

Directives are HTML comments, so other Markdown viewers don't show them. Write them on their own lines, anywhere on the slide; they apply to that slide only. Unknown directives and invalid values are ignored, so an ordinary comment like `<!-- TODO: shorten -->` changes nothing.

One comment can hold several directives, one per line, as in Marp:

```markdown
<!--
layout: title
_class: invert center
color: "#ffffff"
-->
```

A value may be quoted, which a value starting with `#` needs in Marp. Several comments can also share a line: `<!-- layout: title --> <!-- _class: invert -->`.

### `layout`

Sets the slide's layout instead of inferring it.

```markdown
<!-- layout: section -->

## Part two
```

Names: `title`, `section`, `quote`, `code`, `math`, `title-image`, `split`, `full-bleed`, `columns`, `title-content`, `blank`.

### `_class`

Adds classes to the slide. Several are separated by spaces.

```markdown
<!-- _class: invert center -->

## Thank you
```

| Class | Effect |
| --- | --- |
| `center` | Centers the content horizontally and vertically. |
| `center-x` | Centers horizontally only. |
| `center-y` | Centers vertically only. |
| `lead` | Same as `center` (Marp's name). |
| `invert` | Dark slide with light text. |

### `color`

Sets the slide's text color, headings included. `_color` (Marp's spelling) works too.

```markdown
<!-- color: #0057b8 -->
```

The value is a hex color (`#fff`, `#ffff`, `#0057b8`, `#0057b8cc`) or a color name (`white`, `navy`).

## Backgrounds

An image whose alt text starts with the word `bg` is the slide's background.

```markdown
# Launch day

Everything ships at 9:00

![bg dim](photos/stage.jpg)
```

| Syntax | Effect |
| --- | --- |
| `![bg](image.jpg)` | Fills the whole slide, cropped to fit. The slide's content sits on top. |
| `![bg left](image.jpg)` | Fills the left half; the content moves to the right half. |
| `![bg right](image.jpg)` | Fills the right half; the content moves to the left half. |
| `![bg fit](image.jpg)` | Shows the whole image instead of cropping it. `contain` works too, and combines with `left` and `right`: `![bg right fit](image.jpg)`. |
| `![bg dim](image.jpg)` | Darkens the image so text on it reads. Over a full background the text also turns white; a `color` directive still wins. Combines with the other keywords. |
| `![bg blur](image.jpg)` | Blurs the image. The text color doesn't change; add `dim` for white text: `![bg dim blur](image.jpg)`. |

- The keywords go in the alt text, in any order after `bg`, in any letter case. The title (`"…"`) is never a keyword.
- The image must be alone in its paragraph. `See ![bg](a.jpg) here` or an image in a list is an ordinary image.
- Only the first background on a slide is used.
- Paths are relative to the Markdown file, as for any image.

## Image sizes

On a slide, an image's title sets its width:

```markdown
![Architecture](diagram.png "60%")
```

The size is a number with `%`, `px`, `em`, `rem` or `cqi`; `%` is a share of the space the image is in. A title that isn't a size stays an ordinary title. Outside a deck, the title is always a title.

## Step-by-step reveals

While presenting, an element marked with `<!-- step -->` appears on the next click.

```markdown
## Plan

- Measure
- Fix <!-- step -->
- Ship <!-- step -->
```

- **At the end of a list item or paragraph,** it reveals that item or paragraph. It must be the last thing in the text: a `<!-- step -->` in the middle of a sentence is ignored.
- **On its own line,** it reveals the next block: a code block, table, image, quote, diagram or a whole list.

  ````markdown
  <!-- step -->
  ```swift
  ship()
  ```
  ````

- **Numbering.** Each `<!-- step -->` takes the next click. `<!-- step: n -->` puts the element on click `n`, so several elements can appear together:

  ```markdown
  - Problem
  - Cause <!-- step: 1 -->
  - Impact <!-- step: 1 -->
  - Fix <!-- step: 2 -->
  ```

Next reveals the next step and moves to the next slide after the last one; Previous hides the last step and returns to the previous slide fully revealed; jumping to a slide starts it with nothing revealed. Read Mode and PDF export show every step.

## Columns

`<!-- column -->` on its own line starts a new column. `<!-- end-columns -->` ends them. `<!-- columns -->` before the first column is optional: it marks where the columns begin, so anything above it stays above them, across the slide. Ordinary documents use the same three comments; see [Columns](columns.md).

```markdown
## Before and after

- Slow builds
- Manual releases

<!-- column -->

- Cached builds
- One-command releases

<!-- end-columns -->

> [!note]
> Both pipelines ship from the same tag.
```

- Without `<!-- columns -->`, a heading at the top of the slide stays above the columns, across the slide. With it, everything above the comment does: the heading, text lines, an image.
- Everything after `<!-- end-columns -->` spans the slide below the columns. Without it, the rest of the slide stays in the last column.
- The columns share the slide's width equally and keep the slide's text size, so keep each one short.
- A tall image or diagram in a column shrinks to fit the slide; an image alone in its paragraph is centered in its column. For images side by side, put each in its own column.
- A break right after the heading, or just before the end, adds no empty column. A slide needs two columns to be split.
- At most four columns: a fifth or later break is ignored, and the rest stays in the fourth column.
- One set of columns per slide: breaks after `<!-- end-columns -->` are ignored, and so is an end before any break.
- Only breaks at the top level count; one inside a list is ignored.

Kova's `|||` column break is not supported.

## Empty lines

Blank lines don't add space on a slide. `<!-- space -->` on its own line adds one empty line, and `<!-- space: n -->` adds `n`, up to 10.

```markdown
## Agenda

<!-- space: 2 -->

1. Results
2. Plans
```

The space is the slide's line height, so it scales with the slide. A count of 0 or one that isn't a number is ignored.

## Captions

`!caption[text]` on its own line, right below an image, table, diagram or formula, adds a small centered caption.

```markdown
## Sales

![Chart](sales.png)

!caption[Figure 1: sales by quarter]
```

A caption doesn't change the slide's layout: a heading, an image and a caption is still a `title-image` slide. Outside a deck, `!caption[…]` is ordinary text.

## Footnotes

Footnotes keep their numbers across the deck. Each slide lists, at its bottom, the footnotes it references; a footnote referenced on several slides is repeated on each. A footnote referenced in the notes is listed in the notes. Where the definition sits in the file doesn't matter, and definitions no slide references are not shown.

```markdown
## Growth

Revenue grew 12%[^q3].

[^q3]: Q3 report, page 4.
```

## Cards

Frame blocks as a panel with `<!-- card -->` and `<!-- end-card -->`, each on its own line, as in an ordinary document; options such as `style=accent color=success` go in the opening comment. See [Cards](cards.md) for every option.

````markdown
## Q3 at a glance

<!-- card style=accent color=success -->
### Revenue
$48.2k, up 12%
<!-- end-card -->
<!-- column -->
<!-- card style=accent color=danger -->
### Churn
2.1%, down 0.4%
<!-- end-card -->
````

- A card goes in the slide body or inside a column. Alone in a column, it fills the column's height, so a row of cards lines up. Columns are as tall as the tallest one, not the whole slide, so a lone card next to shorter columns doesn't stretch to the bottom.
- A card must open and close within one column, or within the part of the slide above or below the columns; one that crosses a `<!-- column -->` frames nothing.
- A card's padding and corners follow the slide's text size.
- `shape=circle` draws a circle that keeps its shape: it is centered in its column and not stretched to the column's height.

## Widgets

Stat tiles, charts, progress bars, sparklines, status badges and shapes work on slides too. Write `stat`, `chart` and `progress` blocks and `{{sparkline: …}}`, `{{progress: …}}`, `{{badge: …}}` and `{{shape: …}}` shortcodes as in an ordinary document; see [Widgets](widgets.md) for every key.

````markdown
---
slides: true
---

## Revenue grew 12% this quarter

```stat
label: Revenue
value: $48.2k
delta: +12%
trend: up
---
label: Churn
value: 2.1%
delta: -0.4%
trend: down
good: down
```
````

- A `---` line inside a `stat` or `progress` block separates its items; it does not start a new slide.
- Widgets size their text from the slide's text, like everything else on it.
- A bar or line chart is drawn at the full width of its column, twice as wide as it is tall (a horizontal bar chart grows taller with each row), and does not shrink to fit the slide. Give it a slide with only a short heading, or put it in a column; a `pie` or `donut` is at most 320px wide. Mermaid's `xychart-beta` and `pie` also work and shrink to fit like any Mermaid diagram.

## Editing a deck

- **Slide Preview.** **View → Slide Preview** (<kbd>⌘9</kbd>) opens the deck's slides in the right-hand pane, next to the editor. It updates a moment after you stop typing, outlines the slide the cursor is in, and scrolls to it when the cursor moves to another slide. Click a slide to jump to it: the editor scrolls there and puts the cursor at the start of the slide, or, in Read Mode, the document scrolls to it. Clicks on links, buttons and selected text are left alone. Notes are hidden there. Widen the pane for bigger slides.
- **Back to Read Mode.** Leaving Edit Mode (<kbd>⌘E</kbd>) shows the slide the cursor was in, from its top.
- **Slash commands.** In a deck, the `/` menu has a **Slides** group: **New Slide** (`---`), **Speaker Notes** (`???`), **Reveal Step** (`<!-- step -->`) and **New Column** (`<!-- column -->`).

## Presenting

**View → Present** (<kbd>⌥⌘P</kbd>) shows the deck full screen from the first slide, on an external display when there is one. **View → Present from Current Slide** (<kbd>⇧⌥⌘P</kbd>) starts at the slide the cursor is in, or in Read Mode at the slide at the top of the window. While editing, both present the editor's current text.

With two displays, a presenter window on the other display shows the current slide with its notes, the next slide, the slide and step number, and the time since you started. Closing the presenter window keeps presenting, and so does unplugging a display. <kbd>esc</kbd> or closing the document ends the presentation. While another app is in front, the slides step back behind it. If the file changes while you present, the slides update and stay on the same slide.

| Key | What it does |
| --- | --- |
| <kbd>→</kbd> <kbd>↓</kbd> <kbd>Space</kbd> <kbd>⇟</kbd> | Next step, then next slide |
| <kbd>←</kbd> <kbd>↑</kbd> <kbd>⌫</kbd> <kbd>⇞</kbd> | Previous step, then previous slide |
| <kbd>↖</kbd> / <kbd>↘</kbd> | First / last slide |
| A number, then <kbd>↩</kbd> | Jumps to that slide; <kbd>↩</kbd> alone goes to the next step |
| <kbd>B</kbd> / <kbd>W</kbd> | Blanks the screen to black / white; press again to show the slide |
| <kbd>esc</kbd> | Ends the presentation |

Presentation clickers send Page Up and Page Down, so they work without setup. The display stays awake while presenting.

## Export

**File → Export → PDF…** and **File → Print…** lay a deck out one slide per 16:9 page, with every step shown and without the notes.

## Syntax summary

| Syntax | Meaning |
| --- | --- |
| `slides: true` in frontmatter | The file is a deck. |
| `theme`, `theme_overrides`, `aspect`, `font_size`, `paginate`, `header`, `footer`, `title`, `author`, `date` in frontmatter | Deck settings. |
| `---` on its own line | Starts the next slide. |
| `???` line | Starts the slide's speaker notes. |
| `<hr>` | A horizontal rule inside a slide. |
| `![bg](img)`, `![bg left]`, `![bg right]`, `![bg fit]`, `![bg dim]`, `![bg blur]` | Background image. |
| `![alt](img "50%")` | Image width. |
| `<!-- layout: name -->` | Sets the layout. |
| `<!-- _class: name -->` | Adds a class: `center`, `center-x`, `center-y`, `lead`, `invert`. |
| `<!-- color: value -->` | Text color. |
| `<!-- step -->`, `<!-- step: n -->` | Reveals on a click. |
| `<!-- column -->`, `<!-- end-columns -->` | Columns. |
| `<!-- card key=value … -->`, `<!-- end-card -->` | A card around the blocks between them. |
| `<!-- space -->`, `<!-- space: n -->` | Empty lines. |
| `<!-- _paginate: … -->`, `<!-- _header: … -->`, `<!-- _footer: … -->` | This slide's number, header and footer. |
| `<!-- _font_size: … -->` | This slide's base text size. |
| `!caption[text]` | A caption under the block above. |
