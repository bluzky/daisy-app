import Foundation
import XCTest
@testable import MarkdownHelpers

final class LaunchBehaviorSettingTests: XCTestCase {
    func testDefaultsToReopeningTheLastSessionWhenNothingHasBeenStored() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(LaunchBehaviorSetting.read(from: defaults), .reopenLastSession)
        XCTAssertEqual(LaunchBehaviorSetting.read(from: nil), .reopenLastSession)
    }

    func testEveryChoiceRoundTripsAndTheDefaultClearsItsKey() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        for value in LaunchBehaviorSetting.allCases {
            LaunchBehaviorSetting.write(value, to: defaults)
            XCTAssertEqual(LaunchBehaviorSetting.read(from: defaults), value)
        }
        LaunchBehaviorSetting.write(.reopenLastSession, to: defaults)
        XCTAssertNil(defaults.object(forKey: LaunchBehaviorSetting.defaultsKey))
    }

    func testAnUnknownStoredValueFallsBackToTheDefault() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("somethingRemoved", forKey: LaunchBehaviorSetting.defaultsKey)
        XCTAssertEqual(LaunchBehaviorSetting.read(from: defaults), .reopenLastSession)
    }

    func testAFileInsideTheFolderOpensInTheFolderWindow() {
        let plan = LaunchBehaviorSetting.restorePlan(
            folderURL: URL(fileURLWithPath: "/notes"),
            fileURL: URL(fileURLWithPath: "/notes/daily/today.md"))
        XCTAssertTrue(plan.opensFileInFolderWindow)
    }

    func testAFileOutsideTheFolderGetsItsOwnWindow() {
        let plan = LaunchBehaviorSetting.restorePlan(
            folderURL: URL(fileURLWithPath: "/notes"),
            fileURL: URL(fileURLWithPath: "/notes-archive/today.md"))
        XCTAssertFalse(plan.opensFileInFolderWindow)
        XCTAssertFalse(plan.isEmpty)
    }

    func testNothingToRestoreIsEmpty() {
        let plan = LaunchBehaviorSetting.restorePlan(folderURL: nil, fileURL: nil)
        XCTAssertTrue(plan.isEmpty)
        XCTAssertFalse(LaunchBehaviorSetting.restorePlan(
            folderURL: nil, fileURL: URL(fileURLWithPath: "/a.md")).opensFileInFolderWindow)
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "doc.daisy.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        return (defaults, suiteName)
    }
}
