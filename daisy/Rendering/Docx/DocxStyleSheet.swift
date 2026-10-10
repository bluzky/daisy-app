//
//  DocxStyleSheet.swift
//  daisy
//
//  Turns a DocxTheme into word/styles.xml, and owns the unit conversions and
//  property serializers shared with the exporter's direct formatting.
//  App-only. Child order follows the WordprocessingML schema.
//

import Foundation

// MARK: - Units

nonisolated enum DocxUnits {
    static func halfPoints(_ points: Double) -> Int { Int((points * 2).rounded()) }
    static func twips(_ points: Double) -> Int { Int((points * 20).rounded()) }
    /// `w:sz` on borders is in eighths of a point.
    static func eighths(_ points: Double) -> Int { Int((points * 8).rounded()) }
    /// `w:line` with `lineRule="auto"` is in 240ths of a line.
    static func lineUnits(_ multiple: Double) -> Int { Int((multiple * 240).rounded()) }
}

// MARK: - Serializers

nonisolated enum DocxProperties {
    /// `<w:rPr>` children for the text fields of `style`, in schema order.
    /// `background` is emitted as run shading only when `shading` is true
    /// (character styles; paragraph styles shade the paragraph instead).
    /// `parentBold` / `parentItalic` let an explicit `false` switch off an
    /// inherited `true`.
    static func runProperties(
        _ style: ElementStyle, shading: Bool = false,
        parentBold: Bool = false, parentItalic: Bool = false
    ) -> String {
        var xml = ""
        if let font = style.font {
            let name = xmlEscape(font)
            xml += "<w:rFonts w:ascii=\"\(name)\" w:hAnsi=\"\(name)\" w:cs=\"\(name)\"/>"
        }
        if style.bold == true {
            xml += "<w:b/>"
        } else if style.bold == false, parentBold {
            xml += "<w:b w:val=\"0\"/>"
        }
        if style.italic == true {
            xml += "<w:i/>"
        } else if style.italic == false, parentItalic {
            xml += "<w:i w:val=\"0\"/>"
        }
        if style.strike == true { xml += "<w:strike/>" }
        if let color = style.color { xml += "<w:color w:val=\"\(color)\"/>" }
        if let size = style.size {
            let half = DocxUnits.halfPoints(size)
            xml += "<w:sz w:val=\"\(half)\"/><w:szCs w:val=\"\(half)\"/>"
        }
        if style.underline == true { xml += "<w:u w:val=\"single\"/>" }
        if shading, let background = style.background { xml += shd(background) }
        return xml
    }

    static func shd(_ fill: String) -> String {
        "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"\(fill)\"/>"
    }

    /// One border element, e.g. `<w:left .../>`; "" when the side has no width.
    static func border(_ tag: String, _ side: BorderSide?) -> String {
        guard let side, let width = side.width else { return "" }
        let style = DocxThemeValidation.borderStyle(side.style ?? "single")
        return "<w:\(tag) w:val=\"\(style)\" w:sz=\"\(DocxUnits.eighths(width))\" "
            + "w:space=\"\(Int((side.space ?? 0).rounded()))\" w:color=\"\(side.color ?? "auto")\"/>"
    }

    /// `<w:pBdr>` with sides in schema order, or "" when there are none.
    static func paragraphBorders(_ borders: Borders?) -> String {
        guard let borders else { return "" }
        let sides = border("top", borders.top) + border("left", borders.left)
            + border("bottom", borders.bottom) + border("right", borders.right)
        return sides.isEmpty ? "" : "<w:pBdr>\(sides)</w:pBdr>"
    }

    /// `<w:pPr>` children (borders, shading, spacing, indent) in schema order.
    static func paragraphProperties(_ style: ElementStyle) -> String {
        var xml = paragraphBorders(style.border)
        if let background = style.background { xml += shd(background) }
        if style.spaceBefore != nil || style.spaceAfter != nil || style.lineHeight != nil {
            var attributes = ""
            if let before = style.spaceBefore { attributes += " w:before=\"\(DocxUnits.twips(before))\"" }
            if let after = style.spaceAfter { attributes += " w:after=\"\(DocxUnits.twips(after))\"" }
            if let line = style.lineHeight {
                attributes += " w:line=\"\(DocxUnits.lineUnits(line))\" w:lineRule=\"auto\""
            }
            xml += "<w:spacing\(attributes)/>"
        }
        if style.indent != nil || style.indentRight != nil || style.hanging != nil {
            var attributes = ""
            if let left = style.indent { attributes += " w:left=\"\(DocxUnits.twips(left))\"" }
            if let right = style.indentRight { attributes += " w:right=\"\(DocxUnits.twips(right))\"" }
            if let hanging = style.hanging { attributes += " w:hanging=\"\(DocxUnits.twips(hanging))\"" }
            xml += "<w:ind\(attributes)/>"
        }
        return xml
    }
}

// MARK: - Style sheet

nonisolated enum DocxStyleSheet {
    static func xml(for theme: DocxTheme) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        """
        xml += docDefaults(theme.global)
        let parentBold = theme.declarations(.paragraph).bold == true
        let parentItalic = theme.declarations(.paragraph).italic == true

        // Normal: text overrides only. Spacing comes from docDefaults.
        let normalRun = DocxProperties.runProperties(theme.declarations(.paragraph).text)
        xml += "<w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"Normal\">"
            + "<w:name w:val=\"Normal\"/><w:qFormat/>"
            + (normalRun.isEmpty ? "" : "<w:rPr>\(normalRun)</w:rPr>") + "</w:style>"

        for level in 1...6 {
            let style = theme.declarations(.heading(level))
            // Structural properties are not themed: keep-with-next and outline level.
            let paragraph = "<w:keepNext/><w:keepLines/>"
                + DocxProperties.paragraphProperties(style) + "<w:outlineLvl w:val=\"\(level - 1)\"/>"
            xml += paragraphStyle(
                id: "Heading\(level)", name: "heading \(level)", next: "Normal",
                paragraph: paragraph,
                run: DocxProperties.runProperties(
                    style, parentBold: parentBold, parentItalic: parentItalic))
        }

        // The list's indent and hanging belong to numbering.xml, not the style.
        var list = theme.declarations(.list)
        list.indent = nil
        list.hanging = nil
        xml += paragraphStyle(
            id: "ListParagraph", name: "List Paragraph", next: nil,
            paragraph: DocxProperties.paragraphProperties(list), run: "")

        let quote = theme.declarations(.quote)
        xml += paragraphStyle(
            id: "Quote", name: "Quote", next: nil,
            paragraph: DocxProperties.paragraphProperties(quote),
            run: DocxProperties.runProperties(quote, parentBold: parentBold, parentItalic: parentItalic))

        let code = theme.declarations(.codeBlock)
        xml += paragraphStyle(
            id: "CodeBlock", name: "Code Block", next: nil,
            paragraph: DocxProperties.paragraphProperties(code),
            run: DocxProperties.runProperties(code, parentBold: parentBold, parentItalic: parentItalic))

        xml += characterStyle(
            id: "InlineCode", name: "Inline Code",
            run: DocxProperties.runProperties(theme.declarations(.inlineCode), shading: true))
        xml += characterStyle(
            id: "Hyperlink", name: "Hyperlink",
            run: DocxProperties.runProperties(theme.declarations(.link)))
        return xml + "</w:styles>"
    }

    private static func docDefaults(_ global: DocxTheme.GlobalStyle) -> String {
        let font = xmlEscape(global.font)
        let size = DocxUnits.halfPoints(global.size)
        let color = global.color.map { "<w:color w:val=\"\($0)\"/>" } ?? ""
        return "<w:docDefaults><w:rPrDefault><w:rPr>"
            + "<w:rFonts w:ascii=\"\(font)\" w:hAnsi=\"\(font)\" w:eastAsia=\"\(font)\" w:cs=\"\(font)\"/>"
            + color
            + "<w:sz w:val=\"\(size)\"/><w:szCs w:val=\"\(size)\"/>"
            + "<w:lang w:val=\"\(xmlEscape(global.language))\"/></w:rPr></w:rPrDefault>"
            + "<w:pPrDefault><w:pPr><w:spacing w:after=\"\(DocxUnits.twips(global.spaceAfter))\" "
            + "w:line=\"\(DocxUnits.lineUnits(global.lineHeight))\" w:lineRule=\"auto\"/></w:pPr></w:pPrDefault>"
            + "</w:docDefaults>"
    }

    private static func paragraphStyle(
        id: String, name: String, next: String?, paragraph: String, run: String
    ) -> String {
        "<w:style w:type=\"paragraph\" w:styleId=\"\(id)\"><w:name w:val=\"\(name)\"/>"
            + "<w:basedOn w:val=\"Normal\"/>"
            + (next.map { "<w:next w:val=\"\($0)\"/>" } ?? "")
            + "<w:qFormat/>"
            + (paragraph.isEmpty ? "" : "<w:pPr>\(paragraph)</w:pPr>")
            + (run.isEmpty ? "" : "<w:rPr>\(run)</w:rPr>") + "</w:style>"
    }

    private static func characterStyle(id: String, name: String, run: String) -> String {
        "<w:style w:type=\"character\" w:styleId=\"\(id)\"><w:name w:val=\"\(name)\"/>"
            + (run.isEmpty ? "" : "<w:rPr>\(run)</w:rPr>") + "</w:style>"
    }
}

// MARK: - Escaping

nonisolated func xmlEscape(_ text: String) -> String {
    var result = ""
    result.reserveCapacity(text.utf8.count)
    for scalar in text.unicodeScalars {
        switch scalar {
        case "&": result += "&amp;"
        case "<": result += "&lt;"
        case ">": result += "&gt;"
        case "\"": result += "&quot;"
        case "\t", "\n", "\r": result.unicodeScalars.append(scalar)
        default:
            // XML 1.0 forbids most control characters.
            if scalar.value >= 0x20 && scalar.value != 0xFFFE && scalar.value != 0xFFFF {
                result.unicodeScalars.append(scalar)
            }
        }
    }
    return result
}
