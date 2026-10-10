//
//  EscapingHTMLFormatter.swift
//  daisy
//

import Foundation
import Markdown

/// Rewrites matched Obsidian-style `==text==` delimiters into control-character
/// sentinels before cmark parses the document. The sentinels deliberately have
/// the same Character width as the two source delimiters, so source line and
/// column mapping remains stable while the normal Markdown parser still gets
/// to parse nested emphasis, links, and other inline content.
nonisolated enum MarkdownHighlightSource {
    // Cmark source locations use UTF-8 byte columns. Each sentinel is an
    // ASCII control character, so replacing a two-byte `==` delimiter keeps
    // every later source offset stable, including lines containing Unicode.
    static let openingToken = "\u{001C}\u{001D}"
    static let closingToken = "\u{001E}\u{001F}"

    private struct Delimiter {
        let start: Int
        let canOpen: Bool
        let canClose: Bool
        let scope: Int
    }

    private struct HighlightPair {
        let opening: Int
        let closing: Int
    }

    private struct ParsedTextScope {
        let range: Range<Int>
        let id: Int
    }

    private struct SourceOffsetMap {
        let lineByteStarts: [Int]
        let characterByteOffsets: [Int]

        init(characters: [Character]) {
            var lineByteStarts = [0]
            var characterByteOffsets: [Int] = []
            characterByteOffsets.reserveCapacity(characters.count + 1)

            var byteOffset = 0
            for character in characters {
                characterByteOffsets.append(byteOffset)
                byteOffset += String(character).utf8.count
                let lineEnding = character.unicodeScalars.last?.value
                if lineEnding == 0x0A || lineEnding == 0x0D {
                    lineByteStarts.append(byteOffset)
                }
            }
            characterByteOffsets.append(byteOffset)
            self.lineByteStarts = lineByteStarts
            self.characterByteOffsets = characterByteOffsets
        }

        func characterOffset(for location: SourceLocation) -> Int? {
            guard location.line > 0,
                  location.line <= lineByteStarts.count,
                  location.column > 0 else {
                return nil
            }

            let target = lineByteStarts[location.line - 1] + location.column - 1
            var lowerBound = 0
            var upperBound = characterByteOffsets.count
            while lowerBound < upperBound {
                let middle = lowerBound + (upperBound - lowerBound) / 2
                let candidate = characterByteOffsets[middle]
                if target < candidate {
                    upperBound = middle
                } else if target > candidate {
                    lowerBound = middle + 1
                } else {
                    return middle
                }
            }
            return nil
        }
    }

    private static let htmlBlockTags: Set<String> = [
        "address", "article", "aside", "base", "basefont", "blockquote",
        "body", "caption", "center", "col", "colgroup", "dd", "details",
        "dialog", "dir", "div", "dl", "dt", "fieldset", "figcaption",
        "figure", "footer", "form", "frame", "frameset", "h1", "h2", "h3",
        "h4", "h5", "h6", "head", "header", "hr", "html", "iframe",
        "legend", "li", "link", "main", "menu", "menuitem", "nav",
        "noframes", "ol", "optgroup", "option", "p", "param", "section",
        "source", "summary", "table", "tbody", "td", "tfoot", "th",
        "thead", "title", "tr", "track", "ul", "pre", "script", "style"
    ]

    static func preparing(_ markdown: String) -> String {
        let characters = Array(markdown)
        guard characters.contains("=") else { return markdown }

        var protected = Array(repeating: false, count: characters.count)
        var blockBoundaries = Array(repeating: false, count: characters.count)
        protectFencedCode(
            in: characters,
            protected: &protected,
            blockBoundaries: &blockBoundaries
        )
        protectIndentedCode(
            in: characters,
            protected: &protected,
            blockBoundaries: &blockBoundaries
        )
        protectInlineCode(in: characters, protected: &protected)
        protectLinkDestinations(in: characters, protected: &protected)
        protectHTML(
            in: characters,
            protected: &protected,
            blockBoundaries: &blockBoundaries
        )

        // Delimiters must be paired within the parser's text containers. A
        // line-based scope splits soft-wrapped quote/list paragraphs, while
        // pairing globally can consume a both-sided delimiter from a later
        // block before AST validation gets a chance to reject it.
        let sourceScopes = parsedTextScopes(in: characters)

        var delimiters: [Delimiter] = []
        var index = 0
        while index < characters.count {
            if blockBoundaries[index] {
                while index < characters.count, blockBoundaries[index] {
                    index += 1
                }
                continue
            }
            guard characters[index] == "=", !protected[index] else {
                index += 1
                continue
            }

            let start = index
            while index < characters.count,
                  characters[index] == "=",
                  !protected[index] {
                index += 1
            }
            let end = index
            guard !isEscaped(characters, at: start) else { continue }
            let length = end - start
            guard length >= 2 else { continue }

            let before = start > 0 ? characters[start - 1] : nil
            let after = end < characters.count ? characters[end] : nil
            let spaceBefore = isWhitespace(before)
            let spaceAfter = isWhitespace(after)
            let punctuationBefore = isPunctuation(before)
            let punctuationAfter = isPunctuation(after)
            let leftFlanking = !spaceAfter
                && (!punctuationAfter || spaceBefore || punctuationBefore)
            let rightFlanking = !spaceBefore
                && (!punctuationBefore || spaceAfter || punctuationAfter)

            // Match markdown-it-mark's useful behavior for equal runs: an odd
            // run leaves one literal `=` before the pairs, and each pair can
            // participate in delimiter matching independently.
            var pairStart = start + (length.isMultiple(of: 2) ? 0 : 1)
            while pairStart + 1 < end {
                if let scope = scope(containing: pairStart, in: sourceScopes) {
                    delimiters.append(
                        Delimiter(
                            start: pairStart,
                            canOpen: leftFlanking,
                            canClose: rightFlanking,
                            scope: scope
                        )
                    )
                }
                pairStart += 2
            }
        }

        guard !delimiters.isEmpty else { return markdown }

        var openDelimiters: [Delimiter] = []
        var replacements: [Int: String] = [:]
        var pairs: [HighlightPair] = []
        for delimiter in delimiters {
            while let opener = openDelimiters.last,
                  opener.scope != delimiter.scope {
                openDelimiters.removeLast()
            }
            if delimiter.canClose, let opener = openDelimiters.popLast() {
                replacements[opener.start] = openingToken
                replacements[delimiter.start] = closingToken
                pairs.append(HighlightPair(opening: opener.start, closing: delimiter.start))
                continue
            }
            if delimiter.canOpen {
                openDelimiters.append(delimiter)
            }
        }

        guard !replacements.isEmpty else { return markdown }
        var rewritten = characters
        for (start, token) in replacements {
            let tokenCharacters = Array(token)
            guard tokenCharacters.count == 2,
                  rewritten.indices.contains(start),
                  rewritten.indices.contains(start + 1) else {
                continue
            }
            rewritten[start] = tokenCharacters[0]
            rewritten[start + 1] = tokenCharacters[1]
        }
        return restoringRejectedPairs(in: rewritten, pairs: pairs)
    }

    private static func restoringRejectedPairs(in characters: [Character],
                                               pairs: [HighlightPair]) -> String {
        let scopes = parsedTextScopes(in: characters)
        var restored = characters
        for pair in pairs {
            let openingScope = scope(containing: pair.opening, in: scopes)
            let closingScope = scope(containing: pair.closing, in: scopes)
            guard let openingScope, openingScope == closingScope else {
                restoreDelimiter(at: pair.opening, in: &restored)
                restoreDelimiter(at: pair.closing, in: &restored)
                continue
            }
        }
        return String(restored)
    }

    private static func parsedTextScopes(in characters: [Character]) -> [ParsedTextScope] {
        let document = Document(parsing: String(characters))
        let offsetMap = SourceOffsetMap(characters: characters)
        var scopes: [ParsedTextScope] = []
        var nextScope = 0
        collectTextScopes(
            from: document,
            offsetMap: offsetMap,
            scopes: &scopes,
            nextScope: &nextScope
        )
        scopes.sort { $0.range.lowerBound < $1.range.lowerBound }
        return scopes
    }

    @discardableResult
    private static func collectTextScopes(from markup: Markup,
                                          offsetMap: SourceOffsetMap,
                                          scopes: inout [ParsedTextScope],
                                          nextScope: inout Int) -> Bool {
        if markup is CodeBlock
            || markup is HTMLBlock
            || markup is Image
            || markup is InlineCode
            || markup is InlineHTML
            || markup is SymbolLink {
            return markup is InlineHTML
        }

        var scope = nextScope
        var containsInlineHTML = false
        nextScope += 1
        for child in markup.children {
            if child is InlineHTML {
                containsInlineHTML = true
                scope = nextScope
                nextScope += 1
            } else if let text = child as? Text,
                      let range = text.range,
                      let lowerBound = offsetMap.characterOffset(for: range.lowerBound),
                      let upperBound = offsetMap.characterOffset(for: range.upperBound),
                      lowerBound < upperBound {
                scopes.append(
                    ParsedTextScope(range: lowerBound..<upperBound, id: scope)
                )
            } else if collectTextScopes(
                from: child,
                offsetMap: offsetMap,
                scopes: &scopes,
                nextScope: &nextScope
            ) {
                containsInlineHTML = true
                scope = nextScope
                nextScope += 1
            }
        }
        return containsInlineHTML
    }

    private static func scope(containing delimiter: Int,
                              in scopes: [ParsedTextScope]) -> Int? {
        var lowerBound = 0
        var upperBound = scopes.count
        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            let candidate = scopes[middle]
            if delimiter < candidate.range.lowerBound {
                upperBound = middle
            } else if delimiter + 1 >= candidate.range.upperBound {
                lowerBound = middle + 1
            } else {
                return candidate.id
            }
        }
        return nil
    }

    private static func restoreDelimiter(at start: Int,
                                         in characters: inout [Character]) {
        guard characters.indices.contains(start),
              characters.indices.contains(start + 1) else {
            return
        }
        characters[start] = "="
        characters[start + 1] = "="
    }

    private static func protectFencedCode(in characters: [Character],
                                          protected: inout [Bool],
                                          blockBoundaries: inout [Bool]) {
        let lines = lineRanges(in: characters)
        var lineIndex = 0
        while lineIndex < lines.count {
            let line = lines[lineIndex]
            guard let fence = fence(at: line, in: characters) else {
                lineIndex += 1
                continue
            }

            var closingLine = lines.count - 1
            if lineIndex + 1 < lines.count {
                for candidateIndex in (lineIndex + 1)..<lines.count {
                    if isClosingFence(
                        at: lines[candidateIndex],
                        in: characters,
                        character: fence.character,
                        minimumLength: fence.length
                    ) {
                        closingLine = candidateIndex
                        break
                    }
                }
            }

            let end = lines[closingLine].to
            for position in line.from..<end {
                protected[position] = true
                blockBoundaries[position] = true
            }
            lineIndex = closingLine + 1
        }
    }

    private static func protectInlineCode(in characters: [Character],
                                          protected: inout [Bool]) {
        // Let the block/inline parser decide which backtick runs form a code
        // span. A source-wide scan can incorrectly pair runs from separate
        // paragraphs, while these ranges preserve valid multiline spans in a
        // single paragraph.
        guard characters.contains("`") else { return }
        let document = Document(parsing: String(characters))
        let offsetMap = SourceOffsetMap(characters: characters)
        protectInlineCode(
            in: document,
            offsetMap: offsetMap,
            protected: &protected
        )
    }

    private static func protectInlineCode(in markup: Markup,
                                          offsetMap: SourceOffsetMap,
                                          protected: inout [Bool]) {
        if let inlineCode = markup as? InlineCode,
           let range = inlineCode.range,
           let lowerBound = offsetMap.characterOffset(for: range.lowerBound),
           let upperBound = offsetMap.characterOffset(for: range.upperBound),
           lowerBound < upperBound {
            for position in lowerBound..<upperBound {
                protected[position] = true
            }
            return
        }

        for child in markup.children {
            protectInlineCode(
                in: child,
                offsetMap: offsetMap,
                protected: &protected
            )
        }
    }

    private static func protectIndentedCode(in characters: [Character],
                                            protected: inout [Bool],
                                            blockBoundaries: inout [Bool]) {
        let lines = lineRanges(in: characters)
        var lineIndex = 0
        while lineIndex < lines.count {
            let previousLine = lineIndex > 0 ? lines[lineIndex - 1] : nil
            let previousLineIsBlank = previousLine.map {
                characters[$0.from..<$0.to].allSatisfy {
                    $0 == " " || $0 == "\t"
                }
            } ?? true
            let startsAfterBlank = lineIndex == 0 || previousLineIsBlank
            guard startsAfterBlank,
                  hasIndentedCodePrefix(at: lines[lineIndex], in: characters) else {
                lineIndex += 1
                continue
            }

            var lastLine = lineIndex
            while lastLine < lines.count {
                let line = lines[lastLine]
                let blank = characters[line.from..<line.to].allSatisfy {
                    $0 == " " || $0 == "\t"
                }
                if blank || hasIndentedCodePrefix(at: line, in: characters) {
                    lastLine += 1
                } else {
                    break
                }
            }

            let end = lines[lastLine - 1].to
            for position in lines[lineIndex].from..<end {
                protected[position] = true
                blockBoundaries[position] = true
            }
            lineIndex = lastLine
        }
    }

    private static func hasIndentedCodePrefix(at line: (from: Int, to: Int),
                                              in characters: [Character]) -> Bool {
        var index = line.from
        var spaces = 0
        while index < line.to, characters[index] == " " {
            index += 1
            spaces += 1
        }
        return spaces >= 4 || (index < line.to && characters[index] == "\t")
    }

    private static func protectLinkDestinations(in characters: [Character],
                                                protected: inout [Bool]) {
        var index = 0
        while index < characters.count {
            guard characters[index] == "]", !protected[index] else {
                index += 1
                continue
            }

            var opening = index + 1
            while opening < characters.count,
                  characters[opening] == " ",
                  !protected[opening] {
                opening += 1
            }
            guard opening < characters.count, characters[opening] == "(" else {
                index += 1
                continue
            }

            var cursor = opening
            var depth = 0
            var escaped = false
            var closing: Int?
            while cursor < characters.count {
                if protected[cursor] {
                    cursor += 1
                    continue
                }
                let character = characters[cursor]
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "(" {
                    depth += 1
                } else if character == ")" {
                    depth -= 1
                    if depth == 0 {
                        closing = cursor
                        break
                    }
                } else if character == "\n" {
                    break
                }
                cursor += 1
            }

            if let closing {
                for position in opening...closing {
                    protected[position] = true
                }
                index = closing + 1
            } else {
                index = opening + 1
            }
        }
    }

    private static func protectHTML(in characters: [Character],
                                    protected: inout [Bool],
                                    blockBoundaries: inout [Bool]) {
        let lines = lineRanges(in: characters)
        var lineIndex = 0
        while lineIndex < lines.count {
            let line = lines[lineIndex]
            guard let tag = htmlBlockTag(at: line, in: characters) else {
                lineIndex += 1
                continue
            }

            var closingLine = lineIndex
            if tag == "!--" {
                for candidateIndex in lineIndex..<lines.count {
                    if String(characters[lines[candidateIndex].from..<lines[candidateIndex].to])
                        .contains("-->") {
                        closingLine = candidateIndex
                        break
                    }
                }
            } else {
                let closingMarker = "</\(tag)"
                var foundClosingTag = false
                for candidateIndex in lineIndex..<lines.count {
                    let text = String(characters[lines[candidateIndex].from..<lines[candidateIndex].to])
                        .lowercased()
                    if text.contains(closingMarker) {
                        closingLine = candidateIndex
                        foundClosingTag = true
                        break
                    }
                    if candidateIndex > lineIndex,
                       text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        closingLine = candidateIndex - 1
                        foundClosingTag = true
                        break
                    }
                }
                if !foundClosingTag {
                    closingLine = lines.count - 1
                }
            }

            let end = lines[closingLine].to
            for position in line.from..<end {
                protected[position] = true
                blockBoundaries[position] = true
            }
            lineIndex = closingLine + 1
        }

        // Inline HTML tags and autolinks protect their attributes/destinations
        // without suppressing Markdown in ordinary text between the tags.
        var index = 0
        while index < characters.count {
            guard characters[index] == "<", !protected[index] else {
                index += 1
                continue
            }
            var cursor = index + 1
            var quote: Character?
            while cursor < characters.count {
                let character = characters[cursor]
                if quote != nil {
                    if character == quote { quote = nil }
                } else if character == "\"" || character == "'" {
                    quote = character
                } else if character == ">" {
                    for position in index...cursor {
                        protected[position] = true
                    }
                    index = cursor + 1
                    break
                } else if character == "\n" {
                    index = cursor
                    break
                }
                cursor += 1
            }
            if cursor >= characters.count {
                index = characters.count
            }
        }
    }


    private static func lineRanges(in characters: [Character]) -> [(from: Int, to: Int)] {
        guard !characters.isEmpty else { return [] }
        var ranges: [(from: Int, to: Int)] = []
        var start = 0
        for index in characters.indices where characters[index] == "\n" {
            ranges.append((from: start, to: index))
            start = index + 1
        }
        if start < characters.count {
            ranges.append((from: start, to: characters.count))
        }
        return ranges
    }

    private static func fence(at line: (from: Int, to: Int),
                              in characters: [Character])
        -> (character: Character, length: Int)? {
        var index = line.from
        var indentation = 0
        while index < line.to, characters[index] == " ", indentation < 4 {
            index += 1
            indentation += 1
        }
        guard index < line.to,
              characters[index] == "`" || characters[index] == "~" else {
            return nil
        }
        let character = characters[index]
        let start = index
        while index < line.to, characters[index] == character {
            index += 1
        }
        let length = index - start
        return length >= 3 ? (character: character, length: length) : nil
    }

    private static func isClosingFence(at line: (from: Int, to: Int),
                                       in characters: [Character],
                                       character: Character,
                                       minimumLength: Int) -> Bool {
        var index = line.from
        var indentation = 0
        while index < line.to, characters[index] == " ", indentation < 4 {
            index += 1
            indentation += 1
        }
        let start = index
        while index < line.to, characters[index] == character {
            index += 1
        }
        guard index - start >= minimumLength else { return false }
        return characters[index..<line.to].allSatisfy {
            $0 == " " || $0 == "\t"
        }
    }

    private static func htmlBlockTag(at line: (from: Int, to: Int),
                                     in characters: [Character]) -> String? {
        var index = line.from
        var indentation = 0
        while index < line.to, characters[index] == " ", indentation < 4 {
            index += 1
            indentation += 1
        }
        guard index < line.to, characters[index] == "<" else { return nil }
        if characters[index..<line.to].starts(with: ["<", "!", "-", "-"]) {
            return "!--"
        }
        index += 1
        guard index < line.to, characters[index].isLetter else { return nil }
        let nameStart = index
        while index < line.to, characters[index].isLetter {
            index += 1
        }
        let name = String(characters[nameStart..<index]).lowercased()
        guard htmlBlockTags.contains(name) else { return nil }
        guard index == line.to
                || characters[index] == " "
                || characters[index] == "\t"
                || characters[index] == ">"
                || characters[index] == "/" else {
            return nil
        }
        return name
    }

    private static func isEscaped(_ characters: [Character], at index: Int) -> Bool {
        var backslashes = 0
        var cursor = index
        while cursor > 0, characters[cursor - 1] == "\\" {
            backslashes += 1
            cursor -= 1
        }
        return !backslashes.isMultiple(of: 2)
    }

    private static func isWhitespace(_ character: Character?) -> Bool {
        guard let character else { return true }
        return character.unicodeScalars.allSatisfy {
            CharacterSet.whitespacesAndNewlines.contains($0)
        }
    }

    private static func isPunctuation(_ character: Character?) -> Bool {
        guard let character else { return false }
        let punctuation = CharacterSet.punctuationCharacters.union(.symbols)
        return character.unicodeScalars.allSatisfy { punctuation.contains($0) }
    }
}

nonisolated enum TaskCheckboxSource {
    private static let markerRegex: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"^(\s*(?:>\s*)*(?:[-+*]|\d+[.)])\s+\[)([ xX])(\])"#
        )
    }()

    /// Returns a copy with the task marker on the 1-based source line set to
    /// the requested state. The source line comes from swift-markdown's range,
    /// so duplicate task labels and nested lists remain unambiguous.
    static func settingChecked(_ checked: Bool,
                               onLine sourceLine: Int,
                               in markdown: String) -> String? {
        guard sourceLine > 0 else { return nil }
        var lines = markdown.components(separatedBy: "\n")
        let index = sourceLine - 1
        guard lines.indices.contains(index) else { return nil }

        let line = lines[index]
        let fullRange = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = markerRegex.firstMatch(in: line, range: fullRange),
              let markerRange = Range(match.range(at: 2), in: line) else {
            return nil
        }
        lines[index].replaceSubrange(markerRange, with: checked ? "x" : " ")
        return lines.joined(separator: "\n")
    }
}

// Mirrors swift-markdown's HTMLFormatter but HTML-escapes text, code, and
// attribute values. Upstream HTMLFormatter emits unescaped content
// (swift-markdown 0.7.x), so characters like `<`, `>`, and `&` either render
// invisibly or get reinterpreted as HTML — see issue #33.
nonisolated struct EscapingHTMLFormatter: MarkupWalker {
    private(set) var result = ""

    let options: HTMLFormatterOptions
    let sourceLineOffset: Int
    /// Pre-render fenced code with `CodeHighlighter` so the page paints its
    /// syntax colors on the first frame.
    let highlightsCode: Bool
    /// Interpret Obsidian-style `==highlight==` markers.
    let rendersHighlights: Bool
    /// Upgrade GitHub-style alert blockquotes.
    let rendersCallouts: Bool
    private let sourceLines: [String]
    private let parsedSourceLines: [String]

    private let detectsBareURLs: Bool

    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    private var markdownLinkDepth = 0
    private var rawHTMLLinkExclusions: [String] = []
    private var inTableHead = false
    private var tableColumnAlignments: [Table.ColumnAlignment?]?
    private var currentTableColumn = 0
    private var listDepth = 0
    private var sourceListPrefixToStrip: String?

    private struct SourceIndentedListLine {
        let sourceLine: Int
        let extraDepth: Int
        let displayMarker: String
        let prefixToStrip: String
        let taskChecked: Bool?
    }

    private let strictLineBreaks: Bool

    init(options: HTMLFormatterOptions = [],
         sourceLineOffset: Int = 0,
         sourceMarkdown: String = "",
         parsedMarkdown: String = "",
         highlightsCode: Bool = true,
         rendersHighlights: Bool = true,
         rendersCallouts: Bool = true,
         strictLineBreaks: Bool = false) {
        self.strictLineBreaks = strictLineBreaks
        self.options = options
        self.sourceLineOffset = sourceLineOffset
        self.highlightsCode = highlightsCode
        self.rendersHighlights = rendersHighlights
        self.rendersCallouts = rendersCallouts
        // Escapes/entities can decode into a URL even without a literal scheme.
        self.detectsBareURLs = Self.mayContainHTTP(parsedMarkdown, includesMarkdownEscapes: true)
        self.sourceLines = sourceMarkdown.components(separatedBy: "\n")
        self.parsedSourceLines = parsedMarkdown.components(separatedBy: "\n")
    }

    static func format(_ markdown: String,
                       options: HTMLFormatterOptions = [],
                       sourceLineOffset: Int = 0,
                       sourceMarkdown: String? = nil,
                       highlightsCode: Bool = true,
                       rendersHighlights: Bool = true,
                       rendersCallouts: Bool = true,
                       strictLineBreaks: Bool = false) -> String {
        let preparedMarkdown = rendersHighlights
            ? MarkdownHighlightSource.preparing(markdown)
            : markdown
        let document = Document(parsing: preparedMarkdown)
        var walker = EscapingHTMLFormatter(
            options: options,
            sourceLineOffset: sourceLineOffset,
            sourceMarkdown: sourceMarkdown ?? markdown,
            parsedMarkdown: preparedMarkdown,
            highlightsCode: highlightsCode,
            rendersHighlights: rendersHighlights,
            rendersCallouts: rendersCallouts,
            strictLineBreaks: strictLineBreaks
        )
        walker.visit(document)
        return walker.result
    }

    // MARK: Block elements

    private func sourceLineAttribute(_ markup: Markup) -> String {
        guard let range = markup.range else { return "" }
        let start = range.lowerBound.line + sourceLineOffset
        // SourceRange is half-open. A range ending at column 1 belongs to the
        // previous source line, not the new line whose first column it meets.
        let inclusiveEndLine = range.upperBound.column == 1
            && range.upperBound.line > range.lowerBound.line
            ? range.upperBound.line - 1
            : range.upperBound.line
        let end = max(start, inclusiveEndLine + sourceLineOffset)
        // Keep data-source-line while callers migrate to the richer range.
        return " data-source-line=\"\(start)\" data-source-start=\"\(start)\" data-source-end=\"\(end)\""
    }

    private func precedingBlankLineCount(for markup: Markup) -> Int {
        guard let line = markup.range?.lowerBound.line else { return 0 }
        var precedingLineIndex = line - 2
        var blankLineCount = 0
        while precedingLineIndex >= 0,
              precedingLineIndex < sourceLines.count,
              sourceLines[precedingLineIndex]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty {
            blankLineCount += 1
            precedingLineIndex -= 1
        }
        return blankLineCount
    }

    private func usesDoubleTildeDelimiter(_ strikethrough: Strikethrough) -> Bool {
        guard let start = strikethrough.range?.lowerBound,
              start.line > 0,
              start.column > 0,
              parsedSourceLines.indices.contains(start.line - 1) else {
            // Parsed strikethrough nodes normally have a source range. Keep
            // the established rendering if an upstream parser ever omits it.
            return true
        }

        let line = parsedSourceLines[start.line - 1].utf8
        guard let first = line.index(
            line.startIndex,
            offsetBy: start.column - 1,
            limitedBy: line.endIndex
        ),
              first != line.endIndex,
              line[first] == Character("~").asciiValue,
              let second = line.index(first, offsetBy: 1, limitedBy: line.endIndex),
              second != line.endIndex else {
            return false
        }
        return line[second] == Character("~").asciiValue
    }

    mutating func visitDocument(_ document: Document) {
        for child in document.children {
            // CommonMark discards source blank lines between blocks. Restore
            // every authored line in addition to the blocks' semantic margins.
            for _ in 0..<precedingBlankLineCount(for: child) {
                result += "<div class=\"md-source-blank-line\" aria-hidden=\"true\"></div>\n"
            }
            visit(child)
        }
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        if rendersCallouts, renderAlertIfPresent(blockQuote) {
            return
        }
        if options.contains(.parseAsides),
           let aside = Aside(blockQuote, tagRequirement: .requireSingleWordTag) {
            result += "<aside data-kind=\"\(escapeAttribute(aside.kind.rawValue))\">\n"
            for child in aside.content {
                visit(child)
            }
            result += "</aside>\n"
        } else {
            result += "<blockquote\(sourceLineAttribute(blockQuote))>\n"
            descendInto(blockQuote)
            result += "</blockquote>\n"
        }
    }

    // GitHub-style alerts: `> [!NOTE]`, `> [!TIP]`, `> [!IMPORTANT]`,
    // `> [!WARNING]`, `> [!CAUTION]`. Tag matching is case-insensitive. Any
    // text on the tag line after the closing `]` is used as a custom title;
    // otherwise the alert's default title is used.
    private mutating func renderAlertIfPresent(_ blockQuote: BlockQuote) -> Bool {
        let blocks = Array(blockQuote.children)
        guard let firstPara = blocks.first as? Paragraph else { return false }
        let inlines = Array(firstPara.children)
        guard let firstText = inlines.first as? Text,
              let (kind, prefixLen) = Self.matchAlertTag(firstText.string) else {
            return false
        }

        var firstTextRest = String(firstText.string.dropFirst(prefixLen))
        if firstTextRest.hasPrefix(" ") {
            firstTextRest.removeFirst()
        }

        var titleInlinesAfter: [Markup] = []
        var firstParaBody: [Markup] = []
        var pastTitle = false
        for inline in inlines.dropFirst() {
            if !pastTitle {
                if inline is SoftBreak || inline is LineBreak {
                    pastTitle = true
                    continue
                }
                titleInlinesAfter.append(inline)
            } else {
                firstParaBody.append(inline)
            }
        }

        let hasCustomTitle = !firstTextRest.trimmingCharacters(in: .whitespaces).isEmpty
            || !titleInlinesAfter.isEmpty

        result += "<div class=\"markdown-alert markdown-alert-\(kind.rawValue)\">\n"
        result += "<p class=\"markdown-alert-title\">"
        result += kind.iconSVG
        result += " "
        if hasCustomTitle {
            if !firstTextRest.isEmpty {
                result += escapeText(firstTextRest)
            }
            for inline in titleInlinesAfter {
                visit(inline)
            }
        } else {
            result += escapeText(kind.defaultTitle)
        }
        result += "</p>\n"

        if !firstParaBody.isEmpty {
            result += "<p>"
            for inline in firstParaBody {
                visit(inline)
            }
            result += "</p>\n"
        }
        for block in blocks.dropFirst() {
            visit(block)
        }
        result += "</div>\n"
        return true
    }

    private enum AlertKind: String {
        case note, tip, important, warning, caution

        // GitHub Octicons (info, light-bulb, report, alert, stop).
        // Stripped to the path data only — the wrapper is built by `iconSVG`.
        private var iconPath: String {
            switch self {
            case .note:
                return "M0 8a8 8 0 1 1 16 0A8 8 0 0 1 0 8Zm8-6.5a6.5 6.5 0 1 0 0 13 6.5 6.5 0 0 0 0-13ZM6.5 7.75A.75.75 0 0 1 7.25 7h1a.75.75 0 0 1 .75.75v2.75h.25a.75.75 0 0 1 0 1.5h-2a.75.75 0 0 1 0-1.5h.25v-2h-.25a.75.75 0 0 1-.75-.75ZM8 6a1 1 0 1 1 0-2 1 1 0 0 1 0 2Z"
            case .tip:
                return "M8 1.5c-2.363 0-4 1.69-4 3.75 0 .984.424 1.625.984 2.304l.214.253c.223.264.47.556.673.848.284.411.537.896.621 1.49a.75.75 0 0 1-1.484.211c-.04-.282-.163-.547-.37-.847a8.456 8.456 0 0 0-.542-.68c-.084-.1-.173-.205-.268-.32C3.201 7.75 2.5 6.766 2.5 5.25 2.5 2.31 4.863 0 8 0s5.5 2.31 5.5 5.25c0 1.516-.701 2.5-1.328 3.259-.095.115-.184.22-.268.319-.207.245-.383.453-.541.681-.208.3-.33.565-.37.847a.751.751 0 0 1-1.485-.212c.084-.593.337-1.078.621-1.489.203-.292.45-.584.673-.848.075-.088.147-.173.213-.253.561-.679.985-1.32.985-2.304 0-2.06-1.637-3.75-4-3.75ZM5.75 12h4.5a.75.75 0 0 1 0 1.5h-4.5a.75.75 0 0 1 0-1.5ZM6 15.25a.75.75 0 0 1 .75-.75h2.5a.75.75 0 0 1 0 1.5h-2.5a.75.75 0 0 1-.75-.75Z"
            case .important:
                return "M0 1.75C0 .784.784 0 1.75 0h12.5C15.216 0 16 .784 16 1.75v9.5A1.75 1.75 0 0 1 14.25 13H8.06l-2.573 2.573A1.458 1.458 0 0 1 3 14.543V13H1.75A1.75 1.75 0 0 1 0 11.25Zm1.75-.25a.25.25 0 0 0-.25.25v9.5c0 .138.112.25.25.25h2a.75.75 0 0 1 .75.75v2.19l2.72-2.72a.749.749 0 0 1 .53-.22h6.5a.25.25 0 0 0 .25-.25v-9.5a.25.25 0 0 0-.25-.25Zm7 2.25v2.5a.75.75 0 0 1-1.5 0v-2.5a.75.75 0 0 1 1.5 0ZM9 9a1 1 0 1 1-2 0 1 1 0 0 1 2 0Z"
            case .warning:
                return "M6.457 1.047c.659-1.234 2.427-1.234 3.086 0l6.082 11.378A1.75 1.75 0 0 1 14.082 15H1.918a1.75 1.75 0 0 1-1.543-2.575Zm1.763.707a.25.25 0 0 0-.44 0L1.698 13.132a.25.25 0 0 0 .22.368h12.164a.25.25 0 0 0 .22-.368Zm.53 3.996v2.5a.75.75 0 0 1-1.5 0v-2.5a.75.75 0 0 1 1.5 0ZM9 11a1 1 0 1 1-2 0 1 1 0 0 1 2 0Z"
            case .caution:
                return "M4.47.22A.749.749 0 0 1 5 0h6c.199 0 .389.079.53.22l4.25 4.25c.141.14.22.331.22.53v6a.749.749 0 0 1-.22.53l-4.25 4.25A.749.749 0 0 1 11 16H5a.749.749 0 0 1-.53-.22L.22 11.53A.749.749 0 0 1 0 11V5c0-.199.079-.389.22-.53Zm.84 1.28L1.5 5.31v5.38l3.81 3.81h5.38l3.81-3.81V5.31L10.69 1.5ZM8 4a.75.75 0 0 1 .75.75v3.5a.75.75 0 0 1-1.5 0v-3.5A.75.75 0 0 1 8 4Zm0 8a1 1 0 1 1 0-2 1 1 0 0 1 0 2Z"
            }
        }

        var iconSVG: String {
            "<svg class=\"markdown-alert-icon\" viewBox=\"0 0 16 16\" width=\"16\" height=\"16\" aria-hidden=\"true\"><path d=\"\(iconPath)\"></path></svg>"
        }

        var defaultTitle: String {
            switch self {
            case .note: return "Note"
            case .tip: return "Tip"
            case .important: return "Important"
            case .warning: return "Warning"
            case .caution: return "Caution"
            }
        }
    }

    private static func matchAlertTag(_ text: String) -> (AlertKind, Int)? {
        let tags: [(String, AlertKind)] = [
            ("[!note]", .note),
            ("[!tip]", .tip),
            ("[!important]", .important),
            ("[!warning]", .warning),
            ("[!caution]", .caution),
        ]
        let lower = text.lowercased()
        for (tag, kind) in tags where lower.hasPrefix(tag) {
            return (kind, tag.count)
        }
        return nil
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        let info = CodeFenceInfo(rawInfoString: codeBlock.language)
        var detectedLanguage = info.language.isEmpty
            ? CodeFenceLanguageDetector.detect(codeBlock.code)
            : nil
        let highlighter = highlightsCode && CodeHighlighter.isAvailable
        if highlighter, info.language.isEmpty, detectedLanguage == nil {
            // Same grammar-based fallback the in-page pass uses, so an
            // untyped fence gets its language before the first paint.
            detectedLanguage = CodeHighlighter.detectLanguage(codeBlock.code)
        }
        let language = info.language.isEmpty ? detectedLanguage : info.highlightLanguage
        var languageAttr: String
        if let language, !language.isEmpty {
            let detectedAttr = detectedLanguage == nil
                ? ""
                : " data-md-detected-language=\"true\""
            languageAttr = " class=\"language-\(escapeAttribute(language))\"\(detectedAttr)"
        } else {
            languageAttr = ""
        }
        // Mermaid fences become figures later in the pipeline and math is
        // extracted before the walker runs, so every other fence is ours.
        var body = escapeText(codeBlock.code)
        if highlighter, language != "mermaid" {
            if let language, !language.isEmpty,
               let highlighted = CodeHighlighter.highlight(codeBlock.code, language: language) {
                body = highlighted
            }
            // Stamped done even when no grammar matched: the page then has
            // nothing left for the deferred pass, so it never loads it.
            languageAttr += " data-hljs-done=\"1\""
        }
        let label = info.language.isEmpty ? (detectedLanguage ?? "code") : info.language
        let opening = codeBlock.range.map { range -> String in
            guard parsedSourceLines.indices.contains(range.lowerBound.line - 1) else { return "" }
            return String(decoding: parsedSourceLines[range.lowerBound.line - 1].utf8.dropFirst(range.lowerBound.column - 1), as: UTF8.self)
        } ?? ""
        let isFenced = opening.hasPrefix("```") || opening.hasPrefix("~~~")
        let labelAttribute = isFenced && language != "mermaid"
            ? " data-code-language=\"\(escapeAttribute(label))\"" : ""
        result += "<pre\(sourceLineAttribute(codeBlock))\(labelAttribute)><code\(languageAttr)>\(body)</code></pre>\n"
    }

    mutating func visitHeading(_ heading: Heading) {
        result += "<h\(heading.level)\(sourceLineAttribute(heading))>"
        descendInto(heading)
        result += "</h\(heading.level)>\n"
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        result += "<hr\(sourceLineAttribute(thematicBreak)) />\n"
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) {
        // Raw HTML blocks are passed through per CommonMark.
        result += html.rawHTML
    }

    mutating func visitListItem(_ listItem: ListItem) {
        if let checkbox = listItem.checkbox {
            result += "<li class=\"task-list-item\"\(sourceLineAttribute(listItem))>"
            result += "<input type=\"checkbox\" class=\"task-list-item-checkbox\" disabled=\"\""
            if checkbox == .checked {
                result += " checked=\"\""
            }
            result += " /> "
        } else {
            result += "<li\(sourceLineAttribute(listItem))>"
        }
        descendInto(listItem)
        result += "</li>\n"
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) {
        let start: String
        if orderedList.startIndex != 1 {
            start = " start=\"\(orderedList.startIndex)\""
        } else {
            start = ""
        }
        result += "<ol\(start)\(sourceLineAttribute(orderedList))>\n"
        listDepth += 1
        descendInto(orderedList)
        listDepth -= 1
        result += "</ol>\n"
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) {
        result += "<ul\(sourceLineAttribute(unorderedList))>\n"
        listDepth += 1
        descendInto(unorderedList)
        listDepth -= 1
        result += "</ul>\n"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) {
        result += "<p\(sourceLineAttribute(paragraph))>"
        // Source-indented pseudo-list lines only exist inside a parsed list.
        // Keep the overwhelmingly common top-level paragraph path on the
        // walker's direct traversal instead of materializing all children.
        guard listDepth > 0 else {
            descendInto(paragraph)
            result += "</p>\n"
            return
        }

        let children = Array(paragraph.children)
        var sourceListLineOpen = false
        var sourceListIndentWrappers = 0
        for index in children.indices {
            let child = children[index]
            guard child is SoftBreak || child is LineBreak else {
                visit(child)
                continue
            }

            if sourceListLineOpen {
                result += "</span>"
                result += String(repeating: "</span>", count: sourceListIndentWrappers)
                sourceListLineOpen = false
                sourceListIndentWrappers = 0
                sourceListPrefixToStrip = nil
            }

            let nextChild = children.index(after: index)
            if nextChild < children.endIndex,
               let line = sourceIndentedListLine(startingWith: children[nextChild]) {
                let mappedLine = line.sourceLine + sourceLineOffset
                result += String(
                    repeating: "<span class=\"md-source-list-indent-step\">",
                    count: line.extraDepth
                )
                result += "<span class=\"md-source-list-line\" role=\"listitem\""
                result += " data-source-line=\"\(mappedLine)\" data-source-start=\"\(mappedLine)\" data-source-end=\"\(mappedLine)\""
                result += ">"
                if let checked = line.taskChecked {
                    result += "<span class=\"md-source-list-marker md-source-task-marker\">"
                    result += "<input type=\"checkbox\" class=\"task-list-item-checkbox\" disabled=\"\""
                    if checked { result += " checked=\"\"" }
                    result += " /></span>"
                } else {
                    result += "<span class=\"md-source-list-marker\" aria-hidden=\"true\">"
                    result += escapeText(line.displayMarker)
                    result += "</span>"
                }
                sourceListPrefixToStrip = line.prefixToStrip
                sourceListLineOpen = true
                sourceListIndentWrappers = line.extraDepth
            } else {
                visit(child)
            }
        }
        if sourceListLineOpen {
            result += "</span>"
            result += String(repeating: "</span>", count: sourceListIndentWrappers)
            sourceListPrefixToStrip = nil
        }
        result += "</p>\n"
    }

    private func sourceIndentedListLine(startingWith markup: Markup) -> SourceIndentedListLine? {
        guard listDepth > 0,
              let sourceLine = firstSourceLine(in: markup),
              sourceLines.indices.contains(sourceLine - 1) else {
            return nil
        }
        let source = sourceLines[sourceLine - 1]
        let characters = Array(source)
        var index = 0
        var columns = 0
        while index < characters.count {
            if characters[index] == " " {
                columns += 1
            } else if characters[index] == "\t" {
                columns += 4 - (columns % 4)
            } else {
                break
            }
            index += 1
        }

        let desiredDepth = columns / 4 + 1
        guard desiredDepth > listDepth, index < characters.count else { return nil }

        let markerStart = index
        let displayMarker: String
        if ["-", "+", "*"].contains(characters[index]) {
            displayMarker = "•"
            index += 1
        } else {
            let digitStart = index
            while index < characters.count, characters[index].isNumber {
                index += 1
            }
            guard index > digitStart,
                  index < characters.count,
                  characters[index] == "." || characters[index] == ")" else {
                return nil
            }
            index += 1
            displayMarker = String(characters[digitStart..<index])
        }

        guard index == characters.count
                || characters[index] == " "
                || characters[index] == "\t" else {
            return nil
        }
        while index < characters.count,
              characters[index] == " " || characters[index] == "\t" {
            index += 1
        }

        var taskChecked: Bool?
        if displayMarker == "•",
           index + 2 < characters.count,
           characters[index] == "[",
           characters[index + 2] == "]",
           characters[index + 1] == " "
            || characters[index + 1] == "x"
            || characters[index + 1] == "X" {
            taskChecked = characters[index + 1] != " "
            index += 3
            while index < characters.count,
                  characters[index] == " " || characters[index] == "\t" {
                index += 1
            }
        }

        return SourceIndentedListLine(
            sourceLine: sourceLine,
            extraDepth: desiredDepth - listDepth,
            displayMarker: displayMarker,
            prefixToStrip: String(characters[markerStart..<index]),
            taskChecked: taskChecked
        )
    }

    private func firstSourceLine(in markup: Markup) -> Int? {
        if let line = markup.range?.lowerBound.line {
            return line
        }
        for child in markup.children {
            if let line = firstSourceLine(in: child) {
                return line
            }
        }
        return nil
    }

    mutating func visitTable(_ table: Table) {
        result += "<table\(sourceLineAttribute(table))>\n"
        tableColumnAlignments = table.columnAlignments
        descendInto(table)
        tableColumnAlignments = nil
        result += "</table>\n"
    }

    mutating func visitTableHead(_ tableHead: Table.Head) {
        result += "<thead>\n<tr>\n"
        inTableHead = true
        currentTableColumn = 0
        descendInto(tableHead)
        inTableHead = false
        result += "</tr>\n</thead>\n"
    }

    mutating func visitTableBody(_ tableBody: Table.Body) {
        if !tableBody.isEmpty {
            result += "<tbody>\n"
            descendInto(tableBody)
            result += "</tbody>\n"
        }
    }

    mutating func visitTableRow(_ tableRow: Table.Row) {
        result += "<tr>\n"
        currentTableColumn = 0
        descendInto(tableRow)
        result += "</tr>\n"
    }

    mutating func visitTableCell(_ tableCell: Table.Cell) {
        guard let alignments = tableColumnAlignments,
              currentTableColumn < alignments.count else { return }
        guard tableCell.colspan > 0, tableCell.rowspan > 0 else { return }

        let element = inTableHead ? "th" : "td"
        result += "<\(element)"

        if let alignment = alignments[currentTableColumn] {
            result += " align=\"\(alignment)\""
        }
        currentTableColumn += 1

        if tableCell.rowspan > 1 {
            result += " rowspan=\"\(tableCell.rowspan)\""
        }
        if tableCell.colspan > 1 {
            result += " colspan=\"\(tableCell.colspan)\""
        }

        result += ">"
        descendInto(tableCell)
        result += "</\(element)>\n"
    }

    // MARK: Inline elements

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        result += "<code>\(escapeText(inlineCode.code))</code>"
    }

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        result += "<em>"
        descendInto(emphasis)
        result += "</em>"
    }

    mutating func visitStrong(_ strong: Strong) {
        result += "<strong>"
        descendInto(strong)
        result += "</strong>"
    }

    mutating func visitImage(_ image: Image) {
        result += "<img"
        if let source = image.source, !source.isEmpty {
            result += " src=\"\(escapeAttribute(source))\""
        }
        if let title = image.title, !title.isEmpty {
            result += " title=\"\(escapeAttribute(title))\""
        }
        result += " />"
    }

    mutating func visitInlineHTML(_ inlineHTML: InlineHTML) {
        // Inline HTML arrives as separate opening/closing nodes. Keep raw
        // anchors and code literal even when their contents are Markdown Text.
        guard detectsBareURLs else {
            result += inlineHTML.rawHTML
            return
        }
        let tag = inlineHTML.rawHTML.lowercased()
        for name in ["a", "code", "pre", "script", "style", "textarea"] {
            if tag.range(of: "^<" + name + "(?:\\s|>)", options: .regularExpression) != nil {
                rawHTMLLinkExclusions.append(name)
            } else if tag.range(of: "^</" + name + "\\s*>", options: .regularExpression) != nil,
                      let index = rawHTMLLinkExclusions.lastIndex(of: name) {
                rawHTMLLinkExclusions.removeSubrange(index...)
            }
        }
        result += inlineHTML.rawHTML
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) {
        result += "<br />\n"
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) {
        // Strict mode leaves a soft wrap for HTML to collapse into whitespace.
        result += strictLineBreaks ? "\n" : "<br />\n"
    }

    mutating func visitLink(_ link: Link) {
        result += "<a"
        if let destination = link.destination {
            result += " href=\"\(escapeAttribute(destination))\""
        }
        result += ">"
        markdownLinkDepth += 1
        descendInto(link)
        markdownLinkDepth -= 1
        result += "</a>"
    }

    mutating func visitText(_ text: Text) {
        if let prefix = sourceListPrefixToStrip,
           text.string.hasPrefix(prefix) {
            result += renderText(
                String(text.string.dropFirst(prefix.count))
            )
            sourceListPrefixToStrip = nil
        } else {
            result += renderText(text.string)
        }
    }

    /// ASCII-only candidate check: no Foundation bridging, Unicode case folding,
    /// or temporary lowercase strings. Detection still determines URL boundaries.
    private static func mayContainHTTP(_ string: String, includesMarkdownEscapes: Bool = false) -> Bool {
        var matched = 0
        for byte in string.utf8 {
            if includesMarkdownEscapes && (byte == 38 || byte == 92) { return true }
            let folded = byte | 0x20
            switch (matched, folded) {
            case (_, 104): matched = 1 // h
            case (1, 116): matched = 2 // t
            case (2, 116): matched = 3 // t
            case (3, 112): return true // p
            default: matched = 0
            }
        }
        return false
    }

    private func renderText(_ string: String) -> String {
        guard detectsBareURLs, markdownLinkDepth == 0, rawHTMLLinkExclusions.isEmpty,
              Self.mayContainHTTP(string),
              let detector = Self.linkDetector else {
            return escapeTextWithHighlights(string)
        }
        var html = ""
        var cursor = string.startIndex
        // Highlight sentinels are not prose. Mask them without changing UTF-16
        // offsets so detection stops at the highlight boundary.
        let detectionText = string
            .replacingOccurrences(of: MarkdownHighlightSource.openingToken, with: "  ")
            .replacingOccurrences(of: MarkdownHighlightSource.closingToken, with: "  ")
        for match in detector.matches(in: detectionText, range: NSRange(detectionText.startIndex..., in: detectionText)) {
            guard let range = Range(match.range, in: string),
                  let url = match.url,
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  string[range].lowercased().hasPrefix("http://")
                    || string[range].lowercased().hasPrefix("https://") else { continue }
            html += escapeTextWithHighlights(String(string[cursor..<range.lowerBound]))
            html += "<a href=\"\(escapeAttribute(url.absoluteString))\">\(escapeText(String(string[range])))</a>"
            cursor = range.upperBound
        }
        html += escapeTextWithHighlights(String(string[cursor...]))
        return html
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
        let delimiter = usesDoubleTildeDelimiter(strikethrough)
        result += delimiter ? "<del>" : "~"
        descendInto(strikethrough)
        result += delimiter ? "</del>" : "~"
    }

    mutating func visitSymbolLink(_ symbolLink: SymbolLink) {
        if let destination = symbolLink.destination {
            result += "<code>\(escapeText(destination))</code>"
        }
    }

    mutating func visitInlineAttributes(_ attributes: InlineAttributes) {
        result += "<span data-attributes=\"\(escapeAttribute(attributes.attributes))\""

        if options.contains(.parseInlineAttributeClass) {
            let wrappedAttributes = "{\(attributes.attributes)}"
            if let attributesData = wrappedAttributes.data(using: .utf8) {
                struct ParsedAttributes: Decodable {
                    var `class`: String
                }
                let decoder = JSONDecoder()
                decoder.allowsJSON5 = true
                if let parsed = try? decoder.decode(ParsedAttributes.self, from: attributesData) {
                    result += " class=\"\(escapeAttribute(parsed.class))\""
                }
            }
        }

        result += ">"
        descendInto(attributes)
        result += "</span>"
    }
}

private nonisolated func escapeTextWithHighlights(_ string: String) -> String {
    let openingToken = MarkdownHighlightSource.openingToken
    let closingToken = MarkdownHighlightSource.closingToken
    var result = ""
    result.reserveCapacity(string.count)
    var cursor = string.startIndex

    while cursor < string.endIndex {
        let searchRange = cursor..<string.endIndex
        let opening = string.range(of: openingToken, range: searchRange)
        let closing = string.range(of: closingToken, range: searchRange)
        let next: (range: Range<String.Index>, isOpening: Bool)?
        switch (opening, closing) {
        case let (opening?, closing?):
            next = opening.lowerBound < closing.lowerBound
                ? (opening, true)
                : (closing, false)
        case let (opening?, nil):
            next = (opening, true)
        case let (nil, closing?):
            next = (closing, false)
        case (nil, nil):
            result += escapeTextPreservingInlineTabs(String(string[cursor...]))
            return result
        }

        guard let next else { break }
        result += escapeTextPreservingInlineTabs(String(string[cursor..<next.range.lowerBound]))
        result += next.isOpening
            ? "<mark class=\"md-highlight\">"
            : "</mark>"
        cursor = next.range.upperBound
    }
    return result
}

private nonisolated func escapeText(_ string: String) -> String {
    var out = ""
    out.reserveCapacity(string.count)
    for ch in string {
        switch ch {
        case "&": out += "&amp;"
        case "<": out += "&lt;"
        case ">": out += "&gt;"
        default: out.append(ch)
        }
    }
    return out
}

private nonisolated func escapeTextPreservingInlineTabs(_ string: String) -> String {
    guard string.contains("\t") else { return escapeText(string) }
    return string
        .split(separator: "\t", omittingEmptySubsequences: false)
        .map { escapeText(String($0)) }
        .joined(separator: "<span class=\"md-inline-tab\" aria-hidden=\"true\">&#9;</span>")
}

private nonisolated func escapeAttribute(_ string: String) -> String {
    var out = ""
    out.reserveCapacity(string.count)
    for ch in string {
        switch ch {
        case "&": out += "&amp;"
        case "<": out += "&lt;"
        case ">": out += "&gt;"
        case "\"": out += "&quot;"
        default: out.append(ch)
        }
    }
    return out
}
