//
//  TemplateFileParser.swift
//  daisy
//
//  Splits a template file into slash-menu templates. A marker comment,
//  `<!-- template: Name -->`, starts a template that runs to the next marker,
//  so its body can hold any heading. A file with no marker falls back to the
//  simple form: every H2 is a template named after its heading.
//

import Foundation

nonisolated struct MarkdownTemplate: Equatable, Sendable {
    let name: String
    let body: String
}

nonisolated enum TemplateFileParser {
    static func parse(_ text: String) -> [MarkdownTemplate] {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        var sections = split(lines, boundary: markerName)
        if sections.isEmpty { sections = split(lines, boundary: h2Name) }

        var seen: [String: Int] = [:]
        var templates: [MarkdownTemplate] = []
        for section in sections where !section.name.isEmpty {
            let count = (seen[section.name] ?? 0) + 1
            seen[section.name] = count
            templates.append(MarkdownTemplate(
                name: count == 1 ? section.name : "\(section.name) (\(count))",
                body: trimBlankLines(section.lines)
            ))
        }
        return templates
    }

    // MARK: - Private

    /// Sections opened by `boundary`, which names a line that starts one.
    /// Boundaries inside a fenced code block don't count.
    private static func split(
        _ lines: [String],
        boundary: (String) -> String?
    ) -> [(name: String, lines: [String])] {
        var sections: [(name: String, lines: [String])] = []
        var fence: (marker: Character, length: Int)?
        for line in lines {
            if let open = fence {
                if closesFence(line, open) { fence = nil }
            } else if let opened = opensFence(line) {
                fence = opened
            } else if let name = boundary(line) {
                sections.append((name, []))
                continue
            }
            if !sections.isEmpty { sections[sections.count - 1].lines.append(line) }
        }
        return sections
    }

    /// `<!-- template: Name -->` alone on its line.
    private static func markerName(_ line: String) -> String? {
        let pattern = #"^ {0,3}<!--\s*template\s*:(.*?)-->\s*$"#
        guard let match = line.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        let inner = line[match]
        guard let colon = inner.firstIndex(of: ":"), let end = inner.range(of: "-->", options: .backwards) else {
            return nil
        }
        return inner[inner.index(after: colon)..<end.lowerBound].trimmingCharacters(in: .whitespaces)
    }

    /// `## Name`, with up to three spaces of indent and an optional closing
    /// run of `#`. `###` and deeper are not H2s.
    private static func h2Name(_ line: String) -> String? {
        var rest = Substring(line)
        var indent = 0
        while rest.first == " ", indent < 3 {
            rest = rest.dropFirst()
            indent += 1
        }
        guard rest.hasPrefix("##") else { return nil }
        rest = rest.dropFirst(2)
        guard rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }
        var name = rest.trimmingCharacters(in: .whitespaces)
        if let closing = name.range(of: #"(^|[ \t])#+$"#, options: .regularExpression) {
            name.removeSubrange(closing)
            name = name.trimmingCharacters(in: .whitespaces)
        }
        return name
    }

    private static func opensFence(_ line: String) -> (marker: Character, length: Int)? {
        let trimmed = line.drop { $0 == " " }
        guard line.count - trimmed.count <= 3, let marker = trimmed.first,
              marker == "`" || marker == "~" else { return nil }
        let length = trimmed.prefix { $0 == marker }.count
        guard length >= 3 else { return nil }
        // A backtick fence's info string cannot contain a backtick.
        if marker == "`", trimmed.dropFirst(length).contains("`") { return nil }
        return (marker, length)
    }

    private static func closesFence(_ line: String, _ open: (marker: Character, length: Int)) -> Bool {
        let trimmed = line.drop { $0 == " " }
        guard line.count - trimmed.count <= 3 else { return false }
        let run = trimmed.prefix { $0 == open.marker }
        return run.count >= open.length
            && trimmed.dropFirst(run.count).allSatisfy { $0 == " " || $0 == "\t" }
    }

    private static func trimBlankLines(_ lines: [String]) -> String {
        func isBlank(_ line: String) -> Bool { line.allSatisfy { $0 == " " || $0 == "\t" } }
        var start = 0
        var end = lines.count
        while start < end, isBlank(lines[start]) { start += 1 }
        while end > start, isBlank(lines[end - 1]) { end -= 1 }
        return lines[start..<end].joined(separator: "\n")
    }
}
