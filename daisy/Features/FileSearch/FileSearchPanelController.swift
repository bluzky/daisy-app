//
//  FileSearchPanelController.swift
//  daisy
//
//  The OmniSearch palette: type part of a file name, a phrase from a file or a
//  menu command, pick a result, act on it. Each document presents its own
//  floating panel so the results combine app-wide recents with files from that
//  document’s project root.
//

import Cocoa

@MainActor
final class FileSearchPanelController: NSViewController {

    enum OpenTarget {
        case currentTab
        case newTab
        case newWindow
    }

    /// Called with the chosen file once the panel has gone. The controller
    /// dismisses itself first — see `activateSelection`.
    var onOpen: ((URL, OpenTarget) -> Void)?
    /// Called with a project-relative path when the reader chose "Create".
    /// The controller dismisses itself first, as for `onOpen`.
    var onCreateFile: ((String) -> Void)?
    /// Called when the reader asks for a folder from the empty state.
    var onRequestOpenFolder: (() -> Void)?

    var onDismiss: (() -> Void)?
    private var presentation: FileSearchPanelPresentation?

    static func isKeymapPanel(_ window: NSWindow) -> Bool {
        window is FileSearchPanel
    }

    func present(relativeTo parent: NSWindow?) {
        let presentation = FileSearchPanelPresentation()
        self.presentation = presentation
        presentation.present(self, relativeTo: parent)
    }

    fileprivate func closePalette() {
        guard let presentation else { return }
        self.presentation = nil
        debounce?.cancel()
        debounce = nil
        rankTask?.cancel()
        rankTask = nil
        contentTask?.cancel()
        contentTask = nil
        pendingActivation = nil
        presentation.close()
        onDismiss?()
    }

    private let projectRoot: URL?
    private let index: ProjectFileIndex
    private let commandCatalog: OmniSearchCommandCatalog?

    private let queryField = PlainQueryField()
    private let fieldSeparator = HairlineSeparator()
    private let resultsContainer = NSView()
    private var resultsHeightConstraint: NSLayoutConstraint?
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let openFolderButton = NSButton()
    private let footer = KeyHintFooter()
    /// Height of the key-hint strip under the results.
    private static let footerHeight: CGFloat = 30

    private var hasSearchQuery: Bool {
        !queryField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var snapshot: ProjectFileIndex.Snapshot?
    private var recentURLs: [URL] = []
    /// What `results` is made of: the ranked files and commands, which land
    /// all at once, followed by the contents section, which streams in.
    private var results: [FileSearchResults.Row] = []
    private var baseRows: [FileSearchResults.Row] = []
    private var contentHits: [ProjectContentSearcher.Hit] = []
    private var contentSearching = false
    /// False until the panel has taken its first size, which must not animate.
    private var hasSizedPanel = false
    private var contentTask: Task<Void, Never>?
    /// The field text `results` were ranked for. Nil until the first ranking
    /// lands. When it differs from the field, what is on screen belongs to
    /// an earlier query.
    private var rankedQuery: String?
    private var debounce: DispatchWorkItem?
    private var rankTask: Task<Void, Never>?
    /// A Return pressed while the list was still catching up with the field.
    /// Honoured once the ranking for the current text lands, so the file
    /// opened is the one the reader was about to see at the top.
    private var pendingActivation: OpenTarget?

    init(projectRoot: URL?, index: ProjectFileIndex = .shared,
         commands: OmniSearchCommandCatalog? = nil) {
        self.projectRoot = projectRoot
        self.index = index
        self.commandCatalog = commands
        super.init(nibName: nil, bundle: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(recentDocumentsDidClear),
                                               name: MarkdownDocumentController.recentDocumentsDidClear,
                                               object: nil)
    }

    @objc private func recentDocumentsDidClear() {
        recentURLs = []
        pendingActivation = nil
        guard presentation != nil, isViewLoaded else { return }
        // Remove cleared history immediately, including during a pending rank.
        results = []
        baseRows = []
        tableView.reloadData()
        refreshResults()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    override func loadView() {
        // Sized by frame rather than by self-constraints: AppKit owns a view
        // controller's root view frame, and the panel takes its size from it.
        let root = KeyEquivalentView(frame: NSRect(x: 0, y: 0, width: 480,
                                                   height: projectRoot == nil ? 52 + 108 + Self.footerHeight : 52))
        // Clip the backing surface as well as the glass so no rectangular
        // backdrop is visible outside the rounded panel corners.
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.clear.cgColor
        root.layer?.cornerRadius = 20
        root.layer?.masksToBounds = true
        root.onKey = { [weak self] event in self?.handleNavigationKey(event) ?? false }
        let container = DraggablePaletteContent(frame: root.bounds)
        container.autoresizingMask = [.width, .height]
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: root.bounds)
            glass.autoresizingMask = [.width, .height]
            glass.style = .regular
            glass.cornerRadius = 20
            glass.contentView = container
            root.addSubview(glass)
        } else {
            let effect = NSVisualEffectView(frame: root.bounds)
            effect.autoresizingMask = [.width, .height]
            effect.material = .popover
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = 20
            effect.layer?.masksToBounds = true
            effect.addSubview(container)
            root.addSubview(effect)
        }
        view = root

        let searchIcon = NSImageView()
        searchIcon.translatesAutoresizingMaskIntoConstraints = false
        searchIcon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        searchIcon.symbolConfiguration = .init(pointSize: 19, weight: .regular)
        searchIcon.contentTintColor = .secondaryLabelColor

        // A large, unbezelled field with a hairline under it, the way Xcode's
        // Open Quickly presents it: in a palette the field is the whole point,
        // so it reads as the subject rather than as one control among several.
        queryField.translatesAutoresizingMaskIntoConstraints = false
        queryField.placeholderString = NSLocalizedString("Search files and commands",
                                                         comment: "OmniSearch field placeholder")
        queryField.delegate = self
        queryField.font = .systemFont(ofSize: 20)
        queryField.isBordered = false
        queryField.drawsBackground = false
        queryField.lineBreakMode = .byTruncatingTail

        fieldSeparator.translatesAutoresizingMaskIntoConstraints = false

        tableView.backgroundColor = .clear
        tableView.headerView = nil
        tableView.style = .fullWidth
        tableView.rowHeight = 40
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(rowDoubleClicked)
        // Focus belongs in the field; the arrow keys drive this from there,
        // the way both existing outline views do it.
        tableView.refusesFirstResponder = true
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .preferredFont(forTextStyle: .subheadline)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center
        statusLabel.isHidden = true

        openFolderButton.translatesAutoresizingMaskIntoConstraints = false
        openFolderButton.bezelStyle = .rounded
        openFolderButton.title = NSLocalizedString("Open Folder…", comment: "OmniSearch empty state button")
        openFolderButton.target = self
        openFolderButton.action = #selector(openFolderTapped)
        openFolderButton.isHidden = true

        resultsContainer.translatesAutoresizingMaskIntoConstraints = false
        resultsContainer.isHidden = projectRoot != nil
        fieldSeparator.isHidden = projectRoot != nil
        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.isHidden = projectRoot != nil
        footer.update(hints: footerHints())
        for subview in [searchIcon, queryField, fieldSeparator, resultsContainer, footer] {
            container.addSubview(subview)
        }
        for subview in [scrollView, statusLabel, openFolderButton] {
            resultsContainer.addSubview(subview)
        }

        let resultsHeight = resultsContainer.heightAnchor.constraint(equalToConstant: 108)
        resultsHeightConstraint = resultsHeight
        NSLayoutConstraint.activate([
            resultsHeight,
            // Center the field in the 52-point search row, including when
            // results expand the panel below it.
            queryField.centerYAnchor.constraint(equalTo: container.topAnchor, constant: 26),
            searchIcon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            searchIcon.centerYAnchor.constraint(equalTo: queryField.centerYAnchor),
            searchIcon.widthAnchor.constraint(equalToConstant: 22),
            searchIcon.heightAnchor.constraint(equalToConstant: 22),
            queryField.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 10),
            queryField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -18),

            fieldSeparator.topAnchor.constraint(equalTo: container.topAnchor, constant: 51),
            fieldSeparator.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            fieldSeparator.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            fieldSeparator.heightAnchor.constraint(equalToConstant: 1),

            resultsContainer.topAnchor.constraint(equalTo: fieldSeparator.bottomAnchor),
            resultsContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            resultsContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            footer.topAnchor.constraint(equalTo: resultsContainer.bottomAnchor),
            footer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            footer.heightAnchor.constraint(equalToConstant: Self.footerHeight),

            scrollView.topAnchor.constraint(equalTo: resultsContainer.topAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: resultsContainer.bottomAnchor, constant: -8),

            statusLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24),

            openFolderButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12),
            openFolderButton.centerXAnchor.constraint(equalTo: statusLabel.centerXAnchor)
        ])
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        (view.window as? FileSearchPanel)?.queryField = queryField
        view.window?.makeFirstResponder(queryField)
        recentURLs = NSDocumentController.shared.recentDocumentURLs.filter {
            $0.isFileURL && (ProjectFileIndex.markdownExtensions.contains($0.pathExtension.lowercased())
                            || $0.pathExtension.lowercased() == "txt")
        }
        refreshResults()
        loadIndex()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        debounce?.cancel()
        debounce = nil
        rankTask?.cancel()
        rankTask = nil
        contentTask?.cancel()
        contentTask = nil
        pendingActivation = nil
    }

    /// Keep the field in the same screen position when results change.
    private func updatePanelSize() {
        resultsContainer.isHidden = false
        fieldSeparator.isHidden = false
        footer.isHidden = false
        guard let panel = view.window else { return }
        let resultsHeight: CGFloat = results.isEmpty ? 108 : results.prefix(8).reduce(12) {
            $0 + ($1.isSelectable ? 40 : 24) + tableView.intercellSpacing.height
        }
        resultsHeightConstraint?.constant = resultsHeight
        let height: CGFloat = 52 + resultsHeight + Self.footerHeight
        var frame = panel.frame
        frame.origin.y += frame.height - height
        frame.size.height = height
        if let screen = panel.screen {
            frame.origin.y = max(frame.origin.y, screen.visibleFrame.minY + 16)
        }
        guard frame != panel.frame else { return }
        // An animated resize blocks the main thread for its whole duration, so
        // the first one — the panel taking its opening height — would hold the
        // panel off screen for that long after Cmd+K. Only later changes, with
        // the panel already up, animate.
        let animate = hasSizedPanel && panel.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        defer { hasSizedPanel = true }
        let searchPanel = panel as? FileSearchPanel
        searchPanel?.isResizingForResults = true
        defer { searchPanel?.isResizingForResults = false }
        panel.setFrame(frame, display: true, animate: animate)
        panel.invalidateShadow()
    }

    // MARK: - Index

    private func loadIndex() {
        guard let projectRoot else { return }
        Task { [weak self, index] in
            let snapshot = await index.snapshot(for: projectRoot)
            guard let self, self.presentation != nil else { return }
            self.snapshot = snapshot
            self.refreshResults()
        }
    }

    /// Re-ranks on a short delay. The constant is the toolbar find field's, so
    /// the two search surfaces feel the same under the fingers.
    private func scheduleRefresh() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refreshResults() }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + DocumentWindowController.findDebounceDelay,
                                      execute: work)
    }

    /// Ranks the current field text off the main actor. A full pass over a
    /// large project costs tens of milliseconds, which would stall typing if
    /// it ran here; a newer query cancels the pass in flight instead of
    /// queueing behind it.
    private func refreshResults() {
        debounce?.cancel()
        debounce = nil
        let query = queryField.stringValue
        let snapshot = snapshot
        let recentURLs = recentURLs
        let commands = commandCatalog?.candidates ?? []
        rankTask?.cancel()
        if !hasSearchQuery {
            apply((try? FileSearchResults.rows(query: query, recentURLs: recentURLs, snapshot: nil,
                                               commands: commands)) ?? [], for: query)
            return
        }
        rankTask = Task { [weak self] in
            guard let ranked = try? await Self.rank(query: query, recentURLs: recentURLs,
                                                    snapshot: snapshot, commands: commands),
                  let self, !Task.isCancelled else { return }
            self.apply(ranked, for: query)
        }
    }

    @concurrent
    private nonisolated static func rank(query: String,
                                         recentURLs: [URL], snapshot: ProjectFileIndex.Snapshot?,
                                         commands: [FileSearchResults.CommandCandidate]) async throws -> [FileSearchResults.Row] {
        try FileSearchResults.rows(query: query, recentURLs: recentURLs, snapshot: snapshot, commands: commands)
    }

    private func apply(_ ranked: [FileSearchResults.Row], for query: String) {
        // Superseded while the pass was finishing: the field has moved on and
        // a newer ranking is already on its way.
        guard presentation != nil, query == queryField.stringValue else { return }
        results = ranked
        baseRows = ranked
        rankedQuery = query
        rankTask = nil
        tableView.reloadData()
        scrollView.isHidden = results.isEmpty
        if !results.isEmpty {
            selectRow(results.firstIndex { $0.isSelectable } ?? 0)
        }
        updateStatus()
        updatePanelSize()
        startContentSearch(for: query)
        if let target = pendingActivation, resultsAreCurrent {
            pendingActivation = nil
            activateSelection(target: target)
        }
    }

    // MARK: - Footer

    /// The keys the palette answers to, read from the keymap so a rebound key
    /// shows the key that now works. A command with no binding is left out.
    private func footerHints() -> [KeyHintFooter.Hint] {
        let keymap = KeymapStore.shared.keymap
        func keys(_ command: KeymapCommand) -> String? {
            keymap.bindings(for: command).first?.displayString
        }
        var hints: [KeyHintFooter.Hint] = []
        let labelled: [(KeymapCommand, String)] = [
            (.searchOpenResult, NSLocalizedString("open", comment: "OmniSearch key hint")),
            (.searchOpenResultInNewTab, NSLocalizedString("open in new tab", comment: "OmniSearch key hint")),
            (.searchOpenResultInNewWindow, NSLocalizedString("open in new window", comment: "OmniSearch key hint"))
        ]
        for (command, label) in labelled {
            if let keys = keys(command) { hints.append(.init(keys: keys, label: label)) }
        }
        return hints
    }

    // MARK: - Contents

    /// Scans file contents for what was typed and streams the best hits into
    /// a section below the ranked rows. The rows above never wait on it.
    private func startContentSearch(for query: String) {
        contentTask?.cancel()
        contentTask = nil
        let hadContent = !contentHits.isEmpty || contentSearching
        contentHits = []
        contentSearching = false
        guard let snapshot, FileSearchResults.commandQuery(query) == nil,
              ProjectContentSearcher.isSearchable(query) else {
            if hadContent { refreshContentSection() }
            return
        }
        contentSearching = true
        refreshContentSection()
        // Files already listed for their names are not listed again for their text.
        let skipping = Set(baseRows.compactMap { $0.entry?.url.standardizedFileURL })
        // A weak reference taken once, outside the closure the scan calls from
        // off the main actor.
        let receiver = WeakReceiver(self)
        contentTask = Task {
            try? await ProjectContentSearcher.scan(query: query, snapshot: snapshot, skipping: skipping) {
                hits, done in
                await receiver.panel?.receiveContent(hits, done: done, for: query)
            }
        }
    }

    private func receiveContent(_ hits: [ProjectContentSearcher.Hit], done: Bool, for query: String) {
        guard presentation != nil, rankedQuery == query else { return }
        contentHits = hits
        contentSearching = !done
        if done { contentTask = nil }
        refreshContentSection()
    }

    private func contentRows() -> [FileSearchResults.Row] {
        guard !contentHits.isEmpty || contentSearching else { return [] }
        return [.contentHeading] + (contentHits.isEmpty ? [.searching] : contentHits.map { .content($0) })
    }

    /// Rebuilds the list under the selection: the ranked rows above do not move,
    /// so a row the reader has arrowed to stays put while hits arrive below.
    private func refreshContentSection() {
        let previous = tableView.selectedRow
        results = baseRows + contentRows()
        tableView.reloadData()
        scrollView.isHidden = results.isEmpty
        if results.indices.contains(previous), results[previous].isSelectable {
            tableView.selectRowIndexes([previous], byExtendingSelection: false)
        } else if let first = results.firstIndex(where: { $0.isSelectable }) {
            selectRow(first)
        }
        updateStatus()
        updatePanelSize()
    }

    /// True when the rows on screen were ranked for exactly what is in the
    /// field, with nothing newer scheduled or in flight.
    private var resultsAreCurrent: Bool {
        rankedQuery == queryField.stringValue && debounce == nil && rankTask == nil
            && !(hasSearchQuery && results.isEmpty && projectRoot != nil && snapshot == nil)
    }

    private func updateStatus() {
        openFolderButton.isHidden = true
        if results.isEmpty {
            statusLabel.stringValue = hasSearchQuery
                ? NSLocalizedString("No results", comment: "OmniSearch no results")
                : NSLocalizedString("No recent files", comment: "OmniSearch empty history")
            openFolderButton.isHidden = projectRoot != nil
            statusLabel.isHidden = false
            return
        }
        if hasSearchQuery && snapshot?.isTruncated == true {
            statusLabel.stringValue = String(
                format: NSLocalizedString("Showing the first %d files in this project",
                                          comment: "OmniSearch truncated index"),
                snapshot?.candidates.count ?? 0
            )
            statusLabel.isHidden = false
            return
        }
        statusLabel.isHidden = true
    }

    // MARK: - Selection

    /// How far a page key moves. Read from the table rather than assumed, so
    /// it stays right when the panel is resized or the row height changes.
    private var visibleRowCount: Int {
        max(1, tableView.rows(in: tableView.visibleRect).length - 1)
    }

    private func selectRow(_ row: Int) {
        guard !results.isEmpty else { return }
        let firstFile = results.firstIndex { $0.isSelectable } ?? 0
        let clamped = min(max(row, firstFile), results.count - 1)
        let direction = clamped < tableView.selectedRow ? -1 : 1
        var target = clamped
        while results.indices.contains(target), !results[target].isSelectable { target += direction }
        guard results.indices.contains(target) else { return }
        tableView.selectRowIndexes([target], byExtendingSelection: false)
        tableView.scrollRowToVisible(target)
    }

    /// Drives the list from the raw key event.
    ///
    /// This runs from `performKeyEquivalent`, which the window offers every
    /// key-down before the first responder sees it. The delegate route below
    /// does the same job, but only while the field editor is active and
    /// forwarding; going through the window as well means navigation does not
    /// depend on that being true. Whichever runs first consumes the key, so
    /// the two cannot both act on one press.
    private func handleNavigationKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !modifiers.contains(.control) else { return false }

        if event.keyCode == Key.escape {
            closePalette()
            return true
        }
        if let binding = KeyBinding(event: event),
           let command = KeymapStore.shared.keymap.command(for: binding, in: .search) {
            return performSearchCommand(command)
        }

        // Historically modifier variants of palette navigation keys (notably
        // ⇧↓) moved selection. Keep that behavior only while bare binding
        // remains active, so clearing `down` releases it to query field.
        if let binding = KeyBinding(event: event),
           let command = KeymapStore.shared.keymap.command(
               for: KeyBinding(key: binding.key), in: .search
           ), command == .searchSelectPrevious || command == .searchSelectNext {
            return performSearchCommand(command)
        }

        switch event.keyCode {
        case Key.home: selectRow(0)
        case Key.end: selectRow(results.count - 1)
        case Key.pageUp: moveSelection(by: -visibleRowCount)
        case Key.pageDown: moveSelection(by: visibleRowCount)
        default: return false
        }
        return true
    }

    private func performSearchCommand(_ command: KeymapCommand) -> Bool {
        switch command {
        case .searchSelectPrevious: moveSelection(by: -1)
        case .searchSelectNext: moveSelection(by: 1)
        case .searchOpenResult: return activateSelection(target: .currentTab)
        case .searchOpenResultInNewTab: return activateSelection(target: .newTab)
        case .searchOpenResultInNewWindow: return activateSelection(target: .newWindow)
        default: return false
        }
        return true
    }

    private enum Key {
        static let `return`: UInt16 = 36
        static let keypadEnter: UInt16 = 76
        static let escape: UInt16 = 53
        static let pageUp: UInt16 = 116
        static let pageDown: UInt16 = 121
        static let home: UInt16 = 115
        static let end: UInt16 = 119
        static let upArrow: UInt16 = 126
        static let downArrow: UInt16 = 125
    }

    private func moveSelection(by offset: Int) {
        guard !results.isEmpty else { return }
        let next = min(max(tableView.selectedRow + offset, 0), results.count - 1)
        selectRow(next)
    }

    private var selectedResult: FileSearchResults.Row? {
        let row = tableView.selectedRow
        guard results.indices.contains(row), results[row].isSelectable else { return nil }
        return results[row]
    }

    /// The keyboard path. Return is often pressed straight after the last
    /// keystroke, before the debounced ranking for it has run; opening the
    /// highlighted row then would open the previous query's top hit. So when
    /// the list is behind the field, flush the ranking now and act on its
    /// result instead. Returns true whenever the key is consumed.
    @discardableResult
    private func activateSelection(target: OpenTarget) -> Bool {
        guard resultsAreCurrent else {
            // Before the index has loaded there is nothing to rank yet;
            // `loadIndex` ranks once it arrives and honours this then.
            pendingActivation = target
            if debounce != nil || rankTask == nil {
                refreshResults()
            }
            return true
        }
        return openSelectedRow(target: target)
    }

    /// Dismisses before handing the URL back so a Save/Don't Save sheet can
    /// receive focus if the current document has unsaved edits.
    @discardableResult
    private func openSelectedRow(target: OpenTarget) -> Bool {
        guard resultsAreCurrent, let row = selectedResult else { return false }
        activate(row, target: target)
        return true
    }

    /// What Return does depends on the row: open a file, run a command or
    /// create a file. All three dismiss first, so a Save/Don't Save sheet or a
    /// menu action finds the document window in charge of focus.
    private func activate(_ row: FileSearchResults.Row, target: OpenTarget) {
        switch row {
        case .file(let entry):
            openFile(at: entry.url, target: target)
        case .content(let hit):
            openFile(at: hit.url, target: target)
        case .command(let command):
            runCommand(command)
        case .createFile(let newFile):
            createFile(newFile)
        case .recentHeading, .filesHeading, .commandsHeading, .contentHeading, .searching:
            break
        }
    }

    private func runCommand(_ command: FileSearchResults.CommandCandidate) {
        let catalog = commandCatalog
        let parent = view.window?.parent
        closePalette()
        parent?.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { catalog?.perform(id: command.id) }
    }

    private func createFile(_ newFile: FileSearchResults.NewFile) {
        let onCreateFile = onCreateFile
        let parent = view.window?.parent
        closePalette()
        parent?.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { onCreateFile?(newFile.relativePath) }
    }

    private func openFile(at url: URL, target: OpenTarget) {
        let onOpen = onOpen
        let parent = view.window?.parent
        closePalette()
        parent?.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { onOpen?(url, target) }
    }

    /// A mouse activation targets the displayed file, even while a newer query
    /// is pending. Capture its URL before closing cancels the pending ranking.
    @objc private func rowDoubleClicked() {
        let row = tableView.clickedRow
        guard results.indices.contains(row), results[row].isSelectable else { return }
        activate(results[row], target: .currentTab)
    }

    @objc private func openFolderTapped() {
        let onRequestOpenFolder = onRequestOpenFolder
        closePalette()
        DispatchQueue.main.async { onRequestOpenFolder?() }
    }
}

// MARK: - Key handling

extension FileSearchPanelController: NSTextFieldDelegate {

    func controlTextDidChange(_ obj: Notification) {
        // A Return waiting on the old text must not fire on the new one.
        pendingActivation = nil
        debounce?.cancel()
        debounce = nil
        rankTask?.cancel()
        rankTask = nil
        contentTask?.cancel()
        contentTask = nil
        if hasSearchQuery {
            // Keep the published rows and their matching emphasis visible
            // until the new query finishes. apply replaces them together;
            // Keyboard activation waits for the current query; double-clicks
            // open the file explicitly targeted in the displayed results.
            scheduleRefresh()
        } else {
            refreshResults()
        }
    }

    func control(_ control: NSControl,
                 textView: NSTextView,
                 doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(by: -1)
            return true
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: 1)
            return true
        // A one-line field sends `scroll…`, not `move…`, for Home and End —
        // verified against a live field editor rather than assumed. Both
        // spellings are accepted so neither keyboard layout loses the key.
        case #selector(NSResponder.moveToBeginningOfDocument(_:)),
             #selector(NSResponder.scrollToBeginningOfDocument(_:)):
            selectRow(results.firstIndex { $0.isSelectable } ?? 0)
            return true
        case #selector(NSResponder.moveToEndOfDocument(_:)),
             #selector(NSResponder.scrollToEndOfDocument(_:)):
            selectRow(results.count - 1)
            return true
        case #selector(NSResponder.pageUp(_:)), #selector(NSResponder.scrollPageUp(_:)):
            moveSelection(by: -visibleRowCount)
            return true
        case #selector(NSResponder.pageDown(_:)), #selector(NSResponder.scrollPageDown(_:)):
            moveSelection(by: visibleRowCount)
            return true
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertLineBreak(_:)):
            // Option-Return arrives as a line break rather than a newline, so
            // both spellings funnel through the same modifier check.
            let modifiers = NSEvent.modifierFlags
            if modifiers.contains(.command) { return activateSelection(target: .newTab) }
            if modifiers.contains(.option) { return activateSelection(target: .newWindow) }
            return activateSelection(target: .currentTab)
        case #selector(NSResponder.cancelOperation(_:)):
            // The field would otherwise just clear itself, which is not what
            // Escape means when a palette is up.
            closePalette()
            return true
        default:
            return false
        }
    }
}

// MARK: - Results table

extension FileSearchPanelController: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        guard results.indices.contains(row) else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("FileSearchRow")
        func rowView() -> FileSearchRowView {
            tableView.makeView(withIdentifier: identifier, owner: self) as? FileSearchRowView
                ?? FileSearchRowView(identifier: identifier)
        }

        switch results[row] {
        case .recentHeading, .filesHeading, .commandsHeading, .contentHeading:
            return headingView(for: results[row])

        case .searching:
            let label = NSTextField(labelWithString: NSLocalizedString("Searching…", comment: "OmniSearch contents scan running"))
            label.font = .systemFont(ofSize: 12)
            label.textColor = .tertiaryLabelColor
            let container = NSView()
            label.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
                label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
            ])
            return container

        case .content(let hit):
            let cell = rowView()
            cell.configureContent(fileName: hit.candidate.fileName,
                                  snippet: hit.match.snippet,
                                  snippetRanges: hit.match.snippetRanges,
                                  icon: NSWorkspace.shared.icon(forFile: hit.url.path))
            return cell

        case .file(let entry):
            let candidate = entry.candidate
            let cell = rowView()
            // Ranges for the query these rows were actually ranked for, so the
            // emphasis can never describe an older query than the list does.
            let match = FileSearchMatcher.match(query: rankedQuery ?? "", against: candidate)
            cell.configure(fileName: candidate.fileName,
                           relativePath: candidate.relativePath,
                           projectRoot: entry.projectRoot,
                           nameRanges: match?.nameRanges ?? [],
                           pathRanges: match?.pathRanges ?? [],
                           icon: NSWorkspace.shared.icon(forFile: entry.url.path))
            return cell

        case .command(let command):
            let cell = rowView()
            let query = FileSearchResults.commandQuery(rankedQuery ?? "") ?? rankedQuery ?? ""
            let match = FileSearchMatcher.match(query: query, against: command.candidate)
            cell.configureCommand(title: command.title,
                                  titleRanges: match?.nameRanges ?? [],
                                  menuPath: command.menuPath,
                                  shortcut: command.shortcut)
            return cell

        case .createFile(let newFile):
            let cell = rowView()
            cell.configureCreateFile(fileName: newFile.fileName,
                                     directory: newFile.directory,
                                     projectName: newFile.projectRoot.lastPathComponent)
            return cell
        }
    }

    private func headingView(for row: FileSearchResults.Row) -> NSView {
        let title: String
        switch row {
        case .recentHeading: title = NSLocalizedString("Recent Files", comment: "Search history section")
        case .commandsHeading: title = NSLocalizedString("Commands", comment: "OmniSearch commands section")
        case .contentHeading: title = NSLocalizedString("Found in Files", comment: "OmniSearch contents section")
        default: title = NSLocalizedString("File Results", comment: "Project search section")
        }
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        let container = NSView()
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return container
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        results[row].isSelectable
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        results[row].isSelectable ? 40 : 24
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        EmphasizedRowView()
    }
}

/// The strip under the results listing the palette's keys, each as a small
/// key cap followed by what it does.
private final class KeyHintFooter: NSView {

    struct Hint {
        let keys: String
        let label: String
    }

    private let stack = NSStackView()
    private let separator = HairlineSeparator()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        stack.orientation = .horizontal
        stack.spacing = 14
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)
        addSubview(stack)
        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            separator.heightAnchor.constraint(equalToConstant: 1),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -18),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 1)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(hints: [Hint]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for hint in hints {
            let label = NSTextField(labelWithString: hint.label)
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            let pair = NSStackView(views: [KeyCap(hint.keys), label])
            pair.orientation = .horizontal
            pair.spacing = 5
            pair.alignment = .centerY
            stack.addArrangedSubview(pair)
        }
    }
}

/// One key cap: the key text on a faint rounded plate.
private final class KeyCap: NSView {

    private let label: NSTextField

    init(_ text: String) {
        label = NSTextField(labelWithString: text)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 4
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1)
        ])
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // The plate colour is a dynamic colour resolved against the current
    // appearance, so it has to be re-applied when that changes.
    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
        }
    }

    override var wantsUpdateLayer: Bool { true }
}

/// Lets the contents scan hand results back without retaining the panel.
private final class WeakReceiver: Sendable {
    nonisolated(unsafe) weak var panel: FileSearchPanelController?
    @MainActor init(_ panel: FileSearchPanelController) { self.panel = panel }
}

/// Draws the selection in the accent colour even though the table is not the
/// first responder.
///
/// The field keeps focus so typing carries on, and an unfocused `NSTableView`
/// normally renders its selection in a muted grey. The arrow keys were moving
/// the selection all along; it just did not look like anything was happening.
private final class EmphasizedRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        NSColor.selectedContentBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 8, dy: 1),
                     xRadius: 13, yRadius: 13).fill()
    }

    override var isEmphasized: Bool {
        get { true }
        set { }
    }
}

/// One result: the file's icon, its name, and where it sits in the project.
private final class FileSearchRowView: NSTableCellView {

    private let icon = NSImageView()
    private let name = NSTextField(labelWithString: "")
    private let path = NSTextField(labelWithString: "")
    private let shortcut = NSTextField(labelWithString: "")

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        icon.translatesAutoresizingMaskIntoConstraints = false
        name.translatesAutoresizingMaskIntoConstraints = false
        path.translatesAutoresizingMaskIntoConstraints = false
        shortcut.translatesAutoresizingMaskIntoConstraints = false
        shortcut.font = .systemFont(ofSize: 12)
        shortcut.textColor = .secondaryLabelColor
        shortcut.setContentCompressionResistancePriority(.required, for: .horizontal)
        shortcut.setContentHuggingPriority(.required, for: .horizontal)

        name.lineBreakMode = .byTruncatingTail
        path.lineBreakMode = .byTruncatingMiddle
        name.maximumNumberOfLines = 1
        path.maximumNumberOfLines = 1
        name.cell?.usesSingleLineMode = true
        path.cell?.usesSingleLineMode = true

        addSubview(icon)
        addSubview(name)
        addSubview(path)
        addSubview(shortcut)
        textField = name

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22),

            name.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            shortcut.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            shortcut.centerYAnchor.constraint(equalTo: centerYAnchor),

            name.trailingAnchor.constraint(lessThanOrEqualTo: shortcut.leadingAnchor, constant: -8),
            name.topAnchor.constraint(equalTo: topAnchor, constant: 4),

            path.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            path.trailingAnchor.constraint(lessThanOrEqualTo: shortcut.leadingAnchor, constant: -8),
            path.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 1)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(fileName: String,
                   relativePath: String,
                   projectRoot: URL?,
                   nameRanges: [Range<Int>],
                   pathRanges: [Range<Int>],
                   icon iconImage: NSImage?) {
        name.attributedStringValue = Self.emphasising(nameRanges,
                                                      in: fileName,
                                                      base: Self.nameFont,
                                                      emphasis: Self.nameMatchFont,
                                                      color: .labelColor,
                                                      paragraphStyle: Self.nameParagraphStyle)

        // A slash in the query matches the path, so show the whole path for
        // the emphasis to sit on. Otherwise the name above already is the last
        // component, and repeating it would be noise.
        let subtitle = pathRanges.isEmpty
            ? (relativePath as NSString).deletingLastPathComponent
            : relativePath
        let breadcrumb = NSMutableAttributedString(attributedString: Self.emphasising(
            pathRanges, in: subtitle, base: Self.pathFont,
            emphasis: Self.pathMatchFont, color: .secondaryLabelColor,
            paragraphStyle: Self.pathParagraphStyle
        ))
        // Replace separators after applying match ranges, preserving Unicode
        // offsets and emphasis while making the hierarchy easier to scan.
        for index in subtitle.indices.reversed() where subtitle[index] == "/" {
            let range = NSRange(index..<subtitle.index(after: index), in: subtitle)
            // Absolute recent-file paths have no named component before the
            // first slash. Omit that separator, but keep "/" for root itself.
            let replacement = index == subtitle.startIndex ? (subtitle == "/" ? "/" : "") : " › "
            breadcrumb.replaceCharacters(in: range, with: replacement)
        }
        if let projectRoot {
            let prefix = projectRoot.lastPathComponent + (subtitle.isEmpty ? "" : " › ")
            breadcrumb.insert(NSAttributedString(string: prefix, attributes: [
                .font: Self.pathFont, .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: Self.pathParagraphStyle
            ]), at: 0)
            path.toolTip = projectRoot.appendingPathComponent(relativePath).path
        } else {
            path.toolTip = relativePath
        }
        path.attributedStringValue = breadcrumb

        iconImage?.size = NSSize(width: 22, height: 22)
        icon.image = iconImage
        icon.contentTintColor = nil
        shortcut.stringValue = ""
    }

    /// A hit inside a file's text: the file, and the line it was found on.
    func configureContent(fileName: String, snippet: String, snippetRanges: [Range<Int>],
                          icon iconImage: NSImage?) {
        name.attributedStringValue = Self.emphasising([], in: fileName,
                                                      base: Self.nameFont, emphasis: Self.nameMatchFont,
                                                      color: .labelColor,
                                                      paragraphStyle: Self.nameParagraphStyle)
        path.attributedStringValue = Self.emphasising(snippetRanges, in: snippet,
                                                      base: Self.pathFont, emphasis: Self.pathMatchFont,
                                                      color: .secondaryLabelColor,
                                                      paragraphStyle: Self.snippetParagraphStyle)
        path.toolTip = snippet
        shortcut.stringValue = ""
        iconImage?.size = NSSize(width: 22, height: 22)
        icon.image = iconImage
        icon.contentTintColor = nil
    }

    /// A menu command: its title, the menu it lives in, and its shortcut.
    func configureCommand(title: String, titleRanges: [Range<Int>], menuPath: String, shortcut shortcutText: String?) {
        name.attributedStringValue = Self.emphasising(titleRanges, in: title,
                                                      base: Self.nameFont, emphasis: Self.nameMatchFont,
                                                      color: .labelColor,
                                                      paragraphStyle: Self.nameParagraphStyle)
        path.attributedStringValue = Self.emphasising([], in: menuPath,
                                                      base: Self.pathFont, emphasis: Self.pathMatchFont,
                                                      color: .secondaryLabelColor,
                                                      paragraphStyle: Self.pathParagraphStyle)
        path.toolTip = menuPath
        shortcut.stringValue = shortcutText ?? ""
        setSymbol("command")
    }

    /// The "create it" row: what will be made and where.
    func configureCreateFile(fileName: String, directory: String, projectName: String) {
        let title = String(format: NSLocalizedString("Create “%@”", comment: "OmniSearch create file row; %@ is the file name"),
                           fileName)
        name.attributedStringValue = Self.emphasising([], in: title,
                                                      base: Self.nameFont, emphasis: Self.nameMatchFont,
                                                      color: .labelColor,
                                                      paragraphStyle: Self.nameParagraphStyle)
        let location = ([projectName] + directory.split(separator: "/").map(String.init)).joined(separator: " › ")
        path.attributedStringValue = Self.emphasising([], in: location,
                                                      base: Self.pathFont, emphasis: Self.pathMatchFont,
                                                      color: .secondaryLabelColor,
                                                      paragraphStyle: Self.pathParagraphStyle)
        path.toolTip = location
        shortcut.stringValue = ""
        setSymbol("doc.badge.plus")
    }

    private func setSymbol(_ symbolName: String) {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .regular))
        icon.image = image
        icon.contentTintColor = .secondaryLabelColor
    }

    /// Bolds the characters the query matched — the thing that makes a fuzzy
    /// result legible, because it shows *why* this file matched what was typed.
    private static func emphasising(_ ranges: [Range<Int>],
                                    in string: String,
                                    base: NSFont,
                                    emphasis: NSFont,
                                    color: NSColor,
                                    paragraphStyle: NSParagraphStyle) -> NSAttributedString {
        let attributed = NSMutableAttributedString(
            string: string,
            attributes: [.font: base, .foregroundColor: color, .paragraphStyle: paragraphStyle]
        )
        for range in FileSearchMatcher.nsRanges(ranges, in: string) {
            attributed.addAttribute(.font, value: emphasis, range: range)
        }
        return attributed
    }

    private static let nameFont = NSFont.systemFont(ofSize: 13)
    private static let nameMatchFont = NSFont.systemFont(ofSize: 13, weight: .bold)
    private static let pathFont = NSFont.systemFont(ofSize: 11)
    private static let pathMatchFont = NSFont.systemFont(ofSize: 11, weight: .bold)

    // Attributed strings need their own line-break policy; the field's setting
    // alone does not prevent the default paragraph style from wrapping.
    private static let nameParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        return style.copy() as! NSParagraphStyle
    }()

    private static let snippetParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        return style.copy() as! NSParagraphStyle
    }()

    private static let pathParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingMiddle
        return style.copy() as! NSParagraphStyle
    }()
}

/// A text field that never draws a focus ring.
///
/// Setting `focusRingType` on the field alone is not enough: that is the
/// `NSView` property, while the ring is drawn by the field's *cell*, which
/// carries a separate `focusRingType` of its own. Both are cleared here, and
/// `drawFocusRingMask()` is overridden as well so nothing can put it back.
///
/// The palette is a panel whose field is focused the moment it opens and never
/// gives focus up, so a ring saying "this is focused" tells the reader nothing
/// and just boxes in the one element that should read as plain text.
private final class PlainQueryField: NSTextField {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        suppressFocusRing()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        suppressFocusRing()
    }

    private func suppressFocusRing() {
        focusRingType = .none
        cell?.focusRingType = .none
    }

    override var focusRingType: NSFocusRingType {
        get { .none }
        set { }
    }

    override func drawFocusRingMask() {}

    override var focusRingMaskBounds: NSRect { .zero }

    /// While the field is being edited it is not really the field on screen
    /// but the window's shared field editor, which carries its own ring
    /// setting that nothing above reaches. It is handed over on focus, so
    /// this is where to clear it.
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted, let editor = currentEditor() as? NSTextView {
            editor.focusRingType = .none
            editor.drawsBackground = false
        }
        return accepted
    }
}

/// Offers the palette every key-down before the first responder gets it.
///
/// The window walks this method down the view tree for each key press, which
/// is how a default button answers Return. Handling the palette's keys here
/// covers the ones the field editor would never forward anyway — ⌘Return is
/// resolved as a key equivalent long before the field sees it — and does not
/// rely on the field being mid-edit for the rest.
private final class KeyEquivalentView: NSView {

    override var mouseDownCanMoveWindow: Bool { true }

    var onKey: ((NSEvent) -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onKey?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
}


/// Owns the floating window independently of NSViewController presentation.
/// Every close clears the document's palette reference before another search.
@MainActor
private final class FileSearchPanelPresentation: NSObject, NSWindowDelegate {
    private var panel: FileSearchPanel?
    private weak var presentedController: FileSearchPanelController?
    private var parentCloseObserver: NSObjectProtocol?

    func present(_ viewController: FileSearchPanelController, relativeTo parent: NSWindow?) {
        let content = viewController.view
        let panel = FileSearchPanel(contentRect: content.bounds,
                                    styleMask: [.borderless],
                                    backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.fullScreenAuxiliary]
        panel.hidesOnDeactivate = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentViewController = viewController
        panel.delegate = self
        self.panel = panel
        presentedController = viewController

        let visibleFrame = parent?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let savedOffset = parent == nil ? nil : UserDefaults.standard.array(forKey: Self.positionKey) as? [Double]
        let frame = FileSearchPanelPlacement.frame(
            contentSize: content.frame.size,
            parentFrame: parent?.frame ?? visibleFrame,
            visibleFrame: visibleFrame,
            savedOffset: savedOffset
        )
        panel.setFrame(frame, display: false)
        parent?.addChildWindow(panel, ordered: .above)
        if let parent {
            parentCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: parent, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.presentedController?.closePalette() }
            }
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        if let parentCloseObserver {
            NotificationCenter.default.removeObserver(parentCloseObserver)
        }
        parentCloseObserver = nil
        presentedController = nil
        panel?.delegate = nil
        if let panel {
            let parent = panel.parent
            let restoreFocus = panel.isKeyWindow || NSApp.keyWindow == nil
            parent?.removeChildWindow(panel)
            panel.orderOut(nil)
            panel.contentViewController = nil
            panel.close()
            // Return keyboard focus to the document for its menu shortcuts.
            if restoreFocus { parent?.makeKeyAndOrderFront(nil) }
        }
        panel = nil
    }

    private static let positionKey = "FileSearchPanel.parentOffset"

    func windowDidMove(_ notification: Notification) {
        guard let panel, let parent = panel.parent, panel.isVisible, !panel.isResizingForResults,
              NSEvent.pressedMouseButtons & 1 != 0 else { return }
        // Keep the search bar relative to its document, independent of result
        // height and the display on which the document is opened next.
        UserDefaults.standard.set(
            [panel.frame.minX - parent.frame.minX, parent.frame.maxY - panel.frame.maxY],
            forKey: Self.positionKey
        )
    }

    func windowDidResignKey(_ notification: Notification) {
        presentedController?.closePalette()
    }
}

private final class FileSearchPanel: NSPanel {
    weak var queryField: NSTextField?
    var isResizingForResults = false

    // The shared field editor fills the search field, including its empty
    // trailing space. Intercept that space before it consumes the mouse event.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, event.clickCount == 1,
           !event.modifierFlags.contains(.shift),
           let field = queryField,
           field.bounds.contains(field.convert(event.locationInWindow, from: nil)),
           let editor = field.currentEditor() as? NSTextView,
           let layout = editor.layoutManager, let container = editor.textContainer {
            layout.ensureLayout(for: container)
            let point = editor.convert(event.locationInWindow, from: nil)
            let textEnd = editor.textContainerOrigin.x + layout.usedRect(for: container).maxX
            if field.stringValue.isEmpty || point.x > textEnd + 6 {
                editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
                performDrag(with: event)
                return
            }
        }
        super.sendEvent(event)
    }

    override func animationResizeTime(_ newFrame: NSRect) -> TimeInterval { 0.16 }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Unoccupied space in the palette moves its window; text and result controls
/// retain their own mouse handling.
private final class DraggablePaletteContent: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}
