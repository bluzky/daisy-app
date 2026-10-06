import XCTest
@testable import MarkdownHelpers

final class FileSearchResultsTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/project")

    func testBlankQueryPreservesRecencyDeduplicatesAndCapsHistory() throws {
        let urls = (0..<12).map { root.appendingPathComponent("file-\($0).md") }
        let rows = try FileSearchResults.rows(query: "  ", recentURLs: [urls[0]] + urls, snapshot: nil)
        XCTAssertEqual(rows.first, .recentHeading)
        XCTAssertEqual(rows.compactMap { $0.entry?.url }, Array(urls.prefix(10)))
    }

    func testMatchingHistoryPrecedesProjectResultsWithoutDuplicates() throws {
        let recent = [root.appendingPathComponent("guide.md"), URL(fileURLWithPath: "/elsewhere/guide-old.md")]
        let snapshot = ProjectFileIndex.Snapshot(root: root, candidates: [
            .init(relativePath: "guide.md"), .init(relativePath: "guide-new.md"), .init(relativePath: "other.md")
        ], isTruncated: false)
        let rows = try FileSearchResults.rows(query: "guide", recentURLs: recent, snapshot: snapshot)
        XCTAssertEqual(rows.first, .recentHeading)
        XCTAssertEqual(rows[3], .filesHeading)
        XCTAssertEqual(rows.compactMap { $0.entry?.url }, recent + [root.appendingPathComponent("guide-new.md")])
        XCTAssertEqual(rows.last?.entry?.projectRoot, root)
        XCTAssertNil(rows[1].entry?.projectRoot)
    }

    func testHistorySearchWithoutProjectAndClearedHistory() throws {
        let recent = URL(fileURLWithPath: "/outside/notes.md")
        XCTAssertEqual(try FileSearchResults.rows(query: "outside/notes", recentURLs: [recent], snapshot: nil).last?.entry?.url, recent)
        XCTAssertEqual(try FileSearchResults.rows(query: "", recentURLs: [], snapshot: nil), [])
        XCTAssertEqual(try FileSearchResults.rows(query: "missing", recentURLs: [recent], snapshot: nil), [])
    }
    func testSymlinkHistoryAndProjectMatchAppearOnlyOnce() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("guide.md")
        let alias = directory.appendingPathComponent("guide-link.md")
        try "# Guide".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: file)
        let snapshot = ProjectFileIndex.Snapshot(root: directory, candidates: [
            .init(relativePath: "guide.md")
        ], isTruncated: false)
        let rows = try FileSearchResults.rows(query: "guide", recentURLs: [alias, file], snapshot: snapshot)
        XCTAssertEqual(rows.compactMap { $0.entry?.url }, [file])
        XCTAssertFalse(rows.contains(.filesHeading))
    }

    func testDifferentAliasNameDoesNotHideMatchingRecentTarget() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("guide.md")
        let alias = directory.appendingPathComponent("shortcut.md")
        try "# Guide".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: file)

        let matching = try FileSearchResults.rows(query: "guide.md", recentURLs: [alias, file], snapshot: nil)
        XCTAssertEqual(matching.compactMap { $0.entry?.url }, [file])
        let aliasMatch = try FileSearchResults.rows(query: "shortcut", recentURLs: [alias, file], snapshot: nil)
        XCTAssertEqual(aliasMatch.compactMap { $0.entry?.url }, [alias])
        let blank = try FileSearchResults.rows(query: "", recentURLs: [alias, file], snapshot: nil)
        XCTAssertEqual(blank.compactMap { $0.entry?.url }, [alias])
    }

    func testCurrentFileIdentityMatchesAnAliasBeforeReloading() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("edited.md")
        let alias = directory.appendingPathComponent("shortcut.md")
        try "Old disk content".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: file)
        // The selection guard must recognize this identity without loading old
        // disk content or asking the editor to commit its newer in-memory text.
        XCTAssertEqual(FileSearchResults.resolvedIdentity(file), FileSearchResults.resolvedIdentity(alias))
        XCTAssertNotEqual(FileSearchResults.resolvedIdentity(file),
                          FileSearchResults.resolvedIdentity(directory.appendingPathComponent("other.md")))
    }


    // MARK: - Commands

    private let commands: [FileSearchResults.CommandCandidate] = [
        .init(id: "a", title: "Toggle Sidebar", menuPath: "View", shortcut: "⌘B"),
        .init(id: "b", title: "Show Toolbar", menuPath: "View", shortcut: nil),
        .init(id: "c", title: "Find…", menuPath: "Find", shortcut: "⌘F")
    ]

    func testGreaterThanShowsOnlyCommandsInMenuOrderWhenBlank() throws {
        let rows = try FileSearchResults.rows(query: ">", recentURLs: [root.appendingPathComponent("a.md")],
                                              snapshot: nil, commands: commands)
        XCTAssertEqual(rows.first, .commandsHeading)
        XCTAssertEqual(rows.dropFirst().map { if case .command(let c) = $0 { c.id } else { "?" } }, ["a", "b", "c"])
    }

    func testGreaterThanFiltersCommandsByTitle() throws {
        let rows = try FileSearchResults.rows(query: "> side", recentURLs: [], snapshot: nil, commands: commands)
        XCTAssertEqual(rows.count, 2)
        guard case .command(let command) = rows[1] else { return XCTFail("expected a command row") }
        XCTAssertEqual(command.id, "a")
    }

    func testMixedViewAddsCommandsAfterFilesAndCapsThem() throws {
        let many = (0..<9).map {
            FileSearchResults.CommandCandidate(id: "\($0)", title: "Guide Action \($0)", menuPath: "File", shortcut: nil)
        }
        let snapshot = ProjectFileIndex.Snapshot(root: root, candidates: [.init(relativePath: "guide.md")],
                                                 isTruncated: false)
        let rows = try FileSearchResults.rows(query: "guide", recentURLs: [], snapshot: snapshot, commands: many)
        XCTAssertEqual(rows.first, .filesHeading)
        let headingIndex = try XCTUnwrap(rows.firstIndex(of: .commandsHeading))
        XCTAssertEqual(rows.count - headingIndex - 1, FileSearchResults.mixedCommandLimit)
    }

    func testBlankQueryDoesNotListCommands() throws {
        XCTAssertEqual(try FileSearchResults.rows(query: "", recentURLs: [], snapshot: nil, commands: commands), [])
    }

    // MARK: - Create file

    func testCreateRowComesFirstWhenNothingMatchesByName() throws {
        let snapshot = ProjectFileIndex.Snapshot(root: root, candidates: [.init(relativePath: "guide.md")],
                                                 isTruncated: false)
        let rows = try FileSearchResults.rows(query: "notes/roadmap", recentURLs: [], snapshot: snapshot,
                                              commands: commands)
        XCTAssertEqual(rows, [.createFile(.init(relativePath: "notes/roadmap.md", projectRoot: root))])
    }

    func testCreateRowSitsAboveCommandsThatAlsoMatch() throws {
        let snapshot = ProjectFileIndex.Snapshot(root: root, candidates: [], isTruncated: false)
        let rows = try FileSearchResults.rows(query: "sidebar", recentURLs: [], snapshot: snapshot, commands: commands)
        guard case .createFile(let newFile) = rows.first else { return XCTFail("expected create row first") }
        XCTAssertEqual(newFile.relativePath, "sidebar.md")
        XCTAssertEqual(rows[1], .commandsHeading)
    }

    func testCreateRowIsAbsentWhenAFileOrRecentMatches() throws {
        let snapshot = ProjectFileIndex.Snapshot(root: root, candidates: [.init(relativePath: "guide.md")],
                                                 isTruncated: false)
        let byFile = try FileSearchResults.rows(query: "guide", recentURLs: [], snapshot: snapshot)
        XCTAssertFalse(byFile.contains { if case .createFile = $0 { true } else { false } })
        let emptySnapshot = ProjectFileIndex.Snapshot(root: root, candidates: [], isTruncated: false)
        let byRecent = try FileSearchResults.rows(query: "guide", recentURLs: [root.appendingPathComponent("guide.md")],
                                                  snapshot: emptySnapshot)
        XCTAssertFalse(byRecent.contains { if case .createFile = $0 { true } else { false } })
    }

    func testCreateRowWaitsForTheIndexAndNeedsAValidName() throws {
        XCTAssertEqual(try FileSearchResults.rows(query: "roadmap", recentURLs: [], snapshot: nil), [])
        let snapshot = ProjectFileIndex.Snapshot(root: root, candidates: [], isTruncated: false)
        XCTAssertEqual(try FileSearchResults.rows(query: "foo.txt", recentURLs: [], snapshot: snapshot), [])
        XCTAssertEqual(try FileSearchResults.rows(query: "> roadmap", recentURLs: [], snapshot: snapshot), [])
    }

    func testCreateRowDescribesItsFolder() {
        let newFile = FileSearchResults.NewFile(relativePath: "notes/2026/roadmap.md", projectRoot: root)
        XCTAssertEqual(newFile.fileName, "roadmap.md")
        XCTAssertEqual(newFile.directory, "notes/2026")
        XCTAssertEqual(FileSearchResults.NewFile(relativePath: "a.md", projectRoot: root).directory, "")
    }
}
