//
//  SlideDeck.swift
//  daisy
//
//  Splits a parsed Markdown document into presentation slides.
//

import Foundation
import Markdown

/// A document read as slides: `---` at the top level ends a slide, and a
/// paragraph whose first line is `???` starts the slide's speaker notes.
///
/// Built from the same `Document` the formatter renders — after frontmatter,
/// footnote definitions and math have been taken out of the text — so slide
/// boundaries and source lines always agree with the HTML. Markers are only
/// recognised as direct children of the document: a `---` inside a list or
/// quote is an ordinary rule, and frontmatter never reaches the tree.
nonisolated struct SlideDeck {
    /// The slide's layout, inferred from its content and written as the
    /// `mdp-slide--<raw value>` class.
    enum Layout: String, CaseIterable {
        case title
        case section
        case quote
        case code
        case math
        case titleImage = "title-image"
        case grid
        case titleContent = "title-content"
        case blank
    }

    struct Slide {
        /// Blocks shown on the slide, in source order.
        var blocks: [Markup] = []
        /// The `???` paragraph when text follows the marker on its next
        /// lines; that text is the first paragraph of the notes.
        var notesLead: Paragraph?
        /// Note blocks after the `???` paragraph.
        var notes: [Markup] = []
        var layout: Layout = .blank

        var hasNotes: Bool { notesLead != nil || !notes.isEmpty }
        fileprivate var isEmpty: Bool { blocks.isEmpty && !hasNotes }
    }

    let slides: [Slide]

    init(document: Document) {
        var slides: [Slide] = []
        var current = Slide()
        var inNotes = false
        for child in document.children {
            if child is ThematicBreak {
                slides.append(current)
                current = Slide()
                inNotes = false
            } else if !inNotes, let paragraph = child as? Paragraph,
                      let marker = Self.notesMarker(paragraph) {
                inNotes = true
                if marker == .withText { current.notesLead = paragraph }
            } else if inNotes {
                current.notes.append(child)
            } else {
                current.blocks.append(child)
            }
        }
        slides.append(current)
        // A `---` opening the body or closing the file separates nothing.
        if slides.count > 1, slides[0].isEmpty { slides.removeFirst() }
        if slides.count > 1, slides[slides.count - 1].isEmpty { slides.removeLast() }
        self.slides = slides.map { slide in
            var slide = slide
            slide.layout = Self.layout(of: slide.blocks)
            return slide
        }
    }

    // MARK: - Notes marker

    enum NotesMarker: Equatable {
        /// `???` alone in its paragraph.
        case alone
        /// `???` on the first line, notes text on the following lines.
        case withText
    }

    static func notesMarker(_ paragraph: Paragraph) -> NotesMarker? {
        let children = Array(paragraph.children)
        guard let first = children.first as? Text,
              first.string.trimmingCharacters(in: .whitespaces) == "???" else { return nil }
        if children.count == 1 { return .alone }
        guard children[1] is SoftBreak || children[1] is LineBreak else { return nil }
        return children.count > 2 ? .withText : .alone
    }

    /// The notes text after the marker line of a `.withText` paragraph.
    static func notesLeadContent(_ paragraph: Paragraph) -> [Markup] {
        Array(paragraph.children.dropFirst(2))
    }

    // MARK: - Layout inference

    /// The longest paragraph a `title` slide keeps under its H1, in characters.
    static let titleSubtitleLimit = 200

    /// First matching rule wins. HTML comments don't count as content.
    static func layout(of blocks: [Markup]) -> Layout {
        let content = blocks.filter { !isCommentBlock($0) }
        guard !content.isEmpty else { return .blank }

        if let heading = content[0] as? Heading, heading.level == 1 {
            if content.count == 1 { return .title }
            if content.count == 2, let paragraph = content[1] as? Paragraph,
               imageCount(paragraph) == nil, !isMathBlock(paragraph),
               paragraph.plainText.count <= titleSubtitleLimit {
                return .title
            }
        }
        if content.count == 1, let heading = content[0] as? Heading, heading.level == 2 {
            return .section
        }
        if content.count == 1, let quote = content[0] as? BlockQuote, !isCallout(quote) {
            return .quote
        }

        let hasHeading = content[0] is Heading
        let body = hasHeading ? Array(content.dropFirst()) : content
        if body.count == 1, body[0] is CodeBlock { return .code }
        if body.count == 1, let paragraph = body[0] as? Paragraph, isMathBlock(paragraph) {
            return .math
        }
        if hasHeading, body.count == 1, let paragraph = body[0] as? Paragraph,
           imageCount(paragraph) == 1 {
            return .titleImage
        }
        if !body.isEmpty {
            let counts = body.map { ($0 as? Paragraph).flatMap(imageCount) }
            if !counts.contains(nil), counts.reduce(0, { $0 + ($1 ?? 0) }) >= 3 {
                return .grid
            }
        }
        return .titleContent
    }

    /// The number of images in a paragraph that holds nothing else but
    /// whitespace and line breaks; nil for any other paragraph.
    static func imageCount(_ paragraph: Paragraph) -> Int? {
        var images = 0
        for child in paragraph.children {
            switch child {
            case is Image:
                images += 1
            case is SoftBreak, is LineBreak:
                continue
            case let text as Text where text.string.allSatisfy(\.isWhitespace):
                continue
            default:
                return nil
            }
        }
        return images > 0 ? images : nil
    }

    /// Display math reaches the tree as a placeholder paragraph
    /// (`MarkdownHTML.extractMath`).
    static func isMathBlock(_ paragraph: Paragraph) -> Bool {
        let text = paragraph.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "MdPreviewMathBlock", suffix = "Token"
        guard text.hasPrefix(prefix), text.hasSuffix(suffix),
              text.count > prefix.count + suffix.count else { return false }
        return text.dropFirst(prefix.count).dropLast(suffix.count).allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// `> [!note]` and the other alert types render as callouts, not quotes.
    static func isCallout(_ quote: BlockQuote) -> Bool {
        guard let paragraph = quote.child(at: 0) as? Paragraph else { return false }
        return paragraph.plainText.hasPrefix("[!")
    }

    static func isCommentBlock(_ markup: Markup) -> Bool {
        guard let html = markup as? HTMLBlock else { return false }
        let raw = html.rawHTML.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.hasPrefix("<!--") && raw.hasSuffix("-->")
    }

    // MARK: - Turning it on

    /// True when the frontmatter asks for slides: `slides: true`, or Marp's
    /// `marp: true`.
    static func isDeck(frontmatter raw: String?, format: MarkdownFrontmatter.Format?) -> Bool {
        guard let raw, let format else { return false }
        return MarkdownFrontmatter.parse(raw, format: format).contains { entry in
            let key = entry.key.lowercased()
            return (key == "slides" || key == "marp")
                && entry.value.trimmingCharacters(in: .whitespaces).lowercased() == "true"
        }
    }

    static func isDeck(markdown: String) -> Bool {
        let frontmatter = MarkdownFrontmatter.split(markdown)
        return isDeck(frontmatter: frontmatter.raw, format: frontmatter.format)
    }
}
