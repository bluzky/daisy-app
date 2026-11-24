//
//  EscapingHTMLFormatter+Columns.swift
//  daisy
//
//  Columns in an ordinary document, from HTML comments on their own lines:
//
//      <!-- columns -->
//      First column
//      <!-- column -->
//      Second column
//      <!-- end-columns -->
//
//  The comments are invisible in any other viewer, which shows the content
//  stacked. A group that does not hold two columns, or has no
//  `<!-- end-columns -->`, is left as plain content, so a typo never pulls
//  the rest of the document into a column. Slides have their own columns
//  (`SlideDeck`), with the same limit and the same top-level-only rule.
//  Cards (`EscapingHTMLFormatter+Cards.swift`) may sit inside a column.
//

import Foundation
import Markdown

nonisolated enum DocumentColumns {

    /// The most columns in one group; later breaks stay in the last column.
    static let maximumColumns = SlideDeck.maximumColumns

    enum Marker { case open, column, end }

    /// What a top-level HTML block says, when it is exactly one of the three
    /// comments.
    static func marker(of block: Markup) -> Marker? {
        guard let html = block as? HTMLBlock else { return nil }
        let text = html.rawHTML.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("<!--"), text.hasSuffix("-->"), !text.dropFirst(4).dropLast(3).contains("-->")
        else { return nil }
        let body = text.dropFirst(4).dropLast(3).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch body {
        case "columns": return .open
        case "column": return .column
        case "end-columns": return .end
        default: return nil
        }
    }

    /// One group: the blocks of each column, as indices into the children,
    /// and where the group's closing comment sits.
    struct Group {
        let columns: [Range<Int>]
        let end: Int
    }

    /// The group that opens at `children[open]`, or nil when it is not a
    /// well-formed one (no closing comment, or fewer than two columns).
    static func group(in children: [Markup], opening open: Int) -> Group? {
        var breaks: [Int] = []
        var end: Int?
        var index = open + 1
        while index < children.count {
            switch marker(of: children[index]) {
            case .open: return nil
            case .column: breaks.append(index)
            case .end: end = index
            case nil: break
            }
            if end != nil { break }
            index += 1
        }
        guard let end else { return nil }
        let bounds = [open] + breaks + [end]
        var columns: [Range<Int>] = []
        for (position, lower) in bounds.dropLast().enumerated() {
            let range = (lower + 1)..<bounds[position + 1]
            guard !range.isEmpty else { continue }
            if columns.count == maximumColumns {
                columns[columns.count - 1] = columns[columns.count - 1].lowerBound..<range.upperBound
            } else {
                columns.append(range)
            }
        }
        guard columns.count >= 2 else { return nil }
        return Group(columns: columns, end: end)
    }
}

nonisolated extension EscapingHTMLFormatter {

    /// Visits `document`'s blocks in order, wrapping each well-formed column
    /// group in `.md-columns` and each well-formed card in `.md-card`
    /// (`EscapingHTMLFormatter+Cards.swift`), at the top level or in a column.
    mutating func visitDocumentBlocks(_ document: Document) {
        let children = Array(document.children)
        var index = 0
        while index < children.count {
            let child = children[index]
            if DocumentColumns.marker(of: child) == .open,
               let group = DocumentColumns.group(in: children, opening: index) {
                emitBlankLineSpacers(before: child)
                emit("<div class=\"md-columns\" data-columns=\"\(group.columns.count)\">\n")
                for column in group.columns {
                    emit("<div class=\"md-column\">\n")
                    // The first block's blank lines separate it from the
                    // comment above, not from a sibling.
                    visitBlocksWithCards(children, in: column)
                    emit("</div>\n")
                }
                emit("</div>\n")
                index = group.end + 1
                continue
            }
            if let card = DocumentCards.card(in: children, opening: index, limit: children.count) {
                emitBlankLineSpacers(before: child)
                emitCard(card, in: children)
                index = card.end + 1
                continue
            }
            // CommonMark discards source blank lines between blocks. Restore
            // every authored line in addition to the blocks' semantic margins.
            emitBlankLineSpacers(before: child)
            visit(child)
            index += 1
        }
    }

    mutating func emitBlankLineSpacers(before block: Markup) {
        for _ in 0..<precedingBlankLineCount(for: block) {
            emit("<div class=\"md-source-blank-line\" aria-hidden=\"true\"></div>\n")
        }
    }
}
