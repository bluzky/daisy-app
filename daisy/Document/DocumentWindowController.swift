//
//  DocumentWindowController.swift
//  daisy
//
//  Created by Fauzaan on 4/28/26.
//

import Cocoa
import os
import UniformTypeIdentifiers


// `NSMenuItemValidation` is load-bearing, not tidiness. `validateMenuItem` is only
// reachable from AppKit through an @objc entry point, and `NSWindowController` has
// no such method to override, so without this conformance the implementation below
// is never called: no menu item ever gets its state, and the failure is silent.
final class DocumentWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate, NSSharingServicePickerToolbarItemDelegate, NSSearchFieldDelegate, NSMenuDelegate, NSMenuItemValidation, NSToolbarItemValidation, NSPopoverDelegate {

    var fileSearchPalette: FileSearchPanelController?

    enum NavigationIntent {
        case normal
        case back
        case forward
    }

    enum DiskFileState {
        case unchanged
        case modified(String)
        case missing
        case unreadable
    }

    enum EditedMarkdownSaveResult {
        case saved
        case reloaded(String)
        case cancelled
    }

    enum UnsavedEditResolution {
        case save
        case discard
        case cancel
    }

    enum AutoSaveFeedback: Equatable {
        case none
        case failed
    }

    struct HistoryEntry {
        let url: URL
        /// Scroll offset when the user navigated away; restored on back/forward.
        let scrollPosition: CGFloat
    }

    var currentFileURL: URL?
    var currentMarkdown: String?
    /// The folder this window was opened on, or inherited from the window
    /// it was opened from. Nil for a window opened on a file, whose navigator
    /// root is only the file's own folder.
    var folderRootURL: URL? {
        didSet { updateWorkspaceIndexBinding() }
    }
    /// Whether `folderRootURL` has a workspace marker (see `WorkspaceMarker`).
    var isWorkspace = false {
        didSet {
            updateWorkspaceIndexBinding()
            mainSplit?.setMetadataLinksEnabled(isWorkspace)
            refreshJournalToolbarItem()
            refreshTasksToggleItem()
            addJournalToolbarItemIfNeeded()
        }
    }
    /// The shared index for `indexedWorkspaceRootURL`, and what it last published.
    var workspaceIndex: WorkspaceMetadataIndex?
    var workspaceCandidates: WorkspaceMetadataSnapshot?
    var workspaceSnapshotTask: Task<Void, Never>?
    /// Index updates from this window, run one after another so a restore
    /// never overtakes the overlay it undoes.
    var workspaceIndexUpdates: Task<Void, Never>?
    /// The file whose unsaved text this window has handed to the index.
    var workspaceOverlayURL: URL?
    var workspaceOverlayWork: DispatchWorkItem?
    let workspaceOverlayOwner = UUID()
    /// The workspace root's identity when the index was bound, so the Tasks
    /// sidebar never writes into a root swapped for another directory.
    var taskRootIdentity: WorkspaceFileWriter.RootIdentity?
    /// Check-offs from the Tasks sidebar, run one after another.
    var taskWrites: Task<Void, Never>?
    /// Fallback for controller-driven untitled content outside an NSDocument.
    let untitledDocumentID = UUID().uuidString
    var backHistory: [HistoryEntry] = []
    var forwardHistory: [HistoryEntry] = []
    weak var navigationItem: NSToolbarItemGroup?
    private var fileWatcher: FileWatcher?
    private let fullscreenToolbarTheme = FullscreenToolbarTheme()
    var isTasksToggleSelected = false
    weak var openActionsItem: NSMenuToolbarItem?
    weak var openWithItem: NSMenuToolbarItem?
    weak var openInLLMItem: NSMenuToolbarItem?
    weak var tasksButton: NSButton?
    weak var tasksItem: NSToolbarItem?
    weak var alwaysOnTopButton: NSButton?
    weak var editButton: NSButton?
    var editorChangeRevision = 0
    /// In-memory source shown by preview before the user saves it.
    var editorDraftMarkdown: String?
    /// Last known on-disk source, retained while preview displays a draft.
    var editorBaselineMarkdown: String?
    var isEditorCommitInFlight = false
    var pendingEditorCommitRequested = false
    var pendingCommitShouldExit = false
    var pendingCommitCompletions: [(Bool) -> Void] = []
    /// When sidebar navigation starts from edit mode, the newly loaded file
    /// should return to edit mode instead of dropping the user into preview.
    var pendingEditModeURL: URL?
    /// Set with `pendingEditModeURL` when the editor should open focused with
    /// a new entry appended at the end (Quick Capture's inbox).
    var pendingEditModeAppendedEntry: String?
    var searchOpenRequestID: UUID?
    var autoSaveTimer: Timer?
    var autoSaveTimerID: UUID?
    var isPerformingAutomaticSave = false
    var autoSaveFeedbackResetWork: DispatchWorkItem?
    var outlineRefreshWork: DispatchWorkItem?
    var autoSaveFeedback = AutoSaveFeedback.none {
        didSet { updateWindowSubtitle() }
    }
    /// Drives the native titlebar subtitle while the editor contains changes
    /// that have not yet been written successfully.
    var hasUnsavedEditorChanges = false {
        didSet {
            guard oldValue != hasUnsavedEditorChanges else { return }
            if hasUnsavedEditorChanges {
                // Writing in a preview tab keeps it.
                isPreviewTab = false
                startAutoSaveTimerIfNeeded()
            } else if !isEditorCommitInFlight {
                stopAutoSaveTimer()
            }
            updateWindowSubtitle()
            // The native dot in the tab's close button (and window close
            // button). MarkdownDocument.isDocumentEdited stays false, so
            // set it on the window directly.
            setDocumentEdited(hasUnsavedEditorChanges)
            updateTabEditedIndicator()
            // Saved or discarded: the file speaks for itself again.
            if !hasUnsavedEditorChanges { restoreWorkspaceOverlay() }
        }
    }

    /// The tab bar ignores the window's edited flag, so mark the tab header
    /// itself with an orange dot and title while the editor holds unsaved
    /// changes.
    private static let tabTitleFont = NSFont.systemFont(ofSize: 12, weight: .regular)
    /// A preview tab's title is italic, as in VS Code.
    private static let previewTabTitleFont = NSFontManager.shared.convert(tabTitleFont, toHaveTrait: .italicFontMask)

    /// A tab opened by a single click in the Files sidebar, which the next
    /// click replaces. Editing the file or double-clicking it keeps the tab.
    var isPreviewTab = false {
        didSet {
            guard oldValue != isPreviewTab else { return }
            updateTabEditedIndicator()
        }
    }
    /// The file a sidebar click last asked this preview tab to show. Leaving
    /// Edit Mode can delay the switch past a double-click's second click.
    var requestedPreviewURL: URL?
    /// Opened directly (Finder, ⌘O, recents, command line) rather than from
    /// inside the app, so a Markdown file starts in Read Mode.
    var opensInReadMode = false

    func updateTabEditedIndicator() {
        let tab = documentWindow.tab
        guard hasUnsavedEditorChanges else {
            tab.accessoryView = nil
            tab.attributedTitle = NSAttributedString(
                string: documentWindow.title,
                attributes: [.font: isPreviewTab ? Self.previewTabTitleFont : Self.tabTitleFont])
            return
        }
        let image = NSImage(systemSymbolName: "circle.fill",
                            accessibilityDescription: NSLocalizedString(
                                "Unsaved changes", comment: "Tab indicator for unsaved edits"))
        let dot = NSImageView(image: image ?? NSImage())
        dot.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 7, weight: .regular)
        dot.contentTintColor = .systemOrange
        tab.accessoryView = dot
        tab.attributedTitle = NSAttributedString(
            string: documentWindow.title,
            attributes: [.foregroundColor: NSColor.systemOrange,
                         .font: Self.tabTitleFont])
    }

    weak var copyItem: NSToolbarItem?
    var copyFeedbackWork: DispatchWorkItem?
    /// The Themes & Settings popover while it is on screen.
    var themesPopover: NSPopover?
    /// Armed only while the themes popover is open.
    let themesPopoverEscapeMonitor = EscapeKeyMonitor()
    /// The toolbar's Journal calendar popover while it is on screen.
    var journalCalendarPopover: NSPopover?
    /// Armed only while the Journal calendar is open.
    let journalCalendarEscapeMonitor = EscapeKeyMonitor()
    weak var journalCalendarButton: NSButton?
    /// The Table of Contents / Project Navigator picker in the toolbar.
    var sidebarModeItem: NSToolbarItemGroup?
    /// The original position and spacer while sidebar-only items are removed.
    var collapsedSidebarModePlacement: SidebarToolbarItemOrder.Placement?
    var sidebarToolbarSyncInProgress = false
    var toolbarItemOrderPersistenceReady = false
    var toolbarPreferenceObservations: [NSKeyValueObservation] = []
    /// Timestamp of the last click handled by the sidebar mode picker.
    var sidebarToolbarHandledEventTimestamp: TimeInterval?
    var findBar: FindBar?
    /// Container for the find bar. A content overlay like editBar — not a
    /// titlebar accessory — so showing it never pushes the tab bar down.
    /// Mounted once at setup and toggled via isHidden.
    weak var findBarOverlay: NSView?
    var pendingFindWork: DispatchWorkItem?
    static let findDebounceDelay: TimeInterval = 0.10

    var documentWindow: NSWindow {
        guard let window else {
            fatalError("DocumentWindowController accessed before its window was loaded")
        }
        return window
    }

    var markdownDocument: MarkdownDocument? {
        document as? MarkdownDocument
    }

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 360),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Daisy"
        window.animationBehavior = .default
        window.allowsToolTipsWhenApplicationIsInactive = false
        super.init(window: window)
        setupWindow()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// One-shot override consumed by the next window's setup: "Open in
    /// New Window" needs that window to skip the native tab group during
    /// its first order-front (when AppKit decides tab placement).
    static var nextWindowDeclinesTabbing = false
    /// One-shot for tab requests made from inside a window (Open in New Tab,
    /// ⌘N): the next window keeps that window's workspace, and so joins its
    /// frame.
    static var nextWindowRequestsTab = false
    /// One-shot for a single click in the Files sidebar: the next window is
    /// a preview tab.
    static var nextWindowIsPreview = false

    static func markNextWindowAsSeparate() {
        nextWindowDeclinesTabbing = true
    }

    static func markNextWindowAsTab() {
        nextWindowRequestsTab = true
    }

    /// Windows of one workspace share an identifier, and windows of
    /// different workspaces never do, so AppKit only ever tabs a workspace's
    /// windows together — Merge All Windows and tab dragging included.
    private static let baseTabbingIdentifier = "MarkdownDocumentWindow"

    static func tabbingIdentifier(forWorkspace root: URL?) -> String {
        guard let root else { return baseTabbingIdentifier }
        return baseTabbingIdentifier + ":" + root.path
    }

    /// Every open document window, in no particular order.
    static var allControllers: [DocumentWindowController] {
        NSDocumentController.shared.documents
            .flatMap(\.windowControllers)
            .compactMap { $0 as? DocumentWindowController }
    }

    /// The workspace this window belongs to: its sidebar's root, or for a
    /// file whose sidebar has not taken it yet, the folder it will be bound
    /// to.
    var workspaceRootURL: URL? {
        if let projectRootURL { return projectRootURL }
        return currentFileURL.map { SidebarWorkspace.canonicalURL($0.deletingLastPathComponent()) }
    }

    func syncTabbingIdentifier() {
        documentWindow.tabbingIdentifier = Self.tabbingIdentifier(forWorkspace: workspaceRootURL)
    }

    private func setupWindow() {
        documentWindow.styleMask.insert(.fullSizeContentView)
        // Declared explicitly rather than left to AppKit's implicit default,
        // because Always on Top raises the window above the normal level and a
        // window that has not stated its full-screen capability is the first
        // thing AppKit stops offering Enter Full Screen to.
        documentWindow.collectionBehavior.insert(.fullScreenPrimary)
        applyAlwaysOnTopLevel(isFullScreen: false)
        documentWindow.delegate = self
        documentWindow.tabbingIdentifier = Self.baseTabbingIdentifier
        documentWindow.tabbingMode = Self.nextWindowDeclinesTabbing ? .disallowed : .automatic
        isPreviewTab = Self.nextWindowIsPreview
        Self.nextWindowDeclinesTabbing = false
        Self.nextWindowRequestsTab = false
        Self.nextWindowIsPreview = false
        let split = MainSplitViewController()
        split.onSelectFile = { [weak self] url in
            guard let self, !self.openExternallyIfNeeded(url) else { return }
            self.openFromSidebar(url)
        }
        split.onKeepFile = { [weak self] url in
            self?.keepTab(showing: url)
        }
        documentWindow.contentViewController = split
        documentWindow.setContentSize(NSSize(width: 1100, height: 720))
        documentWindow.center()
        documentWindow.setFrameAutosaveName("MainWindow")

        // AppKit broadcasts item mutations between toolbars with a shared ID.
        // Collapse is per-window, so share saved preferences, not live items.
        let toolbar = NSToolbar(identifier: "MainToolbar-\(UUID().uuidString)")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = false
        documentWindow.toolbar = toolbar
        if let saved = UserDefaults.standard.dictionary(forKey: "MainToolbar.configuration")
            ?? UserDefaults.standard.dictionary(forKey: "NSToolbar Configuration MainToolbar") {
            toolbar.setConfiguration(saved)
        }
        documentWindow.toolbarStyle = .automatic
        restoreToolbarItemOrder(toolbar)
        replaceZoomToolbarItemIfNeeded(in: toolbar)
        migrateLegacySidebarToolbarIfNeeded(in: toolbar)
        observeAndPersistToolbarPreferences(toolbar)
        addJournalToolbarItemIfNeeded()

        installFindBar()
        applyWindowBackgroundTheme()
    }

    /// Applies the user's theme colors to this window: the native window
    /// background plus the preview and editor pages. Also run at setup so
    /// new windows start themed.

    func applyThemeColorsSetting() {
        applyWindowBackgroundTheme()
        mainSplit?.applyThemeColors()
        // The find bar paints the page backgrounds; a theme edit changes those
        // colors without an appearance flip, so force a redraw.
        findBarOverlay?.needsDisplay = true
    }

    /// Tint the window using the current theme while preserving native chrome.
    private func applyWindowBackgroundTheme() {
        // This colors the document window. AppKit moves the full-screen
        // toolbar to a separate window, which needs its own theme treatment.
        documentWindow.backgroundColor = NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return ThemeColorsSetting.current.color(
                .windowBackground, isDark ? .dark : .light
            ) ?? (isDark ? ThemeColorsSetting.defaultColor(.windowBackground, .dark) : .windowBackgroundColor)
        }
        // Preserve native titlebar backing so WebKit can supply the scroll
        // edge on macOS 26+. Earlier systems also use native window chrome.
        documentWindow.titlebarSeparatorStyle = .automatic
        documentWindow.titlebarAppearsTransparent = false
        if #available(macOS 26.0, *) {
            if #unavailable(macOS 27.0) {
                documentWindow.titlebarAppearsTransparent = true
            }
        }
        (findBarOverlay as? EditAccessoryContainerView)?.updateFullscreenBackground()
        updateFullscreenToolbarTheme()
    }

    private func updateFullscreenToolbarTheme() {
        let scheme: ThemeColorScheme = documentWindow.effectiveAppearance
            .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
        fullscreenToolbarTheme.update(
            window: documentWindow,
            color: ThemeColorsSetting.current.color(.windowBackground, scheme)
        )
    }

    func windowDidUpdate(_ notification: Notification) {
        // AppKit can create or replace the detached toolbar after the full-screen
        // notification. Refresh at window updates, with no timer or global scan.
        updateFullscreenToolbarTheme()
    }

    /// AppKit's automatic tab placement runs when NSDocument shows its
    /// windows — but this controller orders the window front itself (from
    /// makeWindowControllers, before showWindows), so the window is already
    /// visible and placement never happens on its own. One frame per
    /// workspace: on first show, join the frontmost window of the same
    /// workspace as a tab, whatever the tabbing preferences say. A window
    /// whose workspace has no frame yet starts one. Only Open in New Window
    /// opts out.
    func attachToExistingTabGroupIfNeeded() {
        guard !documentWindow.isVisible else { return }
        syncTabbingIdentifier()
        guard documentWindow.tabbingMode != .disallowed,
              let host = ([NSApp.mainWindow] + NSApp.orderedWindows)
                  .compactMap({ $0 })
                  .first(where: {
                      $0 !== documentWindow
                          && $0.isVisible
                          && $0.tabbingIdentifier == documentWindow.tabbingIdentifier
                  }) else { return }
        // A tab takes its frame's size; a single file's narrow frame must
        // not become the saved size of workspace windows.
        if host.frameAutosaveName.isEmpty {
            documentWindow.setFrameAutosaveName("")
        }
        host.addTabbedWindow(documentWindow, ordered: .above)
        // A folder window showing nothing yet only held the frame open; the
        // file takes its place rather than leaving an empty tab behind.
        for window in host.tabbedWindows ?? [host] where window !== documentWindow {
            if let placeholder = window.windowController as? DocumentWindowController,
               placeholder.isShowingNothing {
                placeholder.close()
            }
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard hasPendingEditorChanges else { return true }
        requestEndEditing { [weak self] success in
            guard success else { return }
            // close() skips windowShouldClose, so no re-entry loop.
            self?.documentWindow.close()
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        searchOpenRequestID = nil
        fullscreenToolbarTheme.restore()
        fileWatcher?.cancel()
        fileWatcher = nil
        themesPopoverEscapeMonitor.stop()
        journalCalendarEscapeMonitor.stop()
        stopAutoSaveTimer()
        autoSaveFeedbackResetWork?.cancel()
        autoSaveFeedbackResetWork = nil
        releaseWorkspaceIndex()
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        applyAlwaysOnTopLevel(isFullScreen: true)
        // Keep fullSizeContentView so the reveal bar floats over the content.
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        // The toolbar now has a separate AppKit host window.
        applyWindowBackgroundTheme()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        applyAlwaysOnTopLevel(isFullScreen: false)
        // Back to the themed chrome.
        applyWindowBackgroundTheme()
    }

    /// A saved image of the document, decoding while the window is built.
    var pendingSnapshot: DocumentSnapshotCache.Prefetch?

    func display(markdown: String, fileURL: URL?) {
        currentFileURL = fileURL
        currentMarkdown = markdown
        resetAutoSaveFeedback()
        if fileURL == nil {
            stopAutoSaveTimer()
        }
        documentWindow.title = fileURL?.lastPathComponent
            ?? NSLocalizedString("Untitled", comment: "Window title when no document is open")
        updateTabEditedIndicator()
        updateWindowSubtitle()
        attachToExistingTabGroupIfNeeded()
        if let pendingSnapshot {
            self.pendingSnapshot = nil
            (documentWindow.contentViewController as? MainSplitViewController)?
                .showSnapshot(pendingSnapshot)
        }
        documentWindow.makeKeyAndOrderFront(nil)
        #if DEBUG
        Logger.perf.debug(
            "[mdp-perf-open] window-shown t=\(DispatchTime.now().uptimeNanoseconds, privacy: .public)"
        )
        #endif
        // Tab placement is settled once the window is shown; a window opened
        // via "Open in New Window" goes back to normal tabbing afterwards
        // (it can host or join tabs on explicit request, but plain opens no
        // longer recapture it).
        documentWindow.tabbingMode = .automatic
        NSApp.activate()
        refreshOpenWithItem()
        refreshOpenInLLMItem()
        refreshOpenActionsItem()
        updateEditToolbarItem()
        // Folder and untitled windows count too.
        WhatsNewWindow.presentIfNeeded(over: documentWindow)
        if let fileURL {
            NSDocumentController.shared.noteNewRecentDocumentURL(fileURL)
            renderCurrentDocument(text: markdown, fileURL: fileURL)
            recordLastSession()
            startWatching(fileURL)
            offerToBecomeDefaultHandlerIfNeeded()
            if !(opensInReadMode && FileKind.classify(fileURL) == .markdown) {
                enterEditMode()
            }
        }
    }

    /// Opens a Markdown file a link points to, in this window or a new one
    /// as Settings say.
    func openMarkdownLink(_ url: URL) {
        if SettingsModel.shared.opensMarkdownLinksInNewWindows {
            openInNewWindow(url)
        } else {
            present(url: url)
        }
    }

    func present(url: URL) {
        present(url: url, intent: .normal)
    }

    func present(url: URL, intent: NavigationIntent) {
        searchOpenRequestID = nil
        let fragment = url.fragment?.removingPercentEncoding
        let url = Self.fileURLWithoutFragment(url)
        let preserveEditMode = true
        if isEditing || hasPendingEditorChanges {
            requestEndEditing(keepAccessoryMounted: true) { [weak self] success in
                guard success else { return }
                self?.present(url: url, preservingEditMode: preserveEditMode,
                              intent: intent, fragment: fragment)
            }
            return
        }
        present(url: url, preservingEditMode: preserveEditMode, intent: intent, fragment: fragment)
    }

    func present(url: URL, preservingEditMode: Bool,
                         intent: NavigationIntent, fragment: String?, loadedMarkdown: String? = nil) {
        if url.isExistingDirectory {
            pendingEditModeURL = nil
            (NSApp.delegate as? AppDelegate)?.openFolder(url)
            return
        }

        let split = documentWindow.contentViewController as? MainSplitViewController
        guard currentFileURL?.standardizedFileURL != url.standardizedFileURL else {
            // Link into the already-open document — just scroll.
            if let fragment { split?.scrollToAnchor(fragment) }
            return
        }
        let restoredScrollPosition = commitNavigation(to: url, intent: intent)

        // Switching to a different file blanks the preview so the previous
        // doc doesn't linger on screen during sheet dismissal + load.
        let isFileSwitch = currentFileURL != nil && currentFileURL != url
        currentFileURL = url
        currentMarkdown = nil
        pendingEditModeURL = preservingEditMode ? url.standardizedFileURL : nil
        markdownDocument?.replaceFileURL(url)
        documentWindow.title = url.lastPathComponent
        updateTabEditedIndicator()
        resetAutoSaveFeedback()
        updateWindowSubtitle()
        if isFileSwitch {
            split?.clearContent()
        }
        documentWindow.makeKeyAndOrderFront(nil)
        NSApp.activate()
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        refreshOpenWithItem()
        refreshOpenInLLMItem()
        refreshOpenActionsItem()
        updateEditToolbarItem()
        // History restore wins over the link fragment — back/forward returns
        // to where the user actually was.
        if let restoredScrollPosition {
            split?.prepareToScrollAfterNavigation(to: .position(restoredScrollPosition))
        } else if let fragment {
            split?.prepareToScrollAfterNavigation(to: .anchor(fragment))
        } else {
            split?.prepareToScrollAfterNavigation(to: nil)
        }
        if let loadedMarkdown {
            applyLoadedMarkdown(loadedMarkdown, fileURL: url)
        } else {
            loadFile(at: url)
        }
        startWatching(url)
        offerToBecomeDefaultHandlerIfNeeded()
    }

    /// Records the navigation in history, capturing the departing scroll
    /// offset. Returns the position to restore for back/forward, nil otherwise.
    private func commitNavigation(to url: URL, intent: NavigationIntent) -> CGFloat? {
        guard let currentFileURL else { return nil }
        let departed = HistoryEntry(
            url: currentFileURL.standardizedFileURL,
            scrollPosition: (documentWindow.contentViewController as? MainSplitViewController)?
                .previewScrollPosition ?? 0
        )
        defer { updateNavigationItem() }
        switch intent {
        case .normal:
            Self.appendHistory(departed, to: &backHistory)
            forwardHistory.removeAll()
            return nil
        case .back:
            guard let target = backHistory.last,
                  target.url == url.standardizedFileURL else { return nil }
            backHistory.removeLast()
            Self.appendHistory(departed, to: &forwardHistory)
            return target.scrollPosition
        case .forward:
            guard let target = forwardHistory.last,
                  target.url == url.standardizedFileURL else { return nil }
            forwardHistory.removeLast()
            Self.appendHistory(departed, to: &backHistory)
            return target.scrollPosition
        }
    }

    private static func appendHistory(_ entry: HistoryEntry, to history: inout [HistoryEntry]) {
        if history.last?.url == entry.url {
            // Same document again — keep one entry with the latest scroll.
            history[history.count - 1] = entry
        } else {
            history.append(entry)
        }
    }

    static func fileURLWithoutFragment(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.fragment != nil else { return url }
        components.fragment = nil
        return components.url ?? url
    }

    func startWatching(_ url: URL) {
        fileWatcher?.cancel()
        let watcher = FileWatcher(url: url) { [weak self] in
            // While editing with unsaved changes, disk changes must not
            // clobber the session; every commit revalidates the disk
            // contents before writing, so an external edit is resolved
            // explicitly then. A clean editor can safely follow the disk.
            guard let self, self.currentFileURL == url,
                  !self.hasPendingEditorChanges else { return }
            if self.isEditing {
                self.reloadCleanEditorFromDisk()
            } else {
                self.loadFile(at: url, silentOnFailure: true)
            }
        }
        watcher.onRename = { [weak self] newURL in
            self?.handleRename(to: newURL)
        }
        fileWatcher = watcher
    }

    /// The currently-open file moved (Finder rename, editor save-as, etc).
    /// Update the open URL and propagate it to the title, recent docs,
    /// Open With list and sidebar selection — without
    /// re-rendering the WebView, since the markdown content didn't change.
    func handleRename(to newURL: URL) {
        guard currentFileURL != nil else { return }
        // A file moved to the Trash is effectively deleted: close it rather
        // than follow it into `.Trash`.
        if newURL.pathComponents.contains(".Trash") {
            documentWindow.close()
            return
        }
        currentFileURL = newURL
        markdownDocument?.replaceFileURL(newURL)
        documentWindow.title = newURL.lastPathComponent
        updateTabEditedIndicator()
        updateWindowSubtitle()
        NSDocumentController.shared.noteNewRecentDocumentURL(newURL)
        refreshOpenWithItem()
        refreshOpenActionsItem()
        startWatching(newURL)
        if let markdown = currentMarkdown {
            (documentWindow.contentViewController as? MainSplitViewController)?
                .openFileURLDidChange(newURL, markdown: markdown)
        } else {
            loadFile(at: newURL, silentOnFailure: true)
        }
    }

    /// Also read by `WhatsNewWindow` as a sign of earlier use.
    static let didOfferDefaultHandlerKey = "MarkdownPreview.didOfferAsDefaultHandler"

    private func offerToBecomeDefaultHandlerIfNeeded() {
        let key = Self.didOfferDefaultHandlerKey
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        guard let markdownType = UTType("net.daringfireball.markdown")
                ?? UTType(filenameExtension: "md") else { return }

        let currentDefaultID = NSWorkspace.shared.urlForApplication(toOpen: markdownType)
            .flatMap { Bundle(url: $0)?.bundleIdentifier }
        if currentDefaultID == Bundle.main.bundleIdentifier {
            UserDefaults.standard.set(true, forKey: key)
            return
        }

        UserDefaults.standard.set(true, forKey: key)
        Task { @concurrent in
            try? await NSWorkspace.shared.setDefaultApplication(
                at: Bundle.main.bundleURL,
                toOpen: markdownType
            )
        }
    }

    /// The chrome-overlay container (formatting bar, find bar) floats over
    /// the web views, whose cursor tracking (I-beam over text, hand over
    /// links) otherwise fights the bar's buttons. The bar region always
    /// shows the plain arrow.
    ///
    /// Sequoia rows use the native titlebar material with unthemed controls.
    /// On macOS 26+, a formatting container can instead remain transparent
    /// around its native Liquid Glass groups.
    final class EditAccessoryContainerView: NSView {
        private let usesFloatingGlass: Bool
        weak var cursorContentView: NSView?

        private var cursorRegion: NSRect {
            guard usesFloatingGlass else { return bounds }
            guard let cursorContentView else { return .zero }
            return convert(cursorContentView.bounds, from: cursorContentView).intersection(bounds)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            let hit = super.hitTest(point)
            guard usesFloatingGlass, let superview else { return hit }
            return cursorRegion.contains(convert(point, from: superview)) ? hit : nil
        }
        private var fullscreenBackdrop: NSVisualEffectView?
        private var fullscreenThemeFill: NSView?

        convenience init(floatingGlass: Bool = false) {
            self.init(frame: .zero, floatingGlass: floatingGlass)
        }

        private init(frame frameRect: NSRect, floatingGlass: Bool) {
            usesFloatingGlass = floatingGlass
            super.init(frame: frameRect)
            installLegacyBackdropIfNeeded()
        }

        /// Full screen on macOS 26 and later draws the toolbar on an opaque
        /// native strip instead of frosting the page, so the rows below it
        /// use the same solid theme color as the toolbar workaround. Without a
        /// custom background, retain the native titlebar material.
        func updateFullscreenBackground() {
            guard #available(macOS 26.0, *) else { return }
            guard !usesFloatingGlass else { return }
            if window?.styleMask.contains(.fullScreen) == true {
                let scheme: ThemeColorScheme = effectiveAppearance
                    .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
                if let color = ThemeColorsSetting.current.color(.windowBackground, scheme) {
                    if fullscreenThemeFill == nil {
                        let fill = NSView(frame: bounds)
                        fill.wantsLayer = true
                        fill.autoresizingMask = [.width, .height]
                        addSubview(fill, positioned: .below, relativeTo: subviews.first)
                        fullscreenThemeFill = fill
                    }
                    fullscreenThemeFill?.layer?.backgroundColor = color.cgColor
                    fullscreenThemeFill?.isHidden = false
                    fullscreenBackdrop?.isHidden = true
                    return
                }
                fullscreenThemeFill?.isHidden = true
                if fullscreenBackdrop == nil {
                    let backdrop = NSVisualEffectView(frame: bounds)
                    backdrop.material = .titlebar
                    backdrop.blendingMode = .withinWindow
                    backdrop.state = .followsWindowActiveState
                    backdrop.autoresizingMask = [.width, .height]
                    addSubview(backdrop, positioned: .below, relativeTo: subviews.first)
                    fullscreenBackdrop = backdrop
                }
                fullscreenBackdrop?.isHidden = false
            } else {
                fullscreenBackdrop?.isHidden = true
                fullscreenThemeFill?.isHidden = true
            }
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            updateFullscreenBackground()
        }

        override init(frame frameRect: NSRect) {
            usesFloatingGlass = false
            super.init(frame: frameRect)
            installLegacyBackdropIfNeeded()
        }

        required init?(coder: NSCoder) {
            usesFloatingGlass = false
            super.init(coder: coder)
            installLegacyBackdropIfNeeded()
        }

        private func installLegacyBackdropIfNeeded() {
            if #unavailable(macOS 26.0), fullscreenBackdrop == nil {
                let backdrop = NSVisualEffectView(frame: bounds)
                backdrop.material = .titlebar
                backdrop.blendingMode = .withinWindow
                backdrop.state = .followsWindowActiveState
                backdrop.autoresizingMask = [.width, .height]
                addSubview(backdrop)
            }
        }

        override func resetCursorRects() {
            super.resetCursorRects()
            // Only the controls and their inter-group gaps own the cursor.
            // The remaining transparent row belongs to the document.
            addCursorRect(cursorRegion, cursor: .arrow)
        }

        // First install: the cursor rect is computed while the accessory
        // has no frame yet and nothing re-invalidates it, so the web view's
        // cursor wins between the buttons until the bar is reinstalled.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateFullscreenBackground()
            window?.invalidateCursorRects(for: self)
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            window?.invalidateCursorRects(for: self)
        }

        override func cursorUpdate(with event: NSEvent) {
            if cursorRegion.contains(convert(event.locationInWindow, from: nil)) {
                NSCursor.arrow.set()
            }
        }

        override func mouseEntered(with event: NSEvent) {
            super.mouseEntered(with: event)
            cursorUpdate(with: event)
        }

        override func mouseMoved(with event: NSEvent) {
            super.mouseMoved(with: event)
            cursorUpdate(with: event)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            for area in trackingAreas where area.owner === self {
                removeTrackingArea(area)
            }
            addTrackingArea(NSTrackingArea(
                rect: cursorRegion,
                options: [.cursorUpdate, .mouseEnteredAndExited, .mouseMoved,
                          .activeInKeyWindow, .enabledDuringMouseDrag],
                owner: self
            ))
        }
    }

}
