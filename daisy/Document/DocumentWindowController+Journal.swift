//
//  DocumentWindowController+Journal.swift
//  daisy
//
//  The workspace journal in a window: the toolbar's Journal calendar, the
//  Go menu's Today's Journal, Previous Entry and Next Entry, and Insert ▸
//  Unfinished Tasks from Earlier Days (also the slash menu's `/carryover`).
//  Each works only in a workspace window, and only while the Journal
//  extension is on (`JournalSetting`); entries live in `journals/` (see `WorkspaceJournal`).
//

import Cocoa
import SwiftUI

extension DocumentWindowController {
    /// The entry this window is showing, if it is one.
    var currentJournalDay: JournalDay? {
        guard let root = indexedWorkspaceRootURL, let url = currentFileURL else { return nil }
        return WorkspaceJournal.day(of: url, root: root)
    }

    @objc func openTodayJournal(_ sender: Any?) {
        openJournal(JournalDay(date: Date()))
    }

    @objc func openPreviousJournalEntry(_ sender: Any?) {
        openAdjacentJournalEntry(.previous)
    }

    @objc func openNextJournalEntry(_ sender: Any?) {
        openAdjacentJournalEntry(.next)
    }

    /// The workspace journal entries go to, while the extension is on.
    private var journalRootURL: URL? {
        JournalSetting.isEnabled ? indexedWorkspaceRootURL : nil
    }

    /// Opens `day`'s entry the way a clicked Markdown link opens, creating it
    /// first when it has none from the chosen template, if there is one. A
    /// new entry for today takes the earlier days' unfinished tasks while
    /// carry-over is on.
    func openJournal(_ day: JournalDay) {
        guard let root = journalRootURL else {
            NSSound.beep()
            return
        }
        do {
            let isNew = (try WorkspaceJournal.resolve(day: day, root: root)) == nil
            let carryOver = isNew ? journalCarryOverPlan(for: day, root: root) : nil
            let entry = try WorkspaceJournal.openOrCreateReportingCreation(
                day: day, root: root,
                contents: isNew ? newJournalContents(for: day, carryOver: carryOver?.tasks ?? "") : nil)
            // Only once the tasks are in the new entry do they leave the old
            // ones; an entry another writer made first never took them.
            let unchanged = entry.created ? carryOver.map { JournalCarryOver.apply($0, root: root) } ?? [] : []
            openMarkdownLink(entry.url)
            if !unchanged.isEmpty { reportUnremovedCarryOver(from: unchanged) }
        } catch {
            NSAlert(error: error).beginSheetModal(for: documentWindow)
        }
    }

    /// Read only when the entry is about to be created, so edits to the
    /// template file count straight away. The weekday is in the app's
    /// language, as the slash menu writes it.
    private func newJournalContents(for day: JournalDay, carryOver: String) -> String {
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        let template = JournalTemplate.template(named: JournalSetting.templateName, in: TemplateStore.load())
        return JournalTemplate.contents(for: day, template: template, carryOver: carryOver,
                                        locale: Locale(identifier: language))
    }

    /// Today only, so tasks never move back in time.
    private func journalCarryOverPlan(for day: JournalDay, root: URL) -> JournalCarryOver.Plan? {
        guard JournalSetting.carryOverEnabled, day == JournalDay(date: Date()) else { return nil }
        return carryOverPlan(into: day, root: root)
    }

    /// An entry open with unsaved edits in any window keeps its tasks:
    /// rewriting it would set the file against the editor.
    private func carryOverPlan(into day: JournalDay, root: URL) -> JournalCarryOver.Plan? {
        let edited = Set(Self.allControllers.filter(\.hasPendingEditorChanges)
            .compactMap { $0.currentFileURL.map(Self.journalPath) })
        return JournalCarryOver.plan(for: day, lookBack: JournalSetting.carryOverDays, root: root) {
            edited.contains(Self.journalPath($0))
        }
    }

    /// Insert ▸ Unfinished Tasks from Earlier Days: in Edit Mode on today's
    /// entry, whether or not carry-over is on for new entries.
    var canInsertCarriedOverTasks: Bool {
        canFormatMarkdown && canCarryOverTasks
    }

    /// Whether the slash menu offers `/carryover`: today's entry, while the
    /// Journal extension is on. Decided when Edit Mode starts.
    var canCarryOverTasks: Bool {
        journalRootURL != nil && currentJournalDay == JournalDay(date: Date())
    }

    /// Moves the earlier days' unfinished tasks to the caret, on lines of
    /// their own. The entry is saved with them before they leave the old
    /// entries, so a failed save leaves them in both.
    func insertCarriedOverTasksFromMenu() {
        guard canInsertCarriedOverTasks, let root = journalRootURL, let day = currentJournalDay,
              let editor = mainSplit?.editorViewController else {
            NSSound.beep()
            return
        }
        guard let plan = carryOverPlan(into: day, root: root) else {
            NSSound.beep()
            return
        }
        editor.fetchLineInsertionPoint { [weak self] point in
            guard let self, let point else { return }
            var text = point.atLineStart ? plan.tasks : "\n" + plan.tasks
            if point.atLineEnd { text.removeLast() }
            editor.insertMarkdown(text, from: point.from, to: point.to) { [weak self] inserted in
                guard let self, inserted else { return }
                self.hasUnsavedEditorChanges = true
                self.commitEdits(exitAfter: false) { [weak self] saved in
                    guard let self, saved else { return }
                    let unchanged = JournalCarryOver.apply(plan, root: root)
                    if !unchanged.isEmpty { self.reportUnremovedCarryOver(from: unchanged) }
                }
            }
        }
    }

    private static func journalPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private func reportUnremovedCarryOver(from days: [JournalDay]) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Some unfinished tasks are in two entries",
                                              comment: "Journal carry-over alert title")
        alert.informativeText = String(
            format: NSLocalizedString(
                "They were copied to today’s entry but couldn’t be removed from %@, which changed or couldn’t be written.",
                comment: "Journal carry-over alert; %@ lists days"),
            ListFormatter.localizedString(byJoining: days.map(\.string)))
        alert.beginSheetModal(for: documentWindow)
    }

    private func openAdjacentJournalEntry(_ direction: WorkspaceJournal.Direction) {
        guard let root = journalRootURL, let day = currentJournalDay,
              let target = WorkspaceJournal.adjacentDay(to: day, direction, root: root) else {
            NSSound.beep()
            return
        }
        openJournal(target)
    }

    func validateJournalMenuItem(_ menuItem: NSMenuItem) -> Bool? {
        switch menuItem.action {
        case #selector(openTodayJournal(_:)):
            return journalRootURL != nil
        case #selector(openPreviousJournalEntry(_:)):
            return adjacentJournalDay(.previous) != nil
        case #selector(openNextJournalEntry(_:)):
            return adjacentJournalDay(.next) != nil
        default:
            return nil
        }
    }

    private func adjacentJournalDay(_ direction: WorkspaceJournal.Direction) -> JournalDay? {
        guard let root = journalRootURL, let day = currentJournalDay else { return nil }
        return WorkspaceJournal.adjacentDay(to: day, direction, root: root)
    }

    // MARK: - Toolbar

    func makeJournalCalendarItem(willBeInsertedIntoToolbar: Bool) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: .journalCalendar)
        let label = NSLocalizedString("Journal", comment: "Journal toolbar item label")
        let image = NSImage(systemSymbolName: "calendar", accessibilityDescription: label) ?? NSImage()
        let button = NSButton(image: image, target: self, action: #selector(showJournalCalendar(_:)))
        button.setButtonType(.momentaryPushIn)
        button.isBordered = true
        item.view = button
        item.label = label
        item.paletteLabel = label
        // Enabled by workspace state, not by validation.
        item.autovalidates = false
        if willBeInsertedIntoToolbar {
            journalCalendarButton = button
        }
        refreshJournalToolbarItem(item: item, button: button)
        return item
    }

    /// After the Journal extension was turned on or off.
    func applyJournalEnabledSetting() {
        refreshJournalToolbarItem()
        addJournalToolbarItemIfNeeded()
    }

    /// Hidden while the extension is off; otherwise enabled only in a
    /// workspace window, with a tooltip that says why not.
    func refreshJournalToolbarItem() {
        guard let button = journalCalendarButton,
              let item = documentWindow.toolbar?.items.first(where: { $0.itemIdentifier == .journalCalendar })
        else { return }
        refreshJournalToolbarItem(item: item, button: button)
    }

    private func refreshJournalToolbarItem(item: NSToolbarItem, button: NSButton) {
        item.isHidden = !JournalSetting.isEnabled
        let enabled = journalRootURL != nil
        button.isEnabled = enabled
        item.isEnabled = enabled
        item.toolTip = enabled
            ? NSLocalizedString("Open a day’s journal", comment: "Journal toolbar item tooltip")
            : NSLocalizedString("The journal is available in a workspace. Choose File ▸ Initialize Workspace.",
                                comment: "Journal toolbar item tooltip outside a workspace")
        button.toolTip = item.toolTip
        if !enabled { journalCalendarPopover?.close() }
    }

    @objc private func showJournalCalendar(_ sender: NSButton) {
        if let popover = journalCalendarPopover, popover.isShown {
            popover.close()
            return
        }
        guard let root = journalRootURL else {
            NSSound.beep()
            return
        }
        let host = NSHostingController(rootView: JournalCalendarView(
            today: JournalDay(date: Date()),
            current: currentJournalDay,
            entries: WorkspaceJournal.entryDays(root: root),
            open: { [weak self] day in
                self?.journalCalendarPopover?.close()
                self?.openJournal(day)
            }
        ))
        host.sizingOptions = .preferredContentSize
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = host
        popover.delegate = self
        journalCalendarPopover = popover
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
        journalCalendarEscapeMonitor.start { [weak self] in
            guard let popover = self?.journalCalendarPopover, popover.isShown else { return false }
            popover.close()
            return true
        }
    }

    /// The Journal calendar's share of `popoverDidClose`.
    func journalCalendarPopoverDidClose() {
        journalCalendarEscapeMonitor.stop()
        journalCalendarPopover = nil
    }

    /// One-time addition of the Journal calendar, the first time a workspace
    /// window has a toolbar while the extension is on: before Tasks or Share,
    /// or at the end. The item
    /// order is shared, so later windows inherit it, and a reader who takes
    /// it out in Customize Toolbar keeps it out.
    private static let didAddJournalItemKey = "Toolbar.DidAddJournalCalendar"

    func addJournalToolbarItemIfNeeded() {
        guard journalRootURL != nil else { return }
        insertToolbarItemOnce(.journalCalendar, key: Self.didAddJournalItemKey) { identifiers in
            identifiers.firstIndex(of: .tasks) ?? identifiers.firstIndex(of: .share) ?? identifiers.count
        }
    }
}
