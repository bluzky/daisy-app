# Proposal: slide presentations

Status: phase 1 implemented (`daisy/Rendering/Slides/`, `daisy/Features/Presentation/`); phases 2–4 are still proposals. Where phase 1 differs from the first draft, this document describes what was built.

## Summary

Present a Markdown file as slides, in the style of [Kova](https://wiki.kova.md/markdown-and-syntax/): `---` separates slides, the layout of each slide is inferred from what is on it, and a deck stays a readable Markdown document. Slides are rendered by Daisy's own pipeline, so callouts, highlighting, KaTeX, Mermaid, tags and task metadata look the same on a slide as in Read Mode.

```markdown
---
slides: true
theme: dark
---

# Quarterly review
Daisy team · Q4 2026

---

## What shipped

- Tasks sidebar
- Query blocks <!-- step -->
- Hide completed tasks <!-- step -->

???
Mention the query block guide.

---

## New sidebar

![bg right](sidebar.png)

- Calendar of scheduled and due tasks
- Check tasks off without opening the file
```

## Goals and non-goals

Goals:

- Present a Markdown file full screen, with keyboard and clicker navigation.
- Presenter window on a second display: current slide, next slide, notes, timer.
- Kova's core syntax, plus the small Marp subset listed under [Marp decks](#marp-decks).
- Automatic layout, with a per-slide override.
- PDF export with one slide per page.

Non-goals for now:

- Kova's app-specific directives: `!progress`, `!poll`, `!ref`, `!sheet`, `!youtube`, `!video`, `:icon:`.
- Transitions between slides beyond a plain cut or fade.
- Editing on a slide canvas. The source stays Markdown.
- Running marp-core or reveal.js. Both bring their own Markdown parser, so slides would lose Daisy's extensions and need Mermaid and KaTeX wired twice.

## Turning it on

A file is a deck when either is true:

- Its frontmatter has `slides: true`, or `marp: true`, which means the same thing (see [Marp decks](#marp-decks)).
- The user chooses **View → Present** (⌥⌘P) on any Markdown file. This presents without changing the file.

A deck file opens in Read Mode as slides, laid out as a vertical strip of scaled slides, each with its speaker notes below it. Other files render as today. This keeps `---` an ordinary rule in notes that are not decks; in Kova every file is a deck, which would be wrong for Daisy.

## Syntax

Markers are recognised at the **top level of the document only**, from the swift-markdown tree, never by a regex over the source. A `---` inside a list or blockquote, the frontmatter fences, and a setext heading (`Title` followed by `---`) are not slide breaks.

| Syntax | Meaning |
| --- | --- |
| `---` (top-level thematic break) | Ends the current slide. Use `<hr>` for a rule inside a slide. |
| A paragraph that is exactly `???` | Everything after it on the slide is speaker notes. |
| `<!-- layout: name -->` | Overrides the inferred layout. |
| `<!-- _class: name -->`, `<!-- color: #fff -->`, `<!-- _color: … -->` | Adds a class or text color to this slide. |
| `![bg](img.jpg)`, `![bg left](img.jpg)`, `![bg right](img.jpg)`, `![bg fit](img.jpg)` | Background image; only the first on a slide is used. |
| `![alt](img.png "50%")` | Image size. Units: `%`, `px`, `em`, `rem`, `cqi`. |
| `<!-- step -->` / `<!-- step: n -->` | Reveal the element on the next click, or group elements onto click `n`. |
| `!caption[text]` | Caption for the image, table, Mermaid or math block directly above. |
| `!toc` | Generated list of slide titles, skipping the title slide. |

Frontmatter keys: `slides`, `marp`, `theme`, `theme_overrides`, `aspect` (`16:9` default, `16:10`, `4:3`), `paginate`, `header`, `footer`, `author`, `date`.

`<!-- step -->` written at the end of a list item or paragraph is inline HTML inside that element and reveals that element; written on its own line it is an `HTMLBlock` and reveals the next block. Both forms are supported.

Background images:

- An image is a background when its alt text starts with the word `bg`. The remaining alt words are keywords: `left`, `right` (split position) and `fit` / `contain` (scale without cropping; synonyms). Unknown words are ignored.
- The destination is required, as for any Markdown image.
- The title is only ever a size (`"50%"`), never a keyword. A background ignores it.
- Only an image that is the sole content of a top-level paragraph is a background. `![bg](a.jpg)` inside a sentence or list renders as a normal image.

Kova's `|||` column break is not supported. A side-by-side slide uses `![bg left]` / `![bg right]`.

### Marp decks

`marp: true` is an alias for `slides: true`. From Marp, Daisy supports `![bg …]` with the keywords above, `<!-- _class: … -->`, `<!-- _color: … -->`, and the `paginate`, `header` and `footer` frontmatter keys. Known differences:

- Speaker notes are `???` only. Marp's HTML-comment notes are not shown anywhere.
- No Marp CSS themes, `size:` keyword, `<style>` blocks, or directives other than those listed; unknown directives are ignored.
- Global directives in comments (`<!-- paginate: true -->`) are not read; use frontmatter.

## Layout inference

A pure function classifies each slide's blocks, after notes, `bg` images and directives are removed. The first matching rule wins.

| Content | Layout |
| --- | --- |
| `<!-- layout: x -->` present | `x` |
| `![bg left]` / `![bg right]` | `split` |
| `![bg]` and no other content | `full-bleed` |
| Only an H1, optionally with one short paragraph (200 characters or fewer, no list) | `title` |
| Only an H2 | `section` |
| Only a blockquote (not a callout) | `quote` |
| Only a code block or Mermaid block, with an optional heading | `code` |
| Only display math, with an optional heading | `math` |
| A heading and a single image | `title-image` |
| Three or more images, with an optional heading | `grid` |
| Heading plus anything else | `title-content` |
| Nothing visible | `blank` |

Background images are removed before the content rules run, except that `split` and `full-bleed` look at them. A plain `![bg]` behind other content does not change the layout.

Ambiguous inputs and their layout, each a test fixture:

| Slide | Layout |
| --- | --- |
| `# Title` + a 250-character paragraph | `title-content` |
| `# Title` + `- one item` | `title-content` |
| `## Heading` + three images | `grid` |
| `## Heading` + two images | `title-content` |
| `# Title` + `![bg](a.jpg)` | `title` with a background |
| `![bg left](a.jpg)` and no text | `split` with an empty text side |
| `# Title` + `![bg right](a.jpg)` | `split` (a side image wins over `title`) |
| `![bg](a.jpg)` + `![bg](b.jpg)` | `full-bleed` with the first image |
| A callout alone | `title-content` (a callout is not a quote) |
| `## Heading` + a code block + a paragraph | `title-content` |
| Only `???` notes | `blank` |

The layout is a class on the slide (`mdp-slide--title`), and all visual differences are CSS. The status bar in Edit Mode shows the layout of the slide under the caret, as Kova does, so an inferred layout is never a surprise.

## Rendering

### Model

`SlideDeck` (new, `daisy/Rendering/Slides/`) is built from the parsed `Document`:

```swift
struct SlideDeck {
    struct RevealTarget {
        var sourceRange: SourceRange  // the revealed element: a block, list item or paragraph
        var step: Int
    }
    struct Slide {
        var sourceLines: ClosedRange<Int>
        var blocks: [Markup]
        var notes: [Markup]
        var background: Background?
        var layout: Layout
        var classes: [String]
        var reveals: [RevealTarget]   // elements not listed are always visible
        var footnoteNumbers: [Int]    // footnotes referenced on this slide
    }
    var settings: DeckSettings        // from frontmatter
    var slides: [Slide]
}
```

It has no UI or WebKit dependency, so splitting, markers, steps and layout inference are covered by `swift test --package-path tests/swift-tests`.

### Source of the tree

`MarkdownHTML.render` does not parse the source as written. It first splits off frontmatter (keeping a line offset), removes footnote definitions, replaces math with placeholders and prepares highlights, and only then parses (`MarkdownHTML.swift`, `EscapingHTMLFormatter.format`). The deck is built inside the formatter, from **that same `Document`**, so slide boundaries, source ranges and the rendered HTML can never disagree. It must not parse the original text separately.

What the deck relies on, all present in that tree:

- Every node's `range` (`SourceRange`), shifted by the frontmatter line offset as `sourceLineAttribute` already does.
- `ThematicBreak` nodes that are direct children of `Document`.
- `HTMLBlock` (own-line comments) and `InlineHTML` (trailing comments) nodes, in document order.
- Frontmatter never reaches the tree, so its `---` fences cannot split a slide.

Before implementation, a fixture matrix in `tests/swift-tests` covers: setext heading vs `---`; `---` in a list, blockquote and code fence; `***` and `___` breaks; frontmatter with and without a body; `???` as the last line, twice, and in a list; inline and own-line `<!-- step -->`; math and footnotes on the same slide as a break; and source lines of the first block on each slide.

### Footnotes

Footnotes keep their document-wide numbers. Each slide lists, at the bottom, the definitions of the footnotes referenced on that slide; a footnote referenced on several slides is repeated on each. Where the definition sits in the source does not matter, because definitions are already removed before parsing. Definitions that no slide references are not shown. References inside speaker notes add their definition to the notes, not the slide.

### Raw HTML

Decks use the same sanitizer as every document: the page passes article HTML through DOMPurify (`MarkdownHTML+HostBridge.swift`), which keeps `<hr>`, `<section>`, `<aside>`, `<img>` and `data-*` attributes and removes scripts, `<style>`, `style` attributes, forms, iframes and event handlers. Nothing is relaxed for slides.

Because `style` attributes are forbidden, `<!-- color: … -->` becomes `data-slide-color="#fff"` (a sanitized hex or CSS color name, as `ThemeOverrides.sanitizedHexColor` does for themes), and the slide script copies it to a CSS variable after sanitizing. The same applies to image sizes from the title (`data-size="50%"`) and to the scale factor.

DOMPurify also removes HTML comments, so every directive (`layout`, `step`, `_class`, `color`) is read in Swift while building the deck and written out as classes or `data-*` attributes. The page script never looks for comments.

### HTML

`EscapingHTMLFormatter.visitDocument` is the one place that walks top-level blocks. In slide mode it walks the deck instead and emits:

```html
<div class="mdp-deck">
  <section class="mdp-slide-frame" data-slide="3">
    <div class="mdp-slide mdp-slide--title-content">
      <div class="mdp-slide-body">…blocks, with data-step="n" where set…</div>
    </div>
    <aside class="mdp-slide-notes">…</aside>
  </section>
</div>
```

Classes carry the `mdp-` prefix so they can't collide with a document's own HTML. The notes sit outside the slide canvas: Read Mode shows them under the slide, and presenting and printing hide them. Blocks keep their own `data-source-*` attributes; the section has none.

Each element in a slide's `reveals` gets `data-step="n"` as the formatter writes it. Everything after the formatter (math, footnotes, heading IDs, RTL, render extensions) runs unchanged on the result, except that footnote definitions go to slides as described under [Footnotes](#footnotes).

`MarkdownHTML.render` gains a `forcesSlides` parameter for View ▸ Present on a file without `slides: true`. A deck's frontmatter is not rendered as a table. The slide stylesheet and script come from `SlidesExtension` in the render-extension registry, which activates on `.mdp-deck` and is not user-toggleable. Its script (`MdPreviewSlides`) is emitted only for the app (`.lazy`), so the fast-path body swap reloads the page when a document becomes a deck.

### Scaling

No transform. `.mdp-deck` is a size container (`container-type: inline-size`), and a slide's padding and font size are in `cqw`, so its content scales with the deck's width and keeps its 16:9 shape (`aspect-ratio`). The same CSS lays out the Read Mode strip, a full screen (the deck is sized to `min(100vw, 100vh × 16/9)`) and a printed page (the deck is 1280 px wide), and needs no script. Mermaid and KaTeX lay out at the real size. The canvas size (1280×720) only fixes the aspect ratio and the printed page.

### Live updates

The morphdom body swap keeps working: each `<section>` keeps a stable `data-slide` index. The session holds the current slide, so the slide script only re-marks it (`data-mdp-current`) in its `render` hook after a swap; the host also sends `MdPreviewSlides.show(index)` after every load and swap.

## Presenting

- **Present** (⌥⌘P) opens a window with its own `MarkdownWebView` and puts it in native full screen, on an external display when there is one, so the document stays on the laptop. It presents Edit Mode's buffer while editing, like export. Leaving full screen or closing the document window ends the presentation. (Phase 1.)
- **Present from Current Slide** (⇧⌥⌘P) starts at the slide under the caret or scroll position. (Phase 3, with editor slide sync.)
- With two displays, a presenter window on the laptop shows the current slide, next slide, notes, elapsed or countdown timer, and slide count.
- Keys: → ↓ Space PageDown next; ← ↑ PageUp previous; Home / End; number + Return jumps; B / W blank to black or white; Esc exits. Presentation clickers send PageUp/PageDown, so they work without setup.
- `ProcessInfo.beginActivity(options: .idleDisplaySleepDisabled, …)` keeps the display awake while presenting.
- Notes render as Markdown, so links in notes are clickable in the presenter window only.

### Presentation session

A native `PresentationSession` (main actor) owns the state: current slide, current step, timer, blanked, and the rendered HTML. The web views only display it.

- Keys and clicks in either window call the session, which clamps the position and pushes `goTo(slide, step)` to every attached web view. A web view never changes slide on its own.
- **Loading:** a web view is attached once its page reports ready; the session then sends the current position. Input that arrives earlier is applied to the session and reaches the view on attach.
- **Live edit:** a file change re-renders once and reloads both views. The session keeps the slide index and step, clamped to the new slide and step counts, so deleting the current slide moves to the one before it.
- **Display change:** if the external display disappears, the audience window closes and the session continues in single-screen mode on the remaining display, notes toggled with N. Connecting a display does not move an ongoing presentation.
- **Closing:** closing the audience window, Esc, or closing the document ends the session and closes the presenter window. Closing only the presenter window keeps presenting in single-screen mode.
- **Failure:** a web view that fails to load or crashes is reloaded once; on a second failure the session ends with an alert, rather than leaving the two windows out of step.

## Editing

In split view, the slide under the caret is shown, using the source lines the formatter already writes. The editor's slash menu gains `/slide` (inserts `---`), `/notes` (`???`) and `/step`.

## Themes

Slides use Daisy's reading theme by default, through the existing CSS variables (`--text`, `--link`, page background). A deck names a theme in frontmatter; there is no theme picker in the UI:

- Built-in slide themes are CSS files with the same variables plus slide-only ones (title color, accent, fonts, logo position).
- Custom themes are YAML files, in Kova's shape, in `~/.config/daisy/slide-themes/`, with `extends:`, `colors`, `fonts`, `logo` and header and footer templates (`{title} | {date} | {slide_number}/{total}`). They are converted to CSS variables; a theme cannot inject arbitrary CSS.
- `theme_overrides:` in frontmatter changes individual colors for one deck.

## Export

- **PDF and Print:** both use the existing print path. For a deck, the print operation's paper is the slide (960×540 pt, which is 1280×720 CSS px, landscape) with no margins, and there is no text-size accessory. Before `printOperation` runs, the host sets `data-mdp-slides-print` on `<html>` and adds a `@page { size: 1280px 720px; margin: 0 }` style element; the print CSS keyed on the attribute:
  - sizes each slide to the canvas (1280×720 px);
  - adds `break-after: page` to each `<section>` (none after the last);
  - hides notes and, from phase 2, shows every step.

  Both are removed when the print sheet closes. Options in the print accessory: slides per page (1, 2, 4, 6) and notes as a handout; both are further print-mode classes.
- **HTML:** the existing self-contained export (`.inline` vendor loading) plus the slide script, so the file presents in a browser.
- **PPTX (later):** a native writer next to `DocxExporter`, producing editable text boxes rather than slide images; Mermaid as PNG through `MermaidRasterizer`.
- **CLI:** `daisy export deck.md --format pdf` works once PDF export does; `--per-page` and `--notes` mirror the print options.

## Quick Look

A deck file previews as a grid of slide thumbnails. Quick Look already renders with inline vendors and never loads the presenter, so this needs only the slide CSS.

## Phases

1. `SlideDeck` with `---`, `???` and layout inference; slide strip in Read Mode; full-screen Present with keyboard navigation; PDF export.
2. Backgrounds and image sizing, `<!-- layout -->`, `<!-- _class -->`, `<!-- step -->`; presenter window with notes and timer.
3. Themes (built-in and YAML), header and footer templates, `!caption`, `!toc`; editor slide sync and slash commands.
4. HTML and PPTX export, CLI options, Quick Look thumbnails.

Each phase updates `README.md` and `docs/render-extensions.md` in the same change, and adds a deck to `samples/`.

## Decisions

- A deck opens as slides in Read Mode; there is no document view of a deck.
- `???` is the only notes marker, in every deck. HTML comments are never notes, including in `marp: true` decks.
- The theme is chosen in frontmatter only. There is no theme picker in the UI.
