import Foundation
import Darwin
import XCTest
@testable import MarkdownHelpers

final class ThemePresetTests: XCTestCase {
    func testMigrationWorker() throws {
        let env = ProcessInfo.processInfo.environment
        guard let suite = env["THEME_MIGRATION_TEST_SUITE"],
              let directory = env["THEME_MIGRATION_TEST_DIRECTORY"] else { return }
        let shared = try XCTUnwrap(UserDefaults(suiteName: suite))
        let legacy = try XCTUnwrap(UserDefaults(suiteName: suite + ".legacy"))
        defer { legacy.removePersistentDomain(forName: suite + ".legacy") }
        ThemePreset.defaultPreset.recordApplied(in: legacy)
        let url = URL(fileURLWithPath: directory)
        try Data().write(to: url.appendingPathComponent("ready"))
        ThemePreset.migrateLegacyValues(from: legacy, to: shared,
                                       lockURL: url.appendingPathComponent("lock"))
        try Data().write(to: url.appendingPathComponent("finished"))
    }

    func testMigrationWaitsForOtherProcessAndRefreshesSharedSelection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "doc.daisy.tests.\(UUID().uuidString)"
        let shared = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { shared.removePersistentDomain(forName: suite) }
        let descriptor = open(directory.appendingPathComponent("lock").path,
                              O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        XCTAssertEqual(flock(descriptor, LOCK_EX), 0)

        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        child.arguments = ["xctest", "-XCTest", "MarkdownHelpersTests.ThemePresetTests/testMigrationWorker",
                           Bundle(for: Self.self).bundleURL.path]
        var environment = ProcessInfo.processInfo.environment
        environment["THEME_MIGRATION_TEST_SUITE"] = suite
        environment["THEME_MIGRATION_TEST_DIRECTORY"] = directory.path
        child.environment = environment
        try child.run()
        defer { if child.isRunning { child.terminate(); child.waitUntilExit() } }
        let deadline = Date().addingTimeInterval(15)
        while !FileManager.default.fileExists(atPath: directory.appendingPathComponent("ready").path),
              child.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("ready").path))
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("finished").path))
        let ember = try XCTUnwrap(ThemePreset.builtIn.first { $0.name == "Ember" })
        ember.recordApplied(in: shared)
        var look = ember.restoredLook(in: shared)
        look.layout.lineSpacing = 1.87
        ember.save(look, in: shared)
        shared.synchronize()
        XCTAssertEqual(flock(descriptor, LOCK_UN), 0)
        let completionDeadline = Date().addingTimeInterval(15)
        while child.isRunning, Date() < completionDeadline { Thread.sleep(forTimeInterval: 0.01) }
        XCTAssertFalse(child.isRunning)
        guard !child.isRunning else { return }
        XCTAssertEqual(child.terminationStatus, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("finished").path))
        shared.synchronize()
        XCTAssertEqual(ThemePreset.applied(in: shared), ember)
        XCTAssertEqual(ember.restoredLook(in: shared), look)
    }

    func testMigrationFillsMissingLooksWithoutReplacingSharedSelection() throws {
        let names = (0..<2).map { _ in "doc.daisy.tests.\(UUID().uuidString)" }
        let stores = try names.map { try XCTUnwrap(UserDefaults(suiteName: $0)) }
        defer { for (name, store) in zip(names, stores) { store.removePersistentDomain(forName: name) } }
        let original = ThemePreset.defaultPreset
        let ember = try XCTUnwrap(ThemePreset.builtIn.first { $0.name == "Ember" })
        original.recordApplied(in: stores[1])
        ember.recordApplied(in: stores[0])
        var look = ember.restoredLook(in: stores[0])
        look.layout.lineSpacing = 1.87
        ember.save(look, in: stores[0])
        ThemePreset.migrateLegacyValues(from: stores[0], to: stores[1])
        XCTAssertEqual(ThemePreset.applied(in: stores[1]), original)
        XCTAssertEqual(ember.restoredLook(in: stores[1]), look)
    }

    func testAbsentOrInvalidLegacySelectionDoesNotClaimSharedIdentity() throws {
        let names = (0..<3).map { _ in "doc.daisy.tests.\(UUID().uuidString)" }
        let stores = try names.map { try XCTUnwrap(UserDefaults(suiteName: $0)) }
        defer { for (name, store) in zip(names, stores) { store.removePersistentDomain(forName: name) } }
        for invalidID in [nil, "Unknown preset"] as [String?] {
            stores[0].set(invalidID, forKey: ThemePreset.appliedPresetKey)
            ThemePreset.migrateLegacyValues(from: stores[0], to: stores[2])
            XCTAssertNil(stores[2].string(forKey: ThemePreset.appliedPresetKey))
        }
        let ember = try XCTUnwrap(ThemePreset.builtIn.first { $0.name == "Ember" })
        ember.recordApplied(in: stores[1])
        ThemePreset.migrateLegacyValues(from: stores[1], to: stores[2])
        XCTAssertEqual(ThemePreset.applied(in: stores[2]), ember)
    }

    func testSharedThemeIdentityAndSavedLooksWinOverAnotherAppsLegacyValues() throws {
        let names = (0..<3).map { _ in "doc.daisy.tests.\(UUID().uuidString)" }
        let stores = try names.map { try XCTUnwrap(UserDefaults(suiteName: $0)) }
        defer { for (name, store) in zip(names, stores) { store.removePersistentDomain(forName: name) } }
        let (firstApp, secondApp, shared) = (stores[0], stores[1], stores[2])
        let original = ThemePreset.defaultPreset
        let ember = try XCTUnwrap(ThemePreset.builtIn.first { $0.name == "Ember" })
        original.recordApplied(in: firstApp)
        var originalLook = original.restoredLook(in: firstApp)
        originalLook.appearance = .light
        original.save(originalLook, in: firstApp)
        ThemePreset.migrateLegacyValues(from: firstApp, to: shared)
        XCTAssertEqual(original.restoredLook(in: shared), originalLook)

        ember.recordApplied(in: shared)
        ThemeColorsSetting.write(ember.setting, to: shared)
        original.recordApplied(in: secondApp)
        original.save(original.restoredLook(in: secondApp), in: secondApp)
        ThemePreset.migrateLegacyValues(from: secondApp, to: shared)
        XCTAssertEqual(ThemePreset.applied(in: shared), ember)
        XCTAssertEqual(ThemeColorsSetting.read(from: shared), ember.setting)
        XCTAssertEqual(original.restoredLook(in: shared), originalLook)

        original.recordApplied(in: shared)
        ThemeColorsSetting.write(original.restoredLook(in: shared).colors, to: shared)
        let reopened = try XCTUnwrap(UserDefaults(suiteName: names[2]))
        XCTAssertEqual(ThemePreset.applied(in: reopened), original)
        XCTAssertFalse(ThemeColorsSetting.read(from: reopened).isCustomized)
    }

    func testOriginalDarkBackgroundMatchesRequestedRGB() {
        XCTAssertEqual(ThemeColorsSetting.hexString(from: ThemeColorsSetting.defaultColor(.windowBackground, .dark)), "#1C1C1C")
        XCTAssertEqual(ThemeColorsSetting.hexString(from: ThemeColorsSetting.defaultColor(.editorBackground, .dark)), "#1C1C1C")
        XCTAssertEqual(ThemePreset.defaultPreset.darkPalette?.pageBackground, "#1C1C1C")
        XCTAssertFalse(ThemePreset.defaultPreset.setting.isCustomized)
    }

    func testEveryFixedPresetLocksItsAppearanceAndOriginalRemainsAdjustable() {
        let light = Set(["Paper", "Bold", "Calm", "Focus"])
        let dark = Set(["Quiet", "Ember", "Dusk", "Midnight"])
        for preset in ThemePreset.builtIn {
            let required = preset.requiredAppearance
            if light.contains(preset.name) { XCTAssertEqual(required, .light, preset.name) }
            else if dark.contains(preset.name) { XCTAssertEqual(required, .dark, preset.name) }
            else { XCTAssertEqual(preset.name, "Original"); XCTAssertNil(required) }
        }
    }

    func testEmberIsADarkSerifPreset() throws {
        let ember = try XCTUnwrap(ThemePreset.builtIn.first { $0.name == "Ember" })
        XCTAssertEqual(ember.flavor, .dark)
        XCTAssertEqual(ember.font, .iowan)
        XCTAssertNil(ThemePreset.builtIn.first { $0.name == "Graphite" })
    }

    func testThemeIdentityDoesNotDependOnCustomColors() throws {
        let suite = "doc.daisy.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let ember = try XCTUnwrap(ThemePreset.builtIn.first { $0.name == "Ember" })
        ThemeColorsSetting.write(ember.setting, to: defaults)
        XCTAssertEqual(ThemePreset.applied(in: defaults), .defaultPreset)
        XCTAssertNil(ThemePreset.applied(in: defaults).requiredAppearance)
        defaults.set(ember.id, forKey: ThemePreset.appliedPresetKey)
        ThemeColorsSetting.write(ThemeColorsSetting(), to: defaults)
        XCTAssertEqual(ThemePreset.applied(in: defaults).requiredAppearance, .dark)
    }

    func testSavedLooksSurviveSwitchingAndReopeningDefaults() throws {
        let suite = "doc.daisy.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = ThemePreset.defaultPreset
        let ember = try XCTUnwrap(ThemePreset.builtIn.first { $0.name == "Ember" })
        var look = original.restoredLook(in: defaults)
        XCTAssertEqual(look.appearance, .automatic)
        look.appearance = .light
        look.colors = ember.setting // A matching custom palette is still Original.
        look.layout.isCustomized = true
        look.layout.marginsPercent = 25
        look.font = try XCTUnwrap(DocumentFontSetting.allCases.last)
        original.save(look, in: defaults)
        var darkLook = ember.restoredLook(in: defaults)
        darkLook.layout.lineSpacing = 1.8
        darkLook.appearance = .light // Fixed themes must reconcile obsolete saved values.
        ember.save(darkLook, in: defaults)
        let reopened = try XCTUnwrap(UserDefaults(suiteName: suite))
        XCTAssertEqual(original.restoredLook(in: reopened), look)
        XCTAssertEqual(ember.restoredLook(in: reopened).appearance, .dark)
        XCTAssertEqual(ember.restoredLook(in: reopened).layout.lineSpacing, 1.8)
        let reset = ThemePreset.SavedLook(colors: original.setting, font: original.font,
                                         layout: ReaderLayoutSetting(), appearance: .automatic)
        original.save(reset, in: reopened)
        XCTAssertEqual(original.restoredLook(in: defaults), reset)
        XCTAssertEqual(ember.restoredLook(in: defaults).layout.lineSpacing, 1.8)
    }

    func testOriginalLeavesPageBackgroundToNativeWindow() throws {
        let original = ThemePreset.defaultPreset.setting
        XCTAssertFalse(original.isCustomized)
        XCTAssertNil(original.markdownThemeOverrides)
        XCTAssertEqual(EditorHTML.Configuration().lightPageBackground, "transparent")
        XCTAssertEqual(EditorHTML.Configuration().darkPageBackground, "transparent")
        XCTAssertEqual(original.editorOverrideCSS.components(separatedBy: "background: transparent").count - 1, 2)
        for preset in ThemePreset.builtIn where preset != .defaultPreset {
            XCTAssertEqual(preset.setting.markdownThemeOverrides?.darkPageBackground,
                           preset.setting.hexValue(.windowBackground, .dark))
            for scheme in ThemeColorScheme.allCases {
                let background = try XCTUnwrap(preset.setting.hexValue(.windowBackground, scheme))
                XCTAssertTrue(preset.setting.editorOverrideCSS.contains("background: \(background)"))
            }
        }
    }

    func testOriginalClearsEveryStoredColorOverride() throws {
        let suite = "doc.daisy.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        var customized = ThemeColorsSetting()
        for scheme in ThemeColorScheme.allCases {
            for slot in ThemeColorSlot.allCases {
                customized.setHex("#123456", slot, scheme)
            }
        }
        ThemeColorsSetting.write(customized, to: defaults)
        ThemeColorsSetting.write(ThemePreset.defaultPreset.setting, to: defaults)

        let restored = ThemeColorsSetting.read(from: defaults)
        XCTAssertFalse(restored.isCustomized)
        XCTAssertNil(restored.markdownThemeOverrides)
        for scheme in ThemeColorScheme.allCases {
            XCTAssertFalse(restored.hasWindowBackgroundOverride(for: scheme))
            for slot in ThemeColorSlot.allCases {
                XCTAssertNil(defaults.object(forKey: ThemeColorsSetting.defaultsKey(scheme, slot)))
            }
        }
    }

    func testOtherPresetsKeepTheirPalettesForBothAppearances() {
        for preset in ThemePreset.builtIn where preset != .defaultPreset {
            for scheme in ThemeColorScheme.allCases {
                let palette = scheme == .dark ? (preset.darkPalette ?? preset.palette) : preset.palette
                XCTAssertEqual(preset.setting.hexValue(.windowBackground, scheme), palette.pageBackground)
                XCTAssertEqual(preset.setting.hexValue(.codeBlockBackground, scheme), palette.codeBackground)
                XCTAssertEqual(preset.setting.hexValue(.textColor, scheme), palette.text)
                XCTAssertEqual(preset.setting.hexValue(.linkColor, scheme), palette.accent)
                XCTAssertNil(preset.setting.hexValue(.editorBackground, scheme))
            }
        }
    }
}
