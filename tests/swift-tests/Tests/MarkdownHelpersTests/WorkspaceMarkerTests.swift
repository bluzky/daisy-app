import Foundation
import XCTest
@testable import MarkdownHelpers

final class WorkspaceMarkerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspaceMarkerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var daisyDirectory: URL { root.appendingPathComponent(".daisy", isDirectory: true) }

    private func contents(of url: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
    }

    func testFolderWithoutMarkerIsNotWorkspace() {
        XCTAssertFalse(WorkspaceMarker.isWorkspace(root: root))
    }

    func testInitializeWritesOnlyTheMarker() throws {
        try WorkspaceMarker.initialize(root: root)

        XCTAssertTrue(WorkspaceMarker.isWorkspace(root: root))
        XCTAssertEqual(try contents(of: root), [".daisy"])
        XCTAssertEqual(try contents(of: daisyDirectory), ["config.json"])
        let data = try Data(contentsOf: WorkspaceMarker.markerURL(root: root))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Int])
        XCTAssertEqual(json, ["version": 1])
    }

    func testInitializeKeepsExistingMarker() throws {
        try FileManager.default.createDirectory(at: daisyDirectory, withIntermediateDirectories: true)
        let custom = Data("{\"version\": 7, \"extra\": true}".utf8)
        try custom.write(to: WorkspaceMarker.markerURL(root: root))

        try WorkspaceMarker.initialize(root: root)

        XCTAssertEqual(try Data(contentsOf: WorkspaceMarker.markerURL(root: root)), custom)
    }

    func testPresenceCountsWhateverTheContents() throws {
        try FileManager.default.createDirectory(at: daisyDirectory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: WorkspaceMarker.markerURL(root: root))

        XCTAssertTrue(WorkspaceMarker.isWorkspace(root: root))
    }

    func testDaisyFileInsteadOfFolderIsNotWorkspaceAndBlocksInitialize() throws {
        let file = root.appendingPathComponent(".daisy")
        try Data("x".utf8).write(to: file)

        XCTAssertFalse(WorkspaceMarker.isWorkspace(root: root))
        XCTAssertThrowsError(try WorkspaceMarker.initialize(root: root))
        XCTAssertEqual(try Data(contentsOf: file), Data("x".utf8))
    }

    func testConfigDirectoryIsNotWorkspace() throws {
        try FileManager.default.createDirectory(at: WorkspaceMarker.markerURL(root: root),
                                                withIntermediateDirectories: true)

        XCTAssertFalse(WorkspaceMarker.isWorkspace(root: root))
    }

    func testFailedWriteLeavesFolderUnchanged() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: root.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path) }

        XCTAssertThrowsError(try WorkspaceMarker.initialize(root: root))
        XCTAssertEqual(try contents(of: root), [])
    }

    func testMarkerInParentOrSubfolderIsNotDetected() throws {
        let child = root.appendingPathComponent("child", isDirectory: true)
        let grandchild = child.appendingPathComponent("grandchild", isDirectory: true)
        try FileManager.default.createDirectory(at: grandchild, withIntermediateDirectories: true)
        try WorkspaceMarker.initialize(root: grandchild)

        XCTAssertFalse(WorkspaceMarker.isWorkspace(root: child))

        try WorkspaceMarker.remove(root: grandchild)
        try WorkspaceMarker.initialize(root: root)
        XCTAssertFalse(WorkspaceMarker.isWorkspace(root: child))
    }

    func testRemoveDeletesMarkerAndEmptyFolder() throws {
        try WorkspaceMarker.initialize(root: root)

        try WorkspaceMarker.remove(root: root)

        XCTAssertFalse(WorkspaceMarker.isWorkspace(root: root))
        XCTAssertEqual(try contents(of: root), [])
    }

    func testRemoveKeepsOtherFilesInDaisyFolder() throws {
        try WorkspaceMarker.initialize(root: root)
        try Data("keep".utf8).write(to: daisyDirectory.appendingPathComponent("notes.txt"))

        try WorkspaceMarker.remove(root: root)

        XCTAssertFalse(WorkspaceMarker.isWorkspace(root: root))
        XCTAssertEqual(try contents(of: daisyDirectory), ["notes.txt"])
    }

    func testRemoveWithoutMarkerChangesNothing() throws {
        try WorkspaceMarker.remove(root: root)

        XCTAssertEqual(try contents(of: root), [])
    }
}
