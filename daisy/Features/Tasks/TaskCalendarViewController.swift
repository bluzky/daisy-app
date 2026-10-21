//
//  TaskCalendarViewController.swift
//  daisy
//
//  The Tasks sidebar, the window's right-hand pane: a month calendar of the
//  workspace's dated tasks and the list for the chosen day. It reads the
//  workspace index only while the pane is visible, fetching the task list
//  again whenever the index's task revision moves. Checking a task off goes
//  through `onSetTaskChecked`; the window controller does the writing.
//

import Cocoa
import Combine
import SwiftUI

@MainActor
final class TaskCalendarStore: ObservableObject {
    @Published var isWorkspace = false
    @Published var canInitializeWorkspace = false
    @Published var isIndexing = false
    @Published var tasks: [WorkspaceIndexedTask] = []
    @Published var today = JournalDay(date: Date())
    /// Nil shows today, with Overdue and Upcoming.
    @Published var selectedDay: JournalDay?
    @Published var year: Int
    @Published var month: Int
    @Published var focusedDay: JournalDay
    @Published var filter: TaskFilter {
        didSet { Self.saveFilter(filter) }
    }
    /// States checked from the sidebar that the index has not caught up with.
    @Published private(set) var overrides: [String: Bool] = [:]
    /// Tasks checked within their grace period, still shown struck through.
    @Published private(set) var keepsVisible: Set<String> = []
    @Published private(set) var errors: [String: String] = [:]
    @Published private(set) var banner: WorkspaceIndexedTask?
    @Published var collapsedGroups: Set<String> = ["upcoming"]

    var onOpenTask: ((WorkspaceIndexedTask, Bool) -> Void)?
    var onRevealTask: ((WorkspaceIndexedTask) -> Void)?
    var onSetTaskChecked: ((WorkspaceIndexedTask, Bool, @escaping (String?) -> Void) -> Void)?
    var onInitializeWorkspace: (() -> Void)?

    /// The last task checked off here, for Undo and ⌘Z.
    private(set) var undoableTask: WorkspaceIndexedTask?
    private var graceGenerations: [String: Int] = [:]
    private var bannerGeneration = 0

    static let gracePeriod: Duration = .seconds(2)
    static let bannerDuration: Duration = .seconds(5)

    init() {
        let today = JournalDay(date: Date())
        year = today.year
        month = today.month
        focusedDay = today
        filter = Self.loadFilter()
    }

    var input: TaskCalendarModel.Input {
        TaskCalendarModel.Input(tasks: tasks, filter: filter, overrides: overrides, keepsVisible: keepsVisible)
    }

    // MARK: - Days

    func select(_ day: JournalDay) {
        selectedDay = day == today ? nil : day
        focusedDay = day
    }

    func showToday() {
        selectedDay = nil
        year = today.year
        month = today.month
        focusedDay = today
    }

    func dayDidChange() {
        let now = JournalDay(date: Date())
        guard now != today else { return }
        let showedToday = selectedDay == nil
        today = now
        if showedToday { showToday() }
    }

    // MARK: - Tasks

    func apply(_ tasks: [WorkspaceIndexedTask]) {
        self.tasks = tasks
        let byID = Dictionary(tasks.map { ($0.id, $0.task.checked) }, uniquingKeysWith: { first, _ in first })
        // The index has caught up, or the task is gone.
        for (id, checked) in overrides where byID[id] == nil || byID[id] == checked {
            overrides[id] = nil
        }
    }

    func toggle(_ row: TaskRow) {
        setChecked(!row.checked, for: row.task)
    }

    func undo() {
        guard let task = undoableTask else { return }
        undoableTask = nil
        banner = nil
        setChecked(false, for: task)
    }

    func setChecked(_ checked: Bool, for task: WorkspaceIndexedTask) {
        let id = task.id
        overrides[id] = checked
        errors[id] = nil
        if checked {
            keepVisible(id)
            undoableTask = task
            showBanner(for: task)
        } else if undoableTask?.id == id {
            undoableTask = nil
            banner = nil
        }
        guard let onSetTaskChecked else {
            fail(id, NSLocalizedString("Tasks can’t be changed here.", comment: "Tasks sidebar error"))
            return
        }
        onSetTaskChecked(task, checked) { [weak self] error in
            guard let self else { return }
            if let error {
                self.fail(id, error)
                if self.undoableTask?.id == id {
                    self.undoableTask = nil
                    self.banner = nil
                }
                return
            }
            // A write the index never confirms must not pin the row forever.
            Task { [weak self] in
                try? await Task.sleep(for: Self.bannerDuration)
                if self?.overrides[id] == checked { self?.overrides[id] = nil }
            }
        }
    }

    /// The circle springs back and the row says why, kept visible while it does.
    private func fail(_ id: String, _ message: String) {
        overrides[id] = nil
        errors[id] = message
        keepVisible(id, for: Self.bannerDuration)
    }

    private func keepVisible(_ id: String, for duration: Duration = gracePeriod) {
        let generation = (graceGenerations[id] ?? 0) + 1
        graceGenerations[id] = generation
        keepsVisible.insert(id)
        Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard let self, self.graceGenerations[id] == generation else { return }
            self.keepsVisible.remove(id)
            self.errors[id] = nil
        }
    }

    private func showBanner(for task: WorkspaceIndexedTask) {
        bannerGeneration += 1
        let generation = bannerGeneration
        banner = task
        Task { [weak self] in
            try? await Task.sleep(for: Self.bannerDuration)
            guard let self, self.bannerGeneration == generation else { return }
            self.banner = nil
            // ⌘Z undoes only while the Undo button is on screen.
            self.undoableTask = nil
        }
    }

    func reset() {
        tasks = []
        overrides = [:]
        keepsVisible = []
        errors = [:]
        banner = nil
        undoableTask = nil
        isIndexing = false
    }

    // MARK: - Filter

    private static let filterKey = "TasksSidebar.filter"

    private static func loadFilter() -> TaskFilter {
        let stored = UserDefaults.standard.dictionary(forKey: filterKey) ?? [:]
        var filter = TaskFilter()
        filter.showsScheduled = stored["scheduled"] as? Bool ?? filter.showsScheduled
        filter.showsDue = stored["due"] as? Bool ?? filter.showsDue
        filter.showsCompleted = stored["completed"] as? Bool ?? filter.showsCompleted
        filter.showsOverdue = stored["overdue"] as? Bool ?? filter.showsOverdue
        return filter
    }

    private static func saveFilter(_ filter: TaskFilter) {
        UserDefaults.standard.set([
            "scheduled": filter.showsScheduled, "due": filter.showsDue,
            "completed": filter.showsCompleted, "overdue": filter.showsOverdue,
        ], forKey: filterKey)
    }
}

final class TaskCalendarViewController: NSViewController {
    let store = TaskCalendarStore()

    var onOpenTask: ((WorkspaceIndexedTask, Bool) -> Void)? {
        get { store.onOpenTask }
        set { store.onOpenTask = newValue }
    }
    var onRevealTask: ((WorkspaceIndexedTask) -> Void)? {
        get { store.onRevealTask }
        set { store.onRevealTask = newValue }
    }
    /// Completion gets nil on success, or the reason to show under the row.
    var onSetTaskChecked: ((WorkspaceIndexedTask, Bool, @escaping (String?) -> Void) -> Void)? {
        get { store.onSetTaskChecked }
        set { store.onSetTaskChecked = newValue }
    }
    var onInitializeWorkspace: (() -> Void)? {
        get { store.onInitializeWorkspace }
        set { store.onInitializeWorkspace = newValue }
    }
    var canInitializeWorkspace: Bool {
        get { store.canInitializeWorkspace }
        set { store.canInitializeWorkspace = newValue }
    }

    private var index: WorkspaceMetadataIndex?
    private var isPaneVisible = false
    /// Bumped on every bind and visibility change, so a stream or fetch
    /// from an earlier one is ignored.
    private var generation = 0
    private var observationTasks: [Task<Void, Never>] = []
    private var fetchTask: Task<Void, Never>?
    private var fetchSequence = 0
    private var appliedFetch = 0
    private var dayObserver: NSObjectProtocol?

    override func loadView() {
        let pane = TaskPaneView()
        pane.store = store
        let host = NSHostingView(rootView: TaskCalendarView(store: store))
        host.translatesAutoresizingMaskIntoConstraints = false
        pane.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
            host.topAnchor.constraint(equalTo: pane.topAnchor),
            host.bottomAnchor.constraint(equalTo: pane.bottomAnchor),
        ])
        view = pane
        dayObserver = NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.store.dayDidChange() }
        }
    }

    isolated deinit {
        observationTasks.forEach { $0.cancel() }
        fetchTask?.cancel()
        if let dayObserver { NotificationCenter.default.removeObserver(dayObserver) }
    }

    /// The workspace index of the window, or nil outside a workspace.
    func bind(index: WorkspaceMetadataIndex?) {
        guard index !== self.index else { return }
        self.index = index
        store.reset()
        store.isWorkspace = index != nil
        restartObservation()
    }

    func setPaneVisible(_ visible: Bool) {
        guard visible != isPaneVisible else { return }
        isPaneVisible = visible
        if visible { store.dayDidChange() }
        restartObservation()
    }

    private func restartObservation() {
        generation += 1
        observationTasks.forEach { $0.cancel() }
        observationTasks = []
        fetchTask?.cancel()
        fetchTask = nil
        guard isPaneVisible, let index else { return }
        let generation = generation
        observationTasks.append(Task { [weak self] in
            for await _ in await index.taskChanges() {
                guard let self, self.generation == generation else { return }
                self.scheduleFetch(from: index, generation: generation)
            }
        })
        observationTasks.append(Task { [weak self] in
            for await snapshot in await index.snapshots() {
                guard let self, self.generation == generation else { return }
                self.store.isIndexing = !snapshot.isComplete
            }
        })
    }

    /// Coalesces a burst of revisions, as during a scan, into one fetch.
    private func scheduleFetch(from index: WorkspaceMetadataIndex, generation: Int) {
        guard fetchTask == nil else { return }
        fetchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard let self, self.generation == generation, !Task.isCancelled else { return }
            // Cleared before reading, so a revision from here on fetches again.
            self.fetchTask = nil
            self.fetchSequence += 1
            let sequence = self.fetchSequence
            let tasks = await index.tasks()
            guard self.generation == generation, sequence > self.appliedFetch else { return }
            self.appliedFetch = sequence
            self.store.apply(tasks)
        }
    }
}

/// Handles ⌘T (back to today) and ⌘Z (undo the last check-off) while focus
/// is inside the pane, before the menu bar sees them.
private final class TaskPaneView: NSView {
    weak var store: TaskCalendarStore?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let store, let responder = window?.firstResponder as? NSView,
              responder.isDescendant(of: self),
              event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers {
        case "t":
            store.showToday()
            return true
        case "z" where store.undoableTask != nil:
            store.undo()
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}
