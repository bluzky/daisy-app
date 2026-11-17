//
//  MarkdownSectionInsertion.swift
//  daisy
//
//  Where `/move` puts a block in its target file (see
//  docs/technical/move-to-file-proposal.md): the headings the picker offers, the
//  insertion at the end of the file or of a heading's whole section, the
//  block's relative links rewritten for the target's folder, and taking the
//  copy out again for the Undo button. Line-based: headings inside fences
//  and frontmatter are skipped, nothing else is parsed.
//
//  No AppKit, so it links into `tests/swift-tests`.
//

import Foundation

nonisolated enum MarkdownSectionInsertion {
    /// A heading the block can go under.
    nonisolated struct Heading: Equatable, Sendable {
        /// 1-based line of the heading's text.
        let line: Int
        /// Its last line: a setext heading's underline, otherwise `line`.
        let lastLine: Int
        let level: Int
        let title: String
    }

    /// What the editor moved. Only a list item joins a list it lands after.
    nonisolated enum BlockKind: String, Sendable {
        case listItem, paragraph, section
    }

    /// The target's new text, and exactly what went in where, so the Undo
    /// button can take it out again.
    nonisolated struct Insertion: Equatable, Sendable {
        let markdown: String
        let inserted: String
        /// UTF-8 offset of `inserted` in `markdown`.
        let offset: Int
    }

    // MARK: - Headings

    static func headings(in markdown: String) -> [Heading] {
        let lines = lines(of: markdown).map(\.text)
        var headings: [Heading] = []
        var fence: Fence?
        // Whether the line before is paragraph text a setext underline can
        // turn into a heading: not text continuing a list item.
        var previous = Previous.boundary
        var index = frontmatterLineCount(lines)
        while index < lines.count {
            let text = lines[index]
            defer { index += 1 }
            if let open = fence {
                if closes(text, open) {
                    fence = nil
                    previous = .boundary
                }
                continue
            }
            if let open = fenceOpening(text) {
                fence = open
                previous = .other
                continue
            }
            if let atx = atxHeading(text) {
                headings.append(Heading(line: index + 1, lastLine: index + 1, level: atx.level, title: atx.title))
                previous = .boundary
                continue
            }
            if previous == .paragraph, let level = setextLevel(text) {
                headings.append(Heading(line: index, lastLine: index + 1, level: level,
                                        title: lines[index - 1].trimmingCharacters(in: .whitespaces)))
                previous = .boundary
                continue
            }
            if isBlank(text) {
                previous = .boundary
            } else {
                previous = isParagraphText(text) && previous != .other ? .paragraph : .other
            }
        }
        return headings
    }

    // MARK: - Inserting

    /// `block` placed at the end of `markdown`, or after the last line of
    /// `heading`'s whole section (subheadings included), at column 0. A
    /// blank line separates it from what comes before, except a list item
    /// landing after a list of the same kind, which joins it; an ordered
    /// item takes the next number, or 1. `heading` must be one of
    /// `headings(in: markdown)`.
    static func inserting(_ block: String, kind: BlockKind, into markdown: String,
                          under heading: Heading?) -> Insertion {
        let lines = lines(of: markdown)
        let newline = markdown.contains("\r\n") ? "\r\n" : "\n"
        var body = block.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        while body.count > 1, body.last.map(isBlank) == true { body.removeLast() }
        while body.count > 1, body.first.map(isBlank) == true { body.removeFirst() }

        // The section's last line of text, which the block goes after.
        let last: Int?
        if let heading, heading.lastLine <= lines.count {
            let next = headings(in: markdown).first { $0.line > heading.line && $0.level <= heading.level }
            let first = heading.lastLine - 1
            let end = max(first, (next?.line ?? lines.count + 1) - 2)
            last = (first...end).last { !isBlank(lines[$0].text) } ?? first
        } else {
            last = lines.indices.last { !isBlank(lines[$0].text) }
        }

        let joins = kind == .listItem && last.map { joinsList(body[0], after: $0, in: lines) } == true
        if let ordered = orderedMarker(body[0]) {
            let number = joins ? (last.flatMap { topLevelItem(endingAt: $0, in: lines) }
                .flatMap { orderedMarker(lines[$0].text)?.number } ?? 0) + 1 : 1
            body[0] = ordered.indent + String(number) + body[0][ordered.numberEnd...]
        }
        let text = body.joined(separator: newline)

        let inserted: String
        let offset: Int
        if let last {
            var value = newline + (joins ? "" : newline) + text
            if last + 1 < lines.count {
                // The next heading keeps a blank line above it.
                if !isBlank(lines[last + 1].text) { value += newline }
            } else if !markdown.hasSuffix("\n") {
                value += newline
            }
            inserted = value
            offset = lines[last].end
        } else {
            // Empty, or nothing but blank lines: the block starts the file.
            inserted = text + newline
            offset = 0
        }
        var bytes = Array(markdown.utf8)
        bytes.insert(contentsOf: inserted.utf8, at: offset)
        return Insertion(markdown: String(decoding: bytes, as: UTF8.self), inserted: inserted, offset: offset)
    }

    /// `markdown` without `inserted`: at `offset` when it is still there,
    /// otherwise at its only occurrence. Nil when it is gone or appears more
    /// than once, so a copy that was edited is never guessed at.
    static func removing(_ inserted: String, at offset: Int, from markdown: String) -> String? {
        let bytes = Array(markdown.utf8)
        let needle = Array(inserted.utf8)
        guard !needle.isEmpty, needle.count <= bytes.count else { return nil }
        let newline = UInt8(ascii: "\n")
        let carriageReturn = UInt8(ascii: "\r")
        // Whole lines only: `Moved` must not match the start of `Moved, edited`.
        func matches(_ start: Int) -> Bool {
            let end = start + needle.count
            guard start >= 0, end <= bytes.count, bytes[start..<end].elementsEqual(needle) else { return false }
            let startsLine = needle[0] == newline || needle[0] == carriageReturn
                || start == 0 || bytes[start - 1] == newline
            let endsLine = needle[needle.count - 1] == newline
                || end == bytes.count || bytes[end] == newline || bytes[end] == carriageReturn
            return startsLine && endsLine
        }
        var start: Int?
        if matches(offset) {
            start = offset
        } else {
            for candidate in 0...(bytes.count - needle.count) where bytes[candidate] == needle[0] && matches(candidate) {
                guard start == nil else { return nil }
                start = candidate
            }
        }
        guard let start else { return nil }
        var result = bytes
        result.removeSubrange(start..<(start + needle.count))
        return String(decoding: result, as: UTF8.self)
    }

    // MARK: - Links

    /// `block`, taken from `source`, with its relative link, image and
    /// reference-definition destinations rewritten to point at the same
    /// files from `target`'s folder. Code is left alone.
    static func rebasingLinks(in block: String, from source: URL, to target: URL) -> String {
        let folder = source.deletingLastPathComponent().standardizedFileURL
        guard folder != target.deletingLastPathComponent().standardizedFileURL else { return block }
        var fence: Fence?
        return block.components(separatedBy: "\n").map { line in
            if let open = fence {
                if closes(line, open) { fence = nil }
                return line
            }
            if let open = fenceOpening(line) {
                fence = open
                return line
            }
            return rebasingLine(line, from: folder, to: target)
        }.joined(separator: "\n")
    }

    private static func rebasingLine(_ line: String, from folder: URL, to target: URL) -> String {
        var result = line
        var ranges = line.matches(of: #/!?\[[^\]\n]*\]\((<[^>\n]*>|[^)\s<>]+)/#).map {
            $0.output.1.startIndex..<$0.output.1.endIndex
        }
        if let definition = line.firstMatch(of: #/^ {0,3}\[[^\]]+\]:[ \t]*(<[^>\n]*>|\S+)/#) {
            ranges.append(definition.output.1.startIndex..<definition.output.1.endIndex)
        }
        // Back to front, so earlier ranges stay valid.
        for range in ranges.sorted(by: { $0.lowerBound > $1.lowerBound }) {
            // Inside an inline code span: an odd number of backticks before it.
            guard line[..<range.lowerBound].filter({ $0 == "`" }).count % 2 == 0,
                  let rebased = rebased(line[range], from: folder, to: target) else { continue }
            result.replaceSubrange(range, with: rebased)
        }
        return result
    }

    private static func rebased(_ destination: Substring, from folder: URL, to target: URL) -> String? {
        var raw = String(destination)
        if raw.hasPrefix("<"), raw.hasSuffix(">") { raw = String(raw.dropFirst().dropLast()) }
        guard !raw.isEmpty, !raw.hasPrefix("#"), !raw.hasPrefix("/"), !raw.hasPrefix("~"),
              raw.firstMatch(of: /^[A-Za-z][A-Za-z0-9+.\-]*:/) == nil else { return nil }
        let cut = raw.firstIndex { $0 == "#" || $0 == "?" } ?? raw.endIndex
        let encoded = raw[..<cut]
        guard !encoded.isEmpty else { return nil }
        let path = encoded.removingPercentEncoding ?? String(encoded)
        let file = folder.appending(path: path).standardizedFileURL
        return ProjectFileLink.destination(to: file, from: target) + raw[cut...]
    }

    // MARK: - Lines

    private struct Line {
        let text: String
        /// UTF-8 offset where the text ends, before its `\n` or `\r\n`.
        let end: Int
    }

    /// A final newline ends the last line rather than starting another.
    private static func lines(of markdown: String) -> [Line] {
        let bytes = Array(markdown.utf8)
        var lines: [Line] = []
        var start = 0
        func add(_ end: Int) {
            var textEnd = end
            if textEnd > start, bytes[textEnd - 1] == UInt8(ascii: "\r") { textEnd -= 1 }
            lines.append(Line(text: String(decoding: bytes[start..<textEnd], as: UTF8.self), end: textEnd))
        }
        for (index, byte) in bytes.enumerated() where byte == UInt8(ascii: "\n") {
            add(index)
            start = index + 1
        }
        if start < bytes.count { add(bytes.count) }
        return lines
    }

    private enum Previous {
        case boundary, paragraph, other
    }

    private struct Fence {
        let marker: Character
        let length: Int
    }

    private static func isBlank(_ text: String) -> Bool {
        text.allSatisfy { $0 == " " || $0 == "\t" }
    }

    private static func indentWidth(_ text: String) -> Int {
        var width = 0
        for character in text {
            if character == " " { width += 1 } else if character == "\t" { width += 4 - width % 4 } else { break }
        }
        return width
    }

    /// Lines of a leading `---` block closed by `---` or `...`, else 0.
    private static func frontmatterLineCount(_ lines: [String]) -> Int {
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else { return 0 }
        for index in lines.indices.dropFirst() {
            let text = lines[index].trimmingCharacters(in: .whitespaces)
            if text == "---" || text == "..." { return index + 1 }
        }
        return 0
    }

    private static func fenceOpening(_ text: String) -> Fence? {
        guard let match = text.firstMatch(of: /^ {0,3}(`{3,}|~{3,})/), let marker = match.output.1.first else {
            return nil
        }
        // A backtick fence's info string can't hold a backtick.
        if marker == "`", text[match.range.upperBound...].contains("`") { return nil }
        return Fence(marker: marker, length: match.output.1.count)
    }

    private static func closes(_ text: String, _ fence: Fence) -> Bool {
        guard let match = text.wholeMatch(of: /^ {0,3}(`{3,}|~{3,})[ \t]*/) else { return false }
        return match.output.1.first == fence.marker && match.output.1.count >= fence.length
    }

    private static func atxHeading(_ text: String) -> (level: Int, title: String)? {
        guard let match = text.wholeMatch(of: #/^ {0,3}(#{1,6})(?:[ \t]+(.*?))?[ \t]*/#) else { return nil }
        var title = String(match.output.2 ?? "")
        // A closing run of `#` is not part of the title.
        if let closing = title.firstMatch(of: #/(?:^|[ \t]+)#+[ \t]*$/#) { title.removeSubrange(closing.range) }
        return (match.output.1.count, title.trimmingCharacters(in: .whitespaces))
    }

    private static func setextLevel(_ text: String) -> Int? {
        if text.wholeMatch(of: /^ {0,3}=+[ \t]*/) != nil { return 1 }
        if text.wholeMatch(of: /^ {0,3}-+[ \t]*/) != nil { return 2 }
        return nil
    }

    private static func isListItem(_ text: String) -> Bool {
        text.firstMatch(of: /^[ \t]*(?:[-+*]|\d{1,9}[.)])(?:[ \t]|$)/) != nil
    }

    private static func isParagraphText(_ text: String) -> Bool {
        indentWidth(text) < 4 && !isListItem(text)
            && text.firstMatch(of: /^ {0,3}(?:>|<|(?:[-*_][ \t]*){3,}$)/) == nil
    }

    /// The bullet, or the delimiter of an ordered marker: items with
    /// different ones make different lists.
    private static func listStyle(_ text: String) -> String? {
        guard let match = text.firstMatch(of: /^([-+*]|\d{1,9}([.)]))(?:[ \t]|$)/) else { return nil }
        return match.output.2.map { "1" + $0 } ?? String(match.output.1)
    }

    private static func orderedMarker(_ text: String) -> (indent: String, number: Int, numberEnd: String.Index)? {
        guard let match = text.firstMatch(of: /^([ \t]*)(\d{1,9})[.)](?:[ \t]|$)/),
              let number = Int(match.output.2) else { return nil }
        return (String(match.output.1), number, match.output.2.endIndex)
    }

    /// The top-level item whose list `line` ends, when everything from it
    /// to `line` is indented under it.
    private static func topLevelItem(endingAt line: Int, in lines: [Line]) -> Int? {
        guard let top = (0...line).last(where: { !isBlank(lines[$0].text) && indentWidth(lines[$0].text) == 0 }),
              listStyle(lines[top].text) != nil else { return nil }
        return top
    }

    private static func joinsList(_ first: String, after line: Int, in lines: [Line]) -> Bool {
        guard let style = listStyle(first), let top = topLevelItem(endingAt: line, in: lines) else { return false }
        return listStyle(lines[top].text) == style
    }
}
