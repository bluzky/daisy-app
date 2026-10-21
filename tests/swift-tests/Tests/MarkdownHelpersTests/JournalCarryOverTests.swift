import Foundation
import XCTest
@testable import MarkdownHelpers

final class JournalCarryOverTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("JournalCarryOverTests-\(UUID().uuidString)", isDirectory: true)
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

    private func read(_ name: String) throws -> String {
        try String(contentsOf: journals.appendingPathComponent(name), encoding: .utf8)
    }

    // MARK: - Extracting

    func testMovesUncheckedTasksAndKeepsTheRest() throws {
        let split = try XCTUnwrap(JournalCarryOver.extract(from: """
            # 2026-10-20

            - [ ] call the bank
            - [x] ship it
            - plain note
            * [ ] star marker
            1. [ ] numbered

            Done for today.
            """))

        XCTAssertEqual(split.tasks, "- [ ] call the bank\n* [ ] star marker\n1. [ ] numbered\n")
        XCTAssertEqual(split.remaining, "# 2026-10-20\n\n- [x] ship it\n- plain note\n\nDone for today.")
    }

    func testATaskTakesWhatIsNestedUnderIt() throws {
        let split = try XCTUnwrap(JournalCarryOver.extract(from: """
            - [ ] plan trip
              notes on the trip
              - [x] book flight
              - [ ] book hotel
            - [x] done parent
              - [ ] stays with its parent
            """ + "\n"))

        XCTAssertEqual(split.tasks, "- [ ] plan trip\n  notes on the trip\n  - [x] book flight\n  - [ ] book hotel\n")
        XCTAssertEqual(split.remaining, "- [x] done parent\n  - [ ] stays with its parent\n")
    }

    func testATaskUnderAPlainBulletIsDedented() throws {
        let split = try XCTUnwrap(JournalCarryOver.extract(from: "- Project\n  - [ ] sub task\n    more\n"))

        XCTAssertEqual(split.tasks, "- [ ] sub task\n  more\n")
        XCTAssertEqual(split.remaining, "- Project\n")
    }

    func testLooseListItemsLeaveTheirBlankLinesBehind() throws {
        let split = try XCTUnwrap(JournalCarryOver.extract(from: "- [ ] one\n\n- [x] two\n\n- [ ] three\n"))

        XCTAssertEqual(split.tasks, "- [ ] one\n- [ ] three\n")
        XCTAssertEqual(split.remaining, "\n- [x] two\n\n")
    }

    func testIgnoresCodeQuotesAndFrontmatter() {
        XCTAssertNil(JournalCarryOver.extract(from: """
            ---
            todo:
              - [ ] not a task
            ---
            ```
            - [ ] code
            ```
            > - [ ] quoted

                - [ ] indented code
            """))
    }

    func testSkipsAnItemStartingOnItsParentsLine() {
        XCTAssertNil(JournalCarryOver.extract(from: "- - [ ] nested on one line\n"))
    }

    func testKeepsCRLFInTheOldEntryAndWritesLFInTheNew() throws {
        let split = try XCTUnwrap(JournalCarryOver.extract(from: "# Day\r\n- [ ] a\r\n- [x] b\r\n"))

        XCTAssertEqual(split.tasks, "- [ ] a\n")
        XCTAssertEqual(split.remaining, "# Day\r\n- [x] b\r\n")
    }

    func testRefusesALoneCarriageReturn() {
        XCTAssertNil(JournalCarryOver.extract(from: "# Day\r- [ ] a\n"))
    }

    func testALastLineWithoutANewlineStillEndsInOne() throws {
        let split = try XCTUnwrap(JournalCarryOver.extract(from: "# Day\n- [ ] last"))

        XCTAssertEqual(split.tasks, "- [ ] last\n")
        XCTAssertEqual(split.remaining, "# Day\n")
    }

    // MARK: - Planning and applying

    func testLooksBackOnlyTheChosenDaysOldestFirst() throws {
        try write("- [ ] too old\n", to: "2026-10-13.md")
        try write("- [ ] week ago\n", to: "2026-10-14.md")
        try write("- [ ] yesterday\n", to: "2026-10-20.md")
        try write("- [ ] tomorrow\n", to: "2026-10-22.md")
        try write("no tasks\n", to: "2026-10-19.md")

        let plan = try XCTUnwrap(JournalCarryOver.plan(for: day("2026-10-21"), lookBack: 7, root: root))

        XCTAssertEqual(plan.tasks, "- [ ] week ago\n- [ ] yesterday\n")
        XCTAssertEqual(plan.sources.map(\.day), [day("2026-10-14"), day("2026-10-20")])
        XCTAssertEqual(day("2026-03-01").adding(days: -1), day("2026-02-28"))
        XCTAssertEqual(day("2025-12-31").adding(days: 1), day("2026-01-01"))
    }

    func testApplyRemovesTheTasksFromTheirEntries() throws {
        try write("# 2026-10-20\n- [ ] move me\n- [x] done\n", to: "2026-10-20.md")
        let plan = try XCTUnwrap(JournalCarryOver.plan(for: day("2026-10-21"), lookBack: 7, root: root))

        XCTAssertEqual(JournalCarryOver.apply(plan, root: root), [])
        XCTAssertEqual(try read("2026-10-20.md"), "# 2026-10-20\n- [x] done\n")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: journals.path), ["2026-10-20.md"])
    }

    func testAnEntryChangedSinceItWasReadKeepsItsTasks() throws {
        try write("- [ ] move me\n", to: "2026-10-20.md")
        let plan = try XCTUnwrap(JournalCarryOver.plan(for: day("2026-10-21"), lookBack: 7, root: root))
        try write("- [ ] move me\n- [ ] added meanwhile\n", to: "2026-10-20.md")

        XCTAssertEqual(JournalCarryOver.apply(plan, root: root), [day("2026-10-20")])
        XCTAssertEqual(try read("2026-10-20.md"), "- [ ] move me\n- [ ] added meanwhile\n")
    }

    func testExcludedAndSymlinkedEntriesAreLeftAlone() throws {
        try write("- [ ] open with edits\n", to: "2026-10-19.md")
        try write("- [ ] real\n", to: "2026-10-18.md")
        try FileManager.default.createSymbolicLink(at: journals.appendingPathComponent("2026-10-20.md"),
                                                   withDestinationURL: journals.appendingPathComponent("2026-10-18.md"))

        let plan = try XCTUnwrap(JournalCarryOver.plan(for: day("2026-10-21"), lookBack: 7, root: root) {
            $0.lastPathComponent == "2026-10-19.md"
        })

        XCTAssertEqual(plan.sources.map(\.day), [day("2026-10-18")])
    }

    func testKeepsTheEntrysPermissions() throws {
        try write("- [ ] a\n", to: "2026-10-20.md")
        let entry = journals.appendingPathComponent("2026-10-20.md").path
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: entry)
        let plan = try XCTUnwrap(JournalCarryOver.plan(for: day("2026-10-21"), lookBack: 7, root: root))

        XCTAssertEqual(JournalCarryOver.apply(plan, root: root), [])
        let mode = try FileManager.default.attributesOfItem(atPath: entry)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
    }

    func testCreationReportsWhetherItWrote() throws {
        let first = try WorkspaceJournal.openOrCreateReportingCreation(day: day("2026-10-21"), root: root)
        let second = try WorkspaceJournal.openOrCreateReportingCreation(day: day("2026-10-21"), root: root)

        XCTAssertTrue(first.created)
        XCTAssertFalse(second.created)
    }
}
