//
//  MarkdownHTML+Slides.swift
//  daisy
//
//  Slide deck rendering: footnotes per slide, the slide stylesheet, and the
//  page script that shows one slide at a time while presenting.
//

import Foundation
import Markdown

nonisolated extension MarkdownHTML {
    /// Written by the formatter at the end of each slide body and notes
    /// block; replaced by the footnotes referenced since the previous token.
    static let slideFootnotesToken = "MdPreviewSlideFootnotesToken"

    /// Slide canvas size in CSS px. Slides scale to their container with
    /// container-query units, so this only fixes the aspect ratio and the
    /// printed page.
    static let slideCanvasWidth = 1280
    static let slideCanvasHeight = 720

    /// Host-state id (`data-mdp-slides-presenting` on `<html>`) that turns a
    /// deck page into a one-slide-at-a-time presentation.
    static let slidesPresentingStateID = "slides-presenting"
    /// `<html>` attribute set while a deck is being printed.
    static let slidesPrintAttribute = "data-mdp-slides-print"

    /// The number of slides `render` produces for `markdown` shown as a deck.
    static func slideCount(markdown: String,
                           configuration: RenderExtensionConfiguration = .allEnabled) -> Int {
        slideStepCounts(markdown: markdown, configuration: configuration).count
    }

    /// Each slide's number of `<!-- step -->` clicks, one entry per slide.
    /// Parses the same prepared text the formatter does.
    static func slideStepCounts(markdown: String,
                                configuration: RenderExtensionConfiguration = .allEnabled) -> [Int] {
        let body = MarkdownFrontmatter.split(markdown).body
        let footnotes = extractFootnotes(from: body)
        let processed = configuration.isEnabled("katex")
            ? extractMath(from: footnotes.markdown).processedMarkdown
            : footnotes.markdown
        let prepared = EscapingHTMLFormatter.preparedForParsing(
            processed,
            rendersHighlights: configuration.isEnabled("highlight")
        )
        return SlideDeck(document: Document(parsing: prepared)).slides.map(\.stepCount)
    }

    private static let footnoteReferenceTokenRegex: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"MdPreviewFootnoteRef(\d+)Token"#)
    }()

    /// Replaces each `slideFootnotesToken` with the footnotes referenced
    /// between it and the previous token. Runs before the reference tokens
    /// themselves are rendered.
    static func placeSlideFootnotes(in html: String,
                                    footnotes: FootnoteExtraction,
                                    items: [Int: String]) -> String {
        let segments = html.components(separatedBy: slideFootnotesToken)
        guard segments.count > 1 else { return html }
        var result = ""
        result.reserveCapacity(html.count)
        for (index, segment) in segments.enumerated() {
            result += segment
            guard index < segments.count - 1 else { break }
            let nsSegment = segment as NSString
            var numbers: [Int] = []
            for match in footnoteReferenceTokenRegex.matches(
                in: segment, range: NSRange(location: 0, length: nsSegment.length)
            ) {
                guard let tokenIndex = Int(nsSegment.substring(with: match.range(at: 1))),
                      footnotes.references.indices.contains(tokenIndex) else { continue }
                let number = footnotes.references[tokenIndex].number
                if !numbers.contains(number) { numbers.append(number) }
            }
            let listed = numbers.sorted().compactMap { items[$0] }
            if !listed.isEmpty {
                result += "<div class=\"mdp-slide-footnotes\"><ol>\n"
                    + listed.joined(separator: "\n")
                    + "\n</ol></div>"
            }
        }
        return result
    }

    /// Slide layout and presenting. Always on: a deck is something the
    /// document asks for, not a reading preference.
    struct SlidesExtension: MarkdownRenderExtension {
        let id = "slides"
        let descriptor = RenderExtensionDescriptor(
            titleKey: "Slides",
            descriptionKey: nil,
            defaultEnabled: true,
            userToggleable: false
        )
        let order = 400

        func isActive(in context: RenderContext) -> Bool {
            context.html.contains("<div class=\"mdp-deck\">")
        }

        /// Every host runs the script: it applies image sizes and slide
        /// colors, which the sanitizer keeps out of the HTML as styles.
        func assets(mode _: VendorLoading) -> RenderAssets {
            RenderAssets(
                css: MarkdownHTML.slidesStylesheet,
                bodyJS: MarkdownHTML.slidesScript,
                scriptAssetIDs: [id]
            )
        }
    }

    /// Applies `data-mdp-size` and `data-slide-color`, which can't be styles
    /// in the sanitized HTML. While presenting, `MdPreviewSlides.show(index,
    /// step)` marks the current slide, the next one (for the presenter view)
    /// and the revealed steps; the host owns the position and calls `show`
    /// again after every load or body swap.
    static let slidesScript = """
    <script>
    (function() {
      let current = 0;
      let step = 0;
      const frames = () => document.querySelectorAll('article.markdown-body .mdp-slide-frame');
      function apply() {
        const all = frames();
        all.forEach(frame => {
          frame.querySelectorAll('img[data-mdp-size]').forEach(img => { img.style.width = img.dataset.mdpSize; });
          frame.querySelectorAll('.mdp-slide[data-slide-color]').forEach(slide => { slide.style.color = slide.dataset.slideColor; });
        });
        if (!all.length) return;
        current = Math.max(0, Math.min(current, all.length - 1));
        all.forEach((frame, index) => {
          frame.toggleAttribute('data-mdp-current', index === current);
          frame.toggleAttribute('data-mdp-next', index === current + 1);
          frame.querySelectorAll('[data-step]').forEach(element => {
            element.toggleAttribute('data-mdp-shown', index !== current || Number(element.dataset.step) <= step);
          });
        });
      }
      window.MdPreviewSlides = {
        show(index, shownStep) { current = index; step = shownStep || 0; apply(); return current; },
        count() { return frames().length; },
        blank(mode) {
          const root = document.documentElement;
          if (mode === 'black' || mode === 'white') root.setAttribute('data-mdp-slides-blank', mode);
          else root.removeAttribute('data-mdp-slides-blank');
        }
      };
      window.MdPreview?.registerExtension({ id: 'slides', render() { apply(); } });
    })();
    </script>
    """

    /// Each frame is a size container and a slide is sized in its `cqw`
    /// units, so a slide keeps its proportions at any width — the Read Mode
    /// strip, a full screen, the presenter view or a printed page — without
    /// a CSS transform.
    static let slidesStylesheet = """
    article.markdown-body:has(> .mdp-deck) { max-width: 1100px; }
    .mdp-deck {
        display: flex;
        flex-direction: column;
        gap: 2.5em;
        --mdp-slide-bg: Canvas;
    }
    .mdp-slide-frame { margin: 0; container-type: inline-size; }
    .mdp-slide {
        position: relative;
        box-sizing: border-box;
        width: 100%;
        aspect-ratio: \(slideCanvasWidth) / \(slideCanvasHeight);
        overflow: hidden;
        display: flex;
        flex-direction: column;
        padding: 4.5cqw 6cqw;
        font-size: 2.2cqw;
        line-height: 1.4;
        background: var(--mdp-slide-bg);
        border-radius: 0.6cqw;
        box-shadow: 0 0 0 1px color-mix(in srgb, var(--text) 12%, transparent),
                    0 0.4cqw 1.6cqw color-mix(in srgb, #000 10%, transparent);
    }
    .mdp-slide-body {
        position: relative;
        flex: 1;
        min-height: 0;
        display: flex;
        flex-direction: column;
    }
    .mdp-slide-body > * { margin: 0 0 0.6em; }
    .mdp-slide-body > :last-child { margin-bottom: 0; }
    .mdp-slide-body > :is(h1, h2, h3, h4, h5, h6) { margin: 0 0 0.5em; line-height: 1.15; }
    .mdp-slide-body h1 { font-size: 2em; }
    .mdp-slide-body h2 { font-size: 1.6em; }
    .mdp-slide-body img { max-width: 100%; max-height: 100%; object-fit: contain; }
    .mdp-slide[data-slide-color] :is(h1, h2, h3, h4, h5, h6, blockquote) { color: inherit; }
    .mdp-step { display: contents; }

    .mdp-slide--title .mdp-slide-body,
    .mdp-slide--section .mdp-slide-body,
    .mdp-slide--quote .mdp-slide-body,
    .mdp-slide--math .mdp-slide-body,
    .mdp-slide-class-center .mdp-slide-body,
    .mdp-slide-class-lead .mdp-slide-body {
        justify-content: center;
        align-items: center;
        text-align: center;
    }
    .mdp-slide-class-center-x .mdp-slide-body { align-items: center; text-align: center; }
    .mdp-slide-class-center-y .mdp-slide-body { justify-content: center; }
    .mdp-slide-class-invert {
        --mdp-slide-bg: #1d1d1f;
        color: #f5f5f7;
    }
    .mdp-slide-class-invert :is(h1, h2, h3, h4, h5, h6) { color: inherit; }
    .mdp-slide-class-invert :not(pre) > code {
        background: color-mix(in srgb, #fff 14%, transparent);
        color: inherit;
    }
    .mdp-slide--title h1 { font-size: 2.6em; }
    .mdp-slide--title p { color: var(--secondary); font-size: 1.1em; }
    .mdp-slide--section h2 { font-size: 2.4em; margin: 0; }
    .mdp-slide--quote blockquote { font-size: 1.4em; font-style: italic; max-width: 85%; }
    .mdp-slide--math .math-display { font-size: 1.5em; }
    .mdp-slide--code pre { font-size: 0.75em; }
    .mdp-slide--title-image .mdp-slide-body > p:last-of-type {
        flex: 1;
        min-height: 0;
        display: flex;
        justify-content: center;
    }
    /* The body is the grid, so images in one paragraph or one per
       paragraph form a single gallery; a heading spans the first row. */
    .mdp-slide--grid .mdp-slide-body {
        display: grid;
        grid-template-columns: repeat(3, minmax(0, 1fr));
        grid-auto-rows: minmax(0, 1fr);
        gap: 1em;
    }
    .mdp-slide--grid .mdp-slide-body:has(> :is(h1, h2, h3, h4, h5, h6)) {
        grid-template-rows: auto;
    }
    .mdp-slide--grid .mdp-slide-body > * { margin: 0; }
    .mdp-slide--grid .mdp-slide-body > :is(p, .mdp-step) { display: contents; }
    .mdp-slide--grid .mdp-slide-body > :is(h1, h2, h3, h4, h5, h6, .mdp-slide-footnotes) {
        grid-column: 1 / -1;
    }
    .mdp-slide--grid .mdp-slide-body img {
        width: 100%;
        height: 100%;
        min-height: 0;
        object-fit: cover;
    }

    /* Backgrounds: behind the whole slide, or one half beside the text. */
    .mdp-slide-bg { position: absolute; inset: 0; }
    .mdp-slide-bg img {
        display: block;
        width: 100%;
        height: 100%;
        max-width: none;
        max-height: none;
        object-fit: cover;
    }
    .mdp-slide-bg--fit img { object-fit: contain; }
    .mdp-slide-bg--left { right: 50%; }
    .mdp-slide-bg--right { left: 50%; }
    .mdp-slide--bg-left { padding-left: calc(50% + 4cqw); }
    .mdp-slide--bg-right { padding-right: calc(50% + 4cqw); }
    .mdp-slide--split .mdp-slide-body { justify-content: center; }

    .mdp-slide-footnotes {
        margin-top: auto;
        padding-top: 0.5em;
        font-size: 0.55em;
        color: var(--secondary);
    }
    .mdp-slide-footnotes ol { margin: 0; padding-left: 1.5em; }
    .mdp-slide-footnotes p { margin: 0; }

    /* Speaker notes under each slide in Read Mode; hidden when presenting. */
    .mdp-slide-notes {
        margin-top: 0.8em;
        padding-left: 0.8em;
        border-left: 2px solid var(--quote-border);
        color: var(--secondary);
        font-size: 0.9em;
    }
    .mdp-slide-notes > :first-child { margin-top: 0; }
    .mdp-slide-notes > :last-child { margin-bottom: 0; }

    :root[data-mdp-slides-presenting],
    :root[data-mdp-slides-presenting] body,
    :root[data-mdp-slides-presenter],
    :root[data-mdp-slides-presenter] body {
        height: 100%;
        overflow: hidden !important;
    }
    :root[data-mdp-slides-presenting],
    :root[data-mdp-slides-presenting] body { background: #000; }
    :root:is([data-mdp-slides-presenting], [data-mdp-slides-presenter]) body { padding: 0 !important; }
    :root[data-mdp-slides-presenting] article.markdown-body {
        max-width: none;
        height: 100vh;
        margin: 0;
        padding: 0;
        display: flex;
        align-items: center;
        justify-content: center;
    }
    :root[data-mdp-slides-presenting] .mdp-deck {
        width: min(100vw, calc(100vh * \(slideCanvasWidth) / \(slideCanvasHeight)));
        gap: 0;
    }
    :root[data-mdp-slides-presenting] .mdp-slide-frame:not([data-mdp-current]),
    :root[data-mdp-slides-presenting] .mdp-slide-notes { display: none; }
    :root[data-mdp-slides-presenting] .mdp-slide {
        border-radius: 0;
        box-shadow: none;
    }
    :root:is([data-mdp-slides-presenting], [data-mdp-slides-presenter])
        [data-mdp-current] [data-step]:not([data-mdp-shown]) { visibility: hidden; }
    :root[data-mdp-slides-blank] .mdp-deck { visibility: hidden; }
    :root[data-mdp-slides-blank="white"],
    :root[data-mdp-slides-blank="white"] body { background: #fff; }

    /* Presenter view: the current slide and its notes on the left, the
       next slide on the right. */
    :root[data-mdp-slides-presenter] body {
        background: color-mix(in srgb, var(--text) 7%, Canvas);
    }
    :root[data-mdp-slides-presenter] article.markdown-body {
        max-width: none;
        height: 100vh;
        margin: 0;
        padding: 0;
    }
    :root[data-mdp-slides-presenter] .mdp-deck {
        height: 100%;
        box-sizing: border-box;
        padding: 24px;
        display: grid;
        grid-template-columns: 62fr 38fr;
        grid-template-rows: min-content;
        align-items: start;
        gap: 24px;
    }
    :root[data-mdp-slides-presenter] .mdp-slide-frame:not([data-mdp-current], [data-mdp-next]) { display: none; }
    :root[data-mdp-slides-presenter] [data-mdp-current] {
        grid-column: 1;
        grid-row: 1;
        max-height: calc(100vh - 48px);
        overflow-y: auto;
    }
    :root[data-mdp-slides-presenter] [data-mdp-next] { grid-column: 2; grid-row: 1; opacity: 0.85; }
    :root[data-mdp-slides-presenter] [data-mdp-next] .mdp-slide-notes { display: none; }
    :root[data-mdp-slides-presenter] [data-mdp-current] .mdp-slide-notes {
        margin-top: 20px;
        padding-left: 14px;
        border-left-width: 3px;
        color: var(--text);
        font-size: 22px;
        line-height: 1.45;
    }

    /* One slide per page at the canvas size. The host sets the page size
       and margins on the print operation and adds `@page` while printing. */
    @media print {
        :root[\(slidesPrintAttribute)] body { padding: 0 !important; margin: 0; }
        :root[\(slidesPrintAttribute)] article.markdown-body {
            max-width: none !important;
            margin: 0 !important;
            padding: 0 !important;
        }
        :root[\(slidesPrintAttribute)] .mdp-deck {
            display: block;
            width: \(slideCanvasWidth)px;
        }
        :root[\(slidesPrintAttribute)] .mdp-slide-frame { break-after: page; }
        :root[\(slidesPrintAttribute)] .mdp-slide-frame:last-child { break-after: auto; }
        :root[\(slidesPrintAttribute)] .mdp-slide {
            width: \(slideCanvasWidth)px;
            height: \(slideCanvasHeight)px;
            aspect-ratio: auto;
            border-radius: 0;
            box-shadow: none;
        }
        :root[\(slidesPrintAttribute)] .mdp-slide-notes { display: none; }
    }
    """

    /// Injected only while a deck prints: `@page` cannot be scoped to an
    /// attribute, and the base print stylesheet sets paper margins.
    static let slidesPrintPageCSS =
        "@page { size: \(slideCanvasWidth)px \(slideCanvasHeight)px; margin: 0; }"

    /// Host-state id (`data-mdp-slides-presenter` on `<html>`) that lays a
    /// deck page out as the presenter view.
    static let slidesPresenterStateID = "slides-presenter"
}
