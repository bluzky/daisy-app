import Foundation
import XCTest
@testable import MarkdownHelpers

final class WorkspacePageTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspacePageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var pages: URL { root.appendingPathComponent("pages", isDirectory: true) }

    private func contents(of url: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
    }

    private func write(_ text: String, to name: String) throws {
        try FileManager.default.createDirectory(at: pages, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: pages.appendingPathComponent(name))
    }

    func testFileNameKeepsTheMarkerAndFlattensHierarchy() {
        XCTAssertEqual(WorkspacePage.fileName(for: "#daisy"), "#daisy.md")
        XCTAssertEqual(WorkspacePage.fileName(for: "@daisy"), "@daisy.md")
        XCTAssertEqual(WorkspacePage.fileName(for: "+daisy"), "+daisy.md")
        XCTAssertEqual(WorkspacePage.fileName(for: "#area/sub"), "#area--sub.md")
        XCTAssertEqual(WorkspacePage.fileName(for: "#café"), "#café.md")
    }

    func testFileNameRefusesWhatIsNotAToken() {
        for token in ["daisy", "#", "#/a", "#a/", "#a//b", "#123", "#a.b", "#../x", "#a b", "$x", "#a\\b"] {
            XCTAssertNil(WorkspacePage.fileName(for: token), token)
        }
    }

    func testCreatesThePageWithTheTokenAsHeading() throws {
        let page = try WorkspacePage.openOrCreate(token: "#Review", root: root)

        XCTAssertEqual(page.lastPathComponent, "#Review.md")
        XCTAssertEqual(try contents(of: root), ["pages"])
        XCTAssertEqual(try String(contentsOf: page, encoding: .utf8), "# #Review\n")
    }

    func testHierarchicalHeadingKeepsTheSlash() throws {
        let page = try WorkspacePage.openOrCreate(token: "#area/sub", root: root)

        XCTAssertEqual(page.lastPathComponent, "#area--sub.md")
        XCTAssertEqual(try String(contentsOf: page, encoding: .utf8), "# #area/sub\n")
    }

    func testDifferentMarkersGetDifferentPages() throws {
        _ = try WorkspacePage.openOrCreate(token: "#daisy", root: root)
        _ = try WorkspacePage.openOrCreate(token: "@daisy", root: root)
        _ = try WorkspacePage.openOrCreate(token: "+daisy", root: root)

        XCTAssertEqual(try contents(of: pages), ["#daisy.md", "+daisy.md", "@daisy.md"])
    }

    func testExistingPageIsOpenedIgnoringCaseAndNeverOverwritten() throws {
        try write("notes", to: "#review.md")

        let page = try WorkspacePage.openOrCreate(token: "#Review", root: root)

        XCTAssertEqual(page.lastPathComponent, "#review.md")
        XCTAssertEqual(try String(contentsOf: page, encoding: .utf8), "notes")
        XCTAssertEqual(try contents(of: pages), ["#review.md"])
    }

    func testDecomposedSpellingFindsThePage() throws {
        try write("x", to: "#cafe\u{301}.md")

        let page = try XCTUnwrap(try WorkspacePage.resolve(token: "#café", root: root))
        XCTAssertEqual(WorkspacePage.key(page.lastPathComponent), WorkspacePage.key("#café.md"))
        XCTAssertEqual(try contents(of: pages).count, 1)
    }

    func testExactSpellingWinsOverOtherCases() throws {
        try write("a", to: "#Review.md")
        try write("b", to: "#review.md")

        // Case-sensitive volumes can hold both; the default APFS volume keeps one.
        let page = try XCTUnwrap(try WorkspacePage.resolve(token: "#review", root: root))
        XCTAssertEqual(WorkspacePage.key(page.lastPathComponent), "#review.md")
        if try contents(of: pages).count == 2 {
            XCTAssertEqual(page.lastPathComponent, "#review.md")
        }
    }

    func testMissingPageResolvesToNil() throws {
        XCTAssertNil(try WorkspacePage.resolve(token: "#review", root: root))
        XCTAssertFalse(FileManager.default.fileExists(atPath: pages.path), "resolving writes nothing")
    }

    func testInvalidTokenThrows() {
        XCTAssertThrowsError(try WorkspacePage.openOrCreate(token: "#a/", root: root))
        XCTAssertEqual(try contents(of: root), [])
    }

    func testPagesFolderLinkedOutsideTheRootIsRefused() throws {
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspacePageOutside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: pages, withDestinationURL: outside)

        XCTAssertThrowsError(try WorkspacePage.openOrCreate(token: "#review", root: root))
        XCTAssertEqual(try contents(of: outside), [])
    }

    func testPageLinkedOutsideThePagesFolderIsRefused() throws {
        let outside = root.appendingPathComponent("elsewhere.md")
        try Data("x".utf8).write(to: outside)
        try FileManager.default.createDirectory(at: pages, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: pages.appendingPathComponent("#review.md"),
                                                   withDestinationURL: outside)

        XCTAssertThrowsError(try WorkspacePage.resolve(token: "#review", root: root))
    }

    func testFailedWriteLeavesNothingBehind() throws {
        // A read-only root: the pages folder cannot be created.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path) }

        XCTAssertThrowsError(try WorkspacePage.openOrCreate(token: "#review", root: root))
        XCTAssertEqual(try contents(of: root), [])
    }

    func testFolderNamedLikeThePageIsNotAPage() throws {
        try FileManager.default.createDirectory(at: pages.appendingPathComponent("#review.md"),
                                                withIntermediateDirectories: true)

        XCTAssertNil(try WorkspacePage.resolve(token: "#review", root: root))
        XCTAssertThrowsError(try WorkspacePage.openOrCreate(token: "#review", root: root))
    }
}
