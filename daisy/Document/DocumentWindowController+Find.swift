//
//  DocumentWindowController+Find.swift
//  daisy
//
//  The find and replace bar. It appears on demand (⌘F, ⌥⌘F) as a content
//  overlay and owns the query field itself — there is no toolbar search item.
//

import Cocoa

extension DocumentWindowController {
    /// A content overlay like the formatting bar, not a titlebar accessory:
    /// AppKit pins the native tab bar below every accessory, so an
    /// accessory find bar sat above the tabs and shoved them down on every
    /// appearance. The overlay never reflows the layout — see
    /// DocumentWindowController.editBar.
    func installFindBar() {
        let bar = FindBar(
            frame: NSRect(x: 0, y: 0, width: 600, height: FindBar.rowHeight)
        )
        bar.onQueryChanged = { [weak self] query in self?.findQueryDidChange(query) }
        bar.onNavigate = { [weak self] backwards in self?.findFromBar(backwards: backwards) }
        bar.onOptionsChanged = { [weak self] in self?.findOptionsDidChange() }
        bar.onReplace = { [weak self] in self?.replaceCurrentMatch() }
        bar.onReplaceAll = { [weak self] in self?.replaceAllMatches() }
        bar.onClose = { [weak self] in self?.dismissFindBar() }
        bar.onHeightChanged = { [weak self] in self?.mainSplit?.findOverlayVisibilityChanged() }
        self.findBar = bar

        let container = EditAccessoryContainerView()
        // The find bar shows over the preview, whose backdrop follows the
        // window background, not the editor color.
        bar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bar.topAnchor.constraint(equalTo: container.topAnchor),
            bar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        // macOS 27 supplies the native header edge in both read and edit modes.
        if #unavailable(macOS 27.0) {
            let hairline = NSBox()
            hairline.boxType = .separator
            hairline.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(hairline)
            NSLayoutConstraint.activate([
                hairline.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                hairline.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                hairline.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
        }
        container.isHidden = true
        mainSplit?.installFindOverlay(container)
        mainSplit?.findContextDidChange = { [weak self] in self?.syncFindBarWithMode() }
        findBarOverlay = container
        syncFindBarWithMode()
    }

    // MARK: - Showing and hiding

    @IBAction func performFindPanelAction(_ sender: Any?) {
        handleFindAction(sender)
    }

    @IBAction override func performTextFinderAction(_ sender: Any?) {
        handleFindAction(sender)
    }

    func handleFindAction(_ sender: Any?) {
        let tag = (sender as? NSValidatedUserInterfaceItem)?.tag ?? NSTextFinder.Action.showFindInterface.rawValue
        switch tag {
        case NSTextFinder.Action.nextMatch.rawValue:
            findFromBar(backwards: false)
        case NSTextFinder.Action.previousMatch.rawValue:
            findFromBar(backwards: true)
        case NSTextFinder.Action.showReplaceInterface.rawValue:
            showFindBar(expandingReplace: true)
        default:
            showFindBar(expandingReplace: false)
        }
    }

    /// Opens the bar and focuses the query field. The query starts as the
    /// current selection, else the shared find pasteboard string.
    private func showFindBar(expandingReplace: Bool, focusing: Bool = true) {
        guard let bar = findBar else { return }
        syncFindBarWithMode()
        if expandingReplace { bar.setReplaceExpanded(true) }
        let wasHidden = findBarOverlay?.isHidden ?? true
        setFindBarVisible(true)
        guard focusing else { return }

        func focus() {
            if expandingReplace && bar.isReplaceExpanded && !bar.query.isEmpty {
                bar.focusReplacement()
            } else {
                bar.focusQuery()
            }
        }
        mainSplit?.fetchSelectedText { [weak self] selection in
            guard let self else { return }
            let text = Self.findQuery(fromSelection: selection)
            let fallback = wasHidden
                ? NSPasteboard(name: .find).string(forType: .string) ?? ""
                : bar.query
            let query = text ?? fallback
            if query != bar.query {
                bar.query = query
                bar.clearReplacedNote()
                self.runFind(query: query)
            }
            focus()
        }
    }

    /// A selection is a usable query when it is one short line.
    static func findQuery(fromSelection selection: String?) -> String? {
        guard let selection, !selection.isEmpty, selection.count <= 200,
              !selection.contains(where: \.isNewline) else { return nil }
        return selection
    }

    private func setFindBarVisible(_ visible: Bool) {
        guard let overlay = findBarOverlay, overlay.isHidden == visible else { return }
        overlay.isHidden = !visible
        // The editor pads its page below every visible overlay.
        mainSplit?.findOverlayVisibilityChanged()
    }

    private func dismissFindBar() {
        guard let bar = findBar else { return }
        let hadFocus = bar.contains(firstResponder: documentWindow.firstResponder)
        bar.query = ""
        bar.clearReplacedNote()
        runFind(query: "")
        setFindBarVisible(false)
        guard hadFocus else { return }
        if isEditing {
            mainSplit?.editorViewController?.focusEditor()
        } else {
            documentWindow.makeFirstResponder(nil)
        }
    }

    /// Replace only exists while the source is editable.
    func syncFindBarWithMode() {
        guard let bar = findBar else { return }
        bar.isReplaceAvailable = isEditing
    }

    // MARK: - Searching

    private func findQueryDidChange(_ query: String) {
        // Coalesce per-keystroke finds — running the full DOM rewrite + JS
        // round-trip on every char is the dominant stall source on big docs.
        // Empty queries (e.g. user cleared the field) bypass the debounce so
        // the highlight teardown happens immediately.
        pendingFindWork?.cancel()
        if query.isEmpty {
            pendingFindWork = nil
            runFind(query: query)
            return
        }
        let work = DispatchWorkItem { [weak self] in
            self?.runFind(query: query)
        }
        pendingFindWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.findDebounceDelay, execute: work
        )
    }

    private func findOptionsDidChange() {
        guard let bar = findBar, !bar.query.isEmpty else { return }
        runFind(query: bar.query)
    }

    private func runFind(query: String, backwards: Bool = false) {
        // Explicit nav (Enter / prev / next / option change) flushes any pending
        // debounce so the user navigates the freshest results.
        pendingFindWork?.cancel()
        pendingFindWork = nil
        let options = findBar?.options ?? SearchOptions()
        mainSplit?.find(query, backwards: backwards, options: options) { [weak self] result in
            self?.findBar?.update(result)
        }
    }

    /// ⌘G / ⇧⌘G and the bar's chevrons. With the bar closed, they search for
    /// whatever the find pasteboard holds without taking focus.
    private func findFromBar(backwards: Bool) {
        guard let bar = findBar else { return }
        if bar.query.isEmpty {
            let shared = NSPasteboard(name: .find).string(forType: .string) ?? ""
            guard !shared.isEmpty else {
                showFindBar(expandingReplace: false)
                return
            }
            bar.query = shared
        }
        if findBarOverlay?.isHidden ?? true {
            showFindBar(expandingReplace: false, focusing: false)
        }
        runFind(query: bar.query, backwards: backwards)
    }

    // MARK: - Replacing

    private func replaceCurrentMatch() {
        guard let bar = findBar, !bar.query.isEmpty, let split = mainSplit, split.canReplace else { return }
        bar.clearReplacedNote()
        split.replaceCurrent(bar.replacement, query: bar.query, options: bar.options) { [weak bar] result, _ in
            bar?.update(result)
        }
    }

    private func replaceAllMatches() {
        guard let bar = findBar, !bar.query.isEmpty, let split = mainSplit, split.canReplace else { return }
        split.replaceAll(bar.replacement, query: bar.query, options: bar.options) { [weak bar] result, replaced in
            bar?.noteReplaced(replaced)
            bar?.update(result)
        }
    }
}
