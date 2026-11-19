import Foundation
import XCTest
@testable import MarkdownHelpers

final class FileTreeHiddenPatternsTests: XCTestCase {
    private func hidden(_ patterns: String, _ path: String, isDirectory: Bool = false) -> Bool {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        return FileTreeHiddenPatterns(patterns).isHidden(name: name, relativePath: path, isDirectory: isDirectory)
    }

    func testAC_1_1_name_pattern_hides_at_any_depth() {
        XCTAssertTrue(hidden("journals", "journals", isDirectory: true))
        XCTAssertTrue(hidden("journals", "notes/deep/journals", isDirectory: true))
        XCTAssertFalse(hidden("journals", "journals.md"))
    }

    func testAC_1_2_comma_list_with_spaces_and_globs() {
        let text = "*.log, drafts"
        XCTAssertTrue(hidden(text, "a.log"))
        XCTAssertTrue(hidden(text, "x/drafts", isDirectory: true))
        XCTAssertFalse(hidden(text, "readme.md"))
        XCTAssertFalse(hidden(", ,", "anything"))
        XCTAssertTrue(hidden("note-?.md", "note-1.md"))
        XCTAssertTrue(hidden("[a-c]*.md", "b.md"))
        XCTAssertFalse(hidden("[a-c]*.md", "d.md"))
    }

    func testAC_1_3_path_pattern_matches_relative_path_only() {
        XCTAssertTrue(hidden("notes/journals", "notes/journals", isDirectory: true))
        XCTAssertFalse(hidden("notes/journals", "archive/journals", isDirectory: true))
        XCTAssertFalse(hidden("notes/*", "notes/a/b"))
        XCTAssertTrue(hidden("notes/*", "notes/a"))
    }

    func testAC_1_4_trailing_slash_matches_folders_only() {
        XCTAssertTrue(hidden("journals/", "journals", isDirectory: true))
        XCTAssertFalse(hidden("journals/", "journals", isDirectory: false))
    }

    func testAC_1_7_toggle_lists_pattern_matches_and_leaves_the_text_alone() {
        let patterns = FileTreeHiddenPatterns("journals")
        XCTAssertFalse(patterns.isListed(name: "journals", relativePath: "journals", isDirectory: true, showsHiddenFiles: false))
        XCTAssertTrue(patterns.isListed(name: "journals", relativePath: "journals", isDirectory: true, showsHiddenFiles: true))
        XCTAssertTrue(patterns.isListed(name: "a.md", relativePath: "a.md", isDirectory: false, showsHiddenFiles: false))
        XCTAssertEqual(patterns, FileTreeHiddenPatterns("journals"))
    }

    func testAC_1_6_opened_folder_is_never_hidden() throws {
        let key = FileTreeHiddenPatterns.patternsDefaultsKey
        let saved = UserDefaults.standard.string(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        UserDefaults.standard.set("journals", forKey: key)

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("journals")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("journals"),
                                                withIntermediateDirectories: true)
        try "x".write(to: root.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

        let names = FileTreeHiddenPatterns.listedEntries(in: root, relativePath: "").map(\.url.lastPathComponent)
        XCTAssertEqual(names, ["a.md"])
    }

    func testMatchingIgnoresCase() {
        XCTAssertTrue(hidden("Journals", "journals", isDirectory: true))
    }

    func testEmptyTextHidesNothing() {
        XCTAssertTrue(FileTreeHiddenPatterns("").isEmpty)
        XCTAssertFalse(hidden("", "journals", isDirectory: true))
    }

    func testAC_1_5_commit_notification_name_is_stable() {
        XCTAssertEqual(FileTreeHiddenPatterns.didChangeNotification.rawValue,
                       "MarkdownPreview.fileTreeHiddenPatternsDidChange")
    }

    func testAC_1_8_flag_is_stored_and_read_back() {
        let saved = FileTreeHiddenPatterns.showsHiddenFiles
        defer { FileTreeHiddenPatterns.showsHiddenFiles = saved }
        FileTreeHiddenPatterns.showsHiddenFiles = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: FileTreeHiddenPatterns.showsHiddenFilesDefaultsKey))
        XCTAssertTrue(FileTreeHiddenPatterns.showsHiddenFiles)
        FileTreeHiddenPatterns.showsHiddenFiles = false
        XCTAssertFalse(FileTreeHiddenPatterns.showsHiddenFiles)
    }
}
