# Slides

A Markdown file becomes a slide deck when its frontmatter says so:

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

`marp: true` works too. Read Mode then shows the file as a strip of 16:9 slides, with each slide's speaker notes under it. **View → Present** (<kbd>⌥⌘P</kbd>) shows any Markdown file as slides, with or without the frontmatter. See [`samples/slides.md`](../samples/slides.md).

## Syntax

| Syntax | Meaning |
| --- | --- |
| `---` on its own line | Starts the next slide. Use `<hr>` for a rule inside a slide. |
| A `???` line | Everything after it on the slide is speaker notes. |
| `![bg](image.jpg)` | Background image filling the slide. |
| `![bg left](image.jpg)`, `![bg right](image.jpg)` | The image fills one half; the text sits on the other. |
| `![bg fit](image.jpg)` | Shows the whole image instead of filling the area (`contain` works too). |
| `![alt](image.png "50%")` | Image size: a number with `%`, `px`, `em`, `rem` or `cqi`. |
| `<!-- layout: name -->` | Sets the slide's layout instead of inferring it. |
| `<!-- _class: name -->` | Adds a class to the slide: `center`, `center-x`, `center-y`, `lead` or `invert`. |
| `<!-- color: #fff -->` | Text color for the slide, as a hex color or a color name (`_color` works too). |
| `<!-- step -->` | At the end of a list item or paragraph, reveals it on the next click. On its own line, reveals the next block. |
| `<!-- step: 2 -->` | Reveals on click 2, so several elements can appear together. |

Only `---` and `???` at the top level of the file count: in a list, a quote or a code block they are ordinary text. A background must be alone in its paragraph, with the keywords in the alt text; only the first background on a slide is used. Directives apply to the slide they are on. A `<!-- step -->` in the middle of a sentence is ignored: it must be the last thing in the list item or paragraph.

## Layouts

Each slide's layout comes from what is on it; the first match wins.

| Content | Layout |
| --- | --- |
| `<!-- layout: name -->` | that layout |
| `![bg left]` or `![bg right]` | `split` |
| `![bg]` and nothing else | `full-bleed` |
| An H1 alone, or with one short paragraph (up to 200 characters) | `title` |
| An H2 alone | `section` |
| A quote alone (not a callout) | `quote` |
| One code block or Mermaid diagram, with an optional heading | `code` |
| Display math, with an optional heading | `math` |
| A heading and one image | `title-image` |
| Three or more images, with an optional heading | `grid` |
| Anything else | `title-content` |
| Nothing | `blank` |

`title`, `section`, `quote` and `math` are centered; use `<!-- _class: center -->` to center any other slide.

## Presenting

The slides go full screen on an external display when there is one. With two displays, a presenter window on the other one shows the current slide with its notes, the next slide, the slide and step number, and the time since you started. Closing the presenter window keeps presenting; unplugging a display does too.

| Key | What it does |
| --- | --- |
| <kbd>→</kbd> <kbd>↓</kbd> <kbd>Space</kbd> <kbd>⇟</kbd> | Next step, then next slide |
| <kbd>←</kbd> <kbd>↑</kbd> <kbd>⌫</kbd> <kbd>⇞</kbd> | Previous step, then previous slide |
| <kbd>↖</kbd> / <kbd>↘</kbd> | First / last slide |
| A number, then <kbd>↩</kbd> | Jumps to that slide |
| <kbd>B</kbd> / <kbd>W</kbd> | Blanks the screen to black / white |
| <kbd>esc</kbd> | Ends the presentation |

Presentation clickers send Page Up and Page Down, so they work without setup. The display stays awake while presenting.

## Export

PDF export and Print lay a deck out one slide per page at 16:9, with every step shown and without the notes.
