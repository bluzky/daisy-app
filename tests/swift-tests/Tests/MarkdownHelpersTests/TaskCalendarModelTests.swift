import Foundation
import XCTest
@testable import MarkdownHelpers

final class TaskCalendarModelTests: XCTestCase {
    private let today = JournalDay(string: "2026-10-21")!

    private func task(_ text: String, path: String = "a.md", line: Int = 1, checked: Bool = false,
                      due: String? = nil, scheduled: String? = nil,
                      priority: String? = nil) -> WorkspaceIndexedTask {
        WorkspaceIndexedTask(path: path, task: WorkspaceTaskMetadata(
            line: line, due: due, scheduled: scheduled, priority: priority, text: text, checked: checked))
    }

    private func day(_ string: String) -> JournalDay { JournalDay(string: string)! }

    private func texts(_ group: TaskGroup?) -> [String] {
        group?.rows.map(\.task.task.text) ?? []
    }

    private func group(_ groups: [TaskGroup], _ id: String) -> TaskGroup? {
        groups.first { $0.id == id }
    }

    func testTodayGroupsOverdueTodayAndUpcoming() {
        let tasks = [
            task("Late", line: 1, due: "2026-10-18"),
            task("Due today", line: 2, due: "2026-10-21"),
            task("Planned today", line: 3, scheduled: "2026-10-21"),
            task("Both today", line: 4, due: "2026-10-21", scheduled: "2026-10-21"),
            task("Next week", line: 5, scheduled: "2026-10-28"),
            task("Too far", line: 6, due: "2026-10-29"),
            task("Undated", line: 7),
        ]
        let groups = TaskCalendarModel.todayGroups(.init(tasks: tasks), today: today)

        XCTAssertEqual(groups.map(\.id), ["overdue", "today-2026-10-21", "upcoming"])
        XCTAssertEqual(texts(group(groups, "overdue")), ["Late"])
        XCTAssertEqual(texts(group(groups, "today-2026-10-21")), ["Due today", "Planned today", "Both today"])
        XCTAssertEqual(group(groups, "today-2026-10-21")?.rows.map(\.kind), [.due, .scheduled, .due])
        XCTAssertEqual(texts(group(groups, "upcoming")), ["Next week"])
    }

    func testTaskInTodayOrOverdueIsNotRepeatedInUpcoming() {
        let tasks = [
            task("Started", line: 1, due: "2026-10-23", scheduled: "2026-10-21"),
            task("Late but planned", line: 2, due: "2026-10-19", scheduled: "2026-10-22"),
        ]
        let groups = TaskCalendarModel.todayGroups(.init(tasks: tasks), today: today)
        XCTAssertEqual(texts(group(groups, "upcoming")), [])
        XCTAssertEqual(texts(group(groups, "overdue")), ["Late but planned"])
        XCTAssertEqual(texts(group(groups, "today-2026-10-21")), ["Started"])
    }

    func testSortsByPriorityThenDatePathAndLine() {
        let tasks = [
            task("none", path: "a.md", line: 1, due: "2026-10-21"),
            task("low", path: "a.md", line: 2, due: "2026-10-21", priority: "low"),
            task("high b", path: "b.md", line: 1, due: "2026-10-21", priority: "high"),
            task("high a2", path: "a.md", line: 9, due: "2026-10-21", priority: "high"),
            task("high a1", path: "a.md", line: 3, due: "2026-10-21", priority: "high"),
            task("medium", path: "a.md", line: 4, due: "2026-10-21", priority: "medium"),
        ]
        let groups = TaskCalendarModel.todayGroups(.init(tasks: tasks), today: today)
        XCTAssertEqual(texts(group(groups, "today-2026-10-21")),
                       ["high a1", "high a2", "high b", "medium", "low", "none"])
    }

    func testAnotherDaySplitsDueAndScheduled() {
        let tasks = [
            task("Due", line: 1, due: "2026-10-23"),
            task("Planned", line: 2, scheduled: "2026-10-23"),
            task("Both", line: 3, due: "2026-10-23", scheduled: "2026-10-23"),
            task("Other day", line: 4, due: "2026-10-24"),
        ]
        let groups = TaskCalendarModel.dayGroups(.init(tasks: tasks), day: day("2026-10-23"))
        XCTAssertEqual(groups.map(\.id), ["due-2026-10-23", "scheduled-2026-10-23"])
        XCTAssertEqual(texts(groups[0]), ["Due", "Both"])
        XCTAssertEqual(texts(groups[1]), ["Planned"])
        XCTAssertEqual(TaskCalendarModel.dayGroups(.init(tasks: tasks), day: day("2026-10-25")), [])
    }

    func testTaskWithTwoDatesShowsOnBothDays() {
        let tasks = [task("Spread", due: "2026-10-23", scheduled: "2026-10-20")]
        let input = TaskCalendarModel.Input(tasks: tasks)
        XCTAssertEqual(texts(TaskCalendarModel.dayGroups(input, day: day("2026-10-20")).first), ["Spread"])
        XCTAssertEqual(texts(TaskCalendarModel.dayGroups(input, day: day("2026-10-23")).first), ["Spread"])
    }

    func testCompletedHiddenByDefault() {
        let tasks = [task("Done", checked: true, due: "2026-10-01", scheduled: "2026-10-21")]
        let input = TaskCalendarModel.Input(tasks: tasks)
        let groups = TaskCalendarModel.todayGroups(input, today: today)
        XCTAssertTrue(groups.allSatisfy { $0.rows.isEmpty })
        XCTAssertNil(group(groups, "overdue"))
        XCTAssertEqual(TaskCalendarModel.markers(input, today: today), [:])
    }

    func testCompletedShownAfterOpenNeverOverdueOrUpcoming() {
        var filter = TaskFilter()
        filter.showsCompleted = true
        let tasks = [
            task("Done late", line: 1, checked: true, due: "2026-10-01"),
            task("Done today", line: 2, checked: true, due: "2026-10-21", priority: "high"),
            task("Open today", line: 3, due: "2026-10-21"),
            task("Done soon", line: 4, checked: true, due: "2026-10-22"),
        ]
        let input = TaskCalendarModel.Input(tasks: tasks, filter: filter)
        let groups = TaskCalendarModel.todayGroups(input, today: today)

        XCTAssertNil(group(groups, "overdue"))
        let todayGroup = group(groups, "today-2026-10-21")
        XCTAssertEqual(texts(todayGroup), ["Open today", "Done today"])
        XCTAssertEqual(todayGroup?.openCount, 1)
        XCTAssertEqual(todayGroup?.doneCount, 1)
        XCTAssertEqual(texts(group(groups, "upcoming")), [])
        XCTAssertEqual(texts(TaskCalendarModel.dayGroups(input, day: day("2026-10-01")).first), ["Done late"])

        let markers = TaskCalendarModel.markers(input, today: today)
        XCTAssertEqual(markers[day("2026-10-01")], TaskDayMarkers(doneDue: 1))
        XCTAssertEqual(markers[day("2026-10-21")], TaskDayMarkers(openDue: 1, doneDue: 1))
    }

    func testMarkersCountKindsAndOverdue() {
        let tasks = [
            task("a", line: 1, due: "2026-10-19"),
            task("b", line: 2, due: "2026-10-23", scheduled: "2026-10-23"),
            task("c", line: 3, scheduled: "2026-10-23"),
        ]
        let markers = TaskCalendarModel.markers(.init(tasks: tasks), today: today)
        XCTAssertEqual(markers[day("2026-10-19")], TaskDayMarkers(openDue: 1, isOverdue: true))
        XCTAssertEqual(markers[day("2026-10-23")], TaskDayMarkers(openScheduled: 2, openDue: 1))
    }

    func testFilterHidesKindsAndOverdue() {
        let tasks = [task("Late", line: 1, due: "2026-10-18"), task("Plan", line: 2, scheduled: "2026-10-21")]
        var filter = TaskFilter()
        filter.showsOverdue = false
        XCTAssertNil(group(TaskCalendarModel.todayGroups(.init(tasks: tasks, filter: filter), today: today), "overdue"))
        filter = TaskFilter()
        filter.showsScheduled = false
        let groups = TaskCalendarModel.todayGroups(.init(tasks: tasks, filter: filter), today: today)
        XCTAssertEqual(texts(group(groups, "today-2026-10-21")), [])
        XCTAssertEqual(texts(group(groups, "overdue")), ["Late"])
    }

    func testPendingCheckStaysVisibleDuringGrace() {
        let late = task("Late", due: "2026-10-18")
        let input = TaskCalendarModel.Input(tasks: [late], overrides: [late.id: true], keepsVisible: [late.id])
        let groups = TaskCalendarModel.todayGroups(input, today: today)
        // Checked rows leave Overdue, but stay in their day's group.
        XCTAssertNil(group(groups, "overdue"))
        let row = TaskCalendarModel.dayGroups(input, day: day("2026-10-18")).first?.rows.first
        XCTAssertEqual(row?.checked, true)

        let gone = TaskCalendarModel.Input(tasks: [late], overrides: [late.id: true])
        XCTAssertEqual(TaskCalendarModel.dayGroups(gone, day: day("2026-10-18")), [])
    }

    func testUpcomingCrossesMonthYearAndLeapDay() {
        let leapEve = day("2028-02-27")
        let tasks = [task("Leap", line: 1, due: "2028-02-29"), task("March", line: 2, due: "2028-03-05")]
        XCTAssertEqual(texts(group(TaskCalendarModel.todayGroups(.init(tasks: tasks), today: leapEve), "upcoming")),
                       ["Leap", "March"])

        let newYearsEve = day("2026-12-30")
        let next = [task("New year", due: "2027-01-02"), task("Late", line: 2, due: "2026-12-29")]
        let groups = TaskCalendarModel.todayGroups(.init(tasks: next), today: newYearsEve)
        XCTAssertEqual(texts(group(groups, "upcoming")), ["New year"])
        XCTAssertEqual(texts(group(groups, "overdue")), ["Late"])
    }

    func testInvalidDatesAreIgnored() {
        let tasks = [task("Bad", due: "2026-02-30")]
        XCTAssertEqual(TaskCalendarModel.markers(.init(tasks: tasks), today: today), [:])
    }
}
