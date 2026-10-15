import Foundation
import XCTest
@testable import MarkdownHelpers

final class TextFileSettingsTests: XCTestCase {

    func testParsingSplitsOnCommasAndWhitespaceAndLowercases() {
        XCTAssertEqual(TextFileSettings.parse("Lua, PHP;  Justfile\nzig"), ["lua", "php", "justfile", "zig"])
    }

    func testParsingDropsEmptyEntriesAndGlobPrefixes() {
        XCTAssertEqual(TextFileSettings.parse(" , *.lua ,, . "), ["lua"])
    }

    func testBuiltInsMatchWithoutAnyAdditions() {
        XCTAssertTrue(TextFileSettings.isText(fileName: "main.swift", custom: []))
        XCTAssertTrue(TextFileSettings.isText(fileName: "Makefile", custom: []))
        XCTAssertFalse(TextFileSettings.isText(fileName: "photo.png", custom: []))
    }

    func testAnAddedExtensionMatches() {
        XCTAssertFalse(TextFileSettings.isText(fileName: "init.lua", custom: []))
        XCTAssertTrue(TextFileSettings.isText(fileName: "init.lua", custom: ["lua"]))
    }

    func testADottedExtensionEntryMatchesTheExtension() {
        XCTAssertTrue(TextFileSettings.isText(fileName: "init.lua", custom: [".lua"]))
    }

    func testAnAddedFileNameMatchesOnlyThatName() {
        XCTAssertTrue(TextFileSettings.isText(fileName: "Justfile", custom: ["justfile"]))
        XCTAssertFalse(TextFileSettings.isText(fileName: "Justfile.bak", custom: ["justfile"]))
    }

    func testAMarkdownExtensionAddedByTheReaderStillClassifiesAsMarkdown() {
        // `FileKind` checks Markdown first, so an entry cannot demote a note.
        let saved = TextFileSettings.customText
        defer { TextFileSettings.setCustomText(saved) }
        TextFileSettings.setCustomText("md")
        XCTAssertEqual(FileKind.classify(fileName: "note.md"), .markdown)
    }

    func testSettingTheTextMakesItCurrentAndNormalised() {
        let saved = TextFileSettings.customText
        defer { TextFileSettings.setCustomText(saved) }
        let defaults = UserDefaults(suiteName: "TextFileSettingsTests-\(UUID().uuidString)")!
        TextFileSettings.setCustomText("Zig, LUA", defaults: defaults)

        XCTAssertEqual(TextFileSettings.customText, "lua, zig")
        XCTAssertEqual(defaults.string(forKey: TextFileSettings.defaultsKey), "lua, zig")
        XCTAssertEqual(FileKind.classify(fileName: "main.zig"), .text)
    }
}
