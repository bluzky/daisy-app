import Foundation
import XCTest
@testable import MarkdownHelpers

final class WorkspaceFileWriterTests: XCTestCase {
    private var base: URL!
    private var root: URL!
    private var outside: URL!
    private var identity: WorkspaceFileWriter.RootIdentity!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspaceFileWriterTests-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        root = base.appendingPathComponent("root", isDirectory: true)
        outside = base.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("a/b"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside.appendingPathComponent("b"), withIntermediateDirectories: true)
        try write("- [ ] Task\n", to: "a/b/notes.md")
        try Data("- [ ] Outside\n".utf8).write(to: outside.appendingPathComponent("b/notes.md"))
        identity = try WorkspaceFileWriter.RootIdentity(root: root)
    }

    override func tearDownWithError() throws {
        WorkspaceFileWriter.testHook.withLock { $0 = nil }
        try? FileManager.default.removeItem(at: base)
    }

    private func write(_ text: String, to path: String) throws {
        try Data(text.utf8).write(to: root.appendingPathComponent(path))
    }

    private func contents(_ path: String, in folder: URL? = nil) throws -> String {
        try String(contentsOf: (folder ?? root).appendingPathComponent(path), encoding: .utf8)
    }

    private func replace(_ path: String = "a/b/notes.md", expected: String = "- [ ] Task\n",
                         with text: String = "- [x] Task\n") throws -> Bool {
        try WorkspaceFileWriter.replace(relativePath: path, root: root, expected: Data(expected.utf8), with: text,
                                        expectedRootIdentity: identity)
    }

    private func temporaryFiles() throws -> [String] {
        let enumerator = FileManager.default.enumerator(atPath: base.path)
        return (enumerator?.allObjects as? [String] ?? []).filter { $0.hasSuffix(".tmp") }
    }

    func testReplacesUnchangedFileKeepingPermissions() throws {
        let url = root.appendingPathComponent("a/b/notes.md")
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: url.path)
        XCTAssertTrue(try replace())
        XCTAssertEqual(try contents("a/b/notes.md"), "- [x] Task\n")
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o640)
        XCTAssertEqual(try temporaryFiles(), [])
    }

    func testReplaceKeepsExtendedAttributesAndCreationDate() throws {
        let url = root.appendingPathComponent("a/b/notes.md")
        let tags = Data("bplist-tags".utf8)
        let name = "com.apple.metadata:_kMDItemUserTags"
        XCTAssertEqual(tags.withUnsafeBytes { setxattr(url.path, name, $0.baseAddress, tags.count, 0, 0) }, 0)
        let created = Date(timeIntervalSince1970: 1_000_000_000)
        try FileManager.default.setAttributes([.creationDate: created], ofItemAtPath: url.path)

        XCTAssertTrue(try replace())
        var buffer = [UInt8](repeating: 0, count: 64)
        let count = getxattr(url.path, name, &buffer, buffer.count, 0, 0)
        XCTAssertEqual(count, tags.count)
        XCTAssertEqual(Data(buffer.prefix(max(count, 0))), tags)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual(attributes[.creationDate] as? Date, created)
    }

    func testReadReturnsBytes() throws {
        XCTAssertEqual(try WorkspaceFileWriter.read(relativePath: "a/b/notes.md", root: root,
                                                    expectedRootIdentity: identity),
                       Data("- [ ] Task\n".utf8))
    }

    func testRefusesChangedFile() throws {
        try write("- [ ] Task edited\n", to: "a/b/notes.md")
        XCTAssertFalse(try replace())
        XCTAssertEqual(try contents("a/b/notes.md"), "- [ ] Task edited\n")
        XCTAssertEqual(try temporaryFiles(), [])
    }

    func testRefusesInvalidPaths() {
        for path in ["", "/etc/hosts", "../outside/b/notes.md", "a/../a/b/notes.md", "a//b/notes.md",
                     "./a/b/notes.md", "a/b/", "a/b/notes.md\u{0}"] {
            XCTAssertThrowsError(try replace(path), path) { error in
                XCTAssertEqual(error as? WorkspaceFileWriter.WriterError, .invalidPath, path)
            }
        }
    }

    func testRefusesSymlinkTarget() throws {
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("a/b/link.md"),
                                                   withDestinationURL: root.appendingPathComponent("a/b/notes.md"))
        XCTAssertThrowsError(try replace("a/b/link.md"))
        XCTAssertEqual(try contents("a/b/notes.md"), "- [ ] Task\n")
    }

    func testRefusesSymlinkedDirectoryInsideAndOutsideRoot() throws {
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("inside"),
                                                   withDestinationURL: root.appendingPathComponent("a"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape"),
                                                   withDestinationURL: outside)
        XCTAssertThrowsError(try replace("inside/b/notes.md"))
        XCTAssertThrowsError(try replace("escape/b/notes.md", expected: "- [ ] Outside\n"))
        XCTAssertEqual(try contents("a/b/notes.md"), "- [ ] Task\n")
        XCTAssertEqual(try contents("b/notes.md", in: outside), "- [ ] Outside\n")
    }

    func testRefusesHardLink() throws {
        try FileManager.default.linkItem(at: outside.appendingPathComponent("b/notes.md"),
                                         to: root.appendingPathComponent("a/hard.md"))
        XCTAssertThrowsError(try replace("a/hard.md", expected: "- [ ] Outside\n"))
        XCTAssertEqual(try contents("b/notes.md", in: outside), "- [ ] Outside\n")
    }

    func testRefusesDirectoryAndFIFO() throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("a/folder.md"),
                                                withIntermediateDirectories: true)
        XCTAssertEqual(mkfifo(root.appendingPathComponent("a/pipe.md").path, 0o644), 0)
        XCTAssertThrowsError(try replace("a/folder.md"))
        XCTAssertThrowsError(try replace("a/pipe.md"))
        XCTAssertEqual(try temporaryFiles(), [])
    }

    func testRefusesSwappedRoot() throws {
        let identity = try WorkspaceFileWriter.RootIdentity(root: root)
        let moved = base.appendingPathComponent("moved", isDirectory: true)
        try FileManager.default.moveItem(at: root, to: moved)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("a/b"), withIntermediateDirectories: true)
        try write("- [ ] Task\n", to: "a/b/notes.md")
        XCTAssertThrowsError(try WorkspaceFileWriter.replace(
            relativePath: "a/b/notes.md", root: root, expected: Data("- [ ] Task\n".utf8),
            with: "- [x] Task\n", expectedRootIdentity: identity)) { error in
            XCTAssertEqual(error as? WorkspaceFileWriter.WriterError, .rootChanged)
        }
        XCTAssertEqual(try contents("a/b/notes.md"), "- [ ] Task\n")
    }

    /// The directory walk already holds `a/b`'s descriptor, so a symlink
    /// swapped in for `a` afterwards cannot send the write outside.
    func testDirectorySwappedForSymlinkAfterWalkCannotRedirect() throws {
        let root = root!, outside = outside!, base = base!
        WorkspaceFileWriter.testHook.withLock {
            $0 = { step in
                guard step == .afterWalk else { return }
                try? FileManager.default.moveItem(at: root.appendingPathComponent("a"),
                                                  to: base.appendingPathComponent("a-moved"))
                try? FileManager.default.createSymbolicLink(at: root.appendingPathComponent("a"),
                                                            withDestinationURL: outside)
            }
        }
        XCTAssertTrue(try replace())
        XCTAssertEqual(try contents("b/notes.md", in: outside), "- [ ] Outside\n")
        XCTAssertEqual(try contents("a-moved/b/notes.md", in: base), "- [x] Task\n")
        XCTAssertEqual(try temporaryFiles(), [])
    }

    func testTargetReplacedBeforeRenameIsNotOverwritten() throws {
        let target = root.appendingPathComponent("a/b/notes.md")
        WorkspaceFileWriter.testHook.withLock {
            $0 = { step in
                guard step == .beforeRecheck else { return }
                try? FileManager.default.removeItem(at: target)
                try? Data("- [ ] Task\n".utf8).write(to: target)
            }
        }
        // Same bytes, but a new file: the writer gives up rather than replace it.
        XCTAssertFalse(try replace())
        XCTAssertEqual(try contents("a/b/notes.md"), "- [ ] Task\n")
        XCTAssertEqual(try temporaryFiles(), [])
    }

    func testTargetEditedBeforeRenameIsNotOverwritten() throws {
        let target = root.appendingPathComponent("a/b/notes.md")
        WorkspaceFileWriter.testHook.withLock {
            $0 = { step in
                guard step == .beforeRecheck,
                      let handle = try? FileHandle(forWritingTo: target) else { return }
                handle.seekToEndOfFile()
                handle.write(Data("more\n".utf8))
                try? handle.close()
            }
        }
        XCTAssertFalse(try replace())
        XCTAssertEqual(try contents("a/b/notes.md"), "- [ ] Task\nmore\n")
        XCTAssertEqual(try temporaryFiles(), [])
    }
}
