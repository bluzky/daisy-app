import XCTest
@testable import MarkdownHelpers

final class ProjectFileLinkTests: XCTestCase {
    private let document = URL(fileURLWithPath: "/project/guides/setup.md")

    private func destination(_ target: String) -> String {
        ProjectFileLink.destination(to: URL(fileURLWithPath: target), from: document)
    }

    func testLinksAreRelativeToTheDocumentFolder() {
        XCTAssertEqual(destination("/project/guides/install.md"), "install.md")
        XCTAssertEqual(destination("/project/guides/deep/faq.md"), "deep/faq.md")
        XCTAssertEqual(destination("/project/README.md"), "../README.md")
        XCTAssertEqual(destination("/project/assets/img/logo.png"), "../assets/img/logo.png")
        XCTAssertEqual(destination("/project/guides/setup.md"), "setup.md")
    }

    func testSpacesAndParenthesesAreEncoded() {
        XCTAssertEqual(destination("/project/My Notes/plan (draft).md"), "../My%20Notes/plan%20%28draft%29.md")
    }

    func testSymlinkedPrefixesShareTheirRoot() throws {
        // The temporary folder sits under /var, a symlink to /private/var.
        // Symlinks resolve only for files that exist, as both ends of a
        // picked link do, so this uses real files.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        for folder in ["a", "b"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(folder),
                                                    withIntermediateDirectories: true)
        }
        let document = root.appendingPathComponent("a/one.md")
        let target = root.appendingPathComponent("b/two.md")
        try Data().write(to: document)
        try Data().write(to: target)
        let privatePath = URL(fileURLWithPath: "/private" + target.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: privatePath.path))
        XCTAssertEqual(ProjectFileLink.destination(to: privatePath, from: document), "../b/two.md")
    }

    func testDefaultTextDropsOnlyTheMarkdownExtension() {
        XCTAssertEqual(ProjectFileLink.defaultText(for: URL(fileURLWithPath: "/p/Setup Guide.md")), "Setup Guide")
        XCTAssertEqual(ProjectFileLink.defaultText(for: URL(fileURLWithPath: "/p/logo.png")), "logo.png")
        XCTAssertEqual(ProjectFileLink.defaultText(for: URL(fileURLWithPath: "/p/main.swift")), "main.swift")
    }
}
