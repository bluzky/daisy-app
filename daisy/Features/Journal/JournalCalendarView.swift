//
//  JournalCalendarView.swift
//  daisy
//
//  The month grid in the toolbar's Journal popover. Days that already have
//  an entry carry a dot and today is ringed, both in the theme's accent (its
//  link color). Clicking a day, or Return on the focused one, opens it,
//  creating its entry when it has none. Arrow keys move between days, across
//  months too; the focused day is outlined only once they are used.
//

import SwiftUI

struct JournalCalendarView: View {
    let today: JournalDay
    /// The entry the window is showing, if it is one; its month opens first.
    let current: JournalDay?
    let entries: Set<JournalDay>
    let open: (JournalDay) -> Void

    @State private var year: Int
    @State private var month: Int
    @State private var focusedDay: JournalDay
    /// Set by the first arrow key, so a mouse user sees no focused day.
    @State private var showsFocus = false
    @FocusState private var gridFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    private static let cellSize: CGFloat = 30

    init(today: JournalDay, current: JournalDay?, entries: Set<JournalDay>,
         open: @escaping (JournalDay) -> Void) {
        self.today = today
        self.current = current
        self.entries = entries
        self.open = open
        let start = current ?? today
        _year = State(initialValue: start.year)
        _month = State(initialValue: start.month)
        _focusedDay = State(initialValue: start)
    }

    /// The theme's link color, as the sidebar's selected file uses, or the
    /// system accent without a theme override.
    private var accent: Color {
        let scheme: ThemeColorScheme = colorScheme == .dark ? .dark : .light
        return Color(nsColor: ThemeColorsSetting.current.color(.linkColor, scheme) ?? .controlAccentColor)
    }

    /// Gregorian, because entry names are ISO days, but with the reader's
    /// first weekday and language.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .current
        calendar.timeZone = .current
        calendar.firstWeekday = Calendar.current.firstWeekday
        return calendar
    }

    var body: some View {
        VStack(spacing: 8) {
            header
            weekdayRow
            grid
        }
        .padding(12)
        .frame(width: Self.cellSize * 7 + 24)
        .onAppear { gridFocused = true }
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
                    .frame(width: Self.cellSize)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Grid

    private var grid: some View {
        let cells = monthCells
        return VStack(spacing: 2) {
            ForEach(0..<(cells.count / 7), id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { column in
                        if let day = cells[row * 7 + column] {
                            dayCell(day)
                        } else {
                            Color.clear.frame(width: Self.cellSize, height: Self.cellSize)
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
    private var monthCells: [JournalDay?] {
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
        let hasEntry = entries.contains(day)
        let isFocused = showsFocus && gridFocused && day == focusedDay
        return Button {
            focusedDay = day
            open(day)
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(isToday ? accent : Color.clear, lineWidth: 1.5)
                Text("\(day.day)")
                    .font(.system(size: 12, weight: isToday ? .semibold : .regular).monospacedDigit())
                    .foregroundStyle(Color.primary)
                if hasEntry {
                    Circle()
                        .fill(accent)
                        .frame(width: 4, height: 4)
                        .offset(y: 9)
                }
            }
            .frame(width: Self.cellSize - 4, height: Self.cellSize - 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isFocused ? accent.opacity(0.6) : Color.clear, lineWidth: 1)
                    .frame(width: Self.cellSize, height: Self.cellSize)
            )
            .frame(width: Self.cellSize, height: Self.cellSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel(for: day, hasEntry: hasEntry, isToday: isToday)))
    }

    private func accessibilityLabel(for day: JournalDay, hasEntry: Bool, isToday: Bool) -> String {
        var parts = [day.date(in: calendar).formatted(date: .complete, time: .omitted)]
        if isToday { parts.append(NSLocalizedString("Today", comment: "Journal calendar day")) }
        if hasEntry { parts.append(NSLocalizedString("has entry", comment: "Journal calendar day")) }
        return parts.joined(separator: ", ")
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
