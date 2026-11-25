//
//  EscapingHTMLFormatter+Cards.swift
//  daisy
//
//  Cards: blocks framed as one panel, from HTML comments on their own lines:
//
//      <!-- card style=accent bar=top color=success padding=compact shape=pill -->
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
///
/// Each part of the look is its own option: `fill` (the background),
/// `border`, `bar` (a colored edge), `shape`, `padding` and `align`, plus one
/// `color` that whichever of them takes a color uses. `style` is a preset
/// that sets `fill` and `border` (and `bar` for `accent`); an option written
/// beside it overrides the preset, wherever it stands in the comment.
nonisolated struct CardStyle: Equatable, Sendable {
    /// None, the theme's code-block background, 8% or 14% of the color, or
    /// the color itself (with text that reads on it).
    enum Fill: String, CaseIterable, Sendable { case none, surface, soft, tint, solid }
    enum Border: String, CaseIterable, Sendable { case none, thin, thick }
    /// A colored bar down the left side or across the top.
    enum Bar: String, CaseIterable, Sendable { case none, left, top }
    enum Padding: String, CaseIterable, Sendable { case none, compact, normal, roomy }
    enum Align: String, CaseIterable, Sendable { case start, center }
    /// The outline: rounded corners (the default), square ones, fully
    /// round ends, or a circle with its content centered.
    enum Shape: String, CaseIterable, Sendable { case rounded, square, pill, circle }

    /// `style=`: named sets of `fill`, `border` and `bar`.
    enum Preset: String, CaseIterable, Sendable {
        case plain, outline, filled, accent, solid, none

        var fill: Fill {
            switch self {
            case .plain, .accent: .surface
            case .outline, .none: .none
            case .filled: .tint
            case .solid: .solid
            }
        }

        var border: Border {
            switch self {
            case .plain, .outline, .accent: .thin
            case .filled, .solid, .none: .none
            }
        }

        var bar: Bar { self == .accent ? .left : .none }
    }

    var fill = Fill.surface
    var border = Border.thin
    var bar = Bar.none
    /// A palette color name (`WidgetColor`'s semantic ones) or a
    /// lowercased `#rgb` / `#rrggbb`; nil uses the accent.
    var color: String?
    var padding = Padding.normal
    var align = Align.start
    var shape = Shape.rounded

    /// `color` takes the same palette names as every widget
    /// (`WidgetColor.named(_:)`); `default` or `neutral` is the card's
    /// normal look.
    static let paletteColors: [WidgetColor] = WidgetColor.named

    /// Every option a card reads.
    static let optionNames: Set<String> = ["style", "fill", "border", "bar", "color", "padding", "align", "shape"]

    init() {}

    /// Parses the text after `card` in the opening comment: whitespace-
    /// separated `key=value` pairs, values optionally quoted. Nil when any
    /// pair is malformed, repeated, unknown or has a value outside its set.
    init?(options: String) {
        var values: [String: String] = [:]
        for token in options.split(whereSeparator: \.isWhitespace) {
            guard let equals = token.firstIndex(of: "=") else { return nil }
            let key = token[..<equals].lowercased()
            var value = String(token[token.index(after: equals)...]).lowercased()
            if value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" {
                value = String(value.dropFirst().dropLast())
            }
            guard !value.isEmpty, Self.optionNames.contains(key), values[key] == nil else { return nil }
            values[key] = value
        }
        // The preset first, so the options beside it override it.
        if let name = values["style"] {
            guard let preset = Preset(rawValue: name) else { return nil }
            fill = preset.fill
            border = preset.border
            bar = preset.bar
        }
        func read<Value: RawRepresentable>(_ key: String, into target: inout Value) -> Bool
        where Value.RawValue == String {
            guard let raw = values[key] else { return true }
            guard let value = Value(rawValue: raw) else { return false }
            target = value
            return true
        }
        guard read("fill", into: &fill), read("border", into: &border), read("bar", into: &bar),
              read("padding", into: &padding), read("align", into: &align), read("shape", into: &shape)
        else { return nil }
        if let value = values["color"] {
            if let named = WidgetColor.named(value) {
                color = named == .neutral ? nil : named.rawValue
            } else if value.range(of: #"^#(?:[0-9a-f]{3}|[0-9a-f]{6})$"#, options: .regularExpression) != nil {
                color = value
            } else {
                return nil
            }
        }
    }

    /// The wrapper's classes; defaults add nothing beyond `md-card`.
    var classes: String {
        var classes = ["md-card"]
        if fill != .surface { classes.append("md-card-fill-\(fill.rawValue)") }
        if border != .thin { classes.append("md-card-border-\(border.rawValue)") }
        if bar != .none { classes.append("md-card-bar-\(bar.rawValue)") }
        if let color {
            classes.append("md-card-colored")
            if !color.hasPrefix("#") { classes.append("md-card-color-\(color)") }
        }
        if padding != .normal { classes.append("md-card-pad-\(padding.rawValue)") }
        if align != .start { classes.append("md-card-align-\(align.rawValue)") }
        if shape != .rounded { classes.append("md-card-shape-\(shape.rawValue)") }
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
