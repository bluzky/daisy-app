//
//  DocxTheme.swift
//  daisy
//
//  The look of a DOCX export, as data. App-only: the Quick Look extension does
//  not compile this file. See docs/docx-export-themes.md.
//
//  A theme file is decoded leniently (unknown keys and wrong-typed values are
//  dropped, never fatal), validated, has its `$palette` references resolved,
//  and is overlaid field by field on the built-in GitHub theme. What remains
//  in `elements` is therefore a set of *sparse declarations*: only properties
//  that were explicitly set, with colors as `RRGGBB`. Those drive styles.xml.
//  `resolved(_:)` answers "what is the effective value" for layout decisions.
//

import Foundation

nonisolated struct DocxTheme: Sendable, Identifiable, Equatable {
    var id: String
    var name: String
    var global: GlobalStyle
    var page: PageStyle
    /// Validated sparse declarations, already overlaid on GitHub's.
    var elements: [Element: ElementStyle]
    /// Overlaid on GitHub's; a missing token inherits GitHub's value.
    var syntax: [SyntaxToken: SyntaxColor]

    enum Element: String, CaseIterable, Sendable {
        case paragraph, heading1, heading2, heading3, heading4, heading5, heading6
        case link, list, quote, rule, codeBlock, inlineCode
        case table, tableHeader, tableBody

        static func heading(_ level: Int) -> Element {
            switch min(max(level, 1), 6) {
            case 1: return .heading1
            case 2: return .heading2
            case 3: return .heading3
            case 4: return .heading4
            case 5: return .heading5
            default: return .heading6
            }
        }
    }

    struct GlobalStyle: Sendable, Equatable {
        var font: String
        var size: Double
        var language: String
        var lineHeight: Double
        var spaceAfter: Double
        /// nil = no `w:color` emitted (Word's automatic color).
        var color: String?
        var palette: [String: String]
    }

    struct PageStyle: Sendable, Equatable {
        var margin: Double
    }

    func declarations(_ element: Element) -> ElementStyle {
        elements[element] ?? ElementStyle()
    }

    /// nil = emit no color on the run (`SyntaxColor.disabled`).
    func syntaxColor(_ token: SyntaxToken) -> String? {
        if case .color(let hex)? = syntax[token] ?? Self.github.syntax[token] { return hex }
        return nil
    }

    /// Effective values for layout and direct-formatting decisions: the
    /// declaration, then the theme's global, then a neutral default. Never use
    /// this as an emission list; Word's own cascade is not modelled here.
    func resolved(_ element: Element) -> ResolvedStyle {
        let own = declarations(element)
        return ResolvedStyle(
            font: own.font ?? global.font,
            size: own.size ?? global.size,
            bold: own.bold ?? false,
            italic: own.italic ?? false,
            underline: own.underline ?? false,
            strike: own.strike ?? false,
            color: own.color ?? global.color,
            background: own.background,
            border: own.border ?? Borders(),
            indent: own.indent ?? 0,
            indentRight: own.indentRight ?? 0,
            hanging: own.hanging ?? 0,
            spaceBefore: own.spaceBefore ?? 0,
            spaceAfter: own.spaceAfter ?? global.spaceAfter,
            lineHeight: own.lineHeight ?? global.lineHeight,
            markerFont: own.markerFont,
            cellPadding: own.cellPadding ?? CellPadding())
    }
}

// MARK: - Element style

nonisolated struct ElementStyle: Sendable, Equatable {
    var font: String?
    var color: String?
    var background: String?
    var markerFont: String?
    var size: Double?
    var lineHeight: Double?
    var indent: Double?
    var indentRight: Double?
    var hanging: Double?
    var spaceBefore: Double?
    var spaceAfter: Double?
    var bold: Bool?
    var italic: Bool?
    var underline: Bool?
    var strike: Bool?
    var border: Borders?
    var cellPadding: CellPadding?

    init() {}

    var isEmpty: Bool { self == ElementStyle() }

    /// The text properties (the ones a run can carry).
    var text: ElementStyle {
        var result = ElementStyle()
        result.font = font
        result.size = size
        result.color = color
        result.bold = bold
        result.italic = italic
        result.underline = underline
        result.strike = strike
        return result
    }

    /// Field-by-field overlay: `self` wins, `base` fills the gaps.
    func overlaid(on base: ElementStyle) -> ElementStyle {
        var result = base
        if let value = font { result.font = value }
        if let value = color { result.color = value }
        if let value = background { result.background = value }
        if let value = markerFont { result.markerFont = value }
        if let value = size { result.size = value }
        if let value = lineHeight { result.lineHeight = value }
        if let value = indent { result.indent = value }
        if let value = indentRight { result.indentRight = value }
        if let value = hanging { result.hanging = value }
        if let value = spaceBefore { result.spaceBefore = value }
        if let value = spaceAfter { result.spaceAfter = value }
        if let value = bold { result.bold = value }
        if let value = italic { result.italic = value }
        if let value = underline { result.underline = value }
        if let value = strike { result.strike = value }
        if let value = border { result.border = value.overlaid(on: base.border ?? Borders()) }
        if let value = cellPadding {
            result.cellPadding = value.overlaid(on: base.cellPadding ?? CellPadding())
        }
        return result
    }

    /// Drops every property the element does not honour (§3.2 of the proposal).
    func filtered(for element: DocxTheme.Element) -> ElementStyle {
        var keep = Set<Property>()
        switch element {
        case .paragraph, .link:
            keep = Property.text
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6:
            keep = Property.text.union([.spaceBefore, .spaceAfter])
        case .list:
            keep = [.indent, .hanging, .spaceAfter, .markerFont]
        case .quote:
            keep = Property.text.union([.border, .indent, .spaceBefore, .spaceAfter])
        case .rule:
            keep = [.border]
        case .codeBlock:
            keep = Property.text.union([
                .background, .border, .indent, .indentRight, .spaceBefore, .spaceAfter, .lineHeight,
            ])
        case .inlineCode:
            keep = Property.text.union([.background])
        case .table:
            keep = [.border, .cellPadding]
        case .tableHeader, .tableBody:
            keep = Property.text.union([.background])
        }
        var result = ElementStyle()
        if keep.contains(.font) { result.font = font }
        if keep.contains(.size) { result.size = size }
        if keep.contains(.color) { result.color = color }
        if keep.contains(.bold) { result.bold = bold }
        if keep.contains(.italic) { result.italic = italic }
        if keep.contains(.underline) { result.underline = underline }
        if keep.contains(.strike) { result.strike = strike }
        if keep.contains(.background) { result.background = background }
        if keep.contains(.border) {
            result.border = border
            // `inside` (lines between cells) only means something on a table.
            if element != .table { result.border?.inside = nil }
            if result.border?.isEmpty == true { result.border = nil }
        }
        if keep.contains(.indent) { result.indent = indent }
        if keep.contains(.indentRight) { result.indentRight = indentRight }
        if keep.contains(.hanging) { result.hanging = hanging }
        if keep.contains(.spaceBefore) { result.spaceBefore = spaceBefore }
        if keep.contains(.spaceAfter) { result.spaceAfter = spaceAfter }
        if keep.contains(.lineHeight) { result.lineHeight = lineHeight }
        if keep.contains(.markerFont) { result.markerFont = markerFont }
        if keep.contains(.cellPadding) { result.cellPadding = cellPadding }
        return result
    }

    fileprivate enum Property {
        case font, size, color, bold, italic, underline, strike
        case background, border, indent, indentRight, hanging
        case spaceBefore, spaceAfter, lineHeight, markerFont, cellPadding

        static let text: Set<Property> = [.font, .size, .color, .bold, .italic, .underline, .strike]
    }
}

nonisolated struct BorderSide: Sendable, Equatable {
    var width: Double?
    var space: Double?
    var color: String?
    var style: String?

    func overlaid(on base: BorderSide) -> BorderSide {
        BorderSide(
            width: width ?? base.width,
            space: space ?? base.space,
            color: color ?? base.color,
            style: style ?? base.style)
    }
}

/// `all` in a theme file is expanded when decoding: onto the four sides, and
/// onto `inside` (the lines between table cells; other elements ignore it). A
/// specific side then wins over `all`.
nonisolated struct Borders: Sendable, Equatable {
    var top: BorderSide?
    var left: BorderSide?
    var bottom: BorderSide?
    var right: BorderSide?
    var inside: BorderSide?

    var isEmpty: Bool { self == Borders() }

    func overlaid(on base: Borders) -> Borders {
        func merge(_ top: BorderSide?, _ base: BorderSide?) -> BorderSide? {
            switch (top, base) {
            case let (top?, base?): return top.overlaid(on: base)
            case let (top?, nil): return top
            case let (nil, base): return base
            }
        }
        return Borders(
            top: merge(top, base.top), left: merge(left, base.left),
            bottom: merge(bottom, base.bottom), right: merge(right, base.right),
            inside: merge(inside, base.inside))
    }
}

nonisolated struct CellPadding: Sendable, Equatable {
    var vertical: Double?
    var horizontal: Double?

    func overlaid(on base: CellPadding) -> CellPadding {
        CellPadding(
            vertical: vertical ?? base.vertical,
            horizontal: horizontal ?? base.horizontal)
    }
}

nonisolated struct ResolvedStyle: Sendable, Equatable {
    var font: String
    var size: Double
    var bold: Bool
    var italic: Bool
    var underline: Bool
    var strike: Bool
    /// nil = automatic (no `w:color`).
    var color: String?
    var background: String?
    var border: Borders
    var indent: Double
    var indentRight: Double
    var hanging: Double
    var spaceBefore: Double
    var spaceAfter: Double
    var lineHeight: Double
    var markerFont: String?
    var cellPadding: CellPadding
}

// MARK: - Syntax

nonisolated enum SyntaxToken: String, CaseIterable, Sendable {
    case keyword, title, titleClass, string, number, comment
    case doctag, type, builtIn, property, meta, attribute
}

/// Tri-state for syntax colors; a missing key (inherit) is the third state.
nonisolated enum SyntaxColor: Sendable, Equatable, Decodable {
    case color(String)
    /// `null` or `""`: no color for this token.
    case disabled

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .disabled
            return
        }
        let text = try container.decode(String.self)
        if text.isEmpty {
            self = .disabled
        } else if let hex = DocxThemeValidation.color(text) {
            self = .color(hex)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Not a RRGGBB color")
        }
    }
}

// MARK: - Validation

/// Everything that can reach an XML attribute goes through here first.
nonisolated enum DocxThemeValidation {
    static func color(_ text: String) -> String? {
        var hex = text.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.utf8.count == 6, hex.utf8.allSatisfy(\.isHexDigit) else { return nil }
        return hex.uppercased()
    }

    static func fontName(_ text: String) -> String? {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...64).contains(name.count) else { return nil }
        for scalar in name.unicodeScalars {
            if scalar.properties.generalCategory == .control { return nil }
            if "<>&\"'".unicodeScalars.contains(scalar) { return nil }
        }
        return name
    }

    static func language(_ text: String) -> String? {
        let pattern = "^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$"
        return text.range(of: pattern, options: .regularExpression) != nil ? text : nil
    }

    static let borderStyles: Set<String> = [
        "single", "double", "dotted", "dashed", "dotDash", "thick", "none",
    ]

    static func borderStyle(_ text: String) -> String {
        borderStyles.contains(text) ? text : "single"
    }

    static func identifier(_ text: String) -> String? {
        text.range(of: "^[a-z0-9-]{1,32}$", options: .regularExpression) != nil ? text : nil
    }

    static func paletteKey(_ text: String) -> Bool {
        text.range(of: "^[A-Za-z][A-Za-z0-9_]{0,31}$", options: .regularExpression) != nil
    }

    /// Finite and inside `range`, else nil (= unset).
    static func number(_ value: Double?, in range: ClosedRange<Double>) -> Double? {
        guard let value, value.isFinite, range.contains(value) else { return nil }
        return value
    }

    enum Range {
        static let size = 1.0...400.0
        static let length = 0.0...1000.0
        static let lineHeight = 0.5...5.0
        static let borderWidth = 0.0...12.0
        static let borderSpace = 0.0...31.0
        static let cellPadding = 0.0...100.0
        static let margin = 0.0...300.0
    }
}

nonisolated private extension UInt8 {
    var isHexDigit: Bool {
        (0x30...0x39).contains(self) || (0x41...0x46).contains(self) || (0x61...0x66).contains(self)
    }
}

// MARK: - Lenient decoding

nonisolated private struct DynamicKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// What a theme file says before validation: strings are raw, `$name` is
/// unresolved.
nonisolated private struct RawElementStyle: Decodable {
    var font, color, background, markerFont: String?
    var size, lineHeight, indent, indentRight, hanging, spaceBefore, spaceAfter: Double?
    var bold, italic, underline, strike: Bool?
    var border: [String: RawBorderSide]?
    var cellPadding: RawCellPadding?

    private enum CodingKeys: String, CodingKey {
        case font, color, background, markerFont, size, lineHeight, indent, indentRight
        case hanging, spaceBefore, spaceAfter, bold, italic, underline, strike
        case border, cellPadding
    }

    /// A wrong-typed property is dropped alone, not the whole element.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys) -> T? {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? nil
        }
        font = value(.font)
        color = value(.color)
        background = value(.background)
        markerFont = value(.markerFont)
        size = value(.size)
        lineHeight = value(.lineHeight)
        indent = value(.indent)
        indentRight = value(.indentRight)
        hanging = value(.hanging)
        spaceBefore = value(.spaceBefore)
        spaceAfter = value(.spaceAfter)
        bold = value(.bold)
        italic = value(.italic)
        underline = value(.underline)
        strike = value(.strike)
        cellPadding = value(.cellPadding)
        if let sides = try? c.nestedContainer(keyedBy: DynamicKey.self, forKey: .border) {
            var result: [String: RawBorderSide] = [:]
            for key in sides.allKeys {
                if let side = try? sides.decode(RawBorderSide.self, forKey: key) {
                    result[key.stringValue] = side
                }
            }
            border = result
        }
    }
}

nonisolated private struct RawBorderSide: Decodable {
    var width, space: Double?
    var color, style: String?

    private enum CodingKeys: String, CodingKey { case width, space, color, style }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        width = (try? c.decodeIfPresent(Double.self, forKey: .width)) ?? nil
        space = (try? c.decodeIfPresent(Double.self, forKey: .space)) ?? nil
        color = (try? c.decodeIfPresent(String.self, forKey: .color)) ?? nil
        style = (try? c.decodeIfPresent(String.self, forKey: .style)) ?? nil
    }
}

nonisolated private struct RawCellPadding: Decodable {
    var vertical, horizontal: Double?

    private enum CodingKeys: String, CodingKey { case vertical, horizontal }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        vertical = (try? c.decodeIfPresent(Double.self, forKey: .vertical)) ?? nil
        horizontal = (try? c.decodeIfPresent(Double.self, forKey: .horizontal)) ?? nil
    }
}

nonisolated private struct RawGlobal: Decodable {
    var font: String?
    var size, lineHeight, spaceAfter: Double?
    var language, color: String?
    var palette: [String: String] = [:]

    private enum CodingKeys: String, CodingKey {
        case font, size, language, lineHeight, spaceAfter, color, palette
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        font = (try? c.decodeIfPresent(String.self, forKey: .font)) ?? nil
        size = (try? c.decodeIfPresent(Double.self, forKey: .size)) ?? nil
        language = (try? c.decodeIfPresent(String.self, forKey: .language)) ?? nil
        lineHeight = (try? c.decodeIfPresent(Double.self, forKey: .lineHeight)) ?? nil
        spaceAfter = (try? c.decodeIfPresent(Double.self, forKey: .spaceAfter)) ?? nil
        color = (try? c.decodeIfPresent(String.self, forKey: .color)) ?? nil
        if let entries = try? c.nestedContainer(keyedBy: DynamicKey.self, forKey: .palette) {
            for key in entries.allKeys {
                if let text = try? entries.decode(String.self, forKey: key) {
                    palette[key.stringValue] = text
                }
            }
        }
    }
}

nonisolated extension DocxTheme: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, name, global, page, elements, syntax
    }

    private enum PageKeys: String, CodingKey { case margin }

    /// Lenient: only `id` and `name` are required. Everything else that is
    /// missing, unknown, wrong-typed or out of range falls back to GitHub's.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawID = try c.decode(String.self, forKey: .id)
        guard let id = DocxThemeValidation.identifier(rawID) else {
            throw DecodingError.dataCorruptedError(
                forKey: .id, in: c, debugDescription: "Invalid theme id")
        }
        let name = try c.decode(String.self, forKey: .name)
        let base = DocxTheme.github

        // Global: each field is overlaid independently on GitHub's.
        let rawGlobal = try? c.decode(RawGlobal.self, forKey: .global)
        var palette = base.global.palette
        for (key, text) in rawGlobal?.palette ?? [:] {
            if DocxThemeValidation.paletteKey(key), let hex = DocxThemeValidation.color(text) {
                palette[key] = hex
            }
        }
        func resolveColor(_ text: String?) -> String? {
            guard var text else { return nil }
            text = text.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("$") { return palette[String(text.dropFirst())] }
            return DocxThemeValidation.color(text)
        }
        var global = base.global
        global.palette = palette
        if let font = rawGlobal?.font.flatMap(DocxThemeValidation.fontName) { global.font = font }
        if let size = DocxThemeValidation.number(rawGlobal?.size, in: DocxThemeValidation.Range.size) {
            global.size = size
        }
        if let language = rawGlobal?.language.flatMap(DocxThemeValidation.language) {
            global.language = language
        }
        if let value = DocxThemeValidation.number(
            rawGlobal?.lineHeight, in: DocxThemeValidation.Range.lineHeight) {
            global.lineHeight = value
        }
        if let value = DocxThemeValidation.number(
            rawGlobal?.spaceAfter, in: DocxThemeValidation.Range.length) {
            global.spaceAfter = value
        }
        global.color = resolveColor(rawGlobal?.color)

        var page = base.page
        if let pageContainer = try? c.nestedContainer(keyedBy: PageKeys.self, forKey: .page),
           let margin = DocxThemeValidation.number(
            (try? pageContainer.decodeIfPresent(Double.self, forKey: .margin)) ?? nil,
            in: DocxThemeValidation.Range.margin) {
            page.margin = margin
        }

        // Elements: unknown names and undecodable values are skipped.
        var elements = base.elements
        if let container = try? c.nestedContainer(keyedBy: DynamicKey.self, forKey: .elements) {
            for key in container.allKeys {
                guard let element = Element(rawValue: key.stringValue),
                      let raw = try? container.decode(RawElementStyle.self, forKey: key)
                else { continue }
                let declared = Self.sanitize(raw, resolveColor: resolveColor).filtered(for: element)
                elements[element] = declared.overlaid(on: base.elements[element] ?? ElementStyle())
            }
        }

        var syntax = base.syntax
        if let container = try? c.nestedContainer(keyedBy: DynamicKey.self, forKey: .syntax) {
            for key in container.allKeys {
                guard let token = SyntaxToken(rawValue: key.stringValue),
                      let value = try? container.decode(SyntaxColor.self, forKey: key)
                else { continue }
                syntax[token] = value
            }
        }

        self.init(id: id, name: name, global: global, page: page, elements: elements, syntax: syntax)
    }

    private static func sanitize(
        _ raw: RawElementStyle, resolveColor: (String?) -> String?
    ) -> ElementStyle {
        typealias V = DocxThemeValidation
        var style = ElementStyle()
        style.font = raw.font.flatMap(V.fontName)
        style.markerFont = raw.markerFont.flatMap(V.fontName)
        style.color = resolveColor(raw.color)
        style.background = resolveColor(raw.background)
        style.size = V.number(raw.size, in: V.Range.size)
        style.lineHeight = V.number(raw.lineHeight, in: V.Range.lineHeight)
        style.indent = V.number(raw.indent, in: V.Range.length)
        style.indentRight = V.number(raw.indentRight, in: V.Range.length)
        style.hanging = V.number(raw.hanging, in: V.Range.length)
        style.spaceBefore = V.number(raw.spaceBefore, in: V.Range.length)
        style.spaceAfter = V.number(raw.spaceAfter, in: V.Range.length)
        style.bold = raw.bold
        style.italic = raw.italic
        style.underline = raw.underline
        style.strike = raw.strike
        if let padding = raw.cellPadding {
            let value = CellPadding(
                vertical: V.number(padding.vertical, in: V.Range.cellPadding),
                horizontal: V.number(padding.horizontal, in: V.Range.cellPadding))
            if value != CellPadding() { style.cellPadding = value }
        }
        if let sides = raw.border {
            func side(_ raw: RawBorderSide?) -> BorderSide? {
                guard let raw else { return nil }
                let value = BorderSide(
                    width: V.number(raw.width, in: V.Range.borderWidth),
                    space: V.number(raw.space, in: V.Range.borderSpace),
                    color: resolveColor(raw.color),
                    style: raw.style.map(V.borderStyle))
                return value == BorderSide() ? nil : value
            }
            // `all` first, then a specific side overlays it.
            let all = side(sides["all"])
            func specific(_ name: String) -> BorderSide? {
                switch (side(sides[name]), all) {
                case let (own?, all?): return own.overlaid(on: all)
                case let (own?, nil): return own
                case let (nil, all): return all
                }
            }
            let borders = Borders(
                top: specific("top"), left: specific("left"),
                bottom: specific("bottom"), right: specific("right"), inside: all)
            if !borders.isEmpty { style.border = borders }
        }
        return style
    }
}

// MARK: - Built-in GitHub theme

nonisolated extension DocxTheme {
    /// Today's look. The bundled `docx-theme-github.json` must decode to
    /// exactly this value.
    static let github: DocxTheme = {
        let ink = "1F2328", muted = "59636E", border = "BFC5CC", surface = "F6F8FA"

        func text(
            size: Double? = nil, bold: Bool? = nil, color: String? = nil,
            before: Double? = nil, after: Double? = nil
        ) -> ElementStyle {
            var style = ElementStyle()
            style.size = size
            style.bold = bold
            style.color = color
            style.spaceBefore = before
            style.spaceAfter = after
            return style
        }
        func side(_ width: Double, _ space: Double?, _ color: String) -> BorderSide {
            BorderSide(width: width, space: space, color: color, style: "single")
        }

        var elements: [Element: ElementStyle] = [:]
        elements[.paragraph] = ElementStyle()
        let headingSizes: [Double] = [20, 16, 14, 12, 11, 11]
        for (index, size) in headingSizes.enumerated() {
            let level = index + 1
            elements[.heading(level)] = text(
                size: size, bold: true, color: level == 6 ? muted : ink,
                before: level == 1 ? 18 : 14, after: 6)
        }
        var link = ElementStyle()
        link.color = "0969DA"
        link.underline = true
        elements[.link] = link

        var list = ElementStyle()
        list.spaceAfter = 3
        list.indent = 36
        list.hanging = 18
        list.markerFont = "Calibri"
        elements[.list] = list

        var quote = ElementStyle()
        quote.color = muted
        quote.indent = 28.35
        quote.border = Borders(left: side(2.25, 8, border))
        elements[.quote] = quote

        var rule = ElementStyle()
        rule.border = Borders(bottom: side(0.75, 1, border))
        elements[.rule] = rule

        var code = ElementStyle()
        code.font = "Menlo"
        code.size = 10
        code.background = surface
        code.lineHeight = 1.0
        code.spaceBefore = 6
        code.spaceAfter = 0
        code.indent = 5.65
        code.indentRight = 5.65
        let codeSide = side(0.5, 4, "E1E4E8")
        code.border = Borders(top: codeSide, left: codeSide, bottom: codeSide, right: codeSide)
        elements[.codeBlock] = code

        var inline = ElementStyle()
        inline.font = "Menlo"
        inline.size = 10
        inline.color = "1F2328"
        inline.background = "EFF1F3"
        elements[.inlineCode] = inline

        var table = ElementStyle()
        let tableSide = side(0.5, 0, border)
        table.border = Borders(
            top: tableSide, left: tableSide, bottom: tableSide, right: tableSide, inside: tableSide)
        table.cellPadding = CellPadding(vertical: 3, horizontal: 5)
        elements[.table] = table

        var header = ElementStyle()
        header.bold = true
        header.background = "F2F4F7"
        elements[.tableHeader] = header
        elements[.tableBody] = ElementStyle()

        let syntax: [SyntaxToken: SyntaxColor] = [
            .keyword: .color("9B2393"), .title: .color("0F68A0"), .titleClass: .color("0B4F79"),
            .string: .color("C41A16"), .number: .color("1C00CF"), .comment: .color("5D6C79"),
            .doctag: .color("4A5560"), .type: .color("3900A0"), .builtIn: .color("6C36A9"),
            .property: .color("326D74"), .meta: .color("643820"), .attribute: .color("815F03"),
        ]

        return DocxTheme(
            id: "github", name: "GitHub",
            global: GlobalStyle(
                font: "Calibri", size: 11, language: "en-US", lineHeight: 1.15, spaceAfter: 6,
                color: nil,
                palette: ["muted": muted, "border": border, "surface": surface]),
            page: PageStyle(margin: 72),
            elements: elements,
            syntax: syntax)
    }()
}
