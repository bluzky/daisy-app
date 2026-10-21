import Foundation
import XCTest
@testable import MarkdownHelpers

final class JournalTemplateTests: XCTestCase {
    private let day = JournalDay(string: "2026-10-15")!
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    /// 2026-10-21 14:05 UTC, a different day from the entry's.
    private let now = Date(timeIntervalSince1970: 1_792_591_500)

    private func contents(_ body: String?, locale: Locale = Locale(identifier: "en_US")) -> String {
        JournalTemplate.contents(for: day, template: body.map { MarkdownTemplate(name: "Journal", body: $0) },
                                 now: now, calendar: calendar, locale: locale)
    }

    func testWithoutATemplateTheEntryHoldsItsHeading() {
        XCTAssertEqual(contents(nil), "# 2026-10-15\n")
    }

    func testDateAndWeekdayNameTheEntrysDayAndTimeIsNow() {
        XCTAssertEqual(contents("# {{date}} — {{weekday}}\n\nWritten {{time}} ({{datetime}})"),
                       "# 2026-10-15 — Thursday\n\nWritten 14:05 (2026-10-15 14:05)\n")
    }

    func testWeekdayFollowsTheLocale() {
        XCTAssertEqual(contents("{{weekday}}", locale: Locale(identifier: "zh-Hans")), "星期四\n")
    }

    func testCursorIsDroppedEscapesAndUnknownNamesStay() {
        XCTAssertEqual(contents("- {{cursor}}\n\\{{date}} {{nope}} {{ DATE }}"),
                       "- \n{{date}} {{nope}} 2026-10-15\n")
    }

    func testTrailingBlankSpaceEndsInOneNewline() {
        XCTAssertEqual(contents("## Today\n\n- {{cursor}}\n\n\n"), "## Today\n\n-\n")
    }

    func testFindsTheChosenTemplateByExactName() {
        let templates = [MarkdownTemplate(name: "Meeting", body: "m"),
                         MarkdownTemplate(name: "Daily", body: "first"),
                         MarkdownTemplate(name: "Daily (2)", body: "second")]
        XCTAssertEqual(JournalTemplate.template(named: "Daily", in: templates)?.body, "first")
        XCTAssertEqual(JournalTemplate.template(named: "Daily (2)", in: templates)?.body, "second")
        XCTAssertNil(JournalTemplate.template(named: "daily", in: templates))
        XCTAssertNil(JournalTemplate.template(named: "Gone", in: templates))
        XCTAssertNil(JournalTemplate.template(named: nil, in: templates))
    }

    func testCreatesTheEntryFromTheTemplate() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("JournalTemplateTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let entry = try WorkspaceJournal.openOrCreate(day: day, root: root, contents: contents("# {{date}}\n\n## Notes"))
        XCTAssertEqual(try String(contentsOf: entry, encoding: .utf8), "# 2026-10-15\n\n## Notes\n")

        // An existing entry is opened as it is, never rewritten from the template.
        let again = try WorkspaceJournal.openOrCreate(day: day, root: root, contents: "replaced\n")
        XCTAssertEqual(try String(contentsOf: again, encoding: .utf8), "# 2026-10-15\n\n## Notes\n")
    }
}
