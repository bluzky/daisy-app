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
    /// Parses the same prepared text the formatter does.
    static func slideCount(markdown: String,
                           configuration: RenderExtensionConfiguration = .allEnabled) -> Int {
        let body = MarkdownFrontmatter.split(markdown).body
        let footnotes = extractFootnotes(from: body)
        let processed = configuration.isEnabled("katex")
            ? extractMath(from: footnotes.markdown).processedMarkdown
            : footnotes.markdown
        let prepared = EscapingHTMLFormatter.preparedForParsing(
            processed,
            rendersHighlights: configuration.isEnabled("highlight")
        )
        return SlideDeck(document: Document(parsing: prepared)).slides.count
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

        /// The script only matters while presenting, which only the app does.
        func assets(mode: VendorLoading) -> RenderAssets {
            guard mode == .lazy else { return RenderAssets(css: MarkdownHTML.slidesStylesheet) }
            return RenderAssets(
                css: MarkdownHTML.slidesStylesheet,
                bodyJS: MarkdownHTML.slidesScript,
                scriptAssetIDs: [id]
            )
        }
    }

    /// `MdPreviewSlides.show(index)` marks one slide current; the presenting
    /// stylesheet hides the others. The host owns the index and calls `show`
    /// again after every page load or body swap.
    static let slidesScript = """
    <script>
    (function() {
      let current = 0;
      const frames = () => document.querySelectorAll('article.markdown-body .mdp-slide-frame');
      function apply() {
        const all = frames();
        if (!all.length) return;
        current = Math.max(0, Math.min(current, all.length - 1));
        all.forEach((frame, index) => frame.toggleAttribute('data-mdp-current', index === current));
      }
      window.MdPreviewSlides = {
        show(index) { current = index; apply(); return current; },
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

    /// Slides are sized in container-query units of the deck (`cqw`), so a
    /// slide keeps its proportions at any width — the Read Mode strip, a full
    /// screen, or a printed page — without a CSS transform.
    static let slidesStylesheet = """
    article.markdown-body:has(> .mdp-deck) { max-width: 1100px; }
    .mdp-deck {
        container-type: inline-size;
        display: flex;
        flex-direction: column;
        gap: 2.5em;
        --mdp-slide-bg: Canvas;
    }
    .mdp-slide-frame { margin: 0; }
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

    .mdp-slide--title .mdp-slide-body,
    .mdp-slide--section .mdp-slide-body,
    .mdp-slide--quote .mdp-slide-body,
    .mdp-slide--math .mdp-slide-body {
        justify-content: center;
        align-items: center;
        text-align: center;
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
    .mdp-slide--grid .mdp-slide-body > p {
        display: grid;
        grid-template-columns: repeat(3, minmax(0, 1fr));
        gap: 1em;
        flex: 1;
        min-height: 0;
    }
    .mdp-slide--grid .mdp-slide-body > p > img { width: 100%; height: 100%; object-fit: cover; }

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
    :root[data-mdp-slides-presenting] body {
        height: 100%;
        overflow: hidden !important;
        background: #000;
    }
    :root[data-mdp-slides-presenting] body { padding: 0 !important; }
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
    :root[data-mdp-slides-presenting] .mdp-slide { border-radius: 0; box-shadow: none; }
    :root[data-mdp-slides-blank] .mdp-deck { visibility: hidden; }
    :root[data-mdp-slides-blank="white"],
    :root[data-mdp-slides-blank="white"] body { background: #fff; }

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
}
