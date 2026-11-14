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
        XCTAssertEqual(KeymapCommand.viewToggleTasks.titleKey, "Agenda")
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

    func testHideCompletedTasksDefaultsToShiftCommandH() {
        let binding = KeyBinding(string: "shift+cmd+h")!
        XCTAssertEqual(KeymapCommand.viewToggleCompletedTasks.context, .global)
        XCTAssertEqual(KeymapCommand.viewToggleCompletedTasks.rawValue, "view.toggleCompletedTasks")
        XCTAssertEqual(KeymapCommand.viewToggleCompletedTasks.titleKey, "Hide Completed Tasks")
        XCTAssertEqual(Keymap.defaultBindings(for: .viewToggleCompletedTasks), [binding])
        XCTAssertEqual(Keymap().conflicts(for: binding, in: .global), [.viewToggleCompletedTasks])
    }

    func testPresentFromCurrentSlideDefaultsToOptionShiftCommandP() {
        let binding = KeyBinding(string: "opt+shift+cmd+p")!
        XCTAssertEqual(KeymapCommand.viewPresentFromCurrentSlide.context, .global)
        XCTAssertEqual(KeymapCommand.viewPresentFromCurrentSlide.rawValue, "view.presentFromCurrentSlide")
        XCTAssertEqual(KeymapCommand.viewPresentFromCurrentSlide.titleKey, "Present from Current Slide")
        XCTAssertEqual(Keymap.defaultBindings(for: .viewPresentFromCurrentSlide), [binding])
        XCTAssertEqual(Keymap().conflicts(for: binding, in: .global), [.viewPresentFromCurrentSlide])
    }

    func testSidebarPanesAndSlidePreviewUseCommandDigits() {
        XCTAssertEqual(Keymap.defaultBindings(for: .viewShowOutline), [KeyBinding(string: "cmd+1")!])
        XCTAssertEqual(Keymap.defaultBindings(for: .viewShowProjectNavigator), [KeyBinding(string: "cmd+2")!])
        let preview = KeyBinding(string: "cmd+9")!
        XCTAssertEqual(KeymapCommand.viewToggleSlidePreview.rawValue, "view.toggleSlidePreview")
        XCTAssertEqual(KeymapCommand.viewToggleSlidePreview.titleKey, "Slide Preview")
        XCTAssertEqual(Keymap.defaultBindings(for: .viewToggleSlidePreview), [preview])
        XCTAssertEqual(Keymap().conflicts(for: preview, in: .global), [.viewToggleSlidePreview])
        for digit in ["cmd+1", "cmd+2", "cmd+9"] {
            let binding = KeyBinding(string: digit)!
            for context in [KeymapContext.reading, .editing] {
                XCTAssertTrue(Keymap().conflicts(for: binding, in: context).allSatisfy { $0.context == .global },
                              "\(digit) is free in \(context)")
            }
        }
    }

    func testPresentDefaultsToOptionCommandP() {
        let binding = KeyBinding(string: "opt+cmd+p")!
        XCTAssertEqual(KeymapCommand.viewPresent.context, .global)
        XCTAssertEqual(KeymapCommand.viewPresent.rawValue, "view.present")
        XCTAssertEqual(KeymapCommand.viewPresent.titleKey, "Present")
        XCTAssertEqual(Keymap.defaultBindings(for: .viewPresent), [binding])
        XCTAssertEqual(Keymap().conflicts(for: binding, in: .global), [.viewPresent])
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
