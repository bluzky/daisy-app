//
//  TaskCalendarView.swift
//  daisy
//
//  The Agenda sidebar's content: header and filter menu, the month grid with
//  a dot on each day that has scheduled or due tasks, and the list. Today
//  shows Overdue, Today and Upcoming; another day shows its Due
//  and Scheduled tasks. Rows open their file at the task when clicked and
//  check the task off from the checkbox.
//

import SwiftUI

struct TaskCalendarView: View {
    @ObservedObject var store: TaskCalendarStore
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var listFocused: Bool
    @State private var focusedRowID: String?
    @State private var hoveredRowID: String?

    /// The theme's link color, as the Journal calendar uses.
    private var accent: Color {
        let scheme: ThemeColorScheme = colorScheme == .dark ? .dark : .light
        return Color(nsColor: ThemeColorsSetting.current.color(.linkColor, scheme) ?? .controlAccentColor)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.isWorkspace {
                calendar
                Divider()
                list
                    .overlay(alignment: .bottom) { banner }
            } else {
                noWorkspace
            }
        }
        .frame(minWidth: 270, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(NSLocalizedString("Agenda", comment: "Tasks sidebar title"))
                // As the Files sidebar's section headers.
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if store.isWorkspace { filterMenu }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var filterMenu: some View {
        Menu {
            Toggle(NSLocalizedString("Scheduled", comment: "Tasks filter"), isOn: $store.filter.showsScheduled)
            Toggle(NSLocalizedString("Due", comment: "Tasks filter"), isOn: $store.filter.showsDue)
            Divider()
            Toggle(NSLocalizedString("Show Completed", comment: "Tasks filter"), isOn: $store.filter.showsCompleted)
            Toggle(NSLocalizedString("Show Overdue", comment: "Tasks filter"), isOn: $store.filter.showsOverdue)
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(NSLocalizedString("Filter Tasks", comment: "Tasks filter menu tooltip"))
        .accessibilityLabel(Text(NSLocalizedString("Filter Tasks", comment: "Tasks filter menu tooltip")))
    }

    // MARK: - Calendar

    private var calendar: some View {
        let markers = TaskCalendarModel.markers(store.input, today: store.today)
        return MonthCalendarView(
            today: store.today,
            selected: store.selectedDay ?? store.today,
            year: $store.year,
            month: $store.month,
            focusedDay: $store.focusedDay,
            accent: accent,
            stretches: true,
            focusesOnAppear: false,
            marker: { day in dayMarkers(markers[day]) },
            accessibilityLabel: { day in accessibilityLabel(day, markers[day]) },
            open: { store.select($0) }
        )
        .padding(12)
    }

    /// One dot per day: red when something due is overdue, the accent while
    /// any task is open, hollow once they are all done.
    @ViewBuilder
    private func dayMarkers(_ markers: TaskDayMarkers?) -> some View {
        if let markers {
            let open = markers.openScheduled + markers.openDue
            if open > 0 {
                Circle().fill(markers.isOverdue ? Color.red : accent).frame(width: 4, height: 4)
            } else if markers.doneScheduled + markers.doneDue > 0 {
                Circle().strokeBorder(Color.secondary, lineWidth: 1).frame(width: 4, height: 4)
            }
        }
    }

    private func accessibilityLabel(_ day: JournalDay, _ markers: TaskDayMarkers?) -> String {
        var parts = [day.date(in: MonthCalendarView<EmptyView>.calendar).formatted(date: .complete, time: .omitted)]
        if day == store.today { parts.append(NSLocalizedString("Today", comment: "Journal calendar day")) }
        if let markers {
            if markers.openDue > 0 {
                parts.append(String(format: NSLocalizedString("%d due", comment: "Tasks calendar day"), markers.openDue))
            }
            if markers.openScheduled > 0 {
                parts.append(String(format: NSLocalizedString("%d scheduled", comment: "Tasks calendar day"),
                                    markers.openScheduled))
            }
            let done = markers.doneDue + markers.doneScheduled
            if done > 0 {
                parts.append(String(format: NSLocalizedString("%d done", comment: "Tasks calendar day"), done))
            }
            if markers.isOverdue { parts.append(NSLocalizedString("Overdue", comment: "Tasks calendar day")) }
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - List

    private var groups: [TaskGroup] {
        if let day = store.selectedDay {
            return TaskCalendarModel.dayGroups(store.input, day: day)
        }
        return TaskCalendarModel.todayGroups(store.input, today: store.today)
    }

    /// Rows in the order the keyboard moves through them, collapsed
    /// groups left out.
    private func visibleRows(_ groups: [TaskGroup]) -> [TaskRow] {
        groups.filter { !store.collapsedGroups.contains($0.id) }.flatMap(\.rows)
    }

    private var list: some View {
        let groups = groups
        let rows = visibleRows(groups)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let day = store.selectedDay {
                        dayList(day, groups)
                    } else {
                        todayList(groups)
                    }
                    if store.isIndexing {
                        Label(NSLocalizedString("Indexing workspace…", comment: "Tasks sidebar status"),
                              systemImage: "arrow.triangle.2.circlepath")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                }
                .padding(.bottom, store.banner == nil ? 8 : 52)
            }
            .focusable()
            .focusEffectDisabled()
            .focused($listFocused)
            .onKeyPress(keys: [.upArrow, .downArrow, .return, .space]) { press in
                handleKey(press.key, rows: rows, proxy: proxy)
            }
        }
    }

    private func handleKey(_ key: KeyEquivalent, rows: [TaskRow], proxy: ScrollViewProxy) -> KeyPress.Result {
        guard !rows.isEmpty else { return .ignored }
        let current = rows.firstIndex { $0.id == focusedRowID }
        switch key {
        case .upArrow, .downArrow:
            let next = key == .upArrow ? max((current ?? rows.count) - 1, 0) : min((current ?? -1) + 1, rows.count - 1)
            focusedRowID = rows[next].id
            proxy.scrollTo(rows[next].id)
        case .return:
            guard let current else { return .ignored }
            store.onOpenTask?(rows[current].task, false)
        case .space:
            guard let current else { return .ignored }
            store.toggle(rows[current])
        default:
            return .ignored
        }
        return .handled
    }

    @ViewBuilder
    private func todayList(_ groups: [TaskGroup]) -> some View {
        ForEach(groups) { group in
            switch group.kind {
            case .overdue:
                section(group, title: NSLocalizedString("Overdue", comment: "Tasks sidebar section"),
                        titleColor: .red, detail: .date)
            case .today(let day):
                section(group, title: String(format: NSLocalizedString("Today · %@", comment: "Tasks sidebar section"),
                                             shortDay(day)),
                        detail: .kind)
                if group.rows.isEmpty { emptyDay }
            case .upcoming:
                section(group, title: String(format: NSLocalizedString("Upcoming · Next %d Days",
                                                                       comment: "Tasks sidebar section"),
                                             TaskCalendarModel.upcomingDays),
                        detail: .date)
            case .due, .scheduled:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func dayList(_ day: JournalDay, _ groups: [TaskGroup]) -> some View {
        HStack {
            Text(day.date(in: MonthCalendarView<EmptyView>.calendar)
                .formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            countLabel(open: groups.reduce(0) { $0 + $1.openCount }, done: groups.reduce(0) { $0 + $1.doneCount })
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .accessibilityAddTraits(.isHeader)
        if groups.isEmpty {
            emptyDay
        }
        ForEach(groups) { group in
            let title = if case .due = group.kind {
                NSLocalizedString("Due", comment: "Tasks sidebar subsection")
            } else {
                NSLocalizedString("Scheduled", comment: "Tasks sidebar subsection")
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 2)
            ForEach(group.rows) { row in rowView(row, detail: .path) }
        }
        HStack {
            Spacer()
            Button {
                store.showToday()
            } label: {
                Label(NSLocalizedString("Back to Today", comment: "Tasks sidebar button"),
                      systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
    }

    private func section(_ group: TaskGroup, title: String, titleColor: Color = .secondary,
                         detail: RowDetail) -> some View {
        let collapsed = store.collapsedGroups.contains(group.id)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                if collapsed { store.collapsedGroups.remove(group.id) } else { store.collapsedGroups.insert(group.id) }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .frame(width: 10)
                    Text(title.uppercased())
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(titleColor)
                    Spacer()
                    countLabel(open: group.openCount, done: group.doneCount)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(Text(collapsed
                ? NSLocalizedString("Collapsed", comment: "Tasks sidebar section state")
                : NSLocalizedString("Expanded", comment: "Tasks sidebar section state")))
            if !collapsed {
                ForEach(group.rows) { row in rowView(row, detail: detail) }
            }
        }
    }

    @ViewBuilder
    private func countLabel(open: Int, done: Int) -> some View {
        if open + done > 0 {
            Text(done > 0 ? "\(open) · \(done)✓" : "\(open)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text(done > 0
                    ? String(format: NSLocalizedString("%d open, %d done", comment: "Tasks sidebar count"), open, done)
                    : String(format: NSLocalizedString("%d open", comment: "Tasks sidebar count"), open)))
        }
    }

    private var emptyDay: some View {
        VStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(NSLocalizedString("Nothing scheduled or due", comment: "Tasks sidebar empty day"))
                .font(.body)
            Text(NSLocalizedString("Add dates to tasks with /schedule or /due", comment: "Tasks sidebar empty day hint"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
    }

    // MARK: - Rows

    enum RowDetail {
        /// "scheduled · file", for today.
        case kind
        /// "Oct 18 · file", for Overdue and Upcoming.
        case date
        /// The workspace path, under a day's Due or Scheduled heading.
        case path
    }

    private func rowView(_ row: TaskRow, detail: RowDetail) -> some View {
        let task = row.task
        let isHighlighted = hoveredRowID == row.id || (listFocused && focusedRowID == row.id)
        let error = store.errors[task.id]
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button {
                focusedRowID = row.id
                store.toggle(row)
            } label: {
                TaskCheckbox(checked: row.checked, accent: accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(row.checked
                ? NSLocalizedString("Mark task incomplete", comment: "Tasks sidebar checkbox")
                : NSLocalizedString("Mark task complete", comment: "Tasks sidebar checkbox")))

            VStack(alignment: .leading, spacing: 2) {
                Text(styledText(task.task.text))
                    .strikethrough(row.checked)
                    .foregroundStyle(row.checked ? Color.secondary : Color.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                detailLine(row, detail)
                if let error {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            priority(task.task.priority)
            Image(systemName: "arrow.up.right")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .opacity(isHighlighted ? 1 : 0)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHighlighted ? Color.primary.opacity(0.07) : Color.clear)
        )
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            focusedRowID = row.id
            store.onOpenTask?(task, false)
        }
        .onHover { hovering in
            if hovering { hoveredRowID = row.id } else if hoveredRowID == row.id { hoveredRowID = nil }
        }
        .help(task.path)
        .id(row.id)
        .contextMenu {
            Button(NSLocalizedString("Open", comment: "Tasks row context menu")) { store.onOpenTask?(task, false) }
            Button(NSLocalizedString("Open in New Tab", comment: "Tasks row context menu")) { store.onOpenTask?(task, true) }
            Button(NSLocalizedString("Reveal in Files", comment: "Tasks row context menu")) { store.onRevealTask?(task) }
            Divider()
            Button(NSLocalizedString("Copy Task Text", comment: "Tasks row context menu")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(task.task.text, forType: .string)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text(row.checked
            ? NSLocalizedString("Mark task incomplete", comment: "Tasks sidebar checkbox")
            : NSLocalizedString("Mark task complete", comment: "Tasks sidebar checkbox"))) {
            store.toggle(row)
        }
    }

    /// `+project` and `@context` in the accent.
    private func styledText(_ text: String) -> AttributedString {
        var result = AttributedString()
        for (offset, word) in text.split(separator: " ", omittingEmptySubsequences: false).enumerated() {
            if offset > 0 { result.append(AttributedString(" ")) }
            var part = AttributedString(String(word))
            if word.count > 1, word.first == "+" || word.first == "@" { part.foregroundColor = accent }
            result.append(part)
        }
        return result
    }

    private func detailLine(_ row: TaskRow, _ detail: RowDetail) -> some View {
        let isOverdue = row.kind == .due && !row.checked && row.date < store.today
        let file = (row.task.path as NSString).lastPathComponent
        let text: String
        switch detail {
        case .kind:
            text = "\(row.kind == .due ? NSLocalizedString("due", comment: "Tasks row date kind") : NSLocalizedString("scheduled", comment: "Tasks row date kind")) · \(file)"
        case .date:
            text = "\(shortDate(row.date)) · \(file)"
        case .path:
            text = row.task.path
        }
        return HStack(spacing: 4) {
            if detail != .path {
                Image(systemName: row.kind == .due ? "clock" : "calendar")
                    .foregroundStyle(isOverdue ? Color.red : Color.secondary)
                    .accessibilityLabel(Text(row.kind == .due
                        ? NSLocalizedString("Due", comment: "Tasks sidebar subsection")
                        : NSLocalizedString("Scheduled", comment: "Tasks sidebar subsection")))
            }
            Text(text)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.subheadline)
    }

    @ViewBuilder
    private func priority(_ priority: String?) -> some View {
        switch priority {
        case "high":
            priorityMark("!!", .red, NSLocalizedString("Priority: High", comment: "Tasks row priority"))
        case "medium":
            priorityMark("!", .orange, NSLocalizedString("Priority: Medium", comment: "Tasks row priority"))
        case "low":
            priorityMark("!", .blue, NSLocalizedString("Priority: Low", comment: "Tasks row priority"))
        default:
            EmptyView()
        }
    }

    private func priorityMark(_ mark: String, _ color: Color, _ label: String) -> some View {
        Text(mark)
            .font(.callout.weight(.bold))
            .foregroundStyle(color)
            .help(label)
            .accessibilityLabel(Text(label))
    }

    private func shortDay(_ day: JournalDay) -> String {
        day.date(in: MonthCalendarView<EmptyView>.calendar).formatted(.dateTime.weekday(.abbreviated).day())
    }

    private func shortDate(_ day: JournalDay) -> String {
        day.date(in: MonthCalendarView<EmptyView>.calendar).formatted(.dateTime.month(.abbreviated).day())
    }

    // MARK: - Banner and empty states

    @ViewBuilder
    private var banner: some View {
        if let task = store.banner {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(accent)
                Text(String(format: NSLocalizedString("Completed “%@”", comment: "Tasks sidebar banner"), task.task.text))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Button(NSLocalizedString("Undo", comment: "Tasks sidebar banner button")) { store.undo() }
                    .buttonStyle(.borderless)
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 2, y: 1)
            .padding(8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var noWorkspace: some View {
        VStack(spacing: 10) {
            Image(systemName: "checklist")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(NSLocalizedString("The agenda is available in a workspace.", comment: "Tasks sidebar outside a workspace"))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if store.canInitializeWorkspace, store.onInitializeWorkspace != nil {
                Button(NSLocalizedString("Initialize Workspace", comment: "Tasks sidebar button")) {
                    store.onInitializeWorkspace?()
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The rendered Markdown checkbox (`.task-list-item-checkbox`): a rounded
/// square in the separator color, filled with the accent and a white tick
/// when checked.
private struct TaskCheckbox: View {
    let checked: Bool
    let accent: Color
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 14

    var body: some View {
        RoundedRectangle(cornerRadius: size / 4)
            .fill(checked ? accent : Color.clear)
            .overlay {
                RoundedRectangle(cornerRadius: size / 4)
                    .strokeBorder(checked ? accent : Color(nsColor: .separatorColor), lineWidth: 1.5)
            }
            .overlay {
                if checked { Tick().stroke(.white, style: StrokeStyle(lineWidth: size / 8, lineCap: .round, lineJoin: .round)) }
            }
            .frame(width: size, height: size)
            // Centred on the title's capitals, as in the preview.
            .alignmentGuide(.firstTextBaseline) { $0.height * 0.83 }
    }

    /// The preview's tick path, `M4.4 8.4 L7 11 L11.6 5.4` on a 16-unit box.
    private struct Tick: Shape {
        func path(in rect: CGRect) -> Path {
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: rect.minX + rect.width * x / 16, y: rect.minY + rect.height * y / 16)
            }
            var path = Path()
            path.move(to: point(4.4, 8.4))
            path.addLine(to: point(7, 11))
            path.addLine(to: point(11.6, 5.4))
            return path
        }
    }
}
