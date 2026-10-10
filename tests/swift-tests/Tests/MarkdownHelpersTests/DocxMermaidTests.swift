import AppKit
import Foundation
import XCTest
@testable import MarkdownHelpers

final class DocxMermaidTests: XCTestCase {
    private let flowchart = "graph TD\n  A[Start] --> B[End]\n"

    /// Exports `markdown` and returns every part of the package by name.
    private func export(
        _ markdown: String, diagrams: [String: DocxImage] = [:]
    ) throws -> [String: Data] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("out.docx")
        try DocxExporter.write(
            markdown: markdown, assetBaseURL: directory, mermaidDiagrams: diagrams, to: file)
        let unzipped = directory.appendingPathComponent("parts")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", file.path, "-d", unzipped.path]
        try process.run()
        process.waitUntilExit()
        var parts: [String: Data] = [:]
        let enumerator = FileManager.default.enumerator(at: unzipped, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard !url.hasDirectoryPath else { continue }
            let name = String(url.standardizedFileURL.path.dropFirst(unzipped.standardizedFileURL.path.count + 1))
            parts[name] = try Data(contentsOf: url)
        }
        return parts
    }

    private func text(_ parts: [String: Data], _ name: String) throws -> String {
        String(decoding: try XCTUnwrap(parts[name], name), as: UTF8.self)
    }

    private func stubPNG(width: Int, height: Int) throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }

    // MARK: Sources

    func testMermaidSourcesFindsFencesAtAnyDepthInOrder() {
        let markdown = """
        ---
        title: x
        ---
        ```mermaid
        graph LR
          A --> B
        ```

        ```swift
        let x = 1
        ```

        > ```Mermaid title
        > pie
        > ```

        - item

          ```mermaid
          sequenceDiagram
          ```
        """
        XCTAssertEqual(DocxExporter.mermaidSources(in: markdown), [
            "graph LR\n  A --> B\n",
            "pie\n",
            "sequenceDiagram\n",
        ])
    }

    // MARK: Export

    func testRenderedDiagramIsEmbeddedAsCentredPicture() throws {
        let png = try stubPNG(width: 400, height: 200)
        let markdown = "Before\n\n```mermaid\n\(flowchart)```\n\nAfter\n"
        let parts = try export(markdown, diagrams: [
            flowchart: DocxImage(data: png, ext: "png", width: 200, height: 100),
        ])
        let document = try text(parts, "word/document.xml")
        XCTAssertTrue(XMLParser(data: Data(document.utf8)).parse())
        XCTAssertTrue(document.contains("<w:jc w:val=\"center\"/></w:pPr><w:r><w:drawing>"))
        // 200 CSS px = 150 pt = 1 905 000 EMU.
        XCTAssertTrue(document.contains("<wp:extent cx=\"1905000\" cy=\"952500\"/>"))
        XCTAssertTrue(document.contains("descr=\"graph TD\n  A[Start] --&gt; B[End]\n\""))
        XCTAssertFalse(document.contains("CodeBlock"))
        XCTAssertEqual(parts["word/media/image1.png"], png)
        XCTAssertTrue(try text(parts, "[Content_Types].xml")
            .contains("<Default Extension=\"png\" ContentType=\"image/png\"/>"))
        XCTAssertTrue(try text(parts, "word/_rels/document.xml.rels")
            .contains("Target=\"media/image1.png\""))
    }

    func testTallDiagramShrinksToFitThePage() throws {
        let png = try stubPNG(width: 10, height: 10)
        let parts = try export("```mermaid\n\(flowchart)```\n", diagrams: [
            flowchart: DocxImage(data: png, ext: "png", width: 300, height: 3000),
        ])
        let document = try text(parts, "word/document.xml")
        let extent = try XCTUnwrap(document.firstMatch(of: /<wp:extent cx="(\d+)" cy="(\d+)"\/>/))
        let cx = try XCTUnwrap(Double(extent.1)), cy = try XCTUnwrap(Double(extent.2))
        // A4 or Letter less 1 in margins, in EMU; the 3000 px original is 2250 pt.
        XCTAssertLessThan(cy, (842 - 144) * 12700)
        XCTAssertEqual(cy / cx, 10, accuracy: 0.01, "keeps its aspect ratio")
    }

    func testDiagramWithoutRenderingExportsAsCode() throws {
        let markdown = "```mermaid\n\(flowchart)```\n"
        let other = "graph LR\n  X --> Y\n"
        let png = try stubPNG(width: 10, height: 10)
        let parts = try export(markdown, diagrams: [
            other: DocxImage(data: png, ext: "png", width: 10, height: 10),
        ])
        let document = try text(parts, "word/document.xml")
        XCTAssertTrue(document.contains("<w:pStyle w:val=\"CodeBlock\"/>"))
        XCTAssertFalse(document.contains("<w:drawing>"))
        XCTAssertNil(parts["word/media/image1.png"])
    }

    // MARK: Rasterizer

    @MainActor
    func testRasterizerDrawsDiagramsAndSkipsInvalidSource() async throws {
        let invalid = "graph TD\n  A --> \n  ((((\n"
        let images = await MermaidRasterizer.render([flowchart, invalid, flowchart])
        XCTAssertNil(images[invalid])
        XCTAssertEqual(images.count, 1)
        let image = try XCTUnwrap(images[flowchart])
        XCTAssertEqual(image.ext, "png")
        XCTAssertGreaterThan(image.width, 20)
        XCTAssertGreaterThan(image.height, 50, "two stacked nodes")

        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: image.data))
        XCTAssertEqual(Double(bitmap.pixelsWide), image.width * 2, accuracy: 1, "2x PNG")
        // Label text and edges are dark; a blank or failed snapshot has none.
        var dark = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                   color.redComponent + color.greenComponent + color.blueComponent < 1.2 {
                    dark += 1
                }
            }
        }
        XCTAssertGreaterThan(dark, 50)
    }

    @MainActor
    func testDrawingSizeCapsSidesAndPixelArea() throws {
        let small = try XCTUnwrap(MermaidRasterizer.drawingSize(width: 300.5, height: 200))
        XCTAssertEqual(small, CGSize(width: 301, height: 200), "small diagrams keep their size")

        // A near-square diagram within the side cap would still be 8000×8000
        // pixels at 2×; the area cap brings it down to about 4096×4096.
        let square = try XCTUnwrap(MermaidRasterizer.drawingSize(width: 4000, height: 3900))
        let pixels = square.width * 2 * square.height * 2
        XCTAssertLessThanOrEqual(pixels, 4096 * 4096 + 2 * (square.width + square.height) * 2 + 4)
        XCTAssertGreaterThan(pixels, 4000 * 4000, "capped, not shrunk further than needed")
        XCTAssertEqual(square.width / square.height, 4000 / 3900, accuracy: 0.01, "keeps its shape")

        // A long, thin diagram is limited by the side cap, not the area cap.
        let tall = try XCTUnwrap(MermaidRasterizer.drawingSize(width: 100, height: 8000))
        XCTAssertEqual(tall.height, 4000)
        XCTAssertEqual(tall.width, 50)

        XCTAssertNil(MermaidRasterizer.drawingSize(width: 0, height: 100))
        XCTAssertNil(MermaidRasterizer.drawingSize(width: .infinity, height: 100))
    }
}
