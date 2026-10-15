//
//  DocxSyntaxColors.swift
//  daisy
//
//  Turns the preview's highlight.js output into colored text segments for the
//  DOCX export. Classification maps hljs classes to a `SyntaxToken`; the theme
//  maps token to color. App-only.
//

import Foundation

nonisolated enum DocxSyntaxColors {
    struct Segment: Equatable {
        var text: String
        var color: String?
    }

    static func segments(for code: String, fenceInfo: String?, theme: DocxTheme) -> [Segment] {
        let info = CodeFenceInfo(rawInfoString: fenceInfo)
        var language: String? = info.language.isEmpty
            ? CodeFenceLanguageDetector.detect(code)
            : info.highlightLanguage
        if language == nil || language?.isEmpty == true {
            language = CodeHighlighter.detectLanguage(code)
        }
        guard let language, !language.isEmpty, language != "mermaid",
              let html = CodeHighlighter.highlight(code, language: language)
        else { return [Segment(text: code, color: nil)] }
        return parse(html, theme: theme)
    }

    /// Walks `<span class="hljs-…">` / `</span>` and decodes entities. The
    /// highlighter only emits spans and escaped text.
    ///
    /// The span stack holds tokens, never colors, so classification cannot be
    /// affected by two tokens sharing a color or by a token having none.
    static func parse(_ html: String, theme: DocxTheme) -> [Segment] {
        var result: [Segment] = []
        var stack: [SyntaxToken?] = []
        var buffer = ""
        var index = html.startIndex

        func flush() {
            guard !buffer.isEmpty else { return }
            // The nearest recognised token decides, even when its color is
            // none: a disabled token does not fall back to its ancestor.
            let color = stack.reversed().compactMap { $0 }.first.flatMap(theme.syntaxColor)
            if let last = result.last, last.color == color {
                result[result.count - 1].text += buffer
            } else {
                result.append(Segment(text: buffer, color: color))
            }
            buffer = ""
        }

        while index < html.endIndex {
            let character = html[index]
            if character == "<", let close = html[index...].firstIndex(of: ">") {
                let tag = html[html.index(after: index)..<close]
                flush()
                if tag.hasPrefix("/") {
                    if !stack.isEmpty { stack.removeLast() }
                } else {
                    let classes = tag.range(of: "class=\"").flatMap { start in
                        tag[start.upperBound...].firstIndex(of: "\"").map {
                            String(tag[start.upperBound..<$0])
                        }
                    } ?? ""
                    stack.append(token(forClasses: classes, insideMeta: stack.contains { $0 == .meta }))
                }
                index = html.index(after: close)
            } else if character == "&", let semicolon = html[index...].firstIndex(of: ";"),
                      html.distance(from: index, to: semicolon) <= 8,
                      let decoded = decode(String(html[html.index(after: index)..<semicolon])) {
                buffer += decoded
                index = html.index(after: semicolon)
            } else {
                buffer.append(character)
                index = html.index(after: index)
            }
        }
        flush()
        return result
    }

    private static func decode(_ entity: String) -> String? {
        switch entity {
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos": return "'"
        default:
            if entity.hasPrefix("#x"), let value = UInt32(entity.dropFirst(2), radix: 16),
               let scalar = Unicode.Scalar(value) { return String(scalar) }
            if entity.hasPrefix("#"), let value = UInt32(entity.dropFirst()),
               let scalar = Unicode.Scalar(value) { return String(scalar) }
            return nil
        }
    }

    static func token(forClasses classes: String, insideMeta: Bool) -> SyntaxToken? {
        let set = Set(classes.split(separator: " ").map(String.init))
        func has(_ names: String...) -> Bool { names.contains { set.contains("hljs-\($0)") } }
        if has("title") {
            return set.contains("class_") ? .titleClass : .title
        }
        if has("variable") && set.contains("language_") { return .keyword }
        if has("keyword") { return insideMeta ? .meta : .keyword }
        if has("literal", "template-tag", "name", "selector-tag", "section", "bullet") { return .keyword }
        if has("string", "regexp") { return .string }
        if has("number", "char", "symbol") { return .number }
        if has("comment", "quote", "formula") { return .comment }
        if has("doctag") { return .doctag }
        if has("type") { return .type }
        if has("built_in") { return .builtIn }
        if has("variable", "template-variable", "property", "selector-class",
               "selector-id", "selector-attr", "selector-pseudo") { return .property }
        if has("meta") { return .meta }
        if has("attr", "attribute") { return .attribute }
        return nil
    }
}
