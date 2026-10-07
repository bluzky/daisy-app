import XCTest
@testable import MarkdownHelpers

final class ProjectItemNameTests: XCTestCase {

    func testBareNameGetsMarkdownExtension() {
        XCTAssertEqual(ProjectItemName.newFileRelativePath(from: "roadmap"), "roadmap.md")
        XCTAssertEqual(ProjectItemName.newFileRelativePath(from: "  roadmap  "), "roadmap.md")
    }

    func testMarkdownExtensionIsKept() {
        XCTAssertEqual(ProjectItemName.newFileRelativePath(from: "notes.mdx"), "notes.mdx")
        XCTAssertEqual(ProjectItemName.newFileRelativePath(from: "Notes.MD"), "Notes.MD")
    }

    func testNestedPathKeepsFoldersAndLeadingSlashMeansRoot() {
        XCTAssertEqual(ProjectItemName.newFileRelativePath(from: "notes/2026/roadmap"), "notes/2026/roadmap.md")
        XCTAssertEqual(ProjectItemName.newFileRelativePath(from: "/notes/roadmap"), "notes/roadmap.md")
    }

    func testNamesTheIndexCouldNeverFindAreRefused() {
        XCTAssertNil(ProjectItemName.newFileRelativePath(from: ""))
        XCTAssertNil(ProjectItemName.newFileRelativePath(from: "   "))
        XCTAssertNil(ProjectItemName.newFileRelativePath(from: "foo.txt"))
        XCTAssertNil(ProjectItemName.newFileRelativePath(from: ".hidden"))
        XCTAssertNil(ProjectItemName.newFileRelativePath(from: ".config/notes"))
        XCTAssertNil(ProjectItemName.newFileRelativePath(from: "notes/"))
        XCTAssertNil(ProjectItemName.newFileRelativePath(from: "a//b"))
        XCTAssertNil(ProjectItemName.newFileRelativePath(from: "../escape"))
        XCTAssertNil(ProjectItemName.newFileRelativePath(from: "a/./b"))
        XCTAssertNil(ProjectItemName.newFileRelativePath(from: "back\\slash"))
    }

    func testSidebarRulesAreTheSameFunctions() {
        XCTAssertEqual(ProjectItemName.validated("  New Folder "), "New Folder")
        XCTAssertNil(ProjectItemName.validated("a/b"))
        XCTAssertEqual(ProjectItemName.markdownFileName(from: "Untitled"), "Untitled.md")
        XCTAssertEqual(ProjectItemName.markdownFileName(from: "x", defaultExtension: "markdown"), "x.markdown")
        XCTAssertNil(ProjectItemName.markdownFileName(from: "x.png"))
    }

    func testPrunedFoldersAndPathsPastTheIndexDepthAreRefused() {
        XCTAssertNil(ProjectItemName.newFileRelativePath(from: "node_modules/notes"))
        XCTAssertNil(ProjectItemName.newFileRelativePath(from: "docs/build/notes"))
        let twelve = (0..<11).map { "d\($0)" }.joined(separator: "/") + "/note"
        XCTAssertEqual(ProjectItemName.newFileRelativePath(from: twelve), twelve + ".md")
        XCTAssertNil(ProjectItemName.newFileRelativePath(from: "extra/" + twelve))
    }

    func testContainmentFollowsSymlinksOnExistingFolders() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = base.appendingPathComponent("project")
        let outside = base.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("notes"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("dangling"),
                                                   withDestinationURL: base.appendingPathComponent("nowhere"))

        XCTAssertTrue(ProjectItemName.isContained(root.appendingPathComponent("a.md"), in: root))
        XCTAssertTrue(ProjectItemName.isContained(root.appendingPathComponent("notes/new/deep/a.md"), in: root))
        XCTAssertFalse(ProjectItemName.isContained(root.appendingPathComponent("escape/a.md"), in: root))
        XCTAssertFalse(ProjectItemName.isContained(root.appendingPathComponent("escape/sub/a.md"), in: root))
        XCTAssertFalse(ProjectItemName.isContained(root.appendingPathComponent("dangling/a.md"), in: root))
        XCTAssertFalse(ProjectItemName.isContained(outside.appendingPathComponent("a.md"), in: root))
    }
}
