//
//  EscapingHTMLFormatter+Cards.swift
//  daisy
//
//  Cards: blocks framed as one panel, from HTML comments on their own lines:
//
//      <!-- card style=accent edge=top color=success padding=compact -->
//      Any blocks
//      <!-- end-card -->
//
//  Options are `key=value` pairs in the opening comment, from a fixed set of
//  named values and checked hex colors; there is no raw CSS. The page drops
//  every `style` attribute, so a palette color is a class and a hex color a
//  `data-md-card-color` attribute that `CardColorExtension` checks again and
//  sets as the `--md-card-color` custom property. Other viewers hide the
//  comments and show the blocks as usual.
//
//  A card needs its closing comment, at least one block, and valid options;
//  otherwise its blocks are left as plain content, so a typo never frames the
//  rest of the document. Cards do not nest, and columns cannot go inside a
//  card; a card can go inside a column. Slides read the same comments
//  (`SlideDeck`); a card there must stay within one column.
//

import Foundation
import Markdown

/// The options of one card, already checked.
nonisolated struct CardStyle: Equatable, Sendable {
    enum Look: String, CaseIterable, Sendable { case plain, outline, filled, accent }
    enum Padding: String, CaseIterable, Sendable { case compact, normal, roomy }
    enum Align: String, CaseIterable, Sendable { case start, center }
    /// Where an accent card's bar sits.
    enum Edge: String, CaseIterable, Sendable { case left, top }

    var look = Look.plain
    /// A palette color name (`DashboardColor`'s semantic ones) or a
    /// lowercased `#rgb` / `#rrggbb`; nil uses the accent.
    var color: String?
    var tint = false
    var padding = Padding.normal
    var align = Align.start
    var edge = Edge.left

    /// The palette names `color` accepts, the same as every dashboard
    /// widget's; `default` is the card's normal look.
    static let paletteColors: [DashboardColor] = DashboardColor.named

    init() {}

    /// Parses the text after `card` in the opening comment: whitespace-
    /// separated `key=value` pairs, values optionally quoted. Nil when any
    /// pair is malformed, repeated, unknown or has a value outside its set.
    init?(options: String) {
        var seen: Set<String> = []
        for token in options.split(whereSeparator: \.isWhitespace) {
            guard let equals = token.firstIndex(of: "=") else { return nil }
            let key = token[..<equals].lowercased()
            var value = String(token[token.index(after: equals)...]).lowercased()
            if value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" {
                value = String(value.dropFirst().dropLast())
            }
            guard !value.isEmpty, seen.insert(key).inserted else { return nil }
            switch key {
            case "style":
                guard let look = Look(rawValue: value) else { return nil }
                self.look = look
            case "color":
                guard Self.paletteColors.contains(where: { $0.rawValue == value })
                        || value.range(of: #"^#(?:[0-9a-f]{3}|[0-9a-f]{6})$"#, options: .regularExpression) != nil
                else { return nil }
                color = value == DashboardColor.neutral.rawValue ? nil : value
            case "tint":
                guard value == "true" || value == "false" else { return nil }
                tint = value == "true"
            case "padding":
                guard let padding = Padding(rawValue: value) else { return nil }
                self.padding = padding
            case "align":
                guard let align = Align(rawValue: value) else { return nil }
                self.align = align
            case "edge":
                guard let edge = Edge(rawValue: value) else { return nil }
                self.edge = edge
            default:
                return nil
            }
        }
    }

    /// The wrapper's classes; defaults add nothing beyond `md-card`.
    var classes: String {
        var classes = ["md-card"]
        if look != .plain { classes.append("md-card-\(look.rawValue)") }
        if let color {
            classes.append("md-card-colored")
            if !color.hasPrefix("#") { classes.append("md-card-color-\(color)") }
        }
        if tint { classes.append("md-card-tint") }
        if padding != .normal { classes.append("md-card-pad-\(padding.rawValue)") }
        if align != .start { classes.append("md-card-align-\(align.rawValue)") }
        if look == .accent, edge != .left { classes.append("md-card-edge-\(edge.rawValue)") }
        return classes.joined(separator: " ")
    }

    /// ` data-md-card-color="#…"` for a hex color, else empty: a palette
    /// color is a class. The value is a checked hex, never authored CSS.
    var colorAttribute: String {
        guard let color, color.hasPrefix("#") else { return "" }
        return " \(DocumentCards.colorAttribute)=\"\(color)\""
    }

    /// The wrapper's opening tag.
    var openingTag: String {
        "<div class=\"\(classes)\"\(colorAttribute)>\n"
    }
}

nonisolated enum DocumentCards {

    /// Attribute carrying a card's hex color to the page script.
    static let colorAttribute = "data-md-card-color"

    enum Marker: Equatable {
        /// An opening comment; nil when its options are invalid.
        case open(CardStyle?)
        case end
    }

    /// What one comment's text (between `<!--` and `-->`) says.
    static func marker(ofComment comment: String) -> Marker? {
        let body = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = body.lowercased()
        if lower == "end-card" { return .end }
        if lower == "card" { return .open(CardStyle()) }
        guard lower.hasPrefix("card"), let next = body.dropFirst(4).first, next.isWhitespace else { return nil }
        return .open(CardStyle(options: String(body.dropFirst(4))))
    }

    /// What a block says, when it is exactly one card comment.
    static func marker(of block: Markup) -> Marker? {
        guard let html = block as? HTMLBlock else { return nil }
        let text = html.rawHTML.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("<!--"), text.hasSuffix("-->"), !text.dropFirst(4).dropLast(3).contains("-->")
        else { return nil }
        return marker(ofComment: String(text.dropFirst(4).dropLast(3)))
    }

    /// One card: its options, its blocks (indices into the children), and
    /// where its closing comment sits.
    struct Card {
        let style: CardStyle
        let blocks: Range<Int>
        let end: Int
    }

    /// The card that opens at `children[open]`, looking no further than
    /// `limit`; nil when it is not a well-formed one.
    static func card(in children: [Markup], opening open: Int, limit: Int) -> Card? {
        guard case .open(let style?) = marker(of: children[open]) else { return nil }
        var index = open + 1
        while index < limit {
            let child = children[index]
            if DocumentColumns.marker(of: child) != nil { return nil }
            switch marker(of: child) {
            case .open: return nil
            case .end:
                guard index > open + 1 else { return nil }
                return Card(style: style, blocks: (open + 1)..<index, end: index)
            case nil: index += 1
            }
        }
        return nil
    }
}

nonisolated extension EscapingHTMLFormatter {

    /// Visits `children[range]` in order, framing each well-formed card.
    /// Blank-line spacers go between blocks, not before the first.
    mutating func visitBlocksWithCards(_ children: [Markup], in range: Range<Int>) {
        var first = true
        var index = range.lowerBound
        while index < range.upperBound {
            let block = children[index]
            if DocumentColumns.marker(of: block) != nil {
                index += 1
                continue
            }
            if !first { emitBlankLineSpacers(before: block) }
            first = false
            if let card = DocumentCards.card(in: children, opening: index, limit: range.upperBound) {
                emitCard(card, in: children)
                index = card.end + 1
                continue
            }
            visit(block)
            index += 1
        }
    }

    mutating func emitCard(_ card: DocumentCards.Card, in children: [Markup]) {
        emit(card.style.openingTag)
        var first = true
        for block in children[card.blocks] {
            if !first { emitBlankLineSpacers(before: block) }
            first = false
            visit(block)
        }
        emit("</div>\n")
    }
}

nonisolated extension MarkdownHTML {

    /// Sets a card's hex color, which the page cannot take as a `style`
    /// attribute, as its `--md-card-color` custom property. Loads only when a
    /// card has one, in every vendor-loading mode, Quick Look's included.
    struct CardColorExtension: MarkdownRenderExtension {
        let id = "card-colors"
        let descriptor = RenderExtensionDescriptor(
            titleKey: "Card Colors",
            descriptionKey: nil,
            defaultEnabled: true,
            userToggleable: false
        )
        let order = 231

        func isActive(in context: RenderContext) -> Bool {
            context.html.contains(DocumentCards.colorAttribute)
        }

        func assets(mode _: VendorLoading) -> RenderAssets {
            RenderAssets(bodyJS: MarkdownHTML.cardColorScript, scriptAssetIDs: [id])
        }
    }

    static let cardColorScript = """
    <script>
    (function() {
      const HEX = /^#(?:[0-9a-f]{3}|[0-9a-f]{6})$/i;
      function apply(root) {
        const scope = root && root.querySelectorAll ? root : document;
        for (const card of scope.querySelectorAll('[\(DocumentCards.colorAttribute)]')) {
          const color = card.getAttribute('\(DocumentCards.colorAttribute)');
          if (HEX.test(color)) card.style.setProperty('--md-card-color', color);
        }
      }
      window.MdPreview?.registerExtension({ id: 'card-colors', render(root) { apply(root); } });
    })();
    </script>
    """
}
