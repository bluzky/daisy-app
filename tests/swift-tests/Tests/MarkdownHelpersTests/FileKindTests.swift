import Foundation
import XCTest
@testable import MarkdownHelpers

final class FileKindTests: XCTestCase {

    func testEveryMarkdownExtensionIsMarkdown() {
        for ext in ["md", "markdown", "mdown", "mkd", "mdwn", "mdx", "mkdn"] {
            XCTAssertEqual(FileKind.classify(fileName: "note.\(ext)"), .markdown, ext)
        }
    }

    func testTheExtensionMatchIsCaseInsensitive() {
        XCTAssertEqual(FileKind.classify(fileName: "NOTES.MD"), .markdown)
    }

    func testTxtIsText() {
        XCTAssertEqual(FileKind.classify(fileName: "notes.txt"), .text)
    }

    func testSourceFilesAndKnownNamesAreText() {
        for name in ["main.swift", "app.py", "config.yml", "Makefile", "Dockerfile", ".gitignore", ".zshrc", "UPPER.JSON"] {
            XCTAssertEqual(FileKind.classify(fileName: name), .text, name)
        }
    }

    func testEverythingElseIsExternal() {
        for name in ["diagram.png", "paper.pdf", "archive.zip", "noextension", "movie.mov", "data.bin"] {
            XCTAssertEqual(FileKind.classify(fileName: name), .external, name)
        }
    }

    func testMarkdownAndTextOpenInDaisy() {
        XCTAssertTrue(FileKind.markdown.opensInDaisy)
        XCTAssertTrue(FileKind.text.opensInDaisy)
        XCTAssertFalse(FileKind.external.opensInDaisy)
    }

    func testClassifyingAURLUsesItsLastComponent() {
        XCTAssertEqual(FileKind.classify(URL(fileURLWithPath: "/tmp/a.md/photo.png")), .external)
    }
}
