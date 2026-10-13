import Foundation
import XCTest
@testable import MarkdownHelpers

@MainActor
final class DocxCLIOptionTests: XCTestCase {
    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func copyBundledThemes(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let themes = Self.repositoryRoot.appendingPathComponent("daisy/Resources/DocxThemes")
        for source in try FileManager.default.contentsOfDirectory(at: themes, includingPropertiesForKeys: nil) {
            try FileManager.default.copyItem(at: source, to: directory.appendingPathComponent(source.lastPathComponent))
        }
    }

    private func docxPart(_ name: String, at document: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", document.path, name]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let result = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return result
    }

    func testExportsBundledAndCustomThemes() async throws {
        let directory = try temporaryDirectory()
        let input = directory.appendingPathComponent("report.md")
        let bundledOutput = directory.appendingPathComponent("serif.docx")
        let customOutput = directory.appendingPathComponent("custom.docx")
        try "# Report".write(to: input, atomically: true, encoding: .utf8)
        try copyBundledThemes(to: directory.appendingPathComponent(".daisy-resources"))

        let bundledResult = await DaisyExportCommand.run(
            arguments: [input.path, "-f", "docx", "-o", bundledOutput.path, "--theme", "serif", "--mermaid", "off"],
            executableURL: directory.appendingPathComponent("daisy-export"))
        XCTAssertEqual(bundledResult, 0)
        XCTAssertTrue(try docxPart("word/styles.xml", at: bundledOutput).contains("Georgia"))

        let customTheme = directory.appendingPathComponent("custom.json")
        try "{\"id\":\"custom\",\"name\":\"Custom\",\"global\":{\"font\":\"Futura\"}}".write(
            to: customTheme, atomically: true, encoding: .utf8)
        let customResult = await DaisyExportCommand.run(
            arguments: [input.path, "-f", "docx", "-o", customOutput.path,
                        "--theme-file", customTheme.path, "--mermaid", "off"],
            executableURL: directory.appendingPathComponent("daisy-export"))
        XCTAssertEqual(customResult, 0)
        XCTAssertTrue(try docxPart("word/styles.xml", at: customOutput).contains("Futura"))
    }

    func testStrictMermaidFailsWhenDiagramCannotRender() async throws {
        let directory = try temporaryDirectory()
        let input = directory.appendingPathComponent("invalid.md")
        let output = directory.appendingPathComponent("invalid.docx")
        try "```mermaid\ngraph TD\n  A -->\n  ((((\n```".write(to: input, atomically: true, encoding: .utf8)

        let result = await DaisyExportCommand.run(
            arguments: [input.path, "-f", "docx", "-o", output.path, "--mermaid", "strict"],
            executableURL: directory.appendingPathComponent("daisy-export"))

        XCTAssertEqual(result, 69)
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }
}
