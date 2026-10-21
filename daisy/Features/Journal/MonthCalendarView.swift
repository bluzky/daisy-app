//
//  MonthCalendarView.swift
//  daisy
//
//  The month grid shared by the toolbar's Journal popover and the Tasks
//  sidebar: a header with the month and its arrows, the weekday row, and the
//  days, with today ringed in the accent. Each caller draws its own markers
//  under the day number. Clicking a day, or Return on the focused one, calls
//  `open`. Arrow keys move between days, across months too; the focused day
//  is outlined only once they are used.
//

import SwiftUI

struct MonthCalendarView<Marker: View>: View {
    let today: JournalDay
    /// Drawn filled in the accent; nil for none.
    var selected: JournalDay?
    @Binding var year: Int
    @Binding var month: Int
    @Binding var focusedDay: JournalDay
    let accent: Color
    /// Cells grow to fill the width when true, never below `cellSize`.
    var stretches = false
    /// The Journal popover takes focus as it opens; the sidebar does not.
    var focusesOnAppear = true
    let marker: (JournalDay) -> Marker
    let accessibilityLabel: (JournalDay) -> String
    let open: (JournalDay) -> Void

    /// Set by the first arrow key, so a mouse user sees no focused day.
    @State private var showsFocus = false
    @FocusState private var gridFocused: Bool

    static var cellSize: CGFloat { 30 }

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
            Button { showMonth(offset: -1) } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text(NSLocalizedString("Previous Month", comment: "Journal calendar button")))

            Text(monthTitle)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)

            Button { showMonth(offset: 1) } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text(NSLocalizedString("Next Month", comment: "Journal calendar button")))
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .modifier(CellWidth(stretches: stretches))
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Grid

    private var grid: some View {
        let cells = Self.monthCells(year: year, month: month, calendar: calendar)
        return VStack(spacing: 2) {
            ForEach(0..<(cells.count / 7), id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { column in
                        if let day = cells[row * 7 + column] {
                            dayCell(day)
                        } else {
                            Color.clear
                                .frame(height: Self.cellSize)
                                .modifier(CellWidth(stretches: stretches))
                        }
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

    /// The month's days in weeks, nil-padded to whole rows.
    static func monthCells(year: Int, month: Int, calendar: Calendar) -> [JournalDay?] {
        guard let first = JournalDay(year: year, month: month, day: 1) else { return [] }
        let weekday = calendar.component(.weekday, from: first.date(in: calendar))
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let count = JournalDay.daysInMonth(year: year, month: month)
        var cells: [JournalDay?] = Array(repeating: nil, count: leading)
        cells += (1...count).map { JournalDay(year: year, month: month, day: $0) }
        cells += Array(repeating: nil, count: (7 - cells.count % 7) % 7)
        return cells
    }

    private func dayCell(_ day: JournalDay) -> some View {
        let isToday = day == today
        let isSelected = day == selected
        let isFocused = showsFocus && gridFocused && day == focusedDay
        return Button {
            focusedDay = day
            open(day)
        } label: {
            ZStack {
                Circle()
                    .fill(isSelected ? accent : Color.clear)
                Circle()
                    .strokeBorder(isToday && !isSelected ? accent : Color.clear, lineWidth: 1.5)
                Text("\(day.day)")
                    .font(.system(size: 12, weight: isToday || isSelected ? .semibold : .regular).monospacedDigit())
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                marker(day)
                    .offset(y: 9)
            }
            .frame(width: Self.cellSize - 4, height: Self.cellSize - 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isFocused ? accent.opacity(0.6) : Color.clear, lineWidth: 1)
                    .frame(width: Self.cellSize, height: Self.cellSize)
            )
            .frame(height: Self.cellSize)
            .modifier(CellWidth(stretches: stretches))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel(day)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Navigation

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

/// A fixed 30 pt column, or one sharing the row's width with its siblings.
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
