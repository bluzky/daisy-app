import Foundation

struct WorkspaceMetadata: Equatable {
    let tags: [WorkspaceMetadataToken]
    let contexts: [WorkspaceMetadataToken]
    let projects: [WorkspaceMetadataToken]
    let tasks: [WorkspaceTaskMetadata]

    static func extract(_ markdown: String) -> WorkspaceMetadata {
        Scanner(markdown).extract()
    }
}

struct WorkspaceMetadataToken: Equatable {
    /// Exact source spelling, marker included. `key` is NFKC-normalized and
    /// lowercased with en_US_POSIX for deterministic lookup.
    let source: String
    let key: String
    let line: Int
}

struct WorkspaceTaskMetadata: Equatable {
    let line: Int
    let due: String?
    let scheduled: String?
    let priority: String?
}

private struct Scanner {
    private static let taskMarker = try! NSRegularExpression(
        pattern: "^[\\t ]*(?:>[\\t ]*)*(?:[-+*]|[0-9]{1,9}[.)])[\\t ]+\\[[ xX]\\](?:[\\t ]+(.*))?$"
    )
    private static let taskField = try! NSRegularExpression(
        pattern: "(?:^|[\\s,;])(?:(due|scheduled):(\\d{4}-\\d{2}-\\d{2})|p:(high|medium|low))(?=$|[\\s,;.,!?])",
        options: .caseInsensitive
    )
    private static let blockHTMLTags: Set<String> = [
        "address", "article", "aside", "blockquote", "details", "div", "figure", "footer",
        "header", "main", "nav", "ol", "pre", "section", "script", "style", "table", "ul",
    ]

    private let lines: [String]

    init(_ markdown: String) {
        let source = markdown.first == "\u{FEFF}" ? String(markdown.dropFirst()) : markdown
        lines = source.components(separatedBy: .newlines)
    }

    func extract() -> WorkspaceMetadata {
        var tags: [WorkspaceMetadataToken] = []
        var contexts: [WorkspaceMetadataToken] = []
        var projects: [WorkspaceMetadataToken] = []
        var tasks: [WorkspaceTaskMetadata] = []
        var frontmatter: String?
        var fence: (marker: Character, length: Int)?
        var htmlBlock: String?

        for (offset, line) in lines.enumerated() {
            let lineNumber = offset + 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if offset == 0 && (trimmed == "---" || trimmed == "+++") {
                frontmatter = trimmed
                continue
            }
            if let activeFrontmatter = frontmatter {
                if activeFrontmatter == "---", trimmed == "---" || trimmed == "..." {
                    frontmatter = nil
                } else if activeFrontmatter == "+++", trimmed == "+++" {
                    frontmatter = nil
                }
                continue
            }
            if let activeFence = fence {
                if closesFence(line, fence: activeFence) { fence = nil }
                continue
            }
            if let activeHTMLBlock = htmlBlock {
                if closesHTMLBlock(line, tag: activeHTMLBlock) { htmlBlock = nil }
                continue
            }
            if line.contains("|") || (isIndentedCode(line) && taskContent(line) == nil) { continue }
            if let openedFence = openingFence(line) {
                fence = openedFence
                continue
            }
            let htmlTag = openingHTMLBlock(line)
            if htmlTag != nil || line.trimmingCharacters(in: .whitespaces).hasPrefix("<") {
                if let htmlTag, !closesHTMLBlock(line, tag: htmlTag) { htmlBlock = htmlTag }
                continue
            }

            let tokens = tokens(in: line, line: lineNumber)
            tags += tokens.tags
            contexts += tokens.contexts
            projects += tokens.projects
            if let task = task(in: line, line: lineNumber) { tasks.append(task) }
        }
        return WorkspaceMetadata(tags: tags, contexts: contexts, projects: projects, tasks: tasks)
    }

    private func tokens(in line: String, line lineNumber: Int) -> (
        tags: [WorkspaceMetadataToken], contexts: [WorkspaceMetadataToken], projects: [WorkspaceMetadataToken]
    ) {
        let characters = Array(searchableText(line))
        var tags: [WorkspaceMetadataToken] = []
        var contexts: [WorkspaceMetadataToken] = []
        var projects: [WorkspaceMetadataToken] = []
        var index = 0
        while index < characters.count {
            let marker = characters[index]
            guard marker == "#" || marker == "@" || marker == "+" else {
                index += 1
                continue
            }
            let previous = index == 0 ? nil : characters[index - 1]
            guard (previous == nil || !isTokenCharacter(previous!)), index + 1 < characters.count,
                  isTokenStart(characters[index + 1]) else {
                index += 1
                continue
            }
            var end = index + 1
            while end < characters.count, isTokenCharacter(characters[end]) { end += 1 }
            let value = String(characters[(index + 1)..<end])
            if !value.split(separator: "/", omittingEmptySubsequences: false).contains(where: \.isEmpty),
               value.contains(where: \.isLetter) {
                let token = WorkspaceMetadataToken(
                    source: String(characters[index..<end]), key: normalizedKey(value), line: lineNumber
                )
                if marker == "#" { tags.append(token) }
                else if marker == "@" { contexts.append(token) }
                else { projects.append(token) }
            }
            index = end
        }
        return (tags, contexts, projects)
    }

    private func task(in line: String, line lineNumber: Int) -> WorkspaceTaskMetadata? {
        guard let content = taskContent(line) else { return nil }
        var due: String?
        var scheduled: String?
        var priority: String?
        let text = searchableText(content)
        let range = NSRange(text.startIndex..., in: text)
        for match in Self.taskField.matches(in: text, range: range) {
            let field = capture(1, from: match, in: text)?.lowercased()
            let date = capture(2, from: match, in: text)
            if field == "due", let date, validDate(date), due == nil { due = date }
            else if field == "scheduled", let date, validDate(date), scheduled == nil { scheduled = date }
            else if let value = capture(3, from: match, in: text), priority == nil { priority = value.lowercased() }
        }
        return WorkspaceTaskMetadata(line: lineNumber, due: due, scheduled: scheduled, priority: priority)
    }

    private func taskContent(_ line: String) -> String? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = Self.taskMarker.firstMatch(in: line, range: range) else { return nil }
        return capture(1, from: match, in: line) ?? ""
    }

    private func capture(_ index: Int, from match: NSTextCheckingResult, in text: String) -> String? {
        let range = match.range(at: index)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
        return String(text[swiftRange])
    }

    private func searchableText(_ line: String) -> String {
        var result = line
        let patterns = [
            #"!?\[[^\]\r\n]*\]\([^\)\r\n]*\)"#, #"`+[^`\r\n]*`+"#,
            #"<https?://[^>\s]+>"#, #"\b(?:https?|ftp)://[^\s<]+"#, #"\bwww\.[^\s<]+"#,
            #"[\p{L}\p{N}._+\-]+@[\p{L}\p{N}.\-]+\.\p{L}{2,}"#,
        ]
        for pattern in patterns {
            result = result.replacingOccurrences(of: pattern, with: " ", options: [.regularExpression, .caseInsensitive])
        }
        return result
    }

    private func openingFence(_ line: String) -> (marker: Character, length: Int)? {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        guard let marker = trimmed.first, marker == "`" || marker == "~" else { return nil }
        let length = trimmed.prefix(while: { $0 == marker }).count
        return length >= 3 ? (marker, length) : nil
    }

    private func closesFence(_ line: String, fence: (marker: Character, length: Int)) -> Bool {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        let length = trimmed.prefix(while: { $0 == fence.marker }).count
        return length >= fence.length && trimmed.dropFirst(length).allSatisfy { $0 == " " || $0 == "\t" }
    }

    private func openingHTMLBlock(_ line: String) -> String? {
        let trimmed = line.drop(while: { $0.isWhitespace })
        if trimmed.hasPrefix("<!--") { return "!--" }
        guard trimmed.first == "<" else { return nil }
        let name = trimmed.dropFirst().prefix(while: { $0.isLetter || $0.isNumber || $0 == "-" })
        guard !name.isEmpty else { return nil }
        let tag = String(name).lowercased()
        return Self.blockHTMLTags.contains(tag) ? tag : nil
    }

    private func closesHTMLBlock(_ line: String, tag: String) -> Bool {
        tag == "!--" ? line.contains("-->") : line.range(of: "</\(tag)\\s*>", options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func isIndentedCode(_ line: String) -> Bool {
        line.hasPrefix("\t") || line.hasPrefix("    ")
    }

    private func isTokenStart(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "-"
    }

    private func isTokenCharacter(_ character: Character) -> Bool {
        isTokenStart(character) || character == "/"
    }

    private func normalizedKey(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping.lowercased(with: Locale(identifier: "en_US_POSIX"))
    }

    private func validDate(_ value: String) -> Bool {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard let date = calendar.date(from: components) else { return false }
        let checked = calendar.dateComponents([.year, .month, .day], from: date)
        return checked.year == parts[0] && checked.month == parts[1] && checked.day == parts[2]
    }
}
