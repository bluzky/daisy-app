import XCTest
@testable import MarkdownHelpers

final class KeymapTests: XCTestCase {
    func testLegacyInspectorBindingLoadsAsTasksWithoutDiagnostics() throws {
        let file = try KeymapFile(data: Data("""
        { "global": { "ctrl+shift+cmd+i": "view.toggleInspector" } }
        """.utf8))
        let keymap = Keymap(file: file)
        let binding = KeyBinding(string: "ctrl+shift+cmd+i")!
        XCTAssertEqual(keymap.command(for: binding, in: .global), .viewToggleTasks)
        XCTAssertTrue(keymap.diagnostics.isEmpty)
        XCTAssertEqual(keymap.conflicts(for: binding, in: .global), [.viewToggleTasks])
    }

    func testTasksIsOnlyCommandInSettingsAndDefaults() {
        XCTAssertTrue(KeymapCommand.allCases.contains(.viewToggleTasks))
        XCTAssertFalse(KeymapCommand.allCases.map(\.rawValue).contains("view.toggleInspector"))
        XCTAssertNil(KeymapCommand(rawValue: "view.toggleInspector"))
        XCTAssertEqual(KeymapCommand.viewToggleTasks.titleKey, "Tasks")
        let binding = KeyBinding(string: "shift+cmd+i")!
        XCTAssertEqual(Keymap.defaultBindings(for: .viewToggleTasks), [binding])
        XCTAssertEqual(Keymap().conflicts(for: binding, in: .global), [.viewToggleTasks])
        XCTAssertFalse(Keymap().changeToken.contains("view.toggleInspector"))
    }

    func testReferencesHasItsOwnDefaultBinding() {
        let binding = KeyBinding(string: "shift+cmd+r")!
        XCTAssertEqual(KeymapCommand.viewToggleReferences.context, .global)
        XCTAssertEqual(KeymapCommand.viewToggleReferences.titleKey, "References")
        XCTAssertEqual(Keymap.defaultBindings(for: .viewToggleReferences), [binding])
        XCTAssertEqual(Keymap().conflicts(for: binding, in: .global), [.viewToggleReferences])
    }

    func testOpenLinkAtCaretDefaultsToCommandPeriodWhileEditing() {
        let binding = KeyBinding(string: "cmd+.")!
        XCTAssertEqual(KeymapCommand.goOpenLinkAtCaret.context, .editing)
        XCTAssertEqual(KeymapCommand.goOpenLinkAtCaret.titleKey, "Open Link at Caret")
        XCTAssertEqual(Keymap.defaultBindings(for: .goOpenLinkAtCaret), [binding])
        XCTAssertEqual(Keymap().conflicts(for: binding, in: .editing), [.goOpenLinkAtCaret])
    }

    func testSettingsRewriteMigratesLegacyInspectorID() throws {
        var file = try KeymapFile(data: Data("""
        { "global": { "ctrl+shift+cmd+i": "view.toggleInspector" } }
        """.utf8))
        try file.set(KeyBinding(string: "ctrl+cmd+k")!, commandID: "file.omniSearch", in: .global)
        let rewritten = String(decoding: file.serialized(), as: UTF8.self)
        XCTAssertTrue(rewritten.contains("view.toggleTasks"))
        XCTAssertFalse(rewritten.contains("view.toggleInspector"))

        try file.removeOverrides(for: KeymapCommand.viewToggleTasks.rawValue, in: .global)
        XCTAssertFalse(file.entries(in: .global).contains { $0.commandID == "view.toggleTasks" })
    }

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
