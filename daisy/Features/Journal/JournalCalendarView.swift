//
//  JournalCalendarView.swift
//  daisy
//
//  The month grid in the toolbar's Journal popover. Days that already have
//  an entry carry a dot in the theme's accent (its link color), and the day
//  the arrow keys are on is filled with it, as in the editor's date picker;
//  today is bold. Clicking a day, or Return on the focused one, opens it,
//  creating its entry when it has none. The grid itself is
//  `MonthCalendarView`, shared with the Tasks sidebar.
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
    @Environment(\.colorScheme) private var colorScheme

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

    var body: some View {
        MonthCalendarView(
            today: today,
            selected: focusedDay,
            year: $year,
            month: $month,
            focusedDay: $focusedDay,
            accent: accent,
            marker: { day in
                Circle()
                    .fill(entries.contains(day) ? accent : Color.clear)
                    .frame(width: 4, height: 4)
            },
            accessibilityLabel: accessibilityLabel(for:),
            open: open
        )
        .padding(12)
        .frame(width: MonthCalendarView<EmptyView>.cellSize * 7 + 24)
    }

    private func accessibilityLabel(for day: JournalDay) -> String {
        var parts = [day.date(in: MonthCalendarView<EmptyView>.calendar).formatted(date: .complete, time: .omitted)]
        if day == today { parts.append(NSLocalizedString("Today", comment: "Journal calendar day")) }
        if entries.contains(day) { parts.append(NSLocalizedString("has entry", comment: "Journal calendar day")) }
        return parts.joined(separator: ", ")
    }
}
