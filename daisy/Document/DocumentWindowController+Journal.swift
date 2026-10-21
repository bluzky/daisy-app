//
//  DocumentWindowController+Journal.swift
//  daisy
//
//  The workspace journal in a window: the toolbar's Journal calendar and the
//  Go menu's Today's Journal, Previous Entry and Next Entry. Each works only
//  in a workspace window, and only while the Journal extension is on
//  (`JournalSetting`); entries live in `journals/` (see `WorkspaceJournal`).
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
    /// first when it has none from the chosen template, if there is one.
    func openJournal(_ day: JournalDay) {
        guard let root = journalRootURL else {
            NSSound.beep()
            return
        }
        do {
            let entry = try WorkspaceJournal.openOrCreate(day: day, root: root,
                                                          contents: newJournalContents(for: day))
            openMarkdownLink(entry)
        } catch {
            NSAlert(error: error).beginSheetModal(for: documentWindow)
        }
    }

    /// Read only when the entry is about to be created, so edits to the
    /// template file count straight away. The weekday is in the app's
    /// language, as the slash menu writes it.
    private func newJournalContents(for day: JournalDay) -> String? {
        guard let root = journalRootURL,
              (try? WorkspaceJournal.resolve(day: day, root: root)) == nil else { return nil }
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        let template = JournalTemplate.template(named: JournalSetting.templateName, in: TemplateStore.load())
        return JournalTemplate.contents(for: day, template: template, locale: Locale(identifier: language))
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
    /// window has a toolbar while the extension is on: before the Inspector,
    /// or at the end. The item
    /// order is shared, so later windows inherit it, and a reader who takes
    /// it out in Customize Toolbar keeps it out.
    private static let didAddJournalItemKey = "Toolbar.DidAddJournalCalendar"

    func addJournalToolbarItemIfNeeded() {
        guard journalRootURL != nil, let toolbar = documentWindow.toolbar,
              toolbarItemOrderPersistenceReady else { return }
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.didAddJournalItemKey) else { return }
        defaults.set(true, forKey: Self.didAddJournalItemKey)
        let identifiers = toolbar.items.map(\.itemIdentifier)
        guard !identifiers.contains(.journalCalendar) else { return }
        let index = identifiers.firstIndex(of: .inspector)
            ?? identifiers.firstIndex(of: .share)
            ?? identifiers.count
        toolbar.insertItem(withItemIdentifier: .journalCalendar, at: index)
    }
}
