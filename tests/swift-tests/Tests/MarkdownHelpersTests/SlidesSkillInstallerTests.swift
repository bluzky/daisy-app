import Foundation
import XCTest
@testable import MarkdownHelpers

final class SlidesSkillInstallerTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func makeSkill(in root: URL, marker: String) throws -> URL {
        let skill = root.appendingPathComponent("skill-\(marker)", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: skill.appendingPathComponent("references"), withIntermediateDirectories: true)
        try fm.createDirectory(at: skill.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        try marker.write(to: skill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try "guide".write(to: skill.appendingPathComponent("references/slides-guide.md"), atomically: true, encoding: .utf8)
        try "lint".write(to: skill.appendingPathComponent("scripts/check_deck.py"), atomically: true, encoding: .utf8)
        return skill
    }

    func testPresetFoldersUseGivenHome() {
        XCTAssertEqual(SlidesSkillInstaller.Target.claudeCode.defaultFolder(home: "/Users/a")?.path,
                       "/Users/a/.claude/skills")
        XCTAssertEqual(SlidesSkillInstaller.Target.codex.defaultFolder(home: "/Users/a")?.path,
                       "/Users/a/.codex/skills")
        XCTAssertNil(SlidesSkillInstaller.Target.custom.defaultFolder(home: "/Users/a"))
    }

    func testFreshInstallCopiesSkillAndCreatesMissingFolder() throws {
        let root = try temporaryDirectory()
        let skill = try makeSkill(in: root, marker: "v1")
        let target = root.appendingPathComponent("agent/skills", isDirectory: true)

        let installed = try SlidesSkillInstaller.install(bundledSkill: skill, into: target)

        XCTAssertEqual(installed.lastPathComponent, "daisy-slides")
        XCTAssertEqual(try String(contentsOf: installed.appendingPathComponent("SKILL.md"), encoding: .utf8), "v1")
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.appendingPathComponent("references/slides-guide.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.appendingPathComponent("scripts/check_deck.py").path))
    }

    func testReinstallReplacesSkillAndLeavesSiblingsAndNoStaging() throws {
        let root = try temporaryDirectory()
        let target = root.appendingPathComponent("skills", isDirectory: true)
        try FileManager.default.createDirectory(at: target.appendingPathComponent("other-skill"), withIntermediateDirectories: true)
        try "keep".write(to: target.appendingPathComponent("other-skill/SKILL.md"), atomically: true, encoding: .utf8)

        try SlidesSkillInstaller.install(bundledSkill: try makeSkill(in: root, marker: "v1"), into: target)
        let installed = try SlidesSkillInstaller.install(bundledSkill: try makeSkill(in: root, marker: "v2"), into: target)

        XCTAssertEqual(try String(contentsOf: installed.appendingPathComponent("SKILL.md"), encoding: .utf8), "v2")
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("other-skill/SKILL.md"), encoding: .utf8), "keep")
        let entries = try FileManager.default.contentsOfDirectory(atPath: target.path).sorted()
        XCTAssertEqual(entries, ["daisy-slides", "other-skill"])
    }

    func testFailedCopyKeepsExistingInstall() throws {
        let root = try temporaryDirectory()
        let target = root.appendingPathComponent("skills", isDirectory: true)
        let installed = try SlidesSkillInstaller.install(bundledSkill: try makeSkill(in: root, marker: "v1"), into: target)

        let missing = root.appendingPathComponent("does-not-exist", isDirectory: true)
        XCTAssertThrowsError(try SlidesSkillInstaller.install(bundledSkill: missing, into: target))

        XCTAssertEqual(try String(contentsOf: installed.appendingPathComponent("SKILL.md"), encoding: .utf8), "v1")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: target.path), ["daisy-slides"])
    }

    func testReinstallReplacesSymlinkWithoutTouchingItsTarget() throws {
        let root = try temporaryDirectory()
        let target = root.appendingPathComponent("skills", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let checkout = try makeSkill(in: root, marker: "checkout")
        try FileManager.default.createSymbolicLink(at: target.appendingPathComponent("daisy-slides"),
                                                   withDestinationURL: checkout)

        let installed = try SlidesSkillInstaller.install(bundledSkill: try makeSkill(in: root, marker: "v2"), into: target)

        let attributes = try FileManager.default.attributesOfItem(atPath: installed.path)
        XCTAssertEqual(attributes[.type] as? FileAttributeType, .typeDirectory)
        XCTAssertEqual(try String(contentsOf: installed.appendingPathComponent("SKILL.md"), encoding: .utf8), "v2")
        XCTAssertEqual(try String(contentsOf: checkout.appendingPathComponent("SKILL.md"), encoding: .utf8), "checkout")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: target.path), ["daisy-slides"])
    }
}
