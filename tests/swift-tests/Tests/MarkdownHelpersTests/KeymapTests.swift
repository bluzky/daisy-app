import XCTest
@testable import MarkdownHelpers

final class KeymapTests: XCTestCase {
    func testDefaultBindingsRoundTrip() {
        for command in KeymapCommand.allCases {
            for binding in Keymap().bindings(for: command) {
                XCTAssertEqual(KeyBinding(string: binding.description), binding)
            }
        }
    }

    func testFileOverridesAndNullUnbindsDefault() throws {
        let data = Data("""
        {
          "version": 1,
          "reading": {
            "opt+down": null,
            "j": "go.nextItem"
          }
        }
        """.utf8)
        let keymap = Keymap(file: try KeymapFile(data: data))
        XCTAssertNil(keymap.command(for: KeyBinding(string: "opt+down")!, in: .reading))
        XCTAssertEqual(keymap.command(for: KeyBinding(string: "j")!, in: .reading), .goNextItem)
    }

    func testWrongContextAndUnknownCommandAreReportedButIgnored() throws {
        let data = Data("""
        { "editing": { "cmd+b": "go.nextItem", "cmd+y": "new.command" } }
        """.utf8)
        let keymap = Keymap(file: try KeymapFile(data: data))
        XCTAssertEqual(keymap.command(for: KeyBinding(string: "cmd+b")!, in: .editing), .formatBold)
        XCTAssertTrue(keymap.diagnostics.contains { $0.contains("does not belong") })
        XCTAssertTrue(keymap.diagnostics.contains { $0.contains("Unknown command") })
    }

    func testDuplicateKeysPreventRewrite() throws {
        let data = Data("""
        { "reading": { "j": "go.nextItem", "j": "go.previousItem" } }
        """.utf8)
        var file = try KeymapFile(data: data)
        XCTAssertTrue(file.hasDuplicateKeys)
        XCTAssertThrowsError(try file.set(KeyBinding(string: "k")!, commandID: "go.nextItem", in: .reading))
    }

    func testUnknownTopLevelAndEntriesSurviveRewrite() throws {
        let data = Data("""
        {
          "future": { "keep": [1, true] },
          "reading": { "j": "future.command" },
          "version": 1
        }
        """.utf8)
        var file = try KeymapFile(data: data)
        try file.set(KeyBinding(string: "k")!, commandID: "go.nextItem", in: .reading)
        let rewritten = String(decoding: file.serialized(), as: UTF8.self)
        XCTAssertTrue(rewritten.contains("\"future\""))
        XCTAssertTrue(rewritten.contains("\"future.command\""))
        XCTAssertTrue(rewritten.contains("\"k\": \"go.nextItem\""))
    }

    func testNewerVersionIsReadOnly() throws {
        let file = try KeymapFile(data: Data("{ \"version\": 2 }".utf8))
        XCTAssertTrue(file.isReadOnly)
        XCTAssertTrue(file.diagnostics.contains { $0.contains("newer Daisy") })
    }

    func testConflictChecksGlobalAndMode() {
        let keymap = Keymap()
        XCTAssertEqual(keymap.conflicts(for: KeyBinding(string: "cmd+l")!, in: .editing), [.viewToggleSidebar])
        XCTAssertTrue(keymap.conflicts(for: KeyBinding(string: "cmd+b")!, in: .reading).isEmpty)
    }
}
