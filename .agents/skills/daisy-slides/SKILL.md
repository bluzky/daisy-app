---
name: daisy-slides
description: Write, convert and fix slide decks in Daisy's Markdown slide format — `slides: true` frontmatter, `---` slide breaks, `???` speaker notes, inferred layouts, `<!-- … -->` directives (layout, _class, color, step, column, end-columns, space, _paginate/_header/_footer), `![bg …]` backgrounds with left/right/fit/dim/blur, `!caption[…]`, themes and theme files. Use this whenever the user wants a presentation, deck, talk, pitch or slides written in Markdown, wants notes or a document turned into slides, mentions Daisy, Daisy slides or presenting a .md file, asks for a Marp/Kova-style deck to open in Daisy, or wants a Daisy slide theme (`~/.config/daisy/slide-themes/*.yaml`) — even if they only say "make slides from this".
---

# Daisy slides

Daisy is a macOS Markdown app. A Markdown file with `slides: true` in its frontmatter reads as a deck: Read Mode shows a strip of 16:9 slides, **View → Present** (⌥⌘P) shows it full screen, and PDF export prints one slide per page. The deck stays an ordinary Markdown file, so it should read well as plain text too.

This skill covers writing a deck that looks good in Daisy. The complete syntax reference is `references/slides-guide.md` (Daisy's own `docs/slides.md`); read the relevant section when you need an exact rule this file only summarizes.

## Workflow

1. **Plan the slides before writing.** One idea per slide. Decide which slides are a title, a section break, a quote, a diagram, a comparison — Daisy picks the layout from the content, so the content's shape *is* the design.
2. **Write the deck** with the syntax below. Put everything that is detail, evidence or a script into `???` speaker notes, not onto the slide.
3. **Lint it:** `python3 scripts/check_deck.py deck.md` (path relative to this skill). It catches the mistakes that render silently wrong — a `---` that becomes a heading, a step that's ignored, a background that isn't one, unknown layouts and themes, missing images — and estimates slides that may be cut off. Fix every error. The length warning is an estimate (code and short lines fit more): trim the slide if it is clearly long, otherwise tell the user to check that slide in Daisy's Slide Preview.
4. **Tell the user how to see it:** open the file in Daisy; ⌥⌘P to present, ⇧⌥⌘P from the current slide, ⌘9 for the Slide Preview pane beside the editor.

When converting an existing document or Marp/Kova deck, keep the author's words and order; restructure only as far as the slide format needs.

## Why slides must stay short

Daisy never shrinks text to fit. A slide is a fixed 16:9 canvas with roughly 28 px text at 1280 px wide; whatever doesn't fit is cut off, in Read Mode, full screen and the PDF alike. In practice a slide holds a heading plus about 6–7 short bullets, or ~12 lines in total, or a code block of ~14 lines. Long Mermaid diagrams and images are the exception: they shrink to the space left. So when content is long, split it across slides or move it to notes rather than squeezing it.

## Syntax at a glance

```markdown
---
slides: true          # or marp: true
theme: midnight       # default, light, dark, paper, midnight, pitch, or a theme file's id
paginate: true        # slide number, bottom right
footer: "{title} | | {slide_number}/{total}"   # also header; {author} {date}; | splits left/center/right
aspect: 16:9          # 16:10, 4:3
title: Quarterly review
---

# Quarterly review
Daisy team · Q4

---

## What shipped

- Tasks sidebar
- Query blocks <!-- step -->
- Slides <!-- step -->

???
Speaker notes: everything after ??? on this slide.
```

| Want | Write |
| --- | --- |
| New slide | `---` alone on a line, with a **blank line above it** |
| Speaker notes | `???` alone on a line; the rest of the slide is notes |
| Reveal on click | `<!-- step -->` as the **last thing** of a list item or paragraph, or alone on the line above a block; `<!-- step: 2 -->` groups elements |
| Columns | `<!-- column -->` alone on a line between parts; `<!-- end-columns -->` ends them so what follows spans the slide. A heading at the top stays above. Max 4 columns |
| Empty space | `<!-- space -->` or `<!-- space: 3 -->` (blank lines don't add space on a slide) |
| Background | `![bg](img.jpg)` alone in its paragraph; keywords in the alt text: `left`, `right`, `fit`, `dim`, `blur`, combinable (`![bg right fit]`, `![bg dim blur]`) |
| Image width | `![Chart](chart.png "60%")` (also px, em, rem, cqi) |
| Caption | `!caption[Figure 1: …]` alone on the line below an image, table, diagram or formula |
| Force a layout | `<!-- layout: section -->` |
| Center / dark slide | `<!-- _class: center -->`, `center-x`, `center-y`, `lead`, `invert` |
| Text color | `<!-- color: "#0057b8" -->` or a color name |
| Per-slide chrome | `<!-- _paginate: false -->`, `<!-- _header: "" -->` (empty hides), `<!-- _footer: text -->` |
| Rule inside a slide | `<hr>` (never `---`) |

Several directives can share one comment, one per line: `<!--⏎layout: title⏎_class: invert⏎-->`.

Everything Daisy renders works on slides: tables, code, math (`$$…$$`), Mermaid, callouts (`> [!note]`), tasks, footnotes (each slide lists the ones it references).

## Layouts come from content

Daisy chooses each slide's layout; write the content to get the layout you want, and reach for `<!-- layout: … -->` only when inference picks wrong. First match wins:

| Content | Layout |
| --- | --- |
| two or more `<!-- column -->` parts | `columns` |
| `![bg left]` / `![bg right]` | `split` — image on one half, text centered on the other |
| `![bg]` and nothing else | `full-bleed` |
| an H1 alone, or with one paragraph ≤ 200 characters | `title` — centered |
| an H2 alone | `section` — centered, large |
| a blockquote alone (not a callout) | `quote` — centered, large italic |
| one code block or Mermaid diagram (+ optional heading) | `code` |
| display math (+ optional heading) | `math` — centered |
| a heading and one image | `title-image` — image fills the rest |
| anything else | `title-content` — top-left |

Comments, captions and backgrounds don't count as content. Good decks use this deliberately: an `## H2`-only slide between parts, a lone quote for emphasis, one image per slide with a heading.

## Traps that render silently wrong

These don't produce errors in Daisy — the slide just looks wrong — so check for them (the linter flags most):

- **`---` right under a line of text** makes that text a heading (Markdown's setext rule) instead of starting a slide. Always leave a blank line above `---`.
- **`???` with text on the same line** is ordinary text. Put `???` alone; notes start on the next line.
- **`<!-- step -->` mid-sentence** is ignored. It must end the item or paragraph.
- **A `bg` image with other text** on its line or paragraph renders as a normal inline image.
- **Kova's `|||`** is not a column break here; use `<!-- column -->`.
- **Marp habits:** HTML comments are *not* notes (only `???` is); `<!-- paginate: true -->`, `class`, `header`, `footer` without `_` are not read — put deck-wide settings in the frontmatter and use `_`-prefixed directives for one slide. Marp's `![bg brightness:.5]` filters aren't supported; use `dim`/`blur`.
- **Values starting with `#`** in YAML must be quoted (`color: "#fff"`), or YAML reads a comment.
- **Directives inside lists** (`<!-- column -->`, `<!-- space -->` indented under a bullet) are ignored; keep them at the top level.
- **A file starting with `---`** and containing another `---` is read as frontmatter. Start decks with real frontmatter.

## Themes

`theme:` picks the deck's look; without it, slides follow the reader's Daisy theme. Built in: `default`, `light`, `dark`, `paper` (warm, serif), `midnight` (dark blue, bright title slides), `pitch` (white, blue headings, solid-blue title slides). Code colors follow the theme automatically.

To tweak one deck, use `theme_overrides:` in the frontmatter with `colors:` / `fonts:`. To make a reusable theme, write `~/.config/daisy/slide-themes/<id>.yaml`:

```yaml
name: My Brand
extends: light          # start from a built-in or another theme file
appearance: light       # dark|light, for code colors; inferred from a hex background
colors:
  background: "#FFFFFF"
  text: "#1A1A1A"
  heading: "#0057B8"
  accent: "#0057B8"     # links and bullets
  bold: "#B8003F"
  code_background: "#F5F7FA"
  primary: "#0057B8"    # background of title and section slides
  title_text: "#FFFFFF" # their text
fonts:
  title: "Georgia, serif"
  body: "Inter, sans-serif"
  code: "JetBrains Mono, monospace"
footer:
  text: "{title} | | {slide_number}/{total}"
```

Colors must be hex or CSS color names and fonts plain font lists — anything else is dropped, so stick to those forms. A deck's own `header`/`footer` win over the theme's.

## Writing good slides

- **Headlines that say something.** "Revenue grew 12% in Q3" beats "Revenue".
- **Parallel, short bullets** — fragments, not sentences; under ~8 words each.
- **One visual per slide**, with a heading; caption it if the source matters.
- **Section slides** (`## Part two` alone) give long decks rhythm.
- **Steps sparingly** — for a list that's argued point by point, not for every slide.
- **Notes carry the talk.** If the user gives you prose, the slide gets the claim and the notes get the explanation.
- **Images:** keep paths relative to the deck and make sure the files exist; for text over a photo use `![bg dim](…)` (white text) or `![bg dim blur](…)`.
