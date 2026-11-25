//
//  Theme+Slides.swift
//  daisy
//
//  A theme on a slide deck: the deck's `theme:` and `theme_overrides:`, and
//  the CSS that puts the theme's tokens on the slides. Colors go through the
//  variables the page already uses, so `invert`, `dim` and `color`
//  directives, which set colors on a slide, still win.
//

import Foundation

nonisolated extension Theme {
    /// `theme: default` (or no `theme:`) keeps the reading theme.
    static let readingThemeID = "default"

    // MARK: - The deck's theme

    /// The deck's theme (`theme:`; `default` or an unknown name keeps the
    /// reading theme) with its `theme_overrides:` and `font_size` applied.
    static func forDeck(_ settings: SlideDeckSettings, in catalog: [String: Theme]) -> Theme {
        if let id = settings.theme, id != readingThemeID, var theme = catalog[id] {
            theme.applyOverrides(settings.themeOverrides)
            theme.applyDeckFontSize(settings.fontSize)
            return theme
        }
        var theme = Theme(id: readingThemeID, name: "Reading theme", appearance: .system)
        theme.applyOverrides(settings.themeOverrides)
        // Overrides on the reading theme pin the slides' scheme when their
        // background says light or dark, so code colors stay readable.
        if theme.appearance == .system, settings.themeOverrides["appearance"] == nil,
           let background = theme.light["bg"], let luminance = luminance(ofHex: background) {
            theme.appearance = luminance < 0.5 ? .dark : .light
            theme.dark = [:]
        }
        theme.applyDeckFontSize(settings.fontSize)
        return theme
    }

    private mutating func applyDeckFontSize(_ size: Double?) {
        // `font_size` in the frontmatter is the deck's own word on it.
        guard let size else { return }
        light["slide-font-size"] = "\(size / SlideDeck.defaultFontSize * 100)%"
    }

    /// `theme_overrides:` `colors:` keys and the token each sets.
    static let overrideColorTokens: [String: String] = {
        var tokens = [
            "background": "bg", "text": "text", "heading": "heading", "accent": "link",
            "bold": "bold", "code_background": "code-bg",
            "primary": "slide-title-bg", "title_text": "slide-title-text",
            "table_header": "table-header-bg", "table_header_text": "table-header-text",
            "table_border": "table-border", "table_stripe": "table-stripe",
        ]
        for color in WidgetColor.allCases {
            tokens[color.slideThemeKey] = String(color.cssProperty.dropFirst(2))
        }
        return tokens
    }()

    /// `theme_overrides:` `fonts:` keys and the token each sets; `size` is
    /// the slide font size.
    static let overrideFontTokens = ["body": "font-body", "title": "font-heading", "code": "font-code"]

    /// Applies a deck's `theme_overrides:` (`colors:`, `fonts:`,
    /// `table: { style: }`, `appearance:`, `header:`, `footer:`) to both
    /// palettes. Colors are hex, as in theme files; invalid values are dropped.
    mutating func applyOverrides(_ values: [String: SlideYAML.Value]) {
        var tokens: [String: String] = [:]
        for (key, value) in values["colors"]?.map ?? [:] {
            guard let token = Self.overrideColorTokens[key.lowercased()],
                  let color = value.string.flatMap({ Self.sanitized($0, token: token) }) else { continue }
            tokens[token] = color
        }
        // `primary` also colors links when nothing else does.
        if let primary = tokens["slide-title-bg"], tokens["link"] == nil, light["link"] == nil {
            tokens["link"] = primary
        }
        if let style = values["table"]?["style"]?.string,
           let sanitized = Self.sanitized(style, token: "table-style") {
            tokens["table-style"] = sanitized
        }
        for (key, value) in values["fonts"]?.map ?? [:] {
            let key = key.lowercased()
            if key == "size" {
                if let size = value.string, SlideDeck.fontSize(size) != nil { tokens["slide-font-size"] = size }
            } else if let token = Self.overrideFontTokens[key],
                      let font = value.string.flatMap(Self.sanitizedFontFamily) {
                tokens[token] = font
            }
        }
        if let raw = values["appearance"]?.string?.lowercased(),
           let pinned = Appearance(rawValue: raw), pinned != .system {
            light = palette(for: pinned)
            dark = [:]
            appearance = pinned
        }
        if let header = Self.chromeTemplate(values["header"]) { self.header = header }
        if let footer = Self.chromeTemplate(values["footer"]) { self.footer = footer }
        light.merge(tokens) { $1 }
        if appearance == .system {
            dark.merge(tokens.filter { !Self.rootOnlyTokens.contains($0.key) }) { $1 }
        }
    }

    /// Relative luminance (0 black – 1 white) of `#rgb` / `#rrggbb[aa]`.
    static func luminance(ofHex value: String) -> Double? {
        guard let hex = expandedHexColor(value), let rgb = Int(hex.dropFirst().prefix(6), radix: 16)
        else { return nil }
        let channel = { (shift: Int) -> Double in
            let c = Double((rgb >> shift) & 0xff) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }

    // MARK: - CSS

    private typealias Declaration = (property: String, value: String)

    private static let slideScope = ":where(.mdp-deck) .mdp-slide"

    /// Custom properties and font rules scoped to the slides. A theme that
    /// follows the system gets its dark palette from the same color-scheme
    /// attribute and media query the page uses.
    var slideCSS: String {
        let lightTokens = palette(for: .light)
        let darkTokens = palette(for: .dark)
        // Two palettes on the slides: rules read them through variables.
        let splitsSchemes = pinnedDark == nil && (lightTokens != darkTokens || usesDefaultLook)

        var deck: [String] = []
        // Code colors and system colors follow the slides, not the window:
        // a dark theme in a light window still gets dark-mode code colors.
        if let isDark = pinnedDark {
            deck.append("color-scheme: \(isDark ? "dark" : "light"); --hl-plain: var(--text);")
            deck.append((isDark ? MarkdownHTML.darkCodePaletteCSS : MarkdownHTML.lightCodePaletteCSS)
                .replacingOccurrences(of: "\n", with: " "))
            deck.append(isDark
                ? "--code-bg: #262626; --widget-card: #262626; --code-border: #323232; "
                    + "--quote-border: rgb(255 255 255 / 25%); --grid: rgb(255 255 255 / 20%);"
                : "--code-bg: #f9f9f9; --widget-card: #f9f9f9; --code-border: #f0f0f0; "
                    + "--quote-border: rgb(0 0 0 / 15%); --grid: rgb(0 0 0 / 15%);")
        }
        let lightDeclarations = (usesDefaultLook ? Self.defaultLook(dark: pinnedDark == true) : [])
            + Self.declarations(lightTokens, viaVariables: splitsSchemes)
        deck += lightDeclarations.map { "\($0.property): \($0.value);" }
        if let size = lightTokens["slide-font-size"].flatMap(SlideDeck.fontSize) {
            deck.append("--mdp-font-size: \(SlideDeck.cqw(size));")
        }

        var rules: [String] = []
        // On the slides only: the notes under them in Read Mode stay in the
        // page's colors. `:where` keeps it below a slide's own classes.
        if !deck.isEmpty { rules.append("\(Self.slideScope) { \(deck.joined(separator: " ")) }") }
        if splitsSchemes {
            var darkDeclarations = (usesDefaultLook ? Self.defaultLook(dark: true) : [])
                + Self.declarations(darkTokens, viaVariables: true)
            // A value only the light palette sets goes back to the page's
            // own in dark.
            let darkProperties = Set(darkDeclarations.map(\.property))
            for declaration in lightDeclarations where !darkProperties.contains(declaration.property) {
                darkDeclarations.append((declaration.property, "inherit"))
            }
            if !darkDeclarations.isEmpty {
                let body = darkDeclarations.map { "\($0.property): \($0.value);" }.joined(separator: " ")
                rules.append(":where(:root[data-mdp-color-scheme=\"dark\"] .mdp-deck) .mdp-slide { \(body) }")
                rules.append("""
                @media (prefers-color-scheme: dark) {
                    :where(:root:not([data-mdp-color-scheme="light"]) .mdp-deck) .mdp-slide { \(body) }
                }
                """)
            }
        }

        let palettes = splitsSchemes ? [lightTokens, darkTokens] : [lightTokens]
        let sets = { (token: String) in palettes.contains { $0[token] != nil } }
        if sets("link") {
            let link = splitsSchemes ? "var(--link)" : lightTokens["link"]!
            rules.append(".mdp-deck .mdp-slide li::marker { color: \(link); }")
        }
        if sets("bold") {
            let bold = splitsSchemes ? "var(--bold, currentColor)" : lightTokens["bold"]!
            rules.append(".mdp-deck .mdp-slide :is(strong, b) { color: \(bold); }")
        }
        if sets("slide-title-bg") {
            let background = splitsSchemes ? "var(--mdp-title-bg, Canvas)" : lightTokens["slide-title-bg"]!
            let text = splitsSchemes
                ? "var(--mdp-title-text, #ffffff)" : lightTokens["slide-title-text"] ?? "#ffffff"
            rules.append("""
            .mdp-deck :where(.mdp-slide--title, .mdp-slide--section) { \
            --mdp-slide-bg: \(background); --text: \(text); \
            --secondary: color-mix(in srgb, \(text) 80%, transparent); \
            --heading: \(text); }
            """)
        }
        if let style = lightTokens["table-style"].flatMap(MarkdownHTML.TableStyle.init(rawValue:)),
           style != .lines {
            rules.append(MarkdownHTML.tableStyleRules(style, scope: ".mdp-deck .mdp-slide "))
        }
        if let weight = lightTokens["body-weight"] {
            rules.append(".mdp-deck .mdp-slide { font-weight: \(weight); }")
        }
        if let body = lightTokens["font-body"] {
            rules.append(".mdp-deck .mdp-slide { font-family: \(body); }")
        }
        if let heading = lightTokens["font-heading"] {
            rules.append(".mdp-deck .mdp-slide :is(h1, h2, h3, h4, h5, h6) { font-family: \(heading); }")
        }
        if let code = lightTokens["font-code"] {
            rules.append(".mdp-deck .mdp-slide :is(code, pre, kbd, samp) { font-family: \(code); }")
        }
        return rules.joined(separator: "\n")
    }

    /// One palette's custom properties on a slide. With `viaVariables`,
    /// the bold and title-slide colors become variables too, for rules that
    /// must follow the scheme.
    private static func declarations(_ tokens: [String: String], viaVariables: Bool) -> [Declaration] {
        var result: [Declaration] = []
        if let background = tokens["bg"] { result.append(("--mdp-slide-bg", background)) }
        if let text = tokens["text"] {
            result.append(("--text", text))
            result.append(("--secondary", "color-mix(in srgb, \(text) 70%, transparent)"))
        }
        let levels = (1...6).map { "heading-\($0)" }
        if let heading = tokens["heading"] {
            result.append(("--heading", heading))
        } else if tokens["bg"] != nil || tokens["text"] != nil {
            // A reading theme's heading color doesn't belong on slides with
            // their own background and text.
            result.append(("--heading", "initial"))
            for level in levels where tokens[level] == nil { result.append(("--\(level)", "initial")) }
        }
        for level in levels { if let color = tokens[level] { result.append(("--\(level)", color)) } }
        if let link = tokens["link"] { result.append(("--link", link)) }
        // The code background is also the stat tile fill.
        if let code = tokens["code-bg"] {
            result.append(("--code-bg", code))
            result.append(("--widget-card", code))
        }
        for token in ["table-header-bg", "table-header-text", "table-border", "table-stripe"] {
            if let color = tokens[token] { result.append(("--\(token)", color)) }
        }
        for color in WidgetColor.allCases {
            if let value = tokens[String(color.cssProperty.dropFirst(2))] { result.append((color.cssProperty, value)) }
        }
        if viaVariables {
            if let bold = tokens["bold"] { result.append(("--bold", bold)) }
            if let title = tokens["slide-title-bg"] { result.append(("--mdp-title-bg", title)) }
            if let text = tokens["slide-title-text"] { result.append(("--mdp-title-text", text)) }
        }
        return result
    }

    /// The stylesheet's own colors, for Original: the reading theme's
    /// overrides don't reach its slides.
    private static func defaultLook(dark: Bool) -> [Declaration] {
        var result: [Declaration] = [
            ("--text", "-apple-system-label"),
            ("--secondary", "-apple-system-secondary-label"),
            ("--link", dark ? "rgb(65, 156, 255)" : "rgb(0, 104, 218)"),
            ("--code-bg", dark ? "#262626" : "#f9f9f9"),
            ("--widget-card", dark ? "#262626" : "#f9f9f9"),
            ("--heading", "initial"),
        ]
        result += (1...6).map { ("--heading-\($0)", "initial") }
        result += ["table-header-bg", "table-header-text", "table-border", "table-stripe"]
            .map { ("--\($0)", "initial") }
        return result
    }
}
