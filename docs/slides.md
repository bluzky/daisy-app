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
- [Slides](#slides-1)
- [Speaker notes](#speaker-notes)
- [Layouts](#layouts)
- [Directives](#directives)
- [Backgrounds](#backgrounds)
- [Image sizes](#image-sizes)
- [Step-by-step reveals](#step-by-step-reveals)
- [Columns](#columns)
- [Empty lines](#empty-lines)
- [Footnotes](#footnotes)
- [Presenting](#presenting)
- [Export](#export)
- [Syntax summary](#syntax-summary)

## Turning a file into a deck

Add `slides: true` to the frontmatter. Marp's `marp: true` works the same way, and so does TOML frontmatter (`slides = true`).

```markdown
---
slides: true
---
```

A deck's frontmatter configures the deck and is not shown. Without it, a file reads as an ordinary document, where `---` is a horizontal rule. **View → Present** shows any Markdown file as slides, with or without the frontmatter, without changing the file.

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

`<!-- column -->` on its own line starts a new column. `<!-- end-columns -->` ends them.

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

- A heading at the top of the slide stays above the columns, across the slide.
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

## Footnotes

Footnotes keep their numbers across the deck. Each slide lists, at its bottom, the footnotes it references; a footnote referenced on several slides is repeated on each. A footnote referenced in the notes is listed in the notes. Where the definition sits in the file doesn't matter, and definitions no slide references are not shown.

```markdown
## Growth

Revenue grew 12%[^q3].

[^q3]: Q3 report, page 4.
```

## Presenting

**View → Present** (<kbd>⌥⌘P</kbd>) shows the deck full screen, on an external display when there is one. While editing, it presents the editor's current text.

With two displays, a presenter window on the other display shows the current slide with its notes, the next slide, the slide and step number, and the time since you started. Closing the presenter window keeps presenting, and so does unplugging a display. Leaving full screen or closing the document ends the presentation. If the file changes while you present, the slides update and stay on the same slide.

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
| `slides: true` / `marp: true` in frontmatter | The file is a deck. |
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
| `<!-- space -->`, `<!-- space: n -->` | Empty lines. |
