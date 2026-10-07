import Foundation
import XCTest
@testable import MarkdownHelpers

@MainActor
final class BookmarkStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookmarkStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeStore() throws -> (BookmarkStore, UserDefaults) {
        let suite = "BookmarkStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return (BookmarkStore(defaults: defaults), defaults)
    }

    private func makeFile(_ name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try "# Hi".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testAddsFileAndFolderAndFindsThemByURL() throws {
        let (store, _) = try makeStore()
        let file = try makeFile("note.md")

        XCTAssertTrue(store.add(file))
        XCTAssertTrue(store.add(directory))

        XCTAssertEqual(store.bookmarks.map(\.isDirectory), [false, true])
        XCTAssertTrue(store.isBookmarked(file))
        XCTAssertTrue(store.isBookmarked(directory))
    }

    func testRejectsDuplicatesAndMissingItems() throws {
        let (store, _) = try makeStore()
        let file = try makeFile("note.md")

        XCTAssertTrue(store.add(file))
        XCTAssertFalse(store.add(file))
        XCTAssertFalse(store.add(directory.appendingPathComponent("missing.md")))
        XCTAssertEqual(store.bookmarks.count, 1)
    }

    func testRemoveDropsBookmark() throws {
        let (store, _) = try makeStore()
        let file = try makeFile("note.md")
        store.add(file)

        store.remove(id: try XCTUnwrap(store.bookmark(for: file)).id)

        XCTAssertFalse(store.isBookmarked(file))
        XCTAssertTrue(store.bookmarks.isEmpty)
    }

    func testBookmarksPersistAcrossStores() throws {
        let (store, defaults) = try makeStore()
        let file = try makeFile("note.md")
        store.add(file)

        let reloaded = BookmarkStore(defaults: defaults)

        XCTAssertEqual(reloaded.bookmarks, store.bookmarks)
    }

    func testResolveFollowsRenamedItem() throws {
        let (store, _) = try makeStore()
        let file = try makeFile("old.md")
        store.add(file)
        let renamed = directory.appendingPathComponent("new.md")
        try FileManager.default.moveItem(at: file, to: renamed)

        let bookmark = try XCTUnwrap(store.bookmarks.first)
        let resolved = try XCTUnwrap(store.resolve(bookmark))

        XCTAssertEqual(resolved.resolvingSymlinksInPath().path, renamed.resolvingSymlinksInPath().path)
        XCTAssertEqual(store.bookmarks.first?.name, "new.md")
    }

    func testResolveReturnsNilForDeletedItem() throws {
        let (store, _) = try makeStore()
        let file = try makeFile("note.md")
        store.add(file)
        try FileManager.default.removeItem(at: file)

        XCTAssertNil(store.resolve(try XCTUnwrap(store.bookmarks.first)))
    }

    func testChangesPostNotification() throws {
        let (store, _) = try makeStore()
        let file = try makeFile("note.md")
        let posted = expectation(forNotification: BookmarkStore.didChangeNotification, object: store)

        store.add(file)

        wait(for: [posted], timeout: 1)
    }
}
