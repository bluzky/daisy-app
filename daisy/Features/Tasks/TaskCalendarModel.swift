//
//  TaskCalendarModel.swift
//  daisy
//
//  What the Tasks sidebar shows for a set of indexed tasks: the markers on
//  each calendar day, and the grouped rows for today or for a picked day.
//  Only tasks with a valid `scheduled:` or `due:` date take part. Checked
//  tasks are left out unless Show Completed is on, and are never Overdue or
//  Upcoming. Pure Foundation, with today passed in, so the helper tests can
//  drive it.
//

import Foundation

nonisolated enum TaskDateKind: String, Sendable {
    case due
    case scheduled
}

nonisolated struct TaskFilter: Equatable, Sendable {
    var showsScheduled = true
    var showsDue = true
    var showsCompleted = false
    var showsOverdue = true
}

/// One task under one of its dates.
nonisolated struct TaskRow: Identifiable, Equatable, Sendable {
    let task: WorkspaceIndexedTask
    let kind: TaskDateKind
    let date: JournalDay
    /// The state shown, which a pending check from the sidebar may change.
    let checked: Bool

    var id: String { "\(task.id)\u{0}\(kind.rawValue)" }
}

nonisolated struct TaskGroup: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case overdue
        case today(JournalDay)
        case upcoming
        case due(JournalDay)
        case scheduled(JournalDay)
    }

    let kind: Kind
    /// Open rows first, then checked ones, each in sort order.
    let rows: [TaskRow]

    var openCount: Int { rows.count(where: { !$0.checked }) }
    var doneCount: Int { rows.count(where: { $0.checked }) }

    var id: String {
        switch kind {
        case .overdue: "overdue"
        case .today(let day): "today-\(day.string)"
        case .upcoming: "upcoming"
        case .due(let day): "due-\(day.string)"
        case .scheduled(let day): "scheduled-\(day.string)"
        }
    }
}

/// What one calendar day carries. Open tasks draw a filled marker, a day
/// whose tasks are all done a hollow one.
nonisolated struct TaskDayMarkers: Equatable, Sendable {
    var openScheduled = 0
    var doneScheduled = 0
    var openDue = 0
    var doneDue = 0
    /// An open task is due that day and the day is before today.
    var isOverdue = false

    var isEmpty: Bool { openScheduled + doneScheduled + openDue + doneDue == 0 }
}

nonisolated enum TaskCalendarModel {
    /// Days Upcoming looks ahead, today excluded.
    static let upcomingDays = 7

    /// The indexed tasks as shown: `overrides` holds the state of tasks
    /// checked or unchecked from the sidebar whose write the index has not
    /// confirmed yet, and `keepsVisible` tasks checked within their grace
    /// period, which stay as struck-through rows with Show Completed off.
    nonisolated struct Input: Sendable {
        var tasks: [WorkspaceIndexedTask]
        var filter = TaskFilter()
        var overrides: [String: Bool] = [:]
        var keepsVisible: Set<String> = []

        init(tasks: [WorkspaceIndexedTask], filter: TaskFilter = TaskFilter(),
             overrides: [String: Bool] = [:], keepsVisible: Set<String> = []) {
            self.tasks = tasks
            self.filter = filter
            self.overrides = overrides
            self.keepsVisible = keepsVisible
        }

        func checked(_ task: WorkspaceIndexedTask) -> Bool {
            overrides[task.id] ?? task.task.checked
        }

        /// Whether a task in this state is shown at all.
        func isShown(_ task: WorkspaceIndexedTask) -> Bool {
            !checked(task) || filter.showsCompleted || keepsVisible.contains(task.id)
        }

        /// The task's dates the filter shows, as rows.
        func rows(_ task: WorkspaceIndexedTask) -> [TaskRow] {
            guard isShown(task) else { return [] }
            var rows: [TaskRow] = []
            if filter.showsDue, let due = task.task.due.flatMap(JournalDay.init(string:)) {
                rows.append(TaskRow(task: task, kind: .due, date: due, checked: checked(task)))
            }
            if filter.showsScheduled, let scheduled = task.task.scheduled.flatMap(JournalDay.init(string:)) {
                rows.append(TaskRow(task: task, kind: .scheduled, date: scheduled, checked: checked(task)))
            }
            return rows
        }
    }

    // MARK: - Calendar

    static func markers(_ input: Input, today: JournalDay) -> [JournalDay: TaskDayMarkers] {
        var markers: [JournalDay: TaskDayMarkers] = [:]
        for task in input.tasks {
            for row in input.rows(task) {
                var day = markers[row.date, default: TaskDayMarkers()]
                switch (row.kind, row.checked) {
                case (.scheduled, false): day.openScheduled += 1
                case (.scheduled, true): day.doneScheduled += 1
                case (.due, false):
                    day.openDue += 1
                    if row.date < today { day.isOverdue = true }
                case (.due, true): day.doneDue += 1
                }
                markers[row.date] = day
            }
        }
        return markers
    }

    // MARK: - Groups

    /// Overdue (when shown and not empty), today, and Upcoming.
    static func todayGroups(_ input: Input, today: JournalDay) -> [TaskGroup] {
        var overdue: [TaskRow] = []
        var upcoming: [TaskRow] = []
        let horizon = today.adding(days: upcomingDays)
        let onToday = rowsOn(today, input)
        let shownToday = Set((onToday.due + onToday.scheduled).map(\.task.id))
        for task in input.tasks {
            let rows = input.rows(task)
            var isListed = shownToday.contains(task.id)
            if input.filter.showsOverdue,
               let due = rows.first(where: { $0.kind == .due }), !due.checked, due.date < today {
                overdue.append(due)
                isListed = true
            }
            // Each open task not listed above once, at its earliest date
            // ahead; Due on a tie.
            if !isListed, let next = rows.filter({ !$0.checked && $0.date > today && $0.date <= horizon })
                .min(by: { ($0.date, $0.kind == .due ? 0 : 1) < ($1.date, $1.kind == .due ? 0 : 1) }) {
                upcoming.append(next)
            }
        }
        var groups: [TaskGroup] = []
        if !overdue.isEmpty { groups.append(TaskGroup(kind: .overdue, rows: sorted(overdue))) }
        groups.append(TaskGroup(kind: .today(today), rows: sorted(onToday.due + onToday.scheduled)))
        groups.append(TaskGroup(kind: .upcoming, rows: sorted(upcoming)))
        return groups
    }

    /// Due and Scheduled for a day that is not today; empty groups left out.
    static func dayGroups(_ input: Input, day: JournalDay) -> [TaskGroup] {
        let rows = rowsOn(day, input)
        return [TaskGroup(kind: .due(day), rows: sorted(rows.due)),
                TaskGroup(kind: .scheduled(day), rows: sorted(rows.scheduled))]
            .filter { !$0.rows.isEmpty }
    }

    /// A task due and scheduled on the same day shows once, under Due.
    private static func rowsOn(_ day: JournalDay, _ input: Input) -> (due: [TaskRow], scheduled: [TaskRow]) {
        var due: [TaskRow] = []
        var scheduled: [TaskRow] = []
        for task in input.tasks {
            let rows = input.rows(task).filter { $0.date == day }
            if let row = rows.first(where: { $0.kind == .due }) {
                due.append(row)
            } else if let row = rows.first {
                scheduled.append(row)
            }
        }
        return (due, scheduled)
    }

    /// Open before checked; then priority high, medium, low, none; then
    /// date, file path and line.
    static func sorted(_ rows: [TaskRow]) -> [TaskRow] {
        rows.sorted { lhs, rhs in
            if lhs.checked != rhs.checked { return !lhs.checked }
            let left = priorityRank(lhs.task.task.priority), right = priorityRank(rhs.task.task.priority)
            if left != right { return left < right }
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            if lhs.task.path != rhs.task.path { return lhs.task.path < rhs.task.path }
            if lhs.task.task.line != rhs.task.task.line { return lhs.task.task.line < rhs.task.task.line }
            return lhs.kind == .due && rhs.kind != .due
        }
    }

    static func priorityRank(_ priority: String?) -> Int {
        switch priority {
        case "high": 0
        case "medium": 1
        case "low": 2
        default: 3
        }
    }
}
