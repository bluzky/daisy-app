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
    /// The slide's layout, inferred from its content or set with
    /// `<!-- layout: name -->`, and written as the `mdp-slide--<raw value>`
    /// class.
    enum Layout: String, CaseIterable {
        case title
        case section
        case quote
        case code
        case math
        case titleImage = "title-image"
        case split
        case fullBleed = "full-bleed"
        case columns
        case titleContent = "title-content"
        case blank
    }

    /// `![bg](image)`: the first background image on a slide.
    struct Background: Equatable {
        enum Position: String {
            case full
            case left
            case right
        }

        var source: String
        var position: Position = .full
        /// `fit` / `contain`: scale the whole image into the area instead
        /// of covering it.
        var fits = false
        /// `dim`: darken the image so text on it reads.
        var dims = false
        /// `blur`: soften the image behind the text.
        var blurs = false
    }

    /// Where an element starts in the parsed text; the formatter looks up
    /// an element's step by it.
    struct SourceKey: Hashable {
        let line: Int
        let column: Int

        init?(_ markup: Markup) {
            guard let start = markup.range?.lowerBound else { return nil }
            line = start.line
            column = start.column
        }
    }

    struct Slide {
        /// Blocks shown on the slide, in source order, without directives
        /// and background images.
        var blocks: [Markup] = []
        /// The `???` paragraph when text follows the marker on its next
        /// lines; that text is the first paragraph of the notes.
        var notesLead: Paragraph?
        /// Note blocks after the `???` paragraph.
        var notes: [Markup] = []
        var layout: Layout = .blank
        var background: Background?
        /// From `<!-- _class: … -->`, each a plain class name.
        var classes: [String] = []
        /// From `<!-- color: … -->` or `<!-- _color: … -->`: a hex color or
        /// a color name.
        var color: String?
        /// Click on which a block is revealed, by index in `blocks`, from
        /// `<!-- step -->` on the line before it.
        var blockSteps: [Int: Int] = [:]
        /// Click on which a list item or paragraph is revealed, from
        /// `<!-- step -->` at the end of its text.
        var elementSteps: [SourceKey: Int] = [:]
        /// The highest step; 0 when everything shows at once.
        var stepCount = 0
        /// Blocks shown above the columns, across the slide: the heading
        /// that opens a slide with columns. A range of `blocks`.
        var columnHeader: Range<Int> = 0..<0
        /// Each column's blocks, as ranges of `blocks`, from
        /// `<!-- column -->` breaks. Empty unless there are two or more.
        var columns: [Range<Int>] = []
        /// Blocks after `<!-- end-columns -->`, shown below the columns
        /// across the slide. A range of `blocks`.
        var columnFooter: Range<Int> = 0..<0
        /// Empty lines from `<!-- space -->` / `<!-- space: n -->`, by index
        /// in `blocks`; the comment block itself holds the place.
        var spaces: [Int: Int] = [:]
        /// `<!-- _paginate: true|false -->`: this slide's page number
        /// against the deck's `paginate`; nil follows the deck.
        var paginate: Bool?
        /// `<!-- _header: … -->` / `<!-- _footer: … -->`: this slide's
        /// template; an empty value hides it, nil follows the deck.
        var header: String?
        var footer: String?

        var hasNotes: Bool { notesLead != nil || !notes.isEmpty }
        fileprivate var isEmpty: Bool { blocks.isEmpty && !hasNotes && background == nil }
        fileprivate var layoutOverride: Layout?
        /// Indices in `blocks` where a `<!-- column -->` starts a column.
        fileprivate var columnBreaks: [Int] = []
        /// Index in `blocks` of the first block after `<!-- end-columns -->`.
        fileprivate var columnsEnd: Int?
    }

    /// The most columns a slide is split into; later breaks are ignored.
    static let maximumColumns = 4
    /// The most empty lines one `<!-- space: n -->` adds.
    static let maximumSpaceLines = 10

    let slides: [Slide]
    /// The first line of each slide in the parsed text, one per slide: 1,
    /// then the line of each `---`, which belongs to the slide it opens.
    let startLines: [Int]

    init(document: Document) {
        var slides: [Slide] = []
        var startLines = [1]
        var current = Slide()
        var inNotes = false
        var pendingStep: String?
        func finishSlide() {
            (current.columnHeader, current.columns, current.columnFooter) = Self.columns(
                of: current.blocks, breaks: current.columnBreaks, end: current.columnsEnd
            )
            current.layout = current.layoutOverride
                ?? (current.columns.isEmpty ? nil : .columns)
                ?? Self.layout(of: current.blocks, background: current.background)
            slides.append(current)
            current = Slide()
            inNotes = false
            pendingStep = nil
        }
        for child in document.children {
            if child is ThematicBreak {
                finishSlide()
                startLines.append(child.range?.lowerBound.line ?? startLines[startLines.count - 1])
            } else if !inNotes, let paragraph = child as? Paragraph,
                      let marker = Self.notesMarker(paragraph) {
                inNotes = true
                if marker == .withText { current.notesLead = paragraph }
            } else if inNotes {
                current.notes.append(child)
            } else if let directives = Self.directives(in: child) {
                for (key, value) in directives {
                    if key == "space" {
                        current.addSpace(value, block: child)
                    } else {
                        current.apply(key: key, value: value, pendingStep: &pendingStep)
                    }
                }
            } else if let paragraph = child as? Paragraph,
                      let background = Self.background(in: paragraph) {
                // Only the first background on a slide is used.
                if current.background == nil { current.background = background }
            } else {
                current.blocks.append(child)
                if let step = pendingStep {
                    current.blockSteps[current.blocks.count - 1] = current.nextStep(step)
                    pendingStep = nil
                }
                for (key, step) in Self.inlineSteps(in: child) {
                    current.elementSteps[key] = current.nextStep(step)
                }
            }
        }
        finishSlide()
        // A `---` opening the body or closing the file separates nothing.
        if slides.count > 1, slides[0].isEmpty {
            slides.removeFirst()
            startLines.removeFirst()
            startLines[0] = 1
        }
        if slides.count > 1, slides[slides.count - 1].isEmpty {
            slides.removeLast()
            startLines.removeLast()
        }
        self.slides = slides
        self.startLines = startLines
    }

    // MARK: - Directives

    /// The `key: value` pairs of a block made only of HTML comments, or nil
    /// for any other block. `<!-- step -->` has an empty value.
    static func directives(in markup: Markup) -> [(key: String, value: String)]? {
        guard let html = markup as? HTMLBlock else { return nil }
        return comments(in: html.rawHTML)?.flatMap(directives(inComment:))
    }

    private static func comments(in raw: String) -> [String]? {
        var rest = Substring(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        var comments: [String] = []
        while !rest.isEmpty {
            guard rest.hasPrefix("<!--"),
                  let close = rest.range(of: "-->") else { return nil }
            comments.append(String(rest[rest.index(rest.startIndex, offsetBy: 4)..<close.lowerBound]))
            rest = rest[close.upperBound...].drop(while: \.isWhitespace)
        }
        return comments.isEmpty ? nil : comments
    }

    /// One directive per line, as in Marp, where a comment is YAML:
    ///
    ///     <!--
    ///     layout: title
    ///     _class: invert
    ///     -->
    ///
    /// A value may be quoted (`color: "#fff"`, which YAML needs); blank
    /// lines are skipped.
    static func directives(inComment comment: String) -> [(key: String, value: String)] {
        comment.split(whereSeparator: \.isNewline).compactMap { line in
            let text = line.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return nil }
            guard let colon = text.firstIndex(of: ":") else { return (text.lowercased(), "") }
            return (
                text[..<colon].trimmingCharacters(in: .whitespaces).lowercased(),
                unquoted(text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces))
            )
        }
    }

    private static func unquoted(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, first == value.last,
              first == "\"" || first == "'" else { return value }
        return String(value.dropFirst().dropLast())
    }

    /// Steps written at the end of a list item's or paragraph's text, in
    /// source order, keyed by the element they reveal: the list item when
    /// the paragraph is in one, else the paragraph. A step comment anywhere
    /// else in the text is ignored, so it never hides text written after it.
    static func inlineSteps(in markup: Markup) -> [(SourceKey, String)] {
        var steps: [(SourceKey, String)] = []
        func walk(_ node: Markup) {
            if let paragraph = node as? Paragraph {
                let values = trailingComments(of: paragraph)
                    .flatMap(directives(inComment:))
                    .filter { $0.key == "step" }
                    .map(\.value)
                let element = paragraph.parent is ListItem ? paragraph.parent! : paragraph
                if let value = values.first, let sourceKey = SourceKey(element) {
                    steps.append((sourceKey, value))
                }
                return
            }
            for child in node.children { walk(child) }
        }
        walk(markup)
        return steps
    }

    /// The comments that end a paragraph, after its last text, in source
    /// order. Whitespace and line breaks between them don't count.
    private static func trailingComments(of paragraph: Paragraph) -> [String] {
        var found: [String] = []
        for child in paragraph.children.reversed() {
            switch child {
            case is SoftBreak, is LineBreak:
                continue
            case let text as Text where text.string.allSatisfy(\.isWhitespace):
                continue
            case let html as InlineHTML:
                guard let comments = comments(in: html.rawHTML) else { return found }
                found.insert(contentsOf: comments, at: 0)
            default:
                return found
            }
        }
        return found
    }

    // MARK: - Columns

    /// Splits a slide's blocks at its column breaks. A heading opening the
    /// slide stays above the columns, and blocks after `<!-- end-columns -->`
    /// go below them; empty columns (a break right after the heading, or
    /// just before the end) are dropped; at most `maximumColumns`. Fewer
    /// than two columns means no columns.
    static func columns(
        of blocks: [Markup], breaks: [Int], end columnsEnd: Int? = nil
    ) -> (header: Range<Int>, columns: [Range<Int>], footer: Range<Int>) {
        let none = (0..<0, [Range<Int>](), 0..<0)
        guard !breaks.isEmpty else { return none }
        let headerEnd = blocks.first is Heading ? 1 : 0
        let lastIndex = max(headerEnd, columnsEnd ?? blocks.count)
        let starts = [headerEnd] + breaks.map { max($0, headerEnd) }
        var columns: [Range<Int>] = []
        for (index, start) in starts.enumerated() {
            let end = index + 1 < starts.count ? starts[index + 1] : lastIndex
            guard start < end else { continue }
            if columns.count == maximumColumns {
                // Past the limit, the rest stays in the last column.
                columns[columns.count - 1] = columns[columns.count - 1].lowerBound..<end
            } else {
                columns.append(start..<end)
            }
        }
        guard columns.count >= 2 else { return none }
        return (0..<headerEnd, columns, lastIndex..<blocks.count)
    }

    // MARK: - Backgrounds

    /// A background when the paragraph holds only images whose alt text
    /// starts with the word `bg`; the first image is used.
    static func background(in paragraph: Paragraph) -> Background? {
        guard imageCount(paragraph) != nil else { return nil }
        let images = paragraph.children.compactMap { $0 as? Image }
        let words = images.map { $0.plainText.lowercased().split(whereSeparator: \.isWhitespace) }
        guard words.allSatisfy({ $0.first == "bg" }),
              let image = images.first,
              let source = image.source, !source.isEmpty else { return nil }
        var background = Background(source: source)
        for word in words[0].dropFirst() {
            switch word {
            case "left": background.position = .left
            case "right": background.position = .right
            case "fit", "contain": background.fits = true
            case "dim": background.dims = true
            case "blur": background.blurs = true
            default: continue
            }
        }
        return background
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
    static func layout(of blocks: [Markup], background: Background? = nil) -> Layout {
        let content = blocks.filter { block in
            !isCommentBlock(block) && (block as? Paragraph).flatMap(caption) == nil
        }
        if let background {
            if background.position != .full { return .split }
            if content.isEmpty { return .fullBleed }
        }
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
            case let html as InlineHTML where comments(in: html.rawHTML) != nil:
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

    /// The slide holding `line` of the parsed text.
    func slideIndex(atLine line: Int) -> Int {
        max(0, (startLines.lastIndex { $0 <= line } ?? 0))
    }

    // MARK: - Captions

    /// The text of a `!caption[text]` paragraph, which captions the image,
    /// table, diagram or math block above it; nil for any other paragraph.
    static func caption(_ paragraph: Paragraph) -> String? {
        let text = paragraph.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("!caption["), text.hasSuffix("]") else { return nil }
        return String(text.dropFirst("!caption[".count).dropLast())
    }

    /// The deck's title for `{title}`: the first H1 on any slide.
    var firstTitle: String? {
        for slide in slides {
            if let heading = slide.blocks.lazy.compactMap({ $0 as? Heading }).first(where: { $0.level == 1 }) {
                return heading.plainText
            }
        }
        return nil
    }

    // MARK: - Values

    /// A hex color or a CSS color name; anything else is dropped.
    static func sanitizedColor(_ value: String) -> String? {
        let isHex = value.hasPrefix("#") && [4, 5, 7, 9].contains(value.count)
            && value.dropFirst().allSatisfy(\.isHexDigit)
        let isName = (3...24).contains(value.count) && value.allSatisfy { $0.isASCII && $0.isLetter }
        return isHex || isName ? value.lowercased() : nil
    }

    /// An image title that is a size: a number and `%`, `px`, `em`, `rem`
    /// or `cqi`, such as `50%`.
    static func imageSize(_ title: String) -> String? {
        let value = title.trimmingCharacters(in: .whitespaces).lowercased()
        for unit in ["%", "px", "rem", "em", "cqi"] where value.hasSuffix(unit) {
            let number = value.dropLast(unit.count)
            guard !number.isEmpty, Double(number).map({ $0 > 0 }) == true,
                  number.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }) else { return nil }
            return value
        }
        return nil
    }

    /// Plain class names: letters, digits, `-` and `_`.
    static func sanitizedClasses(_ value: String) -> [String] {
        value.split(whereSeparator: \.isWhitespace).map(String.init).filter { name in
            name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        }
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

nonisolated private extension SlideDeck.Slide {
    /// Applies one directive. Unknown keys and invalid values are ignored.
    mutating func apply(key: String, value: String, pendingStep: inout String?) {
        switch key {
        case "layout":
            if let layout = SlideDeck.Layout(rawValue: value.lowercased()) { layoutOverride = layout }
        case "_class":
            classes += SlideDeck.sanitizedClasses(value)
        case "_paginate":
            paginate = value.lowercased() == "true"
        case "_header":
            header = value
        case "_footer":
            footer = value
        case "color", "_color":
            if let color = SlideDeck.sanitizedColor(value) { self.color = color }
        case "step":
            pendingStep = value
        case "column":
            if columnsEnd == nil, columnBreaks.last != blocks.count { columnBreaks.append(blocks.count) }
        case "end-columns":
            if columnsEnd == nil, !columnBreaks.isEmpty { columnsEnd = blocks.count }
        default:
            break
        }
    }

    /// `<!-- space -->` is one empty line, `<!-- space: n -->` is `n`, up to
    /// `maximumSpaceLines`. It stays in the blocks so it keeps its place;
    /// comments don't count toward the layout, and a pending step skips it.
    mutating func addSpace(_ value: String, block: Markup) {
        let lines = value.isEmpty ? 1 : Int(value).flatMap { $0 > 0 ? $0 : nil }
        guard let lines else { return }
        blocks.append(block)
        spaces[blocks.count - 1] = min(lines, SlideDeck.maximumSpaceLines)
    }

    /// `step` takes the click after the highest so far; `step: n` takes
    /// click `n`, so several elements can share one.
    mutating func nextStep(_ value: String) -> Int {
        let step = Int(value).flatMap { $0 > 0 ? $0 : nil } ?? stepCount + 1
        stepCount = max(stepCount, step)
        return step
    }
}
