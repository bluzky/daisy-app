//
//  SlideTheme.swift
//  daisy
//
//  Slide deck themes: colors, fonts, header and footer, from YAML in
//  Kova's shape. A theme becomes CSS custom properties and font rules on
//  the deck; it can't inject arbitrary CSS.
//

import Foundation

nonisolated struct SlideTheme: Equatable {
    var id: String
    var name: String
    /// `colors:` — `background`, `text`, `heading`, `accent` (links and
    /// bullets; `primary` is read when there is no `accent`), `bold`,
    /// `code_background`, and `primary` with `title_text` for title and
    /// section slides.
    var colors: [String: String] = [:]
    /// `fonts:` — `body`, `title` (headings) and `code`.
    var fonts: [String: String] = [:]
    var header: String?
    var footer: String?
    /// `appearance: dark|light`; when absent, read from the background.
    var appearance: String?

    static let defaultID = "default"

    // MARK: - Reading

    /// A theme file's values on top of `base`, the theme it `extends`.
    init(id: String, values: [String: SlideYAML.Value], base: SlideTheme? = nil) {
        self.id = id
        name = values["name"]?.string ?? base?.name ?? id
        colors = base?.colors ?? [:]
        fonts = base?.fonts ?? [:]
        header = base?.header
        footer = base?.footer
        appearance = base?.appearance
        apply(values)
    }

    /// Applies `colors`, `fonts`, `header` and `footer` from theme file or
    /// `theme_overrides:` values. Invalid colors and fonts are dropped.
    mutating func apply(_ values: [String: SlideYAML.Value]) {
        for (key, value) in values["colors"]?.map ?? [:] {
            guard let color = value.string.flatMap(SlideDeck.sanitizedColor) else { continue }
            colors[key.lowercased()] = color
        }
        for (key, value) in values["fonts"]?.map ?? [:] {
            guard let font = value.string.flatMap(Self.sanitizedFontFamily) else { continue }
            fonts[key.lowercased()] = font
        }
        if let appearance = values["appearance"]?.string?.lowercased(),
           ["dark", "light"].contains(appearance) {
            self.appearance = appearance
        }
        if let header = Self.chromeTemplate(values["header"]) { self.header = header }
        if let footer = Self.chromeTemplate(values["footer"]) { self.footer = footer }
    }

    /// `footer: text` or Kova's `footer: { show: …, text: … }`. An empty
    /// string means "no footer" and still overrides the base theme.
    private static func chromeTemplate(_ value: SlideYAML.Value?) -> String? {
        guard let value else { return nil }
        if let text = value.string { return text }
        if value["show"]?.string?.lowercased() == "false" { return "" }
        return value["text"]?.string
    }

    /// A font list of names, commas, spaces, quotes and hyphens.
    static func sanitizedFontFamily(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 200,
              trimmed.allSatisfy({ $0.isLetter || $0.isNumber || " ,-_'\"".contains($0) })
        else { return nil }
        return trimmed
    }

    // MARK: - CSS

    /// Whether the slides are dark: `appearance`, else the background's
    /// brightness when it is a hex color; nil when unknown.
    var isDark: Bool? {
        if let appearance { return appearance == "dark" }
        guard let background = colors["background"],
              let luminance = Self.luminance(ofHex: background) else { return nil }
        return luminance < 0.5
    }

    /// Relative luminance (0 black – 1 white) of `#rgb` / `#rrggbb[aa]`.
    static func luminance(ofHex value: String) -> Double? {
        var hex = value.hasPrefix("#") ? String(value.dropFirst()) : value
        if hex.count == 3 || hex.count == 4 { hex = String(hex.prefix(3).flatMap { [$0, $0] }) }
        guard hex.count >= 6, let rgb = Int(hex.prefix(6), radix: 16) else { return nil }
        let channel = { (shift: Int) -> Double in
            let c = Double((rgb >> shift) & 0xff) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }

    /// Custom properties and font rules scoped to the deck. Colors go
    /// through the variables the page already uses, so `invert`, `dim` and
    /// `color` directives, which set colors on a slide, still win.
    var css: String {
        var deck: [String] = []
        // Code colors and system colors follow the slides, not the window:
        // a dark theme in a light window still gets dark-mode code colors.
        if let isDark {
            deck.append("color-scheme: \(isDark ? "dark" : "light"); --hl-plain: var(--text);")
            deck.append((isDark ? MarkdownHTML.darkCodePaletteCSS : MarkdownHTML.lightCodePaletteCSS)
                .replacingOccurrences(of: "\n", with: " "))
            deck.append(isDark
                ? "--code-bg: #262626; --code-border: #323232; --quote-border: rgb(255 255 255 / 25%);"
                : "--code-bg: #f9f9f9; --code-border: #f0f0f0; --quote-border: rgb(0 0 0 / 15%);")
        }
        if let background = colors["background"] { deck.append("--mdp-slide-bg: \(background);") }
        if let text = colors["text"] {
            deck.append("--text: \(text);")
            deck.append("--secondary: color-mix(in srgb, \(text) 70%, transparent);")
        }
        if let heading = colors["heading"] {
            deck.append("--heading: \(heading);")
        } else if colors["background"] != nil || colors["text"] != nil {
            // A reading theme's heading color doesn't belong on slides with
            // their own background and text.
            deck.append((["--heading"] + (1...6).map { "--heading-\($0)" }).map { "\($0): initial;" }.joined(separator: " "))
        }
        if let accent = colors["accent"] ?? colors["primary"] { deck.append("--link: \(accent);") }
        if let code = colors["code_background"] { deck.append("--code-bg: \(code);") }

        var rules: [String] = []
        // On the slides only: the notes under them in Read Mode stay in the
        // page's colors. `:where` keeps it below a slide's own classes.
        if !deck.isEmpty { rules.append(":where(.mdp-deck) .mdp-slide { \(deck.joined(separator: " ")) }") }
        if let accent = colors["accent"] ?? colors["primary"] {
            rules.append(".mdp-deck .mdp-slide li::marker { color: \(accent); }")
        }
        if let bold = colors["bold"] {
            rules.append(".mdp-deck .mdp-slide :is(strong, b) { color: \(bold); }")
        }
        if let primary = colors["primary"] {
            let titleText = colors["title_text"] ?? "#ffffff"
            rules.append("""
            .mdp-deck :where(.mdp-slide--title, .mdp-slide--section) { \
            --mdp-slide-bg: \(primary); --text: \(titleText); \
            --secondary: color-mix(in srgb, \(titleText) 80%, transparent); \
            --heading: \(titleText); }
            """)
        }
        if let body = fonts["body"] {
            rules.append(".mdp-deck .mdp-slide { font-family: \(body); }")
        }
        if let title = fonts["title"] {
            rules.append(".mdp-deck .mdp-slide :is(h1, h2, h3, h4, h5, h6) { font-family: \(title); }")
        }
        if let code = fonts["code"] {
            rules.append(".mdp-deck .mdp-slide :is(code, pre, kbd, samp) { font-family: \(code); }")
        }
        return rules.joined(separator: "\n")
    }

    // MARK: - Built-in themes

    /// `default` follows the reading theme; the others set their own look.
    static let builtIns: [SlideTheme] = {
        let sources: [(String, String)] = [
            (defaultID, "name: Default"),
            ("light", """
            name: Light
            colors:
              background: "#ffffff"
              text: "#1d1d1f"
              heading: "#1d1d1f"
              accent: "#0a66d8"
              code_background: "#f5f5f7"
            """),
            ("dark", """
            name: Dark
            colors:
              background: "#1c1c1e"
              text: "#f2f2f7"
              heading: "#ffffff"
              accent: "#64a8ff"
              code_background: "#2c2c2e"
            """),
            ("paper", """
            name: Paper
            colors:
              background: "#fbf7ef"
              text: "#2b2a27"
              heading: "#8a4b1f"
              accent: "#b0602c"
              code_background: "#f1eadb"
            fonts:
              body: "Georgia, 'Times New Roman', serif"
              title: "Georgia, 'Times New Roman', serif"
            """),
            ("midnight", """
            name: Midnight
            colors:
              background: "#0f172a"
              text: "#e2e8f0"
              heading: "#93c5fd"
              accent: "#38bdf8"
              code_background: "#1e293b"
              primary: "#1e3a8a"
              title_text: "#ffffff"
            """),
            ("pitch", """
            name: Pitch
            colors:
              background: "#ffffff"
              text: "#111111"
              heading: "#0057b8"
              accent: "#0057b8"
              bold: "#b8003f"
              primary: "#0057b8"
              title_text: "#ffffff"
            """),
        ]
        return sources.map { SlideTheme(id: $0.0, values: SlideYAML.parse($0.1)) }
    }()

    // MARK: - Resolving

    static let builtInCatalog = catalog()

    /// Themes by id, `extends` resolved: built-ins, then theme files, which
    /// may extend a built-in or each other and may replace a built-in.
    /// `files` maps a fallback id (the file name) to the file's text.
    static func catalog(files: [String: String] = [:]) -> [String: SlideTheme] {
        var themes = Dictionary(uniqueKeysWithValues: builtIns.map { ($0.id, $0) })
        var pending: [String: [String: SlideYAML.Value]] = [:]
        for (fileID, text) in files {
            let values = SlideYAML.parse(text)
            let id = (values["id"]?.string ?? fileID).lowercased()
            pending[id] = values
        }
        var resolving: Set<String> = []
        func resolve(_ id: String) -> SlideTheme? {
            if let values = pending[id] {
                guard !resolving.contains(id) else { return nil }  // an `extends` cycle
                resolving.insert(id)
                defer { resolving.remove(id) }
                let base = values["extends"]?.string.flatMap { resolve($0.lowercased()) }
                let theme = SlideTheme(id: id, values: values, base: base)
                pending[id] = nil
                themes[id] = theme
                return theme
            }
            return themes[id]
        }
        for id in pending.keys.sorted() { _ = resolve(id) }
        return themes
    }

    /// The deck's theme (`theme:`, else `default`; an unknown name falls
    /// back to `default`) with its `theme_overrides:` applied.
    static func resolved(for settings: SlideDeckSettings, in catalog: [String: SlideTheme]) -> SlideTheme {
        var theme = settings.theme.flatMap { catalog[$0] }
            ?? catalog[defaultID]
            ?? SlideTheme(id: defaultID, values: [:])
        theme.apply(settings.themeOverrides)
        return theme
    }
}
