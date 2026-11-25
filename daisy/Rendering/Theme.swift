//
//  Theme.swift
//  daisy
//
//  A theme is one CSS file used by the reading view, the editor and slides.
//  It holds design tokens only: CSS custom properties in `:root` (the light
//  palette) and in `@media (prefers-color-scheme: dark) { :root { … } }`
//  (the dark palette), plus a `/* @theme … */` comment with its name,
//  appearance, base theme, and slide header and footer:
//
//      /* @theme
//      name: My Brand
//      appearance: system        # light | dark | system
//      extends: ember
//      footer: "{title} | | {slide_number}/{total}"
//      */
//      :root { --bg: #FFFFFF; --text: #1A1A1A; --link: #0057B8; }
//      @media (prefers-color-scheme: dark) { :root { --bg: #1C1C1E; } }
//
//  Anything else in the file, and any value the app can't accept, is
//  dropped; the rest still applies. A theme must say light, dark or system,
//  or inherit it from the theme it extends, or it is ignored.
//

import Foundation

nonisolated struct Theme: Equatable, Sendable {
    enum Appearance: String, Sendable {
        case light, dark, system
    }

    /// The file name without `.css`, lowercased.
    var id: String
    var name: String
    var appearance: Appearance
    /// Tokens by name without the leading `--`. A `light` or `dark` theme
    /// keeps its one palette here.
    var light: [String: String] = [:]
    /// The dark palette of a `system` theme; empty otherwise.
    var dark: [String: String] = [:]
    var header: String?
    var footer: String?
    /// Original and the themes built on it: on slides they bring back the
    /// stylesheet's default colors instead of the reading theme's.
    var usesDefaultLook = false

    static let originalID = "original"

    init(id: String, name: String, appearance: Appearance,
         light: [String: String] = [:], dark: [String: String] = [:]) {
        self.id = id
        self.name = name
        self.appearance = appearance
        self.light = light
        self.dark = dark
    }

    // MARK: - Tokens

    enum TokenKind {
        case color, font, bodyWeight, tableStyle, slideFontSize
    }

    /// Every token a theme may set, and how its value is checked.
    static let tokenKinds: [String: TokenKind] = {
        var kinds: [String: TokenKind] = [:]
        var colors: [String] = ["bg", "text", "link", "heading", "code-bg",
                                "table-header-bg", "table-header-text", "table-border", "table-stripe",
                                "bold", "slide-title-bg", "slide-title-text"]
        colors += (1...6).map { "heading-\($0)" }
        colors += WidgetColor.allCases.map { String($0.cssProperty.dropFirst(2)) }
        for name in colors { kinds[name] = .color }
        for name in ["font-body", "font-heading", "font-code"] { kinds[name] = .font }
        kinds["body-weight"] = .bodyWeight
        kinds["table-style"] = .tableStyle
        kinds["slide-font-size"] = .slideFontSize
        return kinds
    }()

    /// Tokens read from `:root` only, never from the dark block.
    static let rootOnlyTokens: Set<String> = [
        "font-body", "font-heading", "font-code", "body-weight", "table-style", "slide-font-size",
    ]

    /// The value as the theme stores it, or nil when the token is unknown
    /// or the value isn't accepted.
    static func sanitized(_ value: String, token: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch tokenKinds[token] {
        case .color: return expandedHexColor(value)
        case .font: return sanitizedFontFamily(value)
        case .bodyWeight: return ["400", "600"].contains(value) ? value : nil
        case .tableStyle: return MarkdownHTML.TableStyle(rawValue: value.lowercased())?.rawValue
        case .slideFontSize: return SlideDeck.fontSize(value) == nil ? nil : value
        case nil: return nil
        }
    }

    /// `#rgb`, `#rgba`, `#rrggbb` or `#rrggbbaa`, short forms expanded to
    /// six or eight digits; nil for anything else, color names included.
    static func expandedHexColor(_ value: String) -> String? {
        guard value.range(of: "^#([0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$",
                          options: .regularExpression) != nil else { return nil }
        let digits = value.dropFirst()
        guard digits.count <= 4 else { return value }
        return "#" + String(digits.flatMap { [$0, $0] })
    }

    /// A font list of names, commas, spaces, quotes and hyphens.
    static func sanitizedFontFamily(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 200,
              trimmed.allSatisfy({ $0.isLetter || $0.isNumber || " ,-_'\"".contains($0) })
        else { return nil }
        return trimmed
    }

    // MARK: - Reading a file

    /// One theme file as written, before `extends` is resolved.
    struct File: Equatable, Sendable {
        var id: String
        var name: String?
        var appearance: Appearance?
        var extends: String?
        var header: String?
        var footer: String?
        var light: [String: String] = [:]
        var dark: [String: String] = [:]

        init(id: String, css: String) {
            self.id = id.lowercased()
            let metadata = Self.metadata(in: css)
            name = metadata["name"]?.string.flatMap { $0.isEmpty ? nil : $0 }
            appearance = metadata["appearance"]?.string.flatMap { Appearance(rawValue: $0.lowercased()) }
            extends = metadata["extends"]?.string.flatMap { $0.isEmpty ? nil : $0.lowercased() }
            header = Theme.chromeTemplate(metadata["header"])
            footer = Theme.chromeTemplate(metadata["footer"])
            let palettes = Self.palettes(in: Self.removingComments(css))
            light = palettes.light
            dark = palettes.dark.filter { !Theme.rootOnlyTokens.contains($0.key) }
        }

        /// The YAML in the first comment that starts with `@theme`.
        private static func metadata(in css: String) -> [String: SlideYAML.Value] {
            var rest = css[...]
            while let open = rest.range(of: "/*") {
                guard let close = rest[open.upperBound...].range(of: "*/") else { break }
                let body = rest[open.upperBound..<close.lowerBound]
                let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("@theme") {
                    return SlideYAML.parse(String(trimmed.dropFirst("@theme".count)))
                }
                rest = rest[close.upperBound...]
            }
            return [:]
        }

        private static func removingComments(_ css: String) -> String {
            css.replacingOccurrences(of: "/\\*[\\s\\S]*?(\\*/|$)", with: " ", options: .regularExpression)
        }

        /// Top-level `prelude { body }` blocks; statements ending in `;`
        /// are skipped.
        private static func blocks(in css: Substring) -> [(prelude: String, body: Substring)] {
            var result: [(String, Substring)] = []
            var index = css.startIndex
            var preludeStart = index
            while index < css.endIndex {
                let char = css[index]
                if char == ";" {
                    preludeStart = css.index(after: index)
                } else if char == "{" {
                    let bodyStart = css.index(after: index)
                    var depth = 1
                    var cursor = bodyStart
                    while cursor < css.endIndex, depth > 0 {
                        if css[cursor] == "{" { depth += 1 }
                        if css[cursor] == "}" { depth -= 1 }
                        if depth > 0 { cursor = css.index(after: cursor) }
                    }
                    let prelude = css[preludeStart..<index]
                        .split(whereSeparator: \.isWhitespace).joined(separator: " ")
                    result.append((prelude, css[bodyStart..<cursor]))
                    index = cursor < css.endIndex ? css.index(after: cursor) : cursor
                    preludeStart = index
                    continue
                }
                index = css.index(after: index)
            }
            return result
        }

        private static func palettes(in css: String) -> (light: [String: String], dark: [String: String]) {
            var light: [String: String] = [:]
            var dark: [String: String] = [:]
            for block in blocks(in: css[...]) {
                if block.prelude == ":root" {
                    light.merge(declarations(in: block.body)) { $1 }
                } else if isDarkMediaQuery(block.prelude) {
                    for inner in blocks(in: block.body) where inner.prelude == ":root" {
                        dark.merge(declarations(in: inner.body)) { $1 }
                    }
                }
            }
            return (light, dark)
        }

        private static func isDarkMediaQuery(_ prelude: String) -> Bool {
            let compact = prelude.lowercased().replacingOccurrences(of: " ", with: "")
            return compact == "@media(prefers-color-scheme:dark)"
        }

        /// `--name: value;` declarations with known names and accepted
        /// values; a later one wins.
        private static func declarations(in body: Substring) -> [String: String] {
            var tokens: [String: String] = [:]
            for declaration in body.split(separator: ";") {
                guard let colon = declaration.firstIndex(of: ":") else { continue }
                let property = declaration[..<colon].trimmingCharacters(in: .whitespacesAndNewlines)
                guard property.hasPrefix("--") else { continue }
                let token = String(property.dropFirst(2)).lowercased()
                let value = String(declaration[declaration.index(after: colon)...])
                if let sanitized = Theme.sanitized(value, token: token) { tokens[token] = sanitized }
            }
            return tokens
        }
    }

    // MARK: - Header and footer

    /// `footer: text` or `footer: { show: …, text: … }`. An empty string
    /// means "no footer" and still overrides the base theme.
    static func chromeTemplate(_ value: SlideYAML.Value?) -> String? {
        guard let value else { return nil }
        if let text = value.string { return text }
        if value["show"]?.string?.lowercased() == "false" { return "" }
        return value["text"]?.string
    }

    // MARK: - Resolving

    /// A file on top of `base`, the theme it extends; nil when neither says
    /// light, dark or system.
    init?(file: File, base: Theme?) {
        guard let appearance = file.appearance ?? base?.appearance else { return nil }
        id = file.id
        name = file.name ?? file.id
        self.appearance = appearance
        header = file.header ?? base?.header
        footer = file.footer ?? base?.footer
        usesDefaultLook = file.id == Self.originalID || base?.usesDefaultLook == true
        let baseLight = base.map { $0.palette(for: appearance == .dark ? .dark : .light) } ?? [:]
        light = baseLight.merging(file.light) { $1 }
        if appearance == .system {
            let baseDark = base.map { $0.palette(for: .dark) } ?? [:]
            dark = baseDark.filter { !Self.rootOnlyTokens.contains($0.key) }.merging(file.dark) { $1 }
        }
    }

    /// The tokens this theme shows in one scheme. A one-palette theme gives
    /// that palette to both; root-only tokens always come from `light`.
    func palette(for scheme: Appearance) -> [String: String] {
        guard appearance == .system, scheme == .dark else { return light }
        return light.filter { Self.rootOnlyTokens.contains($0.key) }.merging(dark) { $1 }
    }

    /// The light or dark appearance a theme pins, or nil when it follows
    /// the system.
    var pinnedDark: Bool? {
        switch appearance {
        case .light: false
        case .dark: true
        case .system: nil
        }
    }

    /// Themes by id, `extends` resolved. A user file whose id is a built-in
    /// theme's is skipped, and so is a theme that doesn't say light, dark or
    /// system. In an `extends` cycle the theme where it is found loses its base.
    static func catalog(builtIns: [File], user: [File] = []) -> [String: Theme] {
        var files: [String: File] = [:]
        for file in builtIns { files[file.id] = file }
        let builtInIDs = Set(files.keys)
        for file in user where !builtInIDs.contains(file.id) { files[file.id] = file }

        var themes: [String: Theme] = [:]
        var rejected: Set<String> = []
        var resolving: Set<String> = []
        func resolve(_ id: String) -> Theme? {
            if let theme = themes[id] { return theme }
            guard let file = files[id], !rejected.contains(id), !resolving.contains(id) else { return nil }
            resolving.insert(id)
            defer { resolving.remove(id) }
            let base = file.extends.flatMap { resolve($0) }
            guard let theme = Theme(file: file, base: base) else {
                rejected.insert(id)
                return nil
            }
            themes[id] = theme
            return theme
        }
        for id in files.keys.sorted() { _ = resolve(id) }
        return themes
    }
}
