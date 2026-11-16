//
//  MarkdownComments.swift
//  daisy
//
//  Reader comments written in CriticMarkup, for a person or an AI to act on:
//
//      The API returns {==a 404 on missing ids==}{>>Should be 410 Gone<<}.
//      {>>A comment on a spot, with nothing highlighted<<}
//
//  The anchored text sits in `{==…==}`, and one or more `{>>…<<}` follow it
//  with nothing between. Notes are one line each. The Markdown is never
//  changed by reading it: Read mode, the editor and Copy Comments for AI all
//  work from the same scan, so they can never disagree about what a comment is.
//

import Foundation
import Markdown

nonisolated enum MarkdownComments {

    /// One comment as it reads in the source.
    struct Comment: Equatable, Sendable {
        /// 1-based line the comment starts on.
        let line: Int
        /// The highlighted text, as written. Nil for a comment on a spot.
        let anchor: String?
        /// Every `{>>…<<}` after the anchor, in order. A later one is
        /// typically a reply to the first.
        let notes: [String]
    }

    fileprivate struct Match {
        let range: Range<Int>
        let comment: Comment
        let anchorRange: Range<Int>?
    }

    // MARK: - Reading

    static func comments(in markdown: String) -> [Comment] {
        guard markdown.contains("{>>") else { return [] }
        return matches(in: Array(markdown)).map(\.comment)
    }

    // MARK: - Read mode

    /// The Markdown with every comment turned into inline HTML the page styles.
    /// The note rides in `data-comment`, so no Markdown inside it is parsed and
    /// the line count never changes: source lines stay lined up with the page.
    static func rendering(_ markdown: String) -> String {
        guard markdown.contains("{>>") else { return markdown }
        let characters = Array(markdown)
        let found = matches(in: characters)
        guard !found.isEmpty else { return markdown }

        var output = ""
        output.reserveCapacity(markdown.utf8.count + found.count * 80)
        var cursor = 0
        for match in found {
            output += String(characters[cursor..<match.range.lowerBound])
            // A comment with replies lists its notes, each behind a bullet, so
            // they read as separate; a single note is shown as it is.
            let notes = match.comment.notes
            let isList = notes.count > 1
            let attribute = notes.map { escapeAttribute(isList ? "\u{2022} " + $0 : $0) }.joined(separator: "&#10;")
            let listMark = isList ? " data-list" : ""
            if let anchorRange = match.anchorRange {
                output += "<mark class=\"mdp-comment\" tabindex=\"0\" data-comment=\"\(attribute)\"\(listMark)>"
                output += String(characters[anchorRange])
                output += "</mark>"
            } else {
                let spoken = notes.map(escapeAttribute).joined(separator: ". ")
                output += "<span class=\"mdp-comment mdp-comment-point\" tabindex=\"0\" role=\"note\" "
                output += "aria-label=\"\(spoken)\" data-comment=\"\(attribute)\"\(listMark)></span>"
            }
            cursor = match.range.upperBound
        }
        output += String(characters[cursor...])
        return output
    }

    // MARK: - Copy for AI

    /// A plain-text brief of every comment, for pasting into a prompt next to
    /// (or instead of) the document.
    static func brief(for comments: [Comment], fileName: String?) -> String {
        let name = fileName.map { " in \($0)" } ?? ""
        var text = "\(comments.count) comment\(comments.count == 1 ? "" : "s")\(name). "
        text += "Each is written in the file as {==highlighted text==}{>>comment<<}, or as a bare "
        text += "{>>comment<<}. Apply what each one asks for, then remove its markup and keep the "
        text += "final text. A later note on the same comment is a reply to the first.\n"

        for (index, comment) in comments.enumerated() {
            text += "\n\(index + 1). Line \(comment.line)"
            if let anchor = comment.anchor {
                let flat = anchor.split(whereSeparator: \.isNewline)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .joined(separator: " ")
                text += ", on: \"\(flat)\""
            }
            text += "\n"
            for (offset, note) in comment.notes.enumerated() {
                text += offset == 0 ? "   Comment: \(note)\n" : "   Reply: \(note)\n"
            }
        }
        return text
    }

    // MARK: - Changing comments

    /// One replacement in the document, in UTF-16 offsets: what an editor
    /// buffer and `NSString` both count in.
    struct Edit: Equatable, Sendable {
        let range: Range<Int>
        let replacement: String

        func applied(to text: String) -> String {
            let string = text as NSString
            return string.replacingCharacters(in: NSRange(location: range.lowerBound,
                                                          length: range.upperBound - range.lowerBound),
                                              with: replacement)
        }
    }

    /// Resolves the `index`th comment (as `comments(in:)` numbers them): the
    /// markup goes and the commented text stays. A comment on a spot just goes,
    /// along with one of the spaces around it so no gap is left.
    static func resolveEdit(commentAt index: Int, in markdown: String) -> Edit? {
        let characters = Array(markdown)
        let found = matches(in: characters)
        guard found.indices.contains(index) else { return nil }
        let match = found[index]
        var range = match.range
        var replacement = ""
        if let anchorRange = match.anchorRange {
            replacement = String(characters[anchorRange])
        } else {
            let spaceBefore = range.lowerBound > 0 && characters[range.lowerBound - 1] == " "
            let spaceAfter = range.upperBound < characters.count && characters[range.upperBound] == " "
            if spaceBefore && spaceAfter { range = range.lowerBound..<(range.upperBound + 1) }
        }
        return Edit(range: utf16Range(of: range, in: characters), replacement: replacement)
    }

    /// Adds `note` as one more `{>>…<<}` after the `index`th comment's last
    /// one. Line breaks become spaces, and a `<<}` inside is broken up, so the
    /// reply stays one note.
    static func replyEdit(toCommentAt index: Int, note: String, in markdown: String) -> Edit? {
        let characters = Array(markdown)
        let found = matches(in: characters)
        guard found.indices.contains(index) else { return nil }
        let clean = note.split(whereSeparator: \.isNewline).joined(separator: " ")
            .replacingOccurrences(of: "<<}", with: "<< }")
            .trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return nil }
        let end = utf16Offset(of: found[index].range.upperBound, in: characters)
        return Edit(range: end..<end, replacement: "{>>\(clean)<<}")
    }

    /// Text selected on the rendered page, and where it came from.
    struct PageSelection: Equatable, Sendable {
        /// The selected text as the page shows it.
        let text: String
        /// The source lines of the block it sits in, inclusive.
        let startLine: Int
        let endLine: Int
        /// How many earlier copies of `text` the block's text holds, so a
        /// phrase that repeats is commented where it was selected.
        let occurrence: Int
    }

    /// Comments on what was selected in Read mode. The rendered text is found
    /// again in the block's Markdown, with emphasis marks, link brackets and
    /// the like allowed between its characters, and wrapped as
    /// `{==text==}{>>note<<}`. When it cannot be found, a comment on the spot
    /// goes at the end of the block instead, so the note is never lost.
    /// Nil when the lines or the note are unusable.
    static func addEdit(note: String, selection: PageSelection, in markdown: String) -> Edit? {
        let clean = note.split(whereSeparator: \.isNewline).joined(separator: " ")
            .replacingOccurrences(of: "<<}", with: "<< }")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let wanted = selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !wanted.isEmpty, selection.startLine >= 1,
              selection.endLine >= selection.startLine else { return nil }

        let string = markdown as NSString
        // UTF-16 start of each line, then the block's range.
        var lineStarts = [0]
        for index in 0..<string.length {
            let unit = string.character(at: index)
            let next = index + 1 < string.length ? string.character(at: index + 1) : 0
            if unit == 0x0A || (unit == 0x0D && next != 0x0A) { lineStarts.append(index + 1) }
        }
        guard selection.startLine <= lineStarts.count else { return nil }
        let blockStart = lineStarts[selection.startLine - 1]
        let lastLine = min(selection.endLine, lineStarts.count)
        var blockEnd = lastLine < lineStarts.count ? lineStarts[lastLine] - 1 : string.length
        blockEnd = max(blockEnd, blockStart)
        let block = string.substring(with: NSRange(location: blockStart, length: blockEnd - blockStart))

        if let pattern = sourcePattern(for: wanted),
           let expression = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) {
            // The page counts repeated phrases in rendered text, where notes
            // and comment markup do not appear. So a match inside those is not
            // counted, and a counted match inside an existing anchor is not
            // wrapped again, which would nest one comment in another.
            let whole = Array(markdown)
            var hidden: [Range<Int>] = []
            var anchored: [Range<Int>] = []
            for comment in matches(in: whole) {
                if let anchor = comment.anchorRange {
                    hidden.append(utf16Range(of: comment.range.lowerBound..<anchor.lowerBound, in: whole))
                    hidden.append(utf16Range(of: anchor.upperBound..<comment.range.upperBound, in: whole))
                    anchored.append(utf16Range(of: anchor, in: whole))
                } else {
                    hidden.append(utf16Range(of: comment.range, in: whole))
                }
            }
            func overlaps(_ range: Range<Int>, _ others: [Range<Int>]) -> Bool {
                others.contains { $0.lowerBound < range.upperBound && range.lowerBound < $0.upperBound }
            }

            let blockRange = NSRange(location: 0, length: (block as NSString).length)
            let counted = expression.matches(in: block, range: blockRange).compactMap { match -> NSRange? in
                let absolute = (blockStart + match.range.location)..<(blockStart + match.range.location + match.range.length)
                return overlaps(absolute, hidden) ? nil : match.range
            }
            if counted.indices.contains(selection.occurrence) {
                let range = counted[selection.occurrence]
                let absolute = (blockStart + range.location)..<(blockStart + range.location + range.length)
                let source = (block as NSString).substring(with: range)
                // Never across a paragraph break, which would end the anchor.
                let spansBlankLine = source.range(
                    of: #"(?:\r\n|\n|\r)[ \t>]*(?:\r\n|\n|\r)"#, options: .regularExpression) != nil
                if !overlaps(absolute, anchored), !spansBlankLine,
                   !source.contains("{>>"), !source.contains("{==") {
                    return Edit(range: absolute, replacement: "{==\(source)==}{>>\(clean)<<}")
                }
            }
        }
        // Not found: a comment on the spot, at the end of the block's last line.
        var end = blockEnd
        while end > blockStart, [0x20, 0x09, 0x0D].contains(string.character(at: end - 1)) { end -= 1 }
        return Edit(range: end..<end, replacement: " {>>\(clean)<<}")
    }

    /// A pattern that finds `text`, as rendered, in its Markdown. Between two
    /// characters it allows what rendering drops: emphasis marks, backticks,
    /// escapes, link brackets with their address, and HTML tags. Runs of
    /// white space match any run of white space, line starts and quote marks.
    private static func sourcePattern(for text: String) -> String? {
        let noise = #"(?:\*{1,3}|_{1,3}|~~|`|==|\\|<[^>\n]*>|\]\([^)\n]*\)|\[)*"#
        var tokens: [String] = []
        var previousWasSpace = false
        for character in text {
            if character.isWhitespace {
                // Spaces, quote marks and emphasis marks, and a line break only
                // when the next line is not blank: a blank line ends the block.
                if !previousWasSpace {
                    tokens.append(#"(?:[ \t>*_~`]|(?:\r\n|\n|\r)(?![ \t>]*(?:\r\n|\n|\r|\z)))+"#)
                }
                previousWasSpace = true
            } else {
                tokens.append(NSRegularExpression.escapedPattern(for: String(character)))
                previousWasSpace = false
            }
        }
        let pattern = tokens.joined(separator: noise)
        return pattern.isEmpty ? nil : pattern
    }

    private static func utf16Offset(of position: Int, in characters: [Character]) -> Int {
        characters[..<position].reduce(0) { $0 + $1.utf16.count }
    }

    private static func utf16Range(of range: Range<Int>, in characters: [Character]) -> Range<Int> {
        let lower = utf16Offset(of: range.lowerBound, in: characters)
        let length = characters[range].reduce(0) { $0 + $1.utf16.count }
        return lower..<(lower + length)
    }

    // MARK: - Scanning

    private static func matches(in characters: [Character]) -> [Match] {
        let count = characters.count
        let masked = maskedCharacters(in: characters)
        var found: [Match] = []
        var line = 1
        var linesCountedTo = 0
        var index = 0

        while index < count {
            guard characters[index] == "{", !masked[index],
                  index == 0 || characters[index - 1] != "\\" else {
                index += 1
                continue
            }

            var anchorRange: Range<Int>?
            var cursor = index
            if hasPrefix("{==", in: characters, at: index) {
                guard let close = find("==}", in: characters, from: index + 3, singleLine: false),
                      close > index + 3,
                      hasPrefix("{>>", in: characters, at: close + 3) else {
                    index += 1
                    continue
                }
                anchorRange = (index + 3)..<close
                cursor = close + 3
            } else if !hasPrefix("{>>", in: characters, at: index) {
                index += 1
                continue
            }

            var notes: [String] = []
            while hasPrefix("{>>", in: characters, at: cursor),
                  let end = find("<<}", in: characters, from: cursor + 3, singleLine: true) {
                let note = String(characters[(cursor + 3)..<end]).trimmingCharacters(in: .whitespaces)
                if !note.isEmpty { notes.append(note) }
                cursor = end + 3
            }
            guard !notes.isEmpty else {
                index += 1
                continue
            }

            while linesCountedTo < index {
                if isLineBreak(characters[linesCountedTo]) { line += 1 }
                linesCountedTo += 1
            }
            let anchor = anchorRange.map { String(characters[$0]) }
            found.append(Match(range: index..<cursor,
                               comment: Comment(line: line, anchor: anchor, notes: notes),
                               anchorRange: anchorRange))
            index = cursor
        }
        return found
    }

    /// The line breaks the Markdown parser counts, and so the page's source
    /// lines do: `\n`, `\r\n` and `\r`. Not the wider set `Character.isNewline`
    /// knows (U+2028 and friends), which would drift the line numbers.
    private static func isLineBreak(_ character: Character) -> Bool {
        character == "\n" || character == "\r\n" || character == "\r"
    }

    private static func hasPrefix(_ prefix: String, in characters: [Character], at index: Int) -> Bool {
        var position = index
        for character in prefix {
            guard position < characters.count, characters[position] == character else { return false }
            position += 1
        }
        return true
    }

    /// Where `marker` next starts. Never crosses a blank line (a paragraph
    /// ends there), or any line break when `singleLine`.
    private static func find(_ marker: String, in characters: [Character],
                             from start: Int, singleLine: Bool) -> Int? {
        var index = start
        while index < characters.count {
            if isLineBreak(characters[index]) {
                if singleLine { return nil }
                var next = index + 1
                while next < characters.count, characters[next] == " " || characters[next] == "\t" { next += 1 }
                if next >= characters.count || isLineBreak(characters[next]) { return nil }
            }
            if hasPrefix(marker, in: characters, at: index) { return index }
            index += 1
        }
        return nil
    }

    // MARK: - Code that is not a comment

    /// True for characters a comment must not start in: code of every kind
    /// (fenced, indented, inline, including a span that runs over several
    /// lines) and HTML comments, where the braces are just text. The Markdown
    /// parser decides what is code, so a list's indented paragraph is not
    /// mistaken for an indented code block, and a backtick run pairs the way
    /// the renderer pairs it.
    private static func maskedCharacters(in characters: [Character]) -> [Bool] {
        var masked = Array(repeating: false, count: characters.count)
        maskCode(in: characters, &masked)

        var index = 0
        while index < characters.count {
            if !masked[index], hasPrefix("<!--", in: characters, at: index) {
                var end = index + 4
                while end < characters.count, !hasPrefix("-->", in: characters, at: end) { end += 1 }
                let stop = min(end + 3, characters.count)
                for position in index..<stop { masked[position] = true }
                index = stop
            } else {
                index += 1
            }
        }
        return masked
    }

    private static func maskCode(in characters: [Character], _ masked: inout [Bool]) {
        // Without a fence, indentation or backtick there is no code to find.
        guard characters.contains(where: { $0 == "`" || $0 == "~" || $0 == " " || $0 == "\t" }) else { return }

        // Parser locations are a line and a UTF-8 byte column. Map them back
        // to character offsets.
        var lineStarts = [0]
        for (index, character) in characters.enumerated()
        where character == "\n" || character == "\r\n" || character == "\r" {
            lineStarts.append(index + 1)
        }
        func offset(of location: SourceLocation) -> Int? {
            guard location.line >= 1, location.line <= lineStarts.count, location.column >= 1 else { return nil }
            var index = lineStarts[location.line - 1]
            var bytes = 0
            while index < characters.count, bytes < location.column - 1 {
                let character = characters[index]
                if character == "\n" || character == "\r\n" || character == "\r" { break }
                bytes += String(character).utf8.count
                index += 1
            }
            return index
        }

        func visit(_ markup: Markup) {
            if markup is CodeBlock || markup is InlineCode,
               let range = markup.range,
               let lower = offset(of: range.lowerBound),
               let upper = offset(of: range.upperBound), lower < upper {
                for position in lower..<min(upper, masked.count) { masked[position] = true }
                return
            }
            for child in markup.children { visit(child) }
        }
        visit(Document(parsing: String(characters)))
    }

    private static func escapeAttribute(_ text: String) -> String {
        var output = ""
        for character in text {
            switch character {
            case "&": output += "&amp;"
            case "<": output += "&lt;"
            case ">": output += "&gt;"
            case "\"": output += "&quot;"
            default: output.append(character)
            }
        }
        return output
    }
}
