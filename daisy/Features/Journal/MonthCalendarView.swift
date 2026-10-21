//
//  MonthCalendarView.swift
//  daisy
//
//  The month grid shared by the toolbar's Journal popover and the Tasks
//  sidebar: a header with the month and its arrows, the weekday row, and the
//  days. It follows the editor's date picker (`/schedule`, `/due`): rounded
//  cells, today in bold, the selected day filled in the accent, and the
//  neighbouring months' days dimmed so every month shows six weeks. Each
//  caller draws its own markers under the day number. Clicking a day, or
//  Return on the focused one, calls `open`. Arrow keys move between days,
//  across months too; the focused day is outlined only once they are used.
//  In `.week` the grid is the focused day's week alone and the arrows step
//  a week at a time.
//

import SwiftUI

/// How much of the calendar the grid shows.
enum CalendarSpan: String, CaseIterable {
    case month
    case week
}

struct MonthCalendarView<Marker: View>: View {
    let today: JournalDay
    /// Drawn filled in the accent; nil for none.
    var selected: JournalDay?
    @Binding var year: Int
    @Binding var month: Int
    @Binding var focusedDay: JournalDay
    let accent: Color
    var span: CalendarSpan = .month
    /// Cells grow to fill the width when true, never below `cellSize`.
    var stretches = false
    /// The Journal popover takes focus as it opens; the sidebar does not.
    var focusesOnAppear = true
    let marker: (JournalDay) -> Marker
    let accessibilityLabel: (JournalDay) -> String
    let open: (JournalDay) -> Void

    /// Set by the first arrow key, so a mouse user sees no focused day.
    @State private var showsFocus = false
    @State private var hoveredDay: JournalDay?
    @FocusState private var gridFocused: Bool

    static var cellSize: CGFloat { 32 }

    /// Gregorian, because dates are ISO days, but with the reader's first
    /// weekday and language.
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .current
        calendar.timeZone = .current
        calendar.firstWeekday = Calendar.current.firstWeekday
        return calendar
    }

    private var calendar: Calendar { Self.calendar }

    var body: some View {
        VStack(spacing: 8) {
            header
            weekdayRow
            grid
        }
        .onAppear { if focusesOnAppear { gridFocused = true } }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 4) {
            Button { step(-1) } label: {
                Image(systemName: "chevron.left")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text(span == .week
                ? NSLocalizedString("Previous Week", comment: "Calendar button")
                : NSLocalizedString("Previous Month", comment: "Journal calendar button")))

            Text(monthTitle)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)

            Button { step(1) } label: {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text(span == .week
                ? NSLocalizedString("Next Week", comment: "Calendar button")
                : NSLocalizedString("Next Month", comment: "Journal calendar button")))
        }
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMMMy")
        let first = JournalDay(year: year, month: month, day: 1) ?? today
        return formatter.string(from: first.date(in: calendar))
    }

    private var weekdayRow: some View {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        let ordered = Array(symbols[shift...] + symbols[..<shift])
        return HStack(spacing: 0) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .modifier(CellWidth(stretches: stretches))
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Grid

    private var grid: some View {
        let cells = span == .week
            ? Self.weekCells(containing: focusedDay, calendar: calendar)
            : Self.monthCells(year: year, month: month, calendar: calendar)
        return VStack(spacing: 2) {
            ForEach(0..<(cells.count / 7), id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { column in
                        dayCell(cells[row * 7 + column])
                    }
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($gridFocused)
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .return]) { press in
            if press.key != .return { showsFocus = true }
            switch press.key {
            case .leftArrow: moveFocus(days: -1)
            case .rightArrow: moveFocus(days: 1)
            case .upArrow: moveFocus(days: -7)
            case .downArrow: moveFocus(days: 7)
            default: open(focusedDay)
            }
            return .handled
        }
    }

    /// Six weeks around the month, the days before and after it included.
    static func monthCells(year: Int, month: Int, calendar: Calendar) -> [JournalDay] {
        guard let first = JournalDay(year: year, month: month, day: 1) else { return [] }
        let start = first.date(in: calendar)
        let weekday = calendar.component(.weekday, from: start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        return (0..<42).compactMap { index in
            calendar.date(byAdding: .day, value: index - leading, to: start)
                .map { JournalDay(date: $0, calendar: calendar) }
        }
    }

    /// The week that holds `day`, from the reader's first weekday.
    static func weekCells(containing day: JournalDay, calendar: Calendar) -> [JournalDay] {
        let date = day.date(in: calendar)
        let leading = (calendar.component(.weekday, from: date) - calendar.firstWeekday + 7) % 7
        return (0..<7).compactMap { index in
            calendar.date(byAdding: .day, value: index - leading, to: date)
                .map { JournalDay(date: $0, calendar: calendar) }
        }
    }

    private func dayCell(_ day: JournalDay) -> some View {
        let isToday = day == today
        let isSelected = day == selected
        let isOutside = span == .month && (day.year != year || day.month != month)
        let isFocused = showsFocus && gridFocused && day == focusedDay && !isSelected
        let fill: Color = isSelected ? accent
            : hoveredDay == day ? Color.primary.opacity(0.06) : Color.clear
        return Button {
            focusedDay = day
            if day.year != year || day.month != month {
                year = day.year
                month = day.month
            }
            open(day)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(fill)
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isFocused ? accent.opacity(0.6) : Color.clear, lineWidth: 1)
                Text("\(day.day)")
                    .font(.system(size: 13, weight: isToday ? .bold : .regular).monospacedDigit())
                    .foregroundStyle(isSelected ? Color.white : isOutside ? Color.secondary : Color.primary)
                    .offset(y: -2)
                // White on the filled cell, so an accent marker stays visible.
                marker(day)
                    .frame(height: 4)
                    .saturation(isSelected ? 0 : 1)
                    .brightness(isSelected ? 1 : 0)
                    .offset(y: 10)
            }
            .opacity(isOutside && !isSelected ? 0.6 : 1)
            // Square however wide the column grows.
            .frame(width: Self.cellSize, height: Self.cellSize)
            .modifier(CellWidth(stretches: stretches))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { hoveredDay = day } else if hoveredDay == day { hoveredDay = nil }
        }
        .accessibilityLabel(Text(accessibilityLabel(day)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Navigation

    private func step(_ offset: Int) {
        if span == .week { moveFocus(days: offset * 7) } else { showMonth(offset: offset) }
    }

    private func showMonth(offset: Int) {
        let total = year * 12 + (month - 1) + offset
        year = total / 12
        month = total % 12 + 1
        let day = min(focusedDay.day, JournalDay.daysInMonth(year: year, month: month))
        if let moved = JournalDay(year: year, month: month, day: day) { focusedDay = moved }
    }

    private func moveFocus(days: Int) {
        guard let date = calendar.date(byAdding: .day, value: days, to: focusedDay.date(in: calendar))
        else { return }
        focusedDay = JournalDay(date: date, calendar: calendar)
        year = focusedDay.year
        month = focusedDay.month
    }
}

/// A fixed 32 pt column, or one sharing the row's width with its siblings.
private struct CellWidth: ViewModifier {
    let stretches: Bool

    func body(content: Content) -> some View {
        if stretches {
            content.frame(minWidth: MonthCalendarView<EmptyView>.cellSize, maxWidth: .infinity)
        } else {
            content.frame(width: MonthCalendarView<EmptyView>.cellSize)
        }
    }
}
