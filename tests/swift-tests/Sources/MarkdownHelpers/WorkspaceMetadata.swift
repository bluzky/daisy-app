import Foundation

struct WorkspaceMetadata: Equatable {
    let tags: [WorkspaceMetadataToken]
    let contexts: [WorkspaceMetadataToken]
    let projects: [WorkspaceMetadataToken]
    let tasks: [WorkspaceTaskMetadata]

    static func extract(_ markdown: String) -> WorkspaceMetadata { WorkspaceMetadataScanner(markdown).extract() }
}

struct WorkspaceMetadataToken: Equatable {
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

// Mirrors daisy/Features/WorkspaceMetadata.swift. SwiftPM sources are kept
// separately so helper tests can compile without requiring Xcode project files.
private struct WorkspaceMetadataScanner {
    private static let taskMarker = try! NSRegularExpression(pattern: "^[\\t ]*(?:>[\\t ]*)*(?:[-+*]|[0-9]{1,9}[.)])[\\t ]+\\[[ xX]\\](?:[\\t ]+(.*))?$")
    private static let taskField = try! NSRegularExpression(pattern: "(?:^|[\\s,;])(?:(due|scheduled):(\\d{4}-\\d{2}-\\d{2})|p:(high|medium|low))(?=$|[\\s,;.,!?])", options: .caseInsensitive)
    private static let blockTags: Set<String> = ["address", "article", "aside", "blockquote", "details", "div", "figure", "footer", "header", "main", "nav", "ol", "pre", "section", "script", "style", "table", "ul"]
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
        var fence: (Character, Int)?
        var htmlBlock: String?

        for (offset, line) in lines.enumerated() {
            let number = offset + 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if offset == 0 && (trimmed == "---" || trimmed == "+++") { frontmatter = trimmed; continue }
            if let activeFrontmatter = frontmatter {
                if (activeFrontmatter == "---" && (trimmed == "---" || trimmed == "...")) || (activeFrontmatter == "+++" && trimmed == "+++") { frontmatter = nil }
                continue
            }
            if let activeFence = fence {
                if closesFence(line, activeFence) { fence = nil }
                continue
            }
            if let activeHTMLBlock = htmlBlock {
                if closesHTML(line, activeHTMLBlock) { htmlBlock = nil }
                continue
            }
            if line.contains("|") || (isIndentedCode(line) && taskContent(line) == nil) { continue }
            if let opened = openingFence(line) { fence = opened; continue }
            let tag = openingHTML(line)
            if tag != nil || line.trimmingCharacters(in: .whitespaces).hasPrefix("<") {
                if let tag, !closesHTML(line, tag) { htmlBlock = tag }
                continue
            }
            let found = tokens(line, number)
            tags += found.0; contexts += found.1; projects += found.2
            if let task = task(line, number) { tasks.append(task) }
        }
        return WorkspaceMetadata(tags: tags, contexts: contexts, projects: projects, tasks: tasks)
    }

    private func tokens(_ line: String, _ number: Int) -> ([WorkspaceMetadataToken], [WorkspaceMetadataToken], [WorkspaceMetadataToken]) {
        let characters = Array(searchableText(line))
        var tags: [WorkspaceMetadataToken] = []
        var contexts: [WorkspaceMetadataToken] = []
        var projects: [WorkspaceMetadataToken] = []
        var index = 0
        while index < characters.count {
            let marker = characters[index]
            guard marker == "#" || marker == "@" || marker == "+" else { index += 1; continue }
            let previous = index == 0 ? nil : characters[index - 1]
            guard (previous == nil || !tokenCharacter(previous!)), index + 1 < characters.count, tokenStart(characters[index + 1]) else { index += 1; continue }
            var end = index + 1
            while end < characters.count, tokenCharacter(characters[end]) { end += 1 }
            let value = String(characters[(index + 1)..<end])
            if !value.split(separator: "/", omittingEmptySubsequences: false).contains(where: \.isEmpty), value.contains(where: \.isLetter) {
                let token = WorkspaceMetadataToken(source: String(characters[index..<end]), key: normalizedKey(value), line: number)
                if marker == "#" { tags.append(token) } else if marker == "@" { contexts.append(token) } else { projects.append(token) }
            }
            index = end
        }
        return (tags, contexts, projects)
    }

    private func task(_ line: String, _ number: Int) -> WorkspaceTaskMetadata? {
        guard let content = taskContent(line) else { return nil }
        var due: String?; var scheduled: String?; var priority: String?
        let text = searchableText(content)
        for match in Self.taskField.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            let field = capture(1, match, text)?.lowercased()
            let date = capture(2, match, text)
            if field == "due", let date, validDate(date), due == nil { due = date }
            else if field == "scheduled", let date, validDate(date), scheduled == nil { scheduled = date }
            else if let value = capture(3, match, text), priority == nil { priority = value.lowercased() }
        }
        return WorkspaceTaskMetadata(line: number, due: due, scheduled: scheduled, priority: priority)
    }

    private func taskContent(_ line: String) -> String? {
        guard let match = Self.taskMarker.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { return nil }
        return capture(1, match, line) ?? ""
    }

    private func capture(_ index: Int, _ match: NSTextCheckingResult, _ text: String) -> String? {
        let range = match.range(at: index)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
        return String(text[swiftRange])
    }

    private func searchableText(_ line: String) -> String {
        [#"!?\[[^\]\r\n]*\]\([^\)\r\n]*\)"#, #"`+[^`\r\n]*`+"#, #"<https?://[^>\s]+>"#, #"\b(?:https?|ftp)://[^\s<]+"#, #"\bwww\.[^\s<]+"#, #"[\p{L}\p{N}._+\-]+@[\p{L}\p{N}.\-]+\.\p{L}{2,}"#].reduce(line) {
            $0.replacingOccurrences(of: $1, with: " ", options: [.regularExpression, .caseInsensitive])
        }
    }

    private func openingFence(_ line: String) -> (Character, Int)? {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        guard let marker = trimmed.first, marker == "`" || marker == "~" else { return nil }
        let count = trimmed.prefix(while: { $0 == marker }).count
        return count >= 3 ? (marker, count) : nil
    }

    private func closesFence(_ line: String, _ fence: (Character, Int)) -> Bool {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        let count = trimmed.prefix(while: { $0 == fence.0 }).count
        return count >= fence.1 && trimmed.dropFirst(count).allSatisfy { $0 == " " || $0 == "\t" }
    }

    private func openingHTML(_ line: String) -> String? {
        let trimmed = line.drop(while: \.isWhitespace)
        if trimmed.hasPrefix("<!--") { return "!--" }
        guard trimmed.first == "<" else { return nil }
        let name = trimmed.dropFirst().prefix(while: { $0.isLetter || $0.isNumber || $0 == "-" })
        let tag = String(name).lowercased()
        return Self.blockTags.contains(tag) ? tag : nil
    }

    private func closesHTML(_ line: String, _ tag: String) -> Bool {
        tag == "!--" ? line.contains("-->") : line.range(of: "</\(tag)\\s*>", options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func isIndentedCode(_ line: String) -> Bool { line.hasPrefix("\t") || line.hasPrefix("    ") }
    private func tokenStart(_ character: Character) -> Bool { character.isLetter || character.isNumber || character == "_" || character == "-" }
    private func tokenCharacter(_ character: Character) -> Bool { tokenStart(character) || character == "/" }
    private func normalizedKey(_ value: String) -> String { value.precomposedStringWithCompatibilityMapping.lowercased(with: Locale(identifier: "en_US_POSIX")) }

    private func validDate(_ value: String) -> Bool {
        let values = value.split(separator: "-").compactMap { Int($0) }
        guard values.count == 3 else { return false }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: values[0], month: values[1], day: values[2])) else { return false }
        let checked = calendar.dateComponents([.year, .month, .day], from: date)
        return checked.year == values[0] && checked.month == values[1] && checked.day == values[2]
    }
}
