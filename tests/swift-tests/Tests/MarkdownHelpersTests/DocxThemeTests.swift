import Foundation
import XCTest
@testable import MarkdownHelpers

final class DocxThemeTests: XCTestCase {
    // MARK: Helpers

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let themesDirectory = repoRoot.appendingPathComponent("daisy/Resources/DocxThemes")
    private static let fixtures = repoRoot.appendingPathComponent("tests/fixtures/docx")

    private func decode(_ json: String) throws -> DocxTheme {
        try JSONDecoder().decode(DocxTheme.self, from: Data(json.utf8))
    }

    /// A theme with `id` "t" and the given body fragment (the part after name).
    private func theme(_ body: String) throws -> DocxTheme {
        try decode("{\"id\":\"t\",\"name\":\"T\"\(body.isEmpty ? "" : "," + body)}")
    }

    private func bundledThemes() -> [DocxTheme] {
        DocxThemeStore.themes(inDirectory: Self.themesDirectory)
    }

    private func export(
        _ markdown: String, theme: DocxTheme = .github
    ) throws -> [String: String] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("out.docx")
        try DocxExporter.write(markdown: markdown, assetBaseURL: directory, theme: theme, to: file)
        var parts: [String: String] = [:]
        for name in ["word/styles.xml", "word/document.xml", "word/numbering.xml"] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-p", file.path, name]
            let pipe = Pipe()
            process.standardOutput = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            parts[name] = String(decoding: data, as: UTF8.self)
        }
        return parts
    }

    private func assertWellFormed(_ xml: String, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let parser = XMLParser(data: Data(xml.utf8))
        XCTAssertTrue(parser.parse(), "\(label): \(parser.parserError?.localizedDescription ?? "")",
                      file: file, line: line)
    }

    private let kitchenSink = """
    # H1
    ## H2
    ### H3
    #### H4
    ##### H5
    ###### H6

    Text with **bold**, *italic*, ~~strike~~, `code` and [a link](https://example.com).

    > quote
    > > nested

    - one
      - two
    1. a
    2. b

    ---

    ```swift
    let x = "hi" // c
    ```

    | A | B |
    |---|:-:|
    | `c` | [l](https://example.com) |
    """

    // MARK: 1. Overlay and precedence

    func testGlobalOnlyThemeKeepsGitHubElements() throws {
        let theme = try theme("\"global\":{\"font\":\"Georgia\",\"size\":12}")
        XCTAssertEqual(theme.global.font, "Georgia")
        XCTAssertEqual(theme.global.size, 12)
        XCTAssertEqual(theme.declarations(.codeBlock).font, "Consolas")
        XCTAssertEqual(theme.declarations(.codeBlock).size, 10)
        XCTAssertEqual(theme.declarations(.heading1).size, 20)
        XCTAssertNil(theme.declarations(.heading1).font, "sparse: no global fill")
        XCTAssertNil(theme.declarations(.paragraph).size)
    }

    func testElementOverrideWinsAndMergesFieldByField() throws {
        let theme = try theme("""
        "elements":{"heading1":{"size":30},"quote":{"border":{"left":{"width":4}}},
        "table":{"cellPadding":{"vertical":9}}}
        """)
        XCTAssertEqual(theme.declarations(.heading1).size, 30)
        XCTAssertEqual(theme.declarations(.heading1).bold, true)
        XCTAssertEqual(theme.declarations(.heading1).color, "1F2328")
        let left = theme.declarations(.quote).border?.left
        XCTAssertEqual(left?.width, 4)
        XCTAssertEqual(left?.space, 8)
        XCTAssertEqual(left?.color, "BFC5CC")
        XCTAssertEqual(theme.declarations(.table).cellPadding, CellPadding(vertical: 9, horizontal: 5))
    }

    func testSpecificBorderSideBeatsAll() throws {
        let theme = try theme("""
        "elements":{"codeBlock":{"border":{"all":{"width":1,"color":"112233"},
        "left":{"color":"445566"}}}}
        """)
        let border = try XCTUnwrap(theme.declarations(.codeBlock).border)
        XCTAssertEqual(border.left?.color, "445566")
        XCTAssertEqual(border.left?.width, 1)
        XCTAssertEqual(border.top?.color, "112233")
    }

    func testEffectiveValuesFallBackToGlobal() throws {
        let theme = try theme("\"global\":{\"font\":\"Georgia\",\"color\":\"112233\"}")
        XCTAssertEqual(theme.resolved(.paragraph).font, "Georgia")
        XCTAssertEqual(theme.resolved(.paragraph).color, "112233")
        XCTAssertEqual(theme.resolved(.codeBlock).font, "Consolas")
        XCTAssertEqual(theme.resolved(.heading1).color, "1F2328")
    }

    // MARK: 2. Palette

    func testPaletteReferencesResolve() throws {
        let theme = try theme("""
        "global":{"palette":{"accent":"#abcdef","muted":"010203"}},
        "elements":{"link":{"color":"$accent"},"quote":{"color":"$muted"}}
        """)
        XCTAssertEqual(theme.declarations(.link).color, "ABCDEF")
        XCTAssertEqual(theme.declarations(.quote).color, "010203", "theme palette beats GitHub's")
    }

    func testUnknownPaletteReferenceKeepsGitHubField() throws {
        let theme = try theme("\"elements\":{\"link\":{\"color\":\"$nope\"},\"inlineCode\":{\"background\":\"$nope\"}}")
        XCTAssertEqual(theme.declarations(.link).color, "0969DA")
        XCTAssertEqual(theme.declarations(.inlineCode).background, "EFF1F3")
    }

    // MARK: 3. Validation

    func testInvalidValuesAreDroppedNotThrown() throws {
        let theme = try theme("""
        "global":{"size":100000,"lineHeight":-1,"language":"not a language!","font":"Bad<Font"},
        "page":{"margin":-5},
        "elements":{"heading1":{"color":"red","size":0,"font":"a\\"b"},
        "heading2":{"size":"big"},"mystery":{"size":3},"link":{"color":"#0a0b0c","extra":true}}
        """)
        XCTAssertEqual(theme.global.size, 11)
        XCTAssertEqual(theme.global.lineHeight, 1.15)
        XCTAssertEqual(theme.global.language, "en-US")
        XCTAssertEqual(theme.global.font, "Calibri")
        XCTAssertEqual(theme.page.margin, 72)
        XCTAssertEqual(theme.declarations(.heading1).color, "1F2328")
        XCTAssertEqual(theme.declarations(.heading1).size, 20)
        XCTAssertNil(theme.declarations(.heading1).font)
        XCTAssertEqual(theme.declarations(.heading2).size, 16)
        XCTAssertEqual(theme.declarations(.link).color, "0A0B0C")
    }

    func testIDMustBeValid() {
        XCTAssertThrowsError(try decode("{\"id\":\"../x\",\"name\":\"X\"}"))
        XCTAssertThrowsError(try decode("{\"name\":\"X\"}"))
    }

    // MARK: 4. GitHub file == in-code

    func testBundledGitHubThemeMatchesInCodeTheme() throws {
        let data = try Data(contentsOf: Self.themesDirectory.appendingPathComponent("docx-theme-github.json"))
        let decoded = try JSONDecoder().decode(DocxTheme.self, from: data)
        XCTAssertEqual(decoded, DocxTheme.github)
        XCTAssertEqual(decoded.declarations(.heading1).color, "1F2328")
        XCTAssertEqual(decoded.declarations(.heading6).color, "59636E")
        XCTAssertNil(decoded.global.color)
    }

    // MARK: 5. Units

    func testUnitConversionMatchesTheOldLiterals() {
        XCTAssertEqual(DocxUnits.eighths(0.75), 6)
        XCTAssertEqual(DocxUnits.eighths(2.25), 18)
        XCTAssertEqual(DocxUnits.eighths(0.5), 4)
        XCTAssertEqual(DocxUnits.twips(28.35), 567)
        XCTAssertEqual(DocxUnits.twips(5.65), 113)
        XCTAssertEqual(DocxUnits.twips(72), 1440)
        XCTAssertEqual(DocxUnits.twips(36), 720)
        XCTAssertEqual(DocxUnits.twips(18), 360)
        XCTAssertEqual(DocxUnits.halfPoints(11), 22)
        XCTAssertEqual(DocxUnits.lineUnits(1.15), 276)
        XCTAssertEqual(DocxUnits.lineUnits(1.0), 240)
        XCTAssertEqual(DocxUnits.twips(28.35 * 3), 1701)
    }

    // MARK: 6. Golden output

    func testGitHubStyleSheetMatchesPreRefactorOutput() throws {
        let golden = try String(contentsOf: Self.fixtures.appendingPathComponent("styles-github.xml"), encoding: .utf8)
        XCTAssertEqual(DocxStyleSheet.xml(for: .github), golden)
    }

    func testGitHubDocumentAndNumberingMatchPreRefactorOutput() throws {
        let markdown = try String(contentsOf: Self.fixtures.appendingPathComponent("sample.md"), encoding: .utf8)
        let parts = try export(markdown)
        // Page size follows the region; the rest must be identical.
        func normalised(_ xml: String) -> String {
            xml.replacingOccurrences(
                of: "<w:pgSz [^>]*/>", with: "<w:pgSz/>", options: .regularExpression)
        }
        let document = try String(contentsOf: Self.fixtures.appendingPathComponent("document-github.xml"), encoding: .utf8)
        let numbering = try String(contentsOf: Self.fixtures.appendingPathComponent("numbering-github.xml"), encoding: .utf8)
        XCTAssertEqual(normalised(try XCTUnwrap(parts["word/document.xml"])), normalised(document))
        XCTAssertEqual(parts["word/numbering.xml"], numbering)
    }

    func testStyleSheetHasNoRedundantGlobalValues() {
        let xml = DocxStyleSheet.xml(for: .github)
        let heading1 = xml.components(separatedBy: "w:styleId=\"Heading1\"")[1]
            .components(separatedBy: "</w:style>")[0]
        XCTAssertFalse(heading1.contains("rFonts"))
        let quote = xml.components(separatedBy: "w:styleId=\"Quote\"")[1]
            .components(separatedBy: "</w:style>")[0]
        XCTAssertFalse(quote.contains("<w:spacing"))
    }

    func testGlobalColorOnlyAppearsWhenSet() throws {
        XCTAssertFalse(DocxStyleSheet.xml(for: .github).contains("<w:color w:val=\"000000\"/><w:sz"))
        let rPrDefault: (String) -> String = {
            $0.components(separatedBy: "<w:rPrDefault>")[1].components(separatedBy: "</w:rPrDefault>")[0]
        }
        XCTAssertFalse(rPrDefault(DocxStyleSheet.xml(for: .github)).contains("w:color"))
        let themed = try theme("\"global\":{\"color\":\"010203\"}")
        XCTAssertTrue(rPrDefault(DocxStyleSheet.xml(for: themed)).contains("<w:color w:val=\"010203\"/>"))
    }

    // MARK: 7. Syntax

    func testSyntaxTriState() throws {
        let theme = try theme("""
        "syntax":{"keyword":"#112233","string":null,"number":"","comment":"oops","type":5}
        """)
        XCTAssertEqual(theme.syntaxColor(.keyword), "112233")
        XCTAssertNil(theme.syntaxColor(.string))
        XCTAssertNil(theme.syntaxColor(.number))
        XCTAssertEqual(theme.syntaxColor(.comment), "5D6C79", "invalid = inherit")
        XCTAssertEqual(theme.syntaxColor(.type), "3900A0", "wrong type = inherit")
        XCTAssertEqual(theme.syntaxColor(.meta), "643820", "absent = inherit")
    }

    func testDisabledTokenSuppressesColorAndDoesNotFallBackToParent() throws {
        let theme = try theme("\"syntax\":{\"string\":null}")
        let html = "<span class=\"hljs-keyword\">if <span class=\"hljs-string\">\"x\"</span></span>"
        let segments = DocxSyntaxColors.parse(html, theme: theme)
        XCTAssertEqual(segments, [
            .init(text: "if ", color: "9B2393"), .init(text: "\"x\"", color: nil),
        ])
    }

    func testUnrecognisedSpanInheritsParentToken() {
        let html = "<span class=\"hljs-keyword\">a<span class=\"hljs-whatever\">b</span></span>"
        XCTAssertEqual(DocxSyntaxColors.parse(html, theme: .github), [.init(text: "ab", color: "9B2393")])
    }

    func testMetaAncestryIsByTokenNotColor() throws {
        // meta disabled and keyword/meta sharing a color must not change classification.
        let theme = try theme("\"syntax\":{\"meta\":null,\"keyword\":\"643820\"}")
        let html = "<span class=\"hljs-meta\">#<span class=\"hljs-keyword\">include</span></span> "
            + "<span class=\"hljs-keyword\">int</span>"
        let segments = DocxSyntaxColors.parse(html, theme: theme)
        XCTAssertEqual(segments.first?.text, "#include ")
        XCTAssertNil(segments.first?.color, "keyword inside meta is meta, which is disabled")
        XCTAssertEqual(segments.last?.text, "int")
        XCTAssertEqual(segments.last?.color, "643820")
    }

    // MARK: 8. XML safety

    func testHostileThemeStillProducesWellFormedXML() throws {
        let theme = try theme("""
        "global":{"font":"Evil\\"/><w:x/>","language":"en\\"US","color":"</w:style>","size":1e999},
        "elements":{
        "codeBlock":{"font":"Evil\\"/><w:x/>","border":{"all":{"style":"x\\" w:y=\\"z","color":"</w:style>","width":1e999}}},
        "quote":{"border":{"left":{"style":"x\\" w:y=\\"z","width":2}}},
        "link":{"color":"\\"/><w:x/>"},"list":{"markerFont":"a\\"b"},
        "table":{"border":{"all":{"style":"<>","width":1}},"cellPadding":{"vertical":1e999}}}
        """)
        let parts = try export(kitchenSink, theme: theme)
        for (name, xml) in parts {
            XCTAssertFalse(xml.isEmpty, name)
            assertWellFormed(xml, name)
        }
        let quote = try XCTUnwrap(parts["word/styles.xml"]).components(separatedBy: "w:styleId=\"Quote\"")[1]
        XCTAssertTrue(quote.contains("w:val=\"single\""), "unknown border style falls back to single")
        XCTAssertFalse(try XCTUnwrap(parts["word/styles.xml"]).contains("<w:x/>"))
    }

    func testEveryBundledThemeProducesWellFormedXML() throws {
        let themes = bundledThemes()
        XCTAssertEqual(themes.map(\.id), ["document", "github", "minimal", "serif"])
        for theme in themes {
            for (name, xml) in try export(kitchenSink, theme: theme) {
                assertWellFormed(xml, "\(theme.id) \(name)")
            }
        }
    }

    func testBorderStyleAllowlist() {
        for style in DocxThemeValidation.borderStyles {
            XCTAssertEqual(DocxThemeValidation.borderStyle(style), style)
        }
        XCTAssertEqual(DocxThemeValidation.borderStyle("wave"), "single")
    }

    // MARK: 9. Support matrix

    func testUnsupportedPropertiesAreIgnored() throws {
        let theme = try theme("""
        "elements":{"tableHeader":{"spaceAfter":50,"indent":50},"heading1":{"markerFont":"Georgia"},
        "paragraph":{"spaceAfter":50,"lineHeight":3},"rule":{"color":"112233"},"list":{"color":"112233"}}
        """)
        XCTAssertNil(theme.declarations(.tableHeader).spaceAfter)
        XCTAssertNil(theme.declarations(.heading1).markerFont)
        XCTAssertNil(theme.declarations(.paragraph).spaceAfter)
        XCTAssertNil(theme.declarations(.paragraph).lineHeight)
        XCTAssertNil(theme.declarations(.rule).color)
        XCTAssertNil(theme.declarations(.list).color)
        XCTAssertEqual(DocxStyleSheet.xml(for: theme), DocxStyleSheet.xml(for: .github))
    }

    func testGlobalSpacingChangesDocDefaultsNotNormal() throws {
        let theme = try theme("\"global\":{\"spaceAfter\":10,\"lineHeight\":1.5}")
        let xml = DocxStyleSheet.xml(for: theme)
        XCTAssertTrue(xml.contains("<w:spacing w:after=\"200\" w:line=\"360\" w:lineRule=\"auto\"/></w:pPr></w:pPrDefault>"))
        XCTAssertTrue(xml.contains("<w:name w:val=\"Normal\"/><w:qFormat/></w:style>"))
    }

    // MARK: 10. Table cells

    func testHeaderCellTextPropertiesInSchemaOrder() throws {
        let theme = try theme("""
        "elements":{"tableHeader":{"font":"Georgia","size":12,"color":"112233","underline":true,
        "strike":true,"italic":true}}
        """)
        let document = try XCTUnwrap(export("| Head |\n|---|\n| body |", theme: theme)["word/document.xml"])
        XCTAssertTrue(document.contains(
            "<w:rPr><w:rFonts w:ascii=\"Georgia\" w:hAnsi=\"Georgia\" w:cs=\"Georgia\"/><w:b/><w:i/><w:strike/>"
            + "<w:color w:val=\"112233\"/><w:sz w:val=\"24\"/><w:szCs w:val=\"24\"/><w:u w:val=\"single\"/></w:rPr>"
            + "<w:t xml:space=\"preserve\">Head</w:t>"))
        XCTAssertTrue(document.contains("<w:rPr></w:rPr>") == false)
    }

    func testBodyCellTextAndShading() throws {
        let theme = try theme("\"elements\":{\"tableBody\":{\"color\":\"334455\",\"background\":\"FAFAFA\"}}")
        let document = try XCTUnwrap(export("| H |\n|---|\n| body |", theme: theme)["word/document.xml"])
        XCTAssertTrue(document.contains("<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"FAFAFA\"/>"))
        XCTAssertTrue(document.contains("<w:rPr><w:color w:val=\"334455\"/></w:rPr><w:t xml:space=\"preserve\">body</w:t>"))
    }

    func testInlineStylesWinOverCellDefaults() throws {
        let theme = try theme("""
        "elements":{"tableBody":{"font":"Georgia","size":13,"color":"334455","underline":true}}
        """)
        let document = try XCTUnwrap(
            export("| H |\n|---|\n| `code` [link](https://x.org) **b** |", theme: theme)["word/document.xml"])
        // Inline code defines font and size: only the cell color and underline remain.
        XCTAssertTrue(document.contains(
            "<w:rStyle w:val=\"InlineCode\"/><w:color w:val=\"334455\"/><w:u w:val=\"single\"/>"))
        // Links define color and underline: only the cell font and size remain.
        XCTAssertTrue(document.contains(
            "<w:rStyle w:val=\"Hyperlink\"/><w:rFonts w:ascii=\"Georgia\" w:hAnsi=\"Georgia\" w:cs=\"Georgia\"/>"
            + "<w:sz w:val=\"26\"/><w:szCs w:val=\"26\"/>"))
        // Markdown strong adds bold on top of the cell defaults.
        XCTAssertTrue(document.contains("<w:b/><w:color w:val=\"334455\"/>"))
    }

    func testGitHubBodyCellsGainNoRunProperties() throws {
        let document = try XCTUnwrap(export("| H |\n|---|\n| plain |")["word/document.xml"])
        XCTAssertTrue(document.contains("<w:r><w:t xml:space=\"preserve\">plain</w:t></w:r>"))
    }

    // MARK: 11. Positive serialization

    func testCustomThemeSerialization() throws {
        let theme = try theme("""
        "elements":{"paragraph":{"bold":true},"heading1":{"font":"Georgia"},"link":{"size":12},
        "codeBlock":{"indentRight":10},"quote":{"border":{"left":{"width":3,"color":"112233"}}},
        "inlineCode":{"background":"ABCDEF"},"list":{"markerFont":"Symbol"}}
        """)
        let styles = DocxStyleSheet.xml(for: theme)
        XCTAssertTrue(styles.contains("<w:name w:val=\"Normal\"/><w:qFormat/><w:rPr><w:b/></w:rPr></w:style>"))
        XCTAssertTrue(styles.contains(
            "<w:rPr><w:rFonts w:ascii=\"Georgia\" w:hAnsi=\"Georgia\" w:cs=\"Georgia\"/><w:b/><w:color w:val=\"1F2328\"/><w:sz w:val=\"40\"/>"))
        XCTAssertTrue(styles.contains(
            "<w:rPr><w:color w:val=\"0969DA\"/><w:sz w:val=\"24\"/><w:szCs w:val=\"24\"/><w:u w:val=\"single\"/></w:rPr>"))
        XCTAssertTrue(styles.contains("<w:ind w:left=\"113\" w:right=\"200\"/>"))
        XCTAssertTrue(styles.contains("<w:left w:val=\"single\" w:sz=\"24\" w:space=\"8\" w:color=\"112233\"/>"))
        XCTAssertTrue(styles.contains("<w:fill=\"ABCDEF\"/>") || styles.contains("w:fill=\"ABCDEF\""))
        let numbering = try XCTUnwrap(export("- a", theme: theme)["word/numbering.xml"])
        XCTAssertTrue(numbering.contains("<w:rFonts w:ascii=\"Symbol\" w:hAnsi=\"Symbol\" w:hint=\"default\"/>"))
    }

    func testPageMarginAndListIndents() throws {
        let theme = try theme("""
        "page":{"margin":36},"elements":{"list":{"indent":20,"hanging":10},"quote":{"indent":10}}
        """)
        let parts = try export("- a\n\n> > deep\n", theme: theme)
        XCTAssertTrue(try XCTUnwrap(parts["word/document.xml"]).contains(
            "<w:pgMar w:top=\"720\" w:right=\"720\" w:bottom=\"720\" w:left=\"720\""))
        XCTAssertTrue(try XCTUnwrap(parts["word/document.xml"]).contains("<w:ind w:left=\"400\"/>"))
        XCTAssertTrue(try XCTUnwrap(parts["word/numbering.xml"]).contains("<w:ind w:left=\"400\" w:hanging=\"200\"/>"))
    }

    func testBoldFalseOnlySwitchesOffInheritedBold() throws {
        let plain = try theme("\"elements\":{\"heading1\":{\"bold\":false}}")
        XCTAssertFalse(DocxStyleSheet.xml(for: plain).contains("<w:b w:val=\"0\"/>"))
        let boldBody = try theme("\"elements\":{\"paragraph\":{\"bold\":true},\"heading1\":{\"bold\":false}}")
        XCTAssertTrue(DocxStyleSheet.xml(for: boldBody).contains("<w:b w:val=\"0\"/>"))
    }

    // MARK: 12. Lenient decoding

    func testLenientDecodingKeepsGoodNeighbours() throws {
        let theme = try theme("""
        "elements":{"nonsense":{"size":3},"heading2":"not an object","heading3":{"size":"big","bold":false},
        "heading4":{"size":15}},
        "syntax":{"futureToken":"112233","keyword":"zzzzzz","string":"010203"},
        "unknownTopLevel":{"a":1}
        """)
        XCTAssertEqual(theme.declarations(.heading2).size, 16)
        XCTAssertEqual(theme.declarations(.heading3).size, 14)
        XCTAssertEqual(theme.declarations(.heading3).bold, false)
        XCTAssertEqual(theme.declarations(.heading4).size, 15)
        XCTAssertEqual(theme.syntaxColor(.keyword), "9B2393")
        XCTAssertEqual(theme.syntaxColor(.string), "010203")
    }

    func testNonObjectElementsAndSyntaxYieldGitHub() throws {
        let theme = try theme("\"elements\":[1,2],\"syntax\":\"x\",\"global\":5,\"page\":null")
        XCTAssertEqual(theme.elements, DocxTheme.github.elements)
        XCTAssertEqual(theme.syntax, DocxTheme.github.syntax)
        XCTAssertEqual(theme.global, DocxTheme.github.global)
    }

    // MARK: 13. Automatic color

    func testAutomaticColorWhenNothingSetsOne() {
        XCTAssertNil(DocxTheme.github.resolved(.paragraph).color)
        XCTAssertNil(DocxTheme.github.resolved(.codeBlock).color)
        XCTAssertEqual(DocxTheme.github.resolved(.heading1).color, "1F2328")
    }

    func testDisabledSyntaxTokenEmitsNoRunColor() throws {
        let theme = try theme("\"syntax\":{\"keyword\":null,\"string\":null,\"comment\":null,\"number\":null,\"type\":null,\"builtIn\":null,\"title\":null,\"titleClass\":null,\"property\":null,\"attribute\":null,\"meta\":null,\"doctag\":null}")
        let document = try XCTUnwrap(export("```swift\nlet x = \"a\" // c\n```", theme: theme)["word/document.xml"])
        let code = document.components(separatedBy: "w:val=\"CodeBlock\"")[1].components(separatedBy: "</w:p>")[0]
        XCTAssertFalse(code.contains("w:color"))
    }

    // MARK: 14. Resource loading

    func testStoreLoadsOnlyMatchingThemeFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func write(_ name: String, _ text: String) throws {
            try text.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        try write("docx-theme-b.json", "{\"id\":\"b\",\"name\":\"B\"}")
        try write("docx-theme-a.json", "{\"id\":\"a\",\"name\":\"A\"}")
        try write("docx-theme-wrong.json", "{\"id\":\"other\",\"name\":\"X\"}")
        try write("docx-theme-broken.json", "{nope")
        try write("github.json", "{\"id\":\"github\",\"name\":\"Unrelated\"}")
        try write("config.json", "{\"id\":\"cfg\",\"name\":\"Unrelated\"}")
        XCTAssertEqual(DocxThemeStore.themes(inDirectory: directory).map(\.id), ["a", "b"])
    }

    func testStoreFallsBackToGitHub() throws {
        XCTAssertEqual(DocxThemeStore.themes(inDirectory: nil), [.github])
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }
        XCTAssertEqual(DocxThemeStore.themes(inDirectory: empty), [.github])
        XCTAssertEqual(DocxThemeStore.theme(id: "does-not-exist"), .github)
    }

    func testUserThemesAddToAndOverrideBundledOnes() throws {
        let user = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: user) }
        try "{\"id\":\"mine\",\"name\":\"Mine\"}".write(
            to: user.appendingPathComponent("docx-theme-mine.json"), atomically: true, encoding: .utf8)
        try "{\"id\":\"serif\",\"name\":\"My Serif\",\"global\":{\"font\":\"Arial\"}}".write(
            to: user.appendingPathComponent("docx-theme-serif.json"), atomically: true, encoding: .utf8)
        let bundled = bundledThemes()
        let merged = DocxThemeStore.merged(bundled: bundled, user: DocxThemeStore.loadFiles(in: user))
        XCTAssertEqual(merged.map(\.id), ["document", "github", "mine", "minimal", "serif"])
        XCTAssertEqual(merged.first { $0.id == "serif" }?.name, "My Serif")
        XCTAssertEqual(DocxThemeStore.merged(bundled: bundled, user: []), bundled)
        XCTAssertEqual(DocxThemeStore.merged(bundled: [], user: []), [.github])
    }

    func testDocumentThemeTakesItsLookFromTheRCADocument() throws {
        let report = try XCTUnwrap(bundledThemes().first { $0.id == "document" })
        XCTAssertEqual(report.declarations(.heading2).color, "1F3864")
        XCTAssertEqual(report.declarations(.heading2).size, 13)
        XCTAssertEqual(report.declarations(.tableHeader).background, "1F3864")
        XCTAssertEqual(report.declarations(.table).border?.top?.color, "CCCCCC")
        let styles = DocxStyleSheet.xml(for: report)
        XCTAssertTrue(styles.contains("<w:spacing w:before=\"300\" w:after=\"150\"/>"))
        XCTAssertTrue(styles.contains("<w:sz w:val=\"22\"/><w:szCs w:val=\"22\"/><w:lang"))
    }

    func testBundledThemesLoadFromFiles() {
        let ids = bundledThemes().map(\.id)
        XCTAssertEqual(ids, ["document", "github", "minimal", "serif"])
    }
}
