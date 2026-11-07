//
//  SlideDeckSettings.swift
//  daisy
//
//  A deck's frontmatter settings, and the small YAML reader for them and
//  for slide theme files.
//

import Foundation

/// Reads the YAML used in deck frontmatter and slide theme files: nested
/// mappings by indentation, plain and quoted scalars, and `#` comments.
/// Sequences, anchors and multi-line scalars are not supported; a line it
/// can't read is skipped.
nonisolated enum SlideYAML {
    indirect enum Value: Equatable {
        case scalar(String)
        case map([String: Value])

        var string: String? {
            if case .scalar(let value) = self { return value }
            return nil
        }

        var map: [String: Value]? {
            if case .map(let value) = self { return value }
            return nil
        }

        subscript(key: String) -> Value? { map?[key] }
    }

    static func parse(_ text: String) -> [String: Value] {
        var lines: [(indent: Int, key: String, value: String)] = []
        for raw in text.components(separatedBy: .newlines) {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"),
                  let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = trimmed[..<colon].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            let indent = raw.prefix { $0 == " " || $0 == "\t" }.count
            let value = scalar(String(trimmed[trimmed.index(after: colon)...]))
            lines.append((indent, unquoted(key), value))
        }
        var index = 0
        return block(lines, &index, indent: lines.first?.indent ?? 0)
    }

    private static func block(
        _ lines: [(indent: Int, key: String, value: String)],
        _ index: inout Int,
        indent: Int
    ) -> [String: Value] {
        var result: [String: Value] = [:]
        while index < lines.count, lines[index].indent >= indent {
            let line = lines[index]
            index += 1
            if line.value.isEmpty, index < lines.count, lines[index].indent > line.indent {
                result[line.key] = .map(block(lines, &index, indent: lines[index].indent))
            } else {
                result[line.key] = .scalar(line.value)
            }
        }
        return result
    }

    /// The value after `key:`, without a trailing ` # comment` and quotes.
    private static func scalar(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let quote = trimmed.first, quote == "\"" || quote == "'",
           let close = trimmed.dropFirst().firstIndex(of: quote) {
            return String(trimmed[trimmed.index(after: trimmed.startIndex)..<close])
        }
        if let comment = trimmed.range(of: " #") {
            return trimmed[..<comment.lowerBound].trimmingCharacters(in: .whitespaces)
        }
        return trimmed
    }

    private static func unquoted(_ text: String) -> String {
        guard text.count >= 2, let first = text.first, first == text.last,
              first == "\"" || first == "'" else { return text }
        return String(text.dropFirst().dropLast())
    }
}

/// What a deck's frontmatter sets, besides turning slides on.
nonisolated struct SlideDeckSettings: Equatable {
    enum Aspect: String, CaseIterable {
        case wide = "16:9"
        case wideTall = "16:10"
        case standard = "4:3"

        var width: Int {
            switch self {
            case .wide, .wideTall: 16
            case .standard: 4
            }
        }

        var height: Int {
            switch self {
            case .wide: 9
            case .wideTall: 10
            case .standard: 3
            }
        }

        /// The canvas height for the 1280 px wide canvas.
        var canvasHeight: Int { MarkdownHTML.slideCanvasWidth * height / width }
    }

    var aspect: Aspect = .wide
    var paginate = false
    var header: String?
    var footer: String?
    /// `font_size:` — the base text size in `cqw`; nil follows the theme.
    var fontSize: Double?
    var title: String?
    var author: String?
    var date: String?
    var theme: String?
    /// `theme_overrides:` — the same shape as a theme file's `colors` and
    /// `fonts`, applied on top of the deck's theme.
    var themeOverrides: [String: SlideYAML.Value] = [:]

    init() {}

    init(frontmatter raw: String?, format: MarkdownFrontmatter.Format?) {
        guard let raw, let format else { return }
        let values: [String: SlideYAML.Value]
        switch format {
        case .yaml:
            values = SlideYAML.parse(raw)
        case .toml:
            values = Dictionary(
                MarkdownFrontmatter.parse(raw, format: .toml).map { ($0.key, .scalar($0.value)) },
                uniquingKeysWith: { first, _ in first }
            )
        }
        let string = { (key: String) in values[key]?.string.flatMap { $0.isEmpty ? nil : $0 } }
        aspect = string("aspect").flatMap(Aspect.init(rawValue:)) ?? .wide
        paginate = string("paginate")?.lowercased() == "true"
        header = string("header")
        footer = string("footer")
        fontSize = string("font_size").flatMap(SlideDeck.fontSize)
        title = string("title")
        author = string("author")
        date = string("date")
        theme = string("theme")?.lowercased()
        themeOverrides = values["theme_overrides"]?.map ?? [:]
    }

    init(markdown: String) {
        let frontmatter = MarkdownFrontmatter.split(markdown)
        self.init(frontmatter: frontmatter.raw, format: frontmatter.format)
    }

    // MARK: - Header and footer

    /// `{title}`, `{author}`, `{date}`, `{slide_number}` and `{total}`
    /// filled in, and split at `|` into left, center and right parts.
    static func templateParts(
        _ template: String,
        title: String,
        author: String,
        date: String,
        slideNumber: Int,
        total: Int
    ) -> [String] {
        let filled = template
            .replacingOccurrences(of: "{title}", with: title)
            .replacingOccurrences(of: "{author}", with: author)
            .replacingOccurrences(of: "{date}", with: date)
            .replacingOccurrences(of: "{slide_number}", with: String(slideNumber))
            .replacingOccurrences(of: "{total}", with: String(total))
        let parts = filled.components(separatedBy: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        switch parts.count {
        case 1: return [parts[0], "", ""]
        case 2: return [parts[0], "", parts[1]]
        default: return [parts[0], parts[1], parts[2...].joined(separator: " | ")]
        }
    }
}

/// A slide's header, footer and page number, from the deck's settings and
/// the slide's `_header`, `_footer` and `_paginate` directives.
nonisolated struct SlideChrome {
    let settings: SlideDeckSettings
    let title: String
    let total: Int
    let date: String

    init(settings: SlideDeckSettings, deck: SlideDeck, today: Date = Date()) {
        self.settings = settings
        title = settings.title ?? deck.firstTitle ?? ""
        total = deck.slides.count
        date = settings.date ?? today.formatted(date: .abbreviated, time: .omitted)
    }

    func html(for slide: SlideDeck.Slide, number: Int) -> String {
        var html = ""
        for (name, template) in [("header", slide.header ?? settings.header),
                                 ("footer", slide.footer ?? settings.footer)] {
            guard let template, !template.isEmpty else { continue }
            let parts = SlideDeckSettings.templateParts(
                template, title: title, author: settings.author ?? "", date: date,
                slideNumber: number, total: total
            )
            html += "<div class=\"mdp-slide-\(name)\" aria-hidden=\"true\">"
            html += parts.map { "<span>\(MarkdownHTML.htmlEscape($0))</span>" }.joined()
            html += "</div>"
        }
        if slide.paginate ?? settings.paginate {
            html += "<div class=\"mdp-slide-number\" aria-hidden=\"true\">\(number)</div>"
        }
        return html
    }
}
