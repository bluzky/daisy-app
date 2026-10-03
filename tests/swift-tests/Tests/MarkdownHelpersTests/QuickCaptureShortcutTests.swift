import Foundation
import XCTest
@testable import MarkdownHelpers

final class QuickCaptureShortcutTests: XCTestCase {
    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "QuickCaptureShortcutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    func testDefaultIsControlOptionSpace() {
        XCTAssertEqual(QuickCaptureShortcut.default.displayString, "⌃⌥Space")
        XCTAssertTrue(QuickCaptureShortcut.default.isValid)
    }

    func testMissingValueFallsBackToDefault() throws {
        XCTAssertEqual(QuickCaptureShortcut.current(from: try makeDefaults()), .default)
    }

    func testStoredShortcutRoundTrips() throws {
        let defaults = try makeDefaults()
        let custom = QuickCaptureShortcut(keyCode: 45, modifiers: [.command, .shift], keyLabel: "N")
        QuickCaptureShortcut.store(custom, in: defaults)
        XCTAssertEqual(QuickCaptureShortcut.current(from: defaults), custom)
        XCTAssertEqual(custom.displayString, "⇧⌘N")
    }

    func testShiftOnlyOrUnlabelledShortcutIsInvalid() {
        XCTAssertFalse(QuickCaptureShortcut(keyCode: 0, modifiers: [.shift], keyLabel: "A").isValid)
        XCTAssertFalse(QuickCaptureShortcut(keyCode: 0, modifiers: [], keyLabel: "A").isValid)
        XCTAssertFalse(QuickCaptureShortcut(keyCode: 0, modifiers: [.command], keyLabel: "").isValid)
    }

    func testInvalidStoredShortcutFallsBackToDefault() throws {
        let defaults = try makeDefaults()
        QuickCaptureShortcut.store(QuickCaptureShortcut(keyCode: 0, modifiers: [.shift], keyLabel: "A"),
                                   in: defaults)
        XCTAssertEqual(QuickCaptureShortcut.current(from: defaults), .default)
    }

    func testNewEntryIsADatedHeadingWithRoomToType() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = Date(timeIntervalSince1970: 1_790_000_000) // 2026-09-21 14:13:20 UTC
        XCTAssertEqual(QuickCaptureSetting.newEntry(at: date, calendar: calendar),
                       "## 2026-09-21 14:13\n\n")
    }
}
