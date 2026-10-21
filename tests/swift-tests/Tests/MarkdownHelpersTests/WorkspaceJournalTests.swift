import Foundation
import XCTest
@testable import MarkdownHelpers

final class WorkspaceJournalTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspaceJournalTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var journals: URL { root.appendingPathComponent("journals", isDirectory: true) }

    private func day(_ string: String) -> JournalDay {
        JournalDay(string: string)!
    }

    private func write(_ text: String, to name: String) throws {
        try FileManager.default.createDirectory(at: journals, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: journals.appendingPathComponent(name))
    }

    func testParsesOnlyRealISODays() {
        XCTAssertEqual(JournalDay(string: "2026-10-21")?.string, "2026-10-21")
        XCTAssertEqual(JournalDay(string: "2024-02-29")?.string, "2024-02-29")
        for text in ["2026-02-29", "1900-02-29", "2026-13-01", "2026-00-10", "2026-04-31",
                     "2026-1-01", "26-10-21", "2026-10-21 ", "2026/10/21", "２０２６-10-21", ""] {
            XCTAssertNil(JournalDay(string: text), text)
        }
        XCTAssertEqual(JournalDay(string: "2000-02-29")?.day, 29)
    }

    func testDayOfDateUsesTheCalendarTimeZone() throws {
        // 2026-10-21 23:30 UTC is already the 22nd in Tokyo.
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-21T23:30:00Z"))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!

        XCTAssertEqual(JournalDay(date: instant, calendar: utc).string, "2026-10-21")
        XCTAssertEqual(JournalDay(date: instant, calendar: tokyo).string, "2026-10-22")
    }

    func testCreatesTheEntryWithTheDateAsHeading() throws {
        let entry = try WorkspaceJournal.openOrCreate(day: day("2026-10-21"), root: root)

        XCTAssertEqual(entry.lastPathComponent, "2026-10-21.md")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["journals"])
        XCTAssertEqual(try String(contentsOf: entry, encoding: .utf8), "# 2026-10-21\n")
    }

    func testNeverOverwritesAnExistingEntry() throws {
        try write("kept\n", to: "2026-10-21.md")

        let entry = try WorkspaceJournal.openOrCreate(day: day("2026-10-21"), root: root)

        XCTAssertEqual(try String(contentsOf: entry, encoding: .utf8), "kept\n")
    }

    func testFailedWriteLeavesNothingBehind() throws {
        // A file where the journals folder should be makes creation fail.
        try Data().write(to: journals)

        XCTAssertThrowsError(try WorkspaceJournal.openOrCreate(day: day("2026-10-21"), root: root))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["journals"])
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: journals.path, isDirectory: &isDirectory))
        XCTAssertFalse(isDirectory.boolValue)
    }

    func testRefusesAJournalsFolderOutsideTheRoot() throws {
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspaceJournalOutside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: journals, withDestinationURL: outside)

        XCTAssertThrowsError(try WorkspaceJournal.openOrCreate(day: day("2026-10-21"), root: root))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outside.path), [])
        XCTAssertEqual(WorkspaceJournal.entryDays(root: root), [])
    }

    func testRefusesAnEntrySymlinkedOutsideTheFolder() throws {
        let outside = root.appendingPathComponent("elsewhere.md")
        try Data("x".utf8).write(to: outside)
        try FileManager.default.createDirectory(at: journals, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: journals.appendingPathComponent("2026-10-21.md"),
                                                   withDestinationURL: outside)

        XCTAssertThrowsError(try WorkspaceJournal.resolve(day: day("2026-10-21"), root: root))
    }

    func testEntryDaysIgnoreFilesThatAreNotDays() throws {
        try write("", to: "2026-10-01.md")
        try write("", to: "2026-10-21.md")
        try write("", to: "2026-02-30.md")
        try write("", to: "notes.md")
        try write("", to: "2026-10-05.txt")
        try write("", to: "2026-10-06.MD")
        try FileManager.default.createDirectory(at: journals.appendingPathComponent("2026-10-07.md"),
                                                withIntermediateDirectories: true)

        XCTAssertEqual(WorkspaceJournal.entryDays(root: root), [day("2026-10-01"), day("2026-10-21")])
    }

    func testOnlyRegularFilesInTheFolderAreEntries() throws {
        try write("", to: "2026-10-01.md")
        try write("", to: "2026-10-02.md")
        // A symlink to an entry in the same folder is one.
        try FileManager.default.createSymbolicLink(at: journals.appendingPathComponent("2026-10-03.md"),
                                                   withDestinationURL: journals.appendingPathComponent("2026-10-02.md"))
        // A FIFO, a symlink out of the folder and a dangling symlink are not.
        XCTAssertEqual(mkfifo(journals.appendingPathComponent("2026-10-04.md").path, 0o644), 0)
        let outside = root.appendingPathComponent("elsewhere.md")
        try Data("x".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: journals.appendingPathComponent("2026-10-05.md"),
                                                   withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: journals.appendingPathComponent("2026-10-06.md"),
                                                   withDestinationURL: journals.appendingPathComponent("gone.md"))

        XCTAssertEqual(WorkspaceJournal.entryDays(root: root),
                       [day("2026-10-01"), day("2026-10-02"), day("2026-10-03")])
        XCTAssertEqual(WorkspaceJournal.adjacentDay(to: day("2026-10-03"), .next, root: root), nil)
        XCTAssertNotNil(try WorkspaceJournal.resolve(day: day("2026-10-03"), root: root))
        for name in ["2026-10-04", "2026-10-05", "2026-10-06"] {
            XCTAssertThrowsError(try WorkspaceJournal.resolve(day: day(name), root: root), name)
            XCTAssertThrowsError(try WorkspaceJournal.openOrCreate(day: day(name), root: root), name)
        }
        XCTAssertEqual(try String(contentsOf: outside, encoding: .utf8), "x")
    }

    func testFailedCreationLeavesAnExistingFolderAndItsEntries() throws {
        try write("kept\n", to: "2026-10-01.md")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: journals.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: journals.path) }

        XCTAssertThrowsError(try WorkspaceJournal.openOrCreate(day: day("2026-10-21"), root: root))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: journals.path), ["2026-10-01.md"])
    }

    func testAdjacentDaySkipsGapsAndStopsAtTheEnds() throws {
        try write("", to: "2025-12-31.md")
        try write("", to: "2026-01-03.md")
        try write("", to: "2026-02-28.md")

        XCTAssertEqual(WorkspaceJournal.adjacentDay(to: day("2026-01-03"), .previous, root: root), day("2025-12-31"))
        XCTAssertEqual(WorkspaceJournal.adjacentDay(to: day("2026-01-03"), .next, root: root), day("2026-02-28"))
        // A day without an entry still finds its neighbours.
        XCTAssertEqual(WorkspaceJournal.adjacentDay(to: day("2026-02-01"), .previous, root: root), day("2026-01-03"))
        XCTAssertNil(WorkspaceJournal.adjacentDay(to: day("2025-12-31"), .previous, root: root))
        XCTAssertNil(WorkspaceJournal.adjacentDay(to: day("2026-02-28"), .next, root: root))
    }

    func testDayOfURLOnlyCountsFilesDirectlyInTheJournalsFolder() throws {
        try write("", to: "2026-10-21.md")

        XCTAssertEqual(WorkspaceJournal.day(of: journals.appendingPathComponent("2026-10-21.md"), root: root),
                       day("2026-10-21"))
        XCTAssertNil(WorkspaceJournal.day(of: root.appendingPathComponent("2026-10-21.md"), root: root))
        XCTAssertNil(WorkspaceJournal.day(of: journals.appendingPathComponent("old/2026-10-21.md"), root: root))
        XCTAssertNil(WorkspaceJournal.day(of: journals.appendingPathComponent("notes.md"), root: root))
    }
}
