# Proposal: slide presentations

Status: phases 1 and 2 implemented (`daisy/Rendering/Slides/`, `daisy/Features/Presentation/`); phases 3 and 4 are still proposals. Where the build differs from the first draft, this document describes what was built. The user guide is [docs/slides.md](../slides.md).

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

- Kova's app-specific directives: `!toc`, `!progress`, `!poll`, `!ref`, `!sheet`, `!youtube`, `!video`, `:icon:`.
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
| `![bg](img.jpg)`, `![bg left](img.jpg)`, `![bg right](img.jpg)`, `![bg fit](img.jpg)`, `![bg dim](img.jpg)` | Background image; only the first on a slide is used. `dim` lays a 60% black veil over the image (`::after` on the background), and over a full background turns the text white. `blur` applies `filter: blur(0.8cqw)` to the image, slightly enlarged so its faded edges fall outside the clipped background box. |
| `![alt](img.png "50%")` | Image size. Units: `%`, `px`, `em`, `rem`, `cqi`. |
| `<!-- step -->` / `<!-- step: n -->` | Reveal the element on the next click, or group elements onto click `n`. |
| `<!-- column -->` on its own line | Starts a new column (added after phase 2; see [Columns](#columns)). |
| `<!-- end-columns -->` on its own line | Ends the columns; the rest of the slide spans the width below them. |
| `<!-- space -->` / `<!-- space: n -->` on its own line | Adds one or `n` (up to 10) empty lines at the slide's line height. Blank lines don't add space on a slide: slide mode leaves out Read Mode's blank-line spacers. |
| `!caption[text]` | Caption for the image, table, Mermaid or math block directly above. |

Frontmatter keys: `slides`, `marp`, `theme`, `theme_overrides`, `aspect` (`16:9` default, `16:10`, `4:3`), `paginate`, `header`, `footer`, `author`, `date`.

`<!-- step -->` written at the end of a list item or paragraph is inline HTML inside that element and reveals that element; written on its own line it is an `HTMLBlock` and reveals the next block. Both forms are supported.

Background images:

- An image is a background when its alt text starts with the word `bg`. The remaining alt words are keywords: `left`, `right` (split position), `fit` / `contain` (scale without cropping; synonyms), `dim` (darken) and `blur`. Unknown words are ignored.
- The destination is required, as for any Markdown image.
- The title is only ever a size (`"50%"`), never a keyword. A background ignores it.
- Only an image that is the sole content of a top-level paragraph is a background. `![bg](a.jpg)` inside a sentence or list renders as a normal image.

Kova's `|||` column break is not supported: it would show as a literal `|||` line in every other Markdown viewer. Columns use the `<!-- column -->` directive instead, which is invisible outside Daisy.

### Columns

`<!-- column -->` on its own line at the top level starts a new column; `SlideDeck` records the block index of each break. A heading opening the slide stays above the columns across the full width. `<!-- end-columns -->` closes them: the blocks after it go below the columns, across the slide; without it the rest of the slide stays in the last column. There is one set of columns per slide, so breaks after the end, and an end before any break, are ignored. Empty columns — a break right after that heading, or just before the end — are dropped; fewer than two columns means no columns; past four, later breaks are ignored and the rest stays in the fourth. A slide with columns gets the `columns` layout unless `<!-- layout: … -->` overrides it, and is checked right after the override, before backgrounds.

The formatter writes the heading, then `.mdp-slide-columns` holding one `.mdp-slide-column` per column, then the blocks after the end. The columns are a grid of equal columns (`grid-auto-flow: column; grid-auto-columns: minmax(0, 1fr)`) with one row (`minmax(0, 1fr)`) filling the slide below the heading — or, when blocks follow the end, only as tall as they need. A tall Mermaid diagram or image shrinks to fit, in a column as in the slide body. Columns keep the slide's text size; there is no shrinking for three or four columns, and content that doesn't fit is cut off like on any slide.

### Marp decks

`marp: true` is an alias for `slides: true`. From Marp, Daisy supports `![bg …]` with the keywords above, `<!-- _class: … -->`, `<!-- _color: … -->`, and the `paginate`, `header` and `footer` frontmatter keys. Known differences:

- Speaker notes are `???` only. Marp's HTML-comment notes are not shown anywhere.
- No Marp CSS themes, `size:` keyword, `<style>` blocks, or directives other than those listed; unknown directives are ignored.
- Global directives in comments (`<!-- paginate: true -->`) are not read; use frontmatter.
- As in Marp, one comment can hold several directives, one `key: value` per line; a quoted value is unquoted. Comments are not parsed as full YAML.
- Local directives without `_` (`class`, `color`) don't carry over to the following slides as in Marp: `class` is ignored and `color` applies to its slide only. Local and spot scope may come with the header and footer work in phase 3.

## Layout inference

A pure function classifies each slide's blocks, after notes, `bg` images and directives are removed. The first matching rule wins.

| Content | Layout |
| --- | --- |
| `<!-- layout: x -->` present | `x` |
| Two or more columns from `<!-- column -->` | `columns` |
| `![bg left]` / `![bg right]` | `split` |
| `![bg]` and no other content | `full-bleed` |
| Only an H1, optionally with one short paragraph (200 characters or fewer, no list) | `title` |
| Only an H2 | `section` |
| Only a blockquote (not a callout) | `quote` |
| Only a code block or Mermaid block, with an optional heading | `code` |
| Only display math, with an optional heading | `math` |
| A heading and a single image | `title-image` |
| Heading plus anything else | `title-content` |
| Nothing visible | `blank` |

Background images are removed before the content rules run, except that `split` and `full-bleed` look at them. A plain `![bg]` behind other content does not change the layout.

Ambiguous inputs and their layout, each a test fixture:

| Slide | Layout |
| --- | --- |
| `# Title` + a 250-character paragraph | `title-content` |
| `# Title` + `- one item` | `title-content` |
| `## Heading` + three images | `title-content` (images side by side are columns; a `grid` layout was built and removed, since `<!-- column -->` does the same explicitly) |
| `## Heading` + two images | `title-content` |
| `# Title` + `![bg](a.jpg)` | `title` with a background |
| `![bg left](a.jpg)` and no text | `split` with an empty text side |
| `# Title` + `![bg right](a.jpg)` | `split` (a side image wins over `title`) |
| `![bg](a.jpg)` + `![bg](b.jpg)` | `full-bleed` with the first image |
| A callout alone | `title-content` (a callout is not a quote) |
| `## Heading` + a code block + a paragraph | `title-content` |
| Only `???` notes | `blank` |

The layout is a class on the slide (`mdp-slide--title`), and all visual differences are CSS. The Slide Preview panel shows each slide as laid out, so an inferred layout is never a surprise (see [Editing](#editing)).

## Rendering

### Model

`SlideDeck` (new, `daisy/Rendering/Slides/`) is built from the parsed `Document`:

```swift
struct SlideDeck {
    struct SourceKey: Hashable { let line, column: Int }  // where an element starts
    struct Slide {
        var blocks: [Markup]                // without directives and backgrounds
        var notesLead: Paragraph?           // `???` with text on its next lines
        var notes: [Markup]
        var layout: Layout
        var background: Background?
        var classes: [String]
        var color: String?
        var blockSteps: [Int: Int]          // own-line `<!-- step -->`, by index in blocks
        var elementSteps: [SourceKey: Int]  // inline `<!-- step -->`, by list item or paragraph
        var stepCount: Int
    }
    let slides: [Slide]
}
```

An own-line step wraps its block in `<div class="mdp-step" data-step="n">` with `display: contents`, so the block keeps its place in the slide's layout; an inline step puts `data-step` on the list item or paragraph itself, which the formatter looks up by `SourceKey`. Footnotes are placed after formatting rather than tracked on the slide (see [Footnotes](#footnotes)).

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

`MarkdownHTML.render` gains a `forcesSlides` parameter for View ▸ Present on a file without `slides: true`. A deck's frontmatter is not rendered as a table. The slide stylesheet and script come from `SlidesExtension` in the render-extension registry, which activates on `.mdp-deck` and is not user-toggleable. Its script (`MdPreviewSlides`) is emitted in every host, since it also applies image sizes and slide colors, which the sanitizer keeps out of the HTML as styles; its asset id makes the fast-path body swap reload the page when a document becomes a deck.

### Scaling

No transform. `.mdp-deck` is a size container (`container-type: inline-size`), and a slide's padding and font size are in `cqw`, so its content scales with the deck's width and keeps its 16:9 shape (`aspect-ratio`). The same CSS lays out the Read Mode strip, a full screen (the deck is sized to `min(100vw, 100vh × 16/9)`) and a printed page (the deck is 1280 px wide), and needs no script. Mermaid and KaTeX lay out at the real size. The canvas size (1280×720) only fixes the aspect ratio and the printed page.

### Live updates

The morphdom body swap keeps working: each `<section>` keeps a stable `data-slide` index. The session holds the current slide, so the slide script only re-marks it (`data-mdp-current`) in its `render` hook after a swap; the host also sends `MdPreviewSlides.show(index)` after every load and swap.

## Presenting

- **Present** (⌥⌘P) opens a window with its own `MarkdownWebView` and puts it in native full screen, on an external display when there is one, so the document stays on the laptop. It presents Edit Mode's buffer while editing, like export. Leaving full screen or closing the document window ends the presentation. (Phase 1.)
- **Present from Current Slide** (⇧⌥⌘P) starts at the slide under the caret in Edit Mode, or at the top of the view in Read Mode. (Phase 3; it uses the line-to-slide mapping under [Editing](#editing).)
- With two displays, a presenter window on the laptop shows the current slide with its notes, the next slide, the slide and step number, and the elapsed time. It is one more `MarkdownWebView` of the same deck with the `slides-presenter` host state, laid out by CSS, under a native bar for the number and the clock. A countdown timer is not built yet.
- Keys: → ↓ Space PageDown next; ← ↑ PageUp previous; Home / End; number + Return jumps; B / W blank to black or white; Esc exits. Presentation clickers send PageUp/PageDown, so they work without setup.
- `ProcessInfo.beginActivity(options: .idleDisplaySleepDisabled, …)` keeps the display awake while presenting.
- Notes render as Markdown, so links in notes are clickable in the presenter window only.

### Presentation session

A native `PresentationSession` (main actor) owns the state: current slide, current step, timer, blanked, and the rendered HTML. The web views only display it.

- Keys in either window call the session, which clamps the position and pushes `MdPreviewSlides.show(slide, step)` to every web view. A web view never changes slide on its own. Clicking does not advance.
- **Loading:** a web view is attached once its page reports ready; the session then sends the current position. Input that arrives earlier is applied to the session and reaches the view on attach.
- **Live edit:** a file change re-renders once and reloads both views. The session keeps the slide index and step, clamped to the new slide and step counts, so deleting the current slide moves to the one before it.
- **Display change:** if a display disappears, the presenter window closes and macOS moves the full-screen audience window to the remaining display, so presenting continues on one screen. Connecting a display does not move an ongoing presentation. Notes toggled with N on a single screen are not built yet.
- **Closing:** closing the audience window, Esc, or closing the document ends the session and closes the presenter window. Closing only the presenter window keeps presenting in single-screen mode.
- **Failure:** a web view that fails to load or crashes is reloaded once; on a second failure the session ends with an alert, rather than leaving the two windows out of step. (Not built yet: a reloaded page is told the position again on load, but there is no retry limit or alert.)

## Editing

Edit Mode replaces the preview: the editor is an overlay on Read Mode, and Read Mode only re-renders on leaving Edit Mode. So while editing a deck you see Markdown, not slides. Phase 3 adds a slide preview beside the editor without a new split layout.

### Slide Preview panel

A third panel in the right pane, next to Agenda and References: **View → Slide Preview**, offered only when the document is a deck.

- **Content:** the Read Mode strip of the whole deck, every slide at the pane's width, so the slides before and after the one being edited stay in view. It is a `MarkdownWebView` with a `slides-pane` host state.
- **Scaling with `pageZoom`:** the page is laid out at Read Mode's deck width (1100 CSS px) and `webView.pageZoom` is set to `paneWidth / 1100`, recomputed on resize. The pane shows an exact miniature of Read Mode, including pixel-sized chrome, so it needs no pane-specific sizing CSS. Daisy's text size uses a CSS variable (`textScale`), not `pageZoom`, and the page already accounts for `pageZoom` (`--mdp-chrome-zoom`, height and scroll reporting), so the two don't interfere. Pinch-to-zoom is off in the pane, so it never changes the text-size setting.
- **Notes are hidden** in the pane: at about 0.4× they would be unreadable. The presenter view and Read Mode show them.
- **Updates as you type:** the editor already sends `dirty` on every change. After a pause (about 300 ms) the host fetches the buffer (`fetchMarkdown`) and displays it in the pane; the morphdom body swap changes only the edited slide, so other slides and their diagrams are left alone. In Read Mode the pane shows the rendered document.
- **Following the caret:** the editor's `formattingState` message also carries the caret's line. Swift maps the line to a slide through each slide's start line (a new `startLine` on `SlideDeck.Slide`, shifted by the frontmatter offset), outlines that slide in the pane and scrolls it into view — only when the caret moves to a different slide, not on every keystroke. After the user scrolls the pane, it stops following until the caret moves to another slide. In Read Mode, nothing follows: the strip is already on screen.
- **Width:** the right pane's maximum width (500 pt) is raised for this panel so a slide can be larger.

### Landing on the slide

The same line-to-slide mapping makes leaving Edit Mode (⌘E) land on the slide that holds the caret, its top at the top of the view, and is what **Present from Current Slide** starts from.

### Slash commands

The editor's slash menu gains `/slide` (inserts `---`), `/notes` (`???`) and `/step`.

### Slide chrome in slide units

Separate from the pane, but in the same phase: code-block padding and label and Mermaid frame padding are fixed pixels in the base stylesheet, so they look oversized on a small slide and undersized on a large full-screen display. On slides they are sized in `em`, which scales with the slide, and the code copy and wrap buttons — reading tools, not slide content — are hidden.

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
2. Backgrounds and image sizing, `<!-- layout -->`, `<!-- _class -->`, `<!-- color -->`, `<!-- step -->`; presenter window with notes and timer. Built-in classes: `center`, `center-x`, `center-y`, `lead`, `invert`.
3. Themes (built-in and YAML), header and footer templates, `!caption`; the Slide Preview panel, landing on the slide after Edit Mode, Present from Current Slide, slash commands; slide chrome in slide units.
4. HTML and PPTX export, CLI options, Quick Look thumbnails.

Each phase updates `README.md` and `docs/render-extensions.md` in the same change, and adds a deck to `samples/`.

## Decisions

- A deck opens as slides in Read Mode; there is no document view of a deck.
- `???` is the only notes marker, in every deck. HTML comments are never notes, including in `marp: true` decks.
- The theme is chosen in frontmatter only. There is no theme picker in the UI.
