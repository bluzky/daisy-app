import Foundation
import XCTest
@testable import MarkdownHelpers

final class CodeDocumentTests: XCTestCase {

    func testLanguageComesFromTheExtensionOrItsAlias() {
        XCTAssertEqual(CodeDocument.language(forFileName: "main.swift"), "swift")
        XCTAssertEqual(CodeDocument.language(forFileName: "run.sh"), "bash")
        XCTAssertEqual(CodeDocument.language(forFileName: "app.py"), "python")
        XCTAssertEqual(CodeDocument.language(forFileName: "ci.yml"), "yaml")
        XCTAssertEqual(CodeDocument.language(forFileName: "index.mjs"), "javascript")
        XCTAssertEqual(CodeDocument.language(forFileName: "View.m"), "objective-c")
    }

    func testDotfilesUseTheirName() {
        XCTAssertEqual(CodeDocument.language(forFileName: ".zshrc"), "bash")
    }

    func testPlainTextAndUnknownLanguagesAreEmpty() {
        for name in ["notes.txt", "Makefile", "init.lua", "noextension"] {
            XCTAssertEqual(CodeDocument.language(forFileName: name), "", name)
        }
    }

    // MARK: - Editable

    private func temporaryFile(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "CodeDocumentTests-\(UUID().uuidString).txt")
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testAValidUTF8FileIsEditable() throws {
        XCTAssertTrue(CodeDocument.isEditable(at: try temporaryFile(Data("héllo".utf8))))
    }

    func testAnEmptyFileIsEditable() throws {
        XCTAssertTrue(CodeDocument.isEditable(at: try temporaryFile(Data())))
    }

    func testAFileThatIsNotUTF8IsNotEditable() throws {
        XCTAssertFalse(CodeDocument.isEditable(at: try temporaryFile(Data([0xFF, 0xFE, 0x00, 0x80]))))
    }

    func testAFileOverTheSizeCapIsNotEditable() throws {
        let big = Data(repeating: UInt8(ascii: "a"), count: CodeDocument.maximumBytes + 1)
        XCTAssertFalse(CodeDocument.isEditable(at: try temporaryFile(big)))
    }

    func testAMissingFileIsNotEditable() {
        XCTAssertFalse(CodeDocument.isEditable(at: URL(fileURLWithPath: "/no/such/file.txt")))
    }
}
