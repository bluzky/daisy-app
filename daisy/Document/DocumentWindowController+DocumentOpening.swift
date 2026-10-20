//
//  DocumentWindowController+DocumentOpening.swift
//  daisy
//
//  Opening documents: tabs, windows, folders, and the open panel.
//

import Cocoa

extension DocumentWindowController {
    private struct ContextOpenPayload {
        let fileURL: URL
        let appURL: URL
    }

    func openInNewTab(_ fileURL: URL, startEditing: Bool = false) {
        Self.markNextWindowAsTab()
        openDocumentWindow(for: fileURL, startEditing: startEditing) {
            // If the document was already open, no window was created and
            // the override wasn't consumed — don't let it leak to the next one.
            Self.nextWindowRequestsTab = false
        }
    }

    func openInNewWindow(_ fileURL: URL, startEditing: Bool = false) {
        Self.markNextWindowAsSeparate()
        openDocumentWindow(for: fileURL, startEditing: startEditing) {
            // If the document was already open, no window was created and
            // the override wasn't consumed — don't let it leak to the next one.
            Self.nextWindowDeclinesTabbing = false
        }
    }

    /// Hands a file Daisy does not edit to the system's default app. Returns
    /// true when it did, so callers stop before they create a tab for it.
    @discardableResult
    func openExternallyIfNeeded(_ fileURL: URL) -> Bool {
        let url = Self.fileURLWithoutFragment(fileURL)
        // Folders open as workspaces, whatever their name looks like.
        guard !url.isExistingDirectory else { return false }
        let kind = FileKind.classify(url)
        // Code is edited in place, so a file too big to hold or not valid
        // UTF-8 goes to another app rather than risk a corrupting save.
        if kind == .markdown || (kind == .text && CodeDocument.isEditable(at: url)) {
            return false
        }
        NSWorkspace.shared.open(url)
        return true
    }

    private func openDocumentWindow(for fileURL: URL, startEditing: Bool = false,
                                    completion: (() -> Void)? = nil) {
        if openExternallyIfNeeded(fileURL) {
            completion?()
            return
        }
        let fragment = fileURL.fragment?.removingPercentEncoding
        NSDocumentController.shared.openDocument(withContentsOf: Self.fileURLWithoutFragment(fileURL),
                                                 display: true) { [weak self] document, _, error in
            completion?()
            if startEditing, let controller = document?.windowControllers.first as? DocumentWindowController,
               !controller.isEditing {
                // Completion runs after initial display. Enter now; setting
                // pendingEditModeURL here would miss its post-load check.
                controller.enterEditMode()
            }
            if let fragment,
               let controller = document?.windowControllers.first as? DocumentWindowController,
               let split = controller.documentWindow.contentViewController as? MainSplitViewController {
                split.scrollToAnchorWhenReady(fragment)
            }
            guard let self, let error else { return }
            NSAlert(error: error).beginSheetModal(for: self.documentWindow)
        }
    }

    /// An untitled window with nothing in it and no workspace, which an
    /// opened folder can take over instead of leaving it behind.
    var isBlank: Bool {
        currentFileURL == nil && projectRootURL == nil && !hasUntitledContent
    }

    /// An untitled document someone has written in. A folder window showing
    /// no file yet has none, so it can take the file it opens.
    var hasUntitledContent: Bool {
        currentFileURL == nil
            && (!(currentMarkdown ?? "").isEmpty || hasPendingEditorChanges)
    }

    /// A window showing no file and not being written in shows shortcut
    /// hints instead of a blank page: a folder window before its first file,
    /// or an untitled one taken out of Edit Mode while still empty.
    func updateEmptyHints() {
        mainSplit?.setShowsEmptyHints(currentFileURL == nil && !isEditing && !hasUntitledContent)
    }

    /// Binds this window to `folderURL` as its workspace. Opening a folder
    /// from the UI goes through `AppDelegate.openFolder`, which picks the
    /// window.
    func openFolder(_ folderURL: URL) {
        let folderURL = folderURL.standardizedFileURL
        if currentFileURL == nil {
            documentWindow.title = folderURL.lastPathComponent
            updateTabEditedIndicator()
            updateWindowSubtitle()
        }
        (documentWindow.contentViewController as? MainSplitViewController)?
            .openFolder(folderURL, selectedFileURL: currentFileURL)
        documentWindow.makeKeyAndOrderFront(nil)
        NSApp.activate()
        syncSidebarToolbarState()
        recordLastSession()
    }

    /// Remembers this window's document and file tree root for the "Reopen
    /// last folder and file" launch behaviour. Called after the sidebar has
    /// taken the new file, so the root is the one on screen.
    func recordLastSession() {
        LastSessionStore.record(fileURL: currentFileURL, folderURL: projectRootURL)
    }

    /// The Files sidebar's "Open with External Editor" item: the file in the
    /// default external editor, disabled when there is none.
    func contextMenuExternalEditorItem(for fileURL: URL) -> NSMenuItem {
        let defaultEditor = resolveDefaultEditor(among: editorCandidates(for: fileURL))
        let item = NSMenuItem(
            title: NSLocalizedString("Open with External Editor", comment: "Context menu item"),
            action: #selector(contextLaunchEditor(_:)),
            keyEquivalent: ""
        )
        item.image = NSImage(systemSymbolName: "arrow.up.right.square", accessibilityDescription: nil)
        if let defaultEditor {
            item.target = self
            item.representedObject = ContextOpenPayload(fileURL: fileURL, appURL: defaultEditor.url)
            item.toolTip = localizedOpenIn(displayName(for: defaultEditor.url))
        } else {
            item.isEnabled = false
        }
        return item
    }

    @objc private func contextLaunchEditor(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? ContextOpenPayload else { return }
        launch(payload.fileURL, with: payload.appURL)
    }

    @IBAction func openDocument(_ sender: Any?) {
        promptForDocument(openAsTab: false)
    }

    private func promptForDocument(openAsTab: Bool) {
        let panel = makeOpenPanel()
        panel.beginSheetModal(for: documentWindow) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            if url.isExistingDirectory {
                (NSApp.delegate as? AppDelegate)?.openFolder(url)
                return
            }
            if openAsTab {
                self.openInNewTab(url)
            } else {
                // Plain open: tab placement follows the system
                // "Prefer tabs" setting via attachToExistingTabGroupIfNeeded.
                self.openDocumentWindow(for: url)
            }
        }
    }

    private func makeOpenPanel() -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.message = NSLocalizedString(
            "Choose a file or folder",
            comment: "Open panel prompt"
        )
        panel.allowedContentTypes = []
        return panel
    }

    func loadFile(at url: URL, silentOnFailure: Bool = false) {
        Task { @concurrent [weak self] in
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                await self?.applyLoadedMarkdown(text, fileURL: url)
            } catch {
                // Wrap as NSError (Sendable) so the original presentation —
                // localizedDescription + recovery suggestion — survives the
                // hop back to MainActor.
                let nsError = error as NSError
                await self?.applyLoadFailure(error: nsError,
                                             fileURL: url,
                                             silentOnFailure: silentOnFailure)
            }
        }
    }

    func applyLoadedMarkdown(_ text: String, fileURL: URL) {
        guard currentFileURL?.standardizedFileURL == fileURL.standardizedFileURL else { return }
        currentMarkdown = text
        resetAutoSaveFeedback()
        updateWindowSubtitle()
        refreshOpenInLLMItem()
        updateEditToolbarItem()
        markdownDocument?.replaceContents(markdown: text, fileURL: fileURL)
        renderCurrentDocument(text: text, fileURL: fileURL)
        recordLastSession()
        if pendingEditModeURL == fileURL.standardizedFileURL {
            pendingEditModeURL = nil
            let entry = pendingEditModeAppendedEntry
            pendingEditModeAppendedEntry = nil
            enterEditMode(autofocus: entry != nil, appendingEntry: entry)
        }
    }

    private func applyLoadFailure(error: NSError, fileURL: URL, silentOnFailure: Bool) {
        if pendingEditModeURL == fileURL.standardizedFileURL {
            pendingEditModeURL = nil
            dismissEditChrome()
        }
        guard !silentOnFailure else { return }
        NSAlert(error: error).beginSheetModal(for: documentWindow)
    }

    func renderCurrentDocument(text: String, fileURL: URL?) {
        let documentID = fileURL?.standardizedFileURL.absoluteString
            ?? markdownDocument?.untitledDocumentID
            ?? untitledDocumentID
        (documentWindow.contentViewController as? MainSplitViewController)?
            .display(markdown: text,
                     showsPreview: fileURL.map(FileKind.classify) != .text,
                     fileName: fileURL?.lastPathComponent
                         ?? NSLocalizedString("Untitled", comment: "Untitled document name"),
                     url: fileURL,
                     assetBaseURL: fileURL?.deletingLastPathComponent(),
                     documentID: documentID)
    }
}
