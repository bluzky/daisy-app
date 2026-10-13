import Foundation
import XCTest
@testable import MarkdownHelpers

@MainActor
final class DocxCLITests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    func testExportsDocxFromMarkdownFile() async throws {
        let directory = try temporaryDirectory()
        let input = directory.appendingPathComponent("report.md")
        let output = directory.appendingPathComponent("report.docx")
        try "# Report\n\n- first\n- second\n".write(to: input, atomically: true, encoding: .utf8)
        var errors: [String] = []

        let result = await DaisyExportCommand.run(
            arguments: [input.path, "--format", "docx", "--output", output.path, "--mermaid", "off"],
            executableURL: directory.appendingPathComponent("daisy-export"),
            writeStandardError: { errors.append($0) }
        )

        XCTAssertEqual(result, 0)
        XCTAssertTrue(errors.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", output.path, "word/document.xml"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let xml = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertTrue(xml.contains("Report"))
        XCTAssertTrue(xml.contains("first"))
    }

    func testRejectsMissingFormatAndOutput() async {
        var errors: [String] = []
        let result = await DaisyExportCommand.run(
            arguments: ["input.md"],
            executableURL: URL(fileURLWithPath: "/tmp/daisy-export"),
            writeStandardError: { errors.append($0) }
        )

        XCTAssertEqual(result, 64)
        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors[0].contains("--format docx is required."))
    }

    func testRejectsUnknownFormat() async {
        var errors: [String] = []
        let result = await DaisyExportCommand.run(
            arguments: ["input.md", "--format", "pdf", "--output", "out.pdf"],
            executableURL: URL(fileURLWithPath: "/tmp/daisy-export"),
            writeStandardError: { errors.append($0) }
        )

        XCTAssertEqual(result, 64)
        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors[0].contains("--format docx is required."))
    }
}
