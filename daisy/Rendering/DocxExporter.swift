//
//  DocxExporter.swift
//  daisy
//
//  Writes Markdown as a Word document. App-only: the Quick Look extension
//  does not compile this file.
//
//  A .docx is a ZIP of XML parts. The Markdown AST is walked directly (not the
//  rendered HTML) so headings, lists, code and tables map to real Word
//  structures: real Heading styles, numbered lists, shaded code blocks.
//
//  The look comes from a `DocxTheme` (Docx/DocxTheme.swift): fonts, sizes,
//  colors, borders, spacing, the page margin and the syntax palette. The
//  default `github` theme is Calibri 11 pt body, Menlo 10 pt code, headings
//  20 / 16 / 14 / 12 / 11 / 11 pt, 1 inch margins. Page size is A4 (Letter in
//  US/CA/MX) whatever the theme.
//
//  Mermaid diagrams become pictures when the caller supplies them already
//  rendered (`MermaidRasterizer`, keyed by source); otherwise they export as
//  code. Not exported: math renders as its source text, raw HTML is dropped,
//  and remote images become links.
//

import AppKit
import Foundation
import ImageIO
import Markdown

/// An image ready to embed. `width` / `height` are CSS pixels (96 dpi).
struct DocxImage {
    let data: Data
    let ext: String
    let width: Double
    let height: Double
}

enum DocxExporter {
    static func write(
        markdown: String, assetBaseURL: URL?, theme: DocxTheme = .github,
        mermaidDiagrams: [String: DocxImage] = [:], to url: URL
    ) throws {
        let body = MarkdownFrontmatter.split(markdown).body
        let document = Document(parsing: body)
        var builder = DocxBuilder(
            assetBaseURL: assetBaseURL, theme: theme, mermaidDiagrams: mermaidDiagrams)
        let data = builder.build(document)
        try data.write(to: url, options: .atomic)
    }

    /// Sources of the document's mermaid fences, in the form `write` expects
    /// them as `mermaidDiagrams` keys.
    static func mermaidSources(in markdown: String) -> [String] {
        let document = Document(parsing: MarkdownFrontmatter.split(markdown).body)
        var collector = MermaidCollector()
        collector.visit(document)
        return collector.sources
    }

    fileprivate static func isMermaid(_ code: CodeBlock) -> Bool {
        CodeFenceInfo(rawInfoString: code.language).language == "mermaid"
    }
}

private struct MermaidCollector: MarkupWalker {
    var sources: [String] = []

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        if DocxExporter.isMermaid(codeBlock) { sources.append(codeBlock.code) }
    }
}

// MARK: - Builder

/// Formatting of one run: what Markdown asked for, plus the text defaults of
/// the table cell it sits in. Cell defaults stay separate until serialization
/// so an inline style that defines a property can win over them.
private struct RunStyle {
    var bold = false
    var italic = false
    var strike = false
    var code = false
    var link = false
    /// Text declarations of the enclosing table cell (header or body).
    var cell = ElementStyle()

    init(cell: ElementStyle = ElementStyle()) {
        self.cell = cell
    }

    /// `codeStyle` / `linkStyle` are the sparse `InlineCode` / `Hyperlink`
    /// declarations: any text property they define is dropped from the cell
    /// defaults, so inline code keeps its font and links keep their color.
    func xml(codeStyle: ElementStyle, linkStyle: ElementStyle) -> String {
        var direct = cell
        if code { direct = direct.removingText(definedIn: codeStyle) }
        if link { direct = direct.removingText(definedIn: linkStyle) }
        if bold { direct.bold = true }
        if italic { direct.italic = true }
        if strike { direct.strike = true }
        var props = ""
        if code { props += "<w:rStyle w:val=\"InlineCode\"/>" }
        if link { props += "<w:rStyle w:val=\"Hyperlink\"/>" }
        props += DocxProperties.runProperties(direct)
        return props.isEmpty ? "" : "<w:rPr>\(props)</w:rPr>"
    }
}

private extension ElementStyle {
    func removingText(definedIn other: ElementStyle) -> ElementStyle {
        var result = self
        if other.font != nil { result.font = nil }
        if other.size != nil { result.size = nil }
        if other.color != nil { result.color = nil }
        if other.bold != nil { result.bold = nil }
        if other.italic != nil { result.italic = nil }
        if other.underline != nil { result.underline = nil }
        if other.strike != nil { result.strike = nil }
        return result
    }
}

private struct BlockContext {
    var quoteDepth = 0
    /// Nesting level of the enclosing list item, if any.
    var listLevel: Int?
    var numId: Int?
    var tableCell = false
    /// Text declarations of the table cell being written, if any.
    var tableCellText = ElementStyle()
}

private struct DocxBuilder {
    let assetBaseURL: URL?
    let theme: DocxTheme
    let mermaidDiagrams: [String: DocxImage]

    private var body = ""
    private var relationships: [String] = []
    private var media: [(name: String, data: Data)] = []
    private var mediaExtensions = Set<String>()
    private var orderedLists: [(numId: Int, start: Int)] = []
    private var nextRelationshipID = 1
    private var nextDrawingID = 1

    private static let bulletNumId = 1
    private static let firstOrderedNumId = 2

    private let isLetter = ["US", "CA", "MX"].contains(Locale.current.region?.identifier ?? "")
    private var pageWidth: Int { isLetter ? 12240 : 11906 }
    private var pageHeight: Int { isLetter ? 15840 : 16838 }
    private var margin: Int { DocxUnits.twips(theme.page.margin) }
    private var textWidth: Int { pageWidth - 2 * margin }

    init(assetBaseURL: URL?, theme: DocxTheme, mermaidDiagrams: [String: DocxImage]) {
        self.assetBaseURL = assetBaseURL
        self.theme = theme
        self.mermaidDiagrams = mermaidDiagrams
    }

    mutating func build(_ document: Document) -> Data {
        for child in document.children {
            block(child, BlockContext())
        }
        let documentXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" \
        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" \
        xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" \
        xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" \
        xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">\
        <w:body>\(body)\
        <w:sectPr><w:pgSz w:w="\(pageWidth)" w:h="\(pageHeight)"/>\
        <w:pgMar w:top="\(margin)" w:right="\(margin)" w:bottom="\(margin)" w:left="\(margin)" w:header="720" w:footer="720" w:gutter="0"/>\
        </w:sectPr></w:body></w:document>
        """

        var contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
        <Default Extension="xml" ContentType="application/xml"/>
        """
        let mediaTypes = ["png": "image/png", "jpeg": "image/jpeg", "gif": "image/gif"]
        for ext in mediaExtensions.sorted() {
            contentTypes += "<Default Extension=\"\(ext)\" ContentType=\"\(mediaTypes[ext] ?? "application/octet-stream")\"/>"
        }
        contentTypes += """
        <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>\
        <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>\
        <Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>\
        </Types>
        """

        let rootRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>\
        </Relationships>
        """

        var documentRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
        <Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>\
        <Relationship Id="rIdNumbering" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>
        """
        documentRels += relationships.joined()
        documentRels += "</Relationships>"

        var zip = ZipWriter()
        zip.add("[Content_Types].xml", Data(contentTypes.utf8))
        zip.add("_rels/.rels", Data(rootRels.utf8))
        zip.add("word/document.xml", Data(documentXML.utf8))
        zip.add("word/styles.xml", Data(DocxStyleSheet.xml(for: theme).utf8))
        zip.add("word/numbering.xml", Data(numberingXML().utf8))
        zip.add("word/_rels/document.xml.rels", Data(documentRels.utf8))
        for item in media {
            zip.add("word/media/\(item.name)", item.data)
        }
        return zip.finish()
    }

    // MARK: Blocks

    private mutating func block(_ markup: Markup, _ context: BlockContext) {
        switch markup {
        case let heading as Heading:
            let level = min(max(heading.level, 1), 6)
            body += paragraph(
                style: "Heading\(level)",
                content: inlines(heading.children, RunStyle()),
                context: context)
        case let paragraph as Paragraph:
            body += self.paragraph(
                style: nil,
                content: inlines(paragraph.children, RunStyle(cell: context.tableCellText)),
                context: context,
                continuation: context.listLevel != nil)
        case let code as CodeBlock:
            if DocxExporter.isMermaid(code), let diagram = mermaidDiagrams[code.code] {
                body += paragraph(
                    style: nil,
                    content: drawing(diagram, alt: code.code, fitsPage: true),
                    context: context,
                    continuation: context.listLevel != nil,
                    alignment: "center")
            } else {
                body += codeBlock(code.code, language: code.language)
            }
        case let quote as BlockQuote:
            var inner = context
            inner.quoteDepth += 1
            for child in quote.children { block(child, inner) }
        case let list as UnorderedList:
            self.list(list, ordered: false, start: 1, context)
        case let list as OrderedList:
            self.list(list, ordered: true, start: Int(list.startIndex), context)
        case let table as Markdown.Table:
            self.table(table)
        case is ThematicBreak:
            let border = DocxProperties.paragraphBorders(theme.declarations(.rule).border)
            body += "<w:p><w:pPr>\(border)</w:pPr></w:p>"
        default:
            // HTML blocks and anything else with no Word equivalent.
            break
        }
    }

    private mutating func list(
        _ list: Markup, ordered: Bool, start: Int, _ context: BlockContext
    ) {
        let level = (context.listLevel.map { $0 + 1 }) ?? 0
        var numId = Self.bulletNumId
        if ordered {
            numId = Self.firstOrderedNumId + orderedLists.count
            orderedLists.append((numId, start))
        }
        for case let item as ListItem in list.children {
            var inner = context
            inner.listLevel = level
            inner.numId = numId
            var first = true
            for child in item.children {
                var childContext = inner
                if first, child is Paragraph {
                    // The first paragraph carries the bullet / number.
                    var prefix = ""
                    if let checkbox = item.checkbox {
                        prefix = checkbox == .checked ? "\u{2611} " : "\u{2610} "
                    }
                    let paragraph = child as! Paragraph
                    body += self.paragraph(
                        style: "ListParagraph",
                        content: run(prefix, RunStyle()) + inlines(paragraph.children, RunStyle()),
                        context: inner,
                        numbered: true)
                    first = false
                    continue
                }
                first = false
                if child is UnorderedList || child is OrderedList {
                    childContext = inner
                }
                block(child, childContext)
            }
        }
    }

    private mutating func table(_ table: Markdown.Table) {
        let columnCount = table.maxColumnCount
        guard columnCount > 0 else { return }
        let columnWidth = textWidth / columnCount
        let alignments = table.columnAlignments

        func rowXML(_ cells: [Markup], header: Bool, builder: inout DocxBuilder) -> String {
            let cellStyle = builder.theme.declarations(header ? .tableHeader : .tableBody)
            var row = "<w:tr>"
            if header { row += "<w:trPr><w:tblHeader/></w:trPr>" }
            for index in 0..<columnCount {
                var cellProps = "<w:tcW w:w=\"\(columnWidth)\" w:type=\"dxa\"/>"
                if let background = cellStyle.background { cellProps += DocxProperties.shd(background) }
                var content = ""
                if index < cells.count {
                    var jc = ""
                    if index < alignments.count, let alignment = alignments[index] {
                        switch alignment {
                        case .left: jc = "left"
                        case .center: jc = "center"
                        case .right: jc = "right"
                        }
                    }
                    var context = BlockContext()
                    context.tableCell = true
                    context.tableCellText = cellStyle.text
                    content = builder.paragraph(
                        style: nil,
                        content: builder.inlines(cells[index].children, RunStyle(cell: cellStyle.text)),
                        context: context,
                        alignment: jc)
                } else {
                    content = "<w:p/>"
                }
                row += "<w:tc><w:tcPr>\(cellProps)</w:tcPr>\(content)</w:tc>"
            }
            return row + "</w:tr>"
        }

        let tableStyle = theme.resolved(.table)
        let borders = tableStyle.border
        let borderXML = DocxProperties.border("top", borders.top)
            + DocxProperties.border("left", borders.left)
            + DocxProperties.border("bottom", borders.bottom)
            + DocxProperties.border("right", borders.right)
            + DocxProperties.border("insideH", borders.inside)
            + DocxProperties.border("insideV", borders.inside)
        let vertical = DocxUnits.twips(tableStyle.cellPadding.vertical ?? 0)
        let horizontal = DocxUnits.twips(tableStyle.cellPadding.horizontal ?? 0)
        var xml = """
        <w:tbl><w:tblPr><w:tblW w:w="\(textWidth)" w:type="dxa"/>\
        \(borderXML.isEmpty ? "" : "<w:tblBorders>\(borderXML)</w:tblBorders>")<w:tblLayout w:type="fixed"/>\
        <w:tblCellMar><w:top w:w="\(vertical)" w:type="dxa"/><w:left w:w="\(horizontal)" w:type="dxa"/>\
        <w:bottom w:w="\(vertical)" w:type="dxa"/><w:right w:w="\(horizontal)" w:type="dxa"/></w:tblCellMar>\
        </w:tblPr><w:tblGrid>
        """
        xml += String(repeating: "<w:gridCol w:w=\"\(columnWidth)\"/>", count: columnCount)
        xml += "</w:tblGrid>"
        xml += rowXML(Array(table.head.children), header: true, builder: &self)
        for row in table.body.children {
            xml += rowXML(Array(row.children), header: false, builder: &self)
        }
        xml += "</w:tbl>"
        // Word needs a paragraph after a table; it also spaces the next block.
        xml += "<w:p><w:pPr><w:spacing w:after=\"0\" w:line=\"120\" w:lineRule=\"exact\"/></w:pPr></w:p>"
        body += xml
    }

    private func codeBlock(_ code: String, language: String?) -> String {
        var text = code
        if text.hasSuffix("\n") { text.removeLast() }
        var runs = ""
        for segment in DocxSyntaxColors.segments(for: text, fenceInfo: language, theme: theme) {
            let color = segment.color.map { "<w:rPr><w:color w:val=\"\($0)\"/></w:rPr>" } ?? ""
            for (lineIndex, line) in segment.text.components(separatedBy: "\n").enumerated() {
                if lineIndex > 0 { runs += "<w:r><w:br/></w:r>" }
                for (partIndex, part) in line.components(separatedBy: "\t").enumerated() {
                    var inner = ""
                    if partIndex > 0 { inner += "<w:tab/>" }
                    if !part.isEmpty {
                        inner += "<w:t xml:space=\"preserve\">\(xmlEscape(part))</w:t>"
                    }
                    if !inner.isEmpty { runs += "<w:r>\(color)\(inner)</w:r>" }
                }
            }
        }
        // Word fuses adjacent paragraphs with identical borders and shading
        // into one box, so a thin spacer keeps neighbouring blocks separate.
        return "<w:p><w:pPr><w:pStyle w:val=\"CodeBlock\"/></w:pPr>\(runs)</w:p>"
            + "<w:p><w:pPr><w:spacing w:before=\"0\" w:after=\"0\" w:line=\"160\" w:lineRule=\"exact\"/></w:pPr></w:p>"
    }

    private func paragraph(
        style: String?,
        content: String,
        context: BlockContext,
        numbered: Bool = false,
        continuation: Bool = false,
        alignment: String = ""
    ) -> String {
        var props = ""
        if numbered, let level = context.listLevel, let numId = context.numId {
            props += "<w:pStyle w:val=\"ListParagraph\"/>"
            props += "<w:numPr><w:ilvl w:val=\"\(min(level, 8))\"/><w:numId w:val=\"\(numId)\"/></w:numPr>"
        } else {
            if let style {
                props += "<w:pStyle w:val=\"\(style)\"/>"
            } else if context.quoteDepth > 0 {
                props += "<w:pStyle w:val=\"Quote\"/>"
            }
            if context.tableCell {
                props += "<w:spacing w:after=\"0\"/>"
            }
            if continuation, let level = context.listLevel {
                let indent = theme.resolved(.list).indent * Double(level + 1)
                props += "<w:ind w:left=\"\(DocxUnits.twips(indent))\"/>"
            } else if context.quoteDepth > 1 {
                let indent = theme.resolved(.quote).indent * Double(context.quoteDepth)
                props += "<w:ind w:left=\"\(DocxUnits.twips(indent))\"/>"
            }
        }
        if !alignment.isEmpty { props += "<w:jc w:val=\"\(alignment)\"/>" }
        return "<w:p><w:pPr>\(props)</w:pPr>\(content)</w:p>"
    }

    // MARK: Inlines

    private mutating func inlines<S: Sequence>(_ nodes: S, _ style: RunStyle) -> String
    where S.Element == Markup {
        var xml = ""
        for node in nodes {
            xml += inline(node, style)
        }
        return xml
    }

    private mutating func inline(_ node: Markup, _ style: RunStyle) -> String {
        switch node {
        case let text as Markdown.Text:
            return run(text.string, style)
        case let emphasis as Emphasis:
            var next = style
            next.italic = true
            return inlines(emphasis.children, next)
        case let strong as Strong:
            var next = style
            next.bold = true
            return inlines(strong.children, next)
        case let strike as Strikethrough:
            var next = style
            next.strike = true
            return inlines(strike.children, next)
        case let code as InlineCode:
            var next = style
            next.code = true
            return run(code.code, next)
        case is SoftBreak:
            return run(" ", style)
        case is LineBreak:
            return "<w:r><w:br/></w:r>"
        case let link as Markdown.Link:
            return self.link(link, style)
        case let image as Markdown.Image:
            return self.image(image, style)
        default:
            // Inline HTML and symbol links have no Word equivalent.
            return ""
        }
    }

    private func run(_ text: String, _ style: RunStyle) -> String {
        guard !text.isEmpty else { return "" }
        let properties = style.xml(
            codeStyle: theme.declarations(.inlineCode), linkStyle: theme.declarations(.link))
        return "<w:r>\(properties)<w:t xml:space=\"preserve\">\(xmlEscape(text))</w:t></w:r>"
    }

    private mutating func link(_ link: Markdown.Link, _ style: RunStyle) -> String {
        var next = style
        next.link = true
        let content = inlines(link.children, next)
        guard let destination = link.destination,
              let url = URL(string: destination), url.scheme != nil
        else { return inlines(link.children, style) }
        let id = "rIdL\(nextRelationshipID)"
        nextRelationshipID += 1
        relationships.append(
            "<Relationship Id=\"\(id)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink\" Target=\"\(xmlEscape(destination))\" TargetMode=\"External\"/>")
        return "<w:hyperlink r:id=\"\(id)\">\(content)</w:hyperlink>"
    }

    private mutating func image(_ image: Markdown.Image, _ style: RunStyle) -> String {
        let alt = image.plainText
        guard let source = image.source, !source.isEmpty else { return run(alt, style) }
        guard let fileURL = localFileURL(for: source),
              let embedded = embeddedImage(at: fileURL)
        else {
            // Remote or unreadable: keep the alt text, linked when possible.
            let label = alt.isEmpty ? source : alt
            guard let url = URL(string: source), url.scheme != nil else {
                return run(label, style)
            }
            var next = style
            next.link = true
            let id = "rIdL\(nextRelationshipID)"
            nextRelationshipID += 1
            relationships.append(
                "<Relationship Id=\"\(id)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink\" Target=\"\(xmlEscape(source))\" TargetMode=\"External\"/>")
            return "<w:hyperlink r:id=\"\(id)\">\(run(label, next))</w:hyperlink>"
        }
        return drawing(embedded, alt: alt)
    }

    /// `fitsPage` also caps the height, so a tall picture shrinks onto one
    /// page instead of running off its bottom edge.
    private mutating func drawing(
        _ embedded: DocxImage, alt: String, fitsPage: Bool = false
    ) -> String {
        let mediaName = "image\(media.count + 1).\(embedded.ext)"
        media.append((mediaName, embedded.data))
        mediaExtensions.insert(embedded.ext)
        let id = "rIdI\(nextRelationshipID)"
        nextRelationshipID += 1
        relationships.append(
            "<Relationship Id=\"\(id)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/image\" Target=\"media/\(mediaName)\"/>")

        // 96 dpi pixels -> points, capped to the text column.
        let maxPoints = Double(textWidth) / 20
        var width = embedded.width * 0.75
        var height = embedded.height * 0.75
        if width > maxPoints {
            height *= maxPoints / width
            width = maxPoints
        }
        // Leave room for the paragraph's own spacing within the text area.
        let maxHeight = Double(pageHeight - 2 * margin) / 20 * 0.9
        if fitsPage, height > maxHeight {
            width *= maxHeight / height
            height = maxHeight
        }
        let cx = Int(width * 12700)
        let cy = Int(height * 12700)
        let drawingID = nextDrawingID
        nextDrawingID += 1
        return """
        <w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0">\
        <wp:extent cx="\(cx)" cy="\(cy)"/>\
        <wp:docPr id="\(drawingID)" name="Image \(drawingID)" descr="\(xmlEscape(alt))"/>\
        <a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">\
        <pic:pic><pic:nvPicPr><pic:cNvPr id="\(drawingID)" name="\(mediaName)"/><pic:cNvPicPr/></pic:nvPicPr>\
        <pic:blipFill><a:blip r:embed="\(id)"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>\
        <pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(cx)" cy="\(cy)"/></a:xfrm>\
        <a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic>\
        </a:graphicData></a:graphic></wp:inline></w:drawing></w:r>
        """
    }

    private func localFileURL(for source: String) -> URL? {
        if let url = URL(string: source), let scheme = url.scheme {
            return scheme == "file" ? url : nil
        }
        let decoded = source.removingPercentEncoding ?? source
        if decoded.hasPrefix("/") { return URL(fileURLWithPath: decoded) }
        return assetBaseURL?.appendingPathComponent(decoded)
    }

    /// PNG / JPEG / GIF are embedded as-is; anything else AppKit can read is
    /// re-encoded as PNG.
    private func embeddedImage(
        at url: URL
    ) -> DocxImage? {
        guard let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Double,
              let height = properties[kCGImagePropertyPixelHeight] as? Double,
              width > 0, height > 0
        else { return nil }
        switch CGImageSourceGetType(source) as String? {
        case "public.png": return DocxImage(data: data, ext: "png", width: width, height: height)
        case "public.jpeg": return DocxImage(data: data, ext: "jpeg", width: width, height: height)
        case "com.compuserve.gif": return DocxImage(data: data, ext: "gif", width: width, height: height)
        default:
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  let png = NSBitmapImageRep(cgImage: cgImage)
                    .representation(using: .png, properties: [:])
            else { return nil }
            return DocxImage(data: png, ext: "png", width: width, height: height)
        }
    }

    // MARK: Parts

    private func numberingXML() -> String {
        let bullets = ["\u{2022}", "\u{25E6}", "\u{25AA}"]
        let formats = ["decimal", "lowerLetter", "lowerRoman"]
        var bulletLevels = ""
        var orderedLevels = ""
        let list = theme.resolved(.list)
        let marker = list.markerFont.map {
            "<w:rPr><w:rFonts w:ascii=\"\(xmlEscape($0))\" w:hAnsi=\"\(xmlEscape($0))\" w:hint=\"default\"/></w:rPr>"
        } ?? ""
        for level in 0..<9 {
            let left = DocxUnits.twips(list.indent * Double(level + 1))
            let indent = "<w:pPr><w:ind w:left=\"\(left)\" w:hanging=\"\(DocxUnits.twips(list.hanging))\"/></w:pPr>"
            bulletLevels += """
            <w:lvl w:ilvl="\(level)"><w:start w:val="1"/><w:numFmt w:val="bullet"/>\
            <w:lvlText w:val="\(bullets[level % 3])"/><w:lvlJc w:val="left"/>\(indent)\
            \(marker)</w:lvl>
            """
            orderedLevels += """
            <w:lvl w:ilvl="\(level)"><w:start w:val="1"/><w:numFmt w:val="\(formats[level % 3])"/>\
            <w:lvlText w:val="%\(level + 1)."/><w:lvlJc w:val="left"/>\(indent)</w:lvl>
            """
        }
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">\
        <w:abstractNum w:abstractNumId="0"><w:multiLevelType w:val="hybridMultilevel"/>\(bulletLevels)</w:abstractNum>\
        <w:abstractNum w:abstractNumId="1"><w:multiLevelType w:val="hybridMultilevel"/>\(orderedLevels)</w:abstractNum>\
        <w:num w:numId="\(Self.bulletNumId)"><w:abstractNumId w:val="0"/></w:num>
        """
        for list in orderedLists {
            // Each ordered list is its own num so numbering restarts per list.
            xml += "<w:num w:numId=\"\(list.numId)\"><w:abstractNumId w:val=\"1\"/>"
            xml += "<w:lvlOverride w:ilvl=\"0\"><w:startOverride w:val=\"\(list.start)\"/></w:lvlOverride></w:num>"
        }
        return xml + "</w:numbering>"
    }
}

// MARK: - Helpers

/// Minimal ZIP writer: "stored" (uncompressed) entries only, which every
/// OOXML consumer accepts.
private struct ZipWriter {
    private var output = Data()
    private var central = Data()
    private var count: UInt16 = 0

    private static let crcTable: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
        }
        return value
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    mutating func add(_ name: String, _ data: Data) {
        let nameData = Data(name.utf8)
        let crc = Self.crc32(data)
        let offset = UInt32(output.count)
        // 1980-01-01 00:00, UTF-8 names.
        let time: UInt16 = 0, date: UInt16 = 0x0021, flags: UInt16 = 0x0800

        output.append(le: UInt32(0x0403_4B50))
        output.append(le: UInt16(20))
        output.append(le: flags)
        output.append(le: UInt16(0))
        output.append(le: time)
        output.append(le: date)
        output.append(le: crc)
        output.append(le: UInt32(data.count))
        output.append(le: UInt32(data.count))
        output.append(le: UInt16(nameData.count))
        output.append(le: UInt16(0))
        output.append(nameData)
        output.append(data)

        central.append(le: UInt32(0x0201_4B50))
        central.append(le: UInt16(20))
        central.append(le: UInt16(20))
        central.append(le: flags)
        central.append(le: UInt16(0))
        central.append(le: time)
        central.append(le: date)
        central.append(le: crc)
        central.append(le: UInt32(data.count))
        central.append(le: UInt32(data.count))
        central.append(le: UInt16(nameData.count))
        central.append(le: UInt16(0))
        central.append(le: UInt16(0))
        central.append(le: UInt16(0))
        central.append(le: UInt16(0))
        central.append(le: UInt32(0))
        central.append(le: offset)
        central.append(nameData)
        count += 1
    }

    mutating func finish() -> Data {
        let centralOffset = UInt32(output.count)
        output.append(central)
        output.append(le: UInt32(0x0605_4B50))
        output.append(le: UInt16(0))
        output.append(le: UInt16(0))
        output.append(le: count)
        output.append(le: count)
        output.append(le: UInt32(central.count))
        output.append(le: centralOffset)
        output.append(le: UInt16(0))
        return output
    }
}

private extension Data {
    mutating func append<T: FixedWidthInteger>(le value: T) {
        var little = value.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
