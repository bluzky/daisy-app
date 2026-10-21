//
//  DocumentWindowController+Workspace.swift
//  daisy
//
//  A workspace window is a folder window whose folder has a workspace
//  marker. The window decides membership, never a file's location: only the
//  window's own folder is checked. A window opened on a file is one only
//  when it inherits the workspace from an open workspace window it joins.
//

import Cocoa

extension DocumentWindowController {
    /// The workspace this window's documents get suggestions from, or nil.
    var indexedWorkspaceRootURL: URL? { isWorkspace ? folderRootURL : nil }

    /// Re-reads the marker, so one added or deleted outside Daisy counts.
    func refreshWorkspaceState() {
        isWorkspace = folderRootURL.map(WorkspaceMarker.isWorkspace(root:)) ?? false
    }

    /// Takes the folder and workspace of the window this one was opened from.
    func inheritWorkspace(from source: DocumentWindowController) {
        folderRootURL = source.folderRootURL
        isWorkspace = source.isWorkspace
    }

    static func refreshWorkspaceStates(onRoot root: URL? = nil) {
        for controller in NSDocumentController.shared.documents
            .flatMap(\.windowControllers)
            .compactMap({ $0 as? DocumentWindowController })
        where root == nil || controller.folderRootURL == root {
            controller.refreshWorkspaceState()
        }
        NotificationCenter.default.post(name: WorkspaceMarker.didChangeNotification, object: nil)
    }

    @objc func initializeWorkspace(_ sender: Any?) {
        guard let root = folderRootURL, !isWorkspace else {
            NSSound.beep()
            return
        }
        do {
            try WorkspaceMarker.initialize(root: root)
        } catch {
            NSAlert(error: error).beginSheetModal(for: documentWindow)
        }
        Self.refreshWorkspaceStates(onRoot: root)
    }

    @objc func removeWorkspace(_ sender: Any?) {
        guard let root = indexedWorkspaceRootURL else {
            NSSound.beep()
            return
        }
        do {
            try WorkspaceMarker.remove(root: root)
            WorkspaceMetadataIndex.discardCache(root: root)
        } catch {
            NSAlert(error: error).beginSheetModal(for: documentWindow)
        }
        Self.refreshWorkspaceStates(onRoot: root)
    }

    /// Indexes the workspace again from nothing, replacing its cache file.
    @objc func rebuildWorkspaceIndex(_ sender: Any?) {
        guard let root = indexedWorkspaceRootURL else {
            NSSound.beep()
            return
        }
        WorkspaceMetadataIndex.rebuildCache(root: root)
    }

    // MARK: - Index

    /// Binds this window to the shared index for its workspace, or lets go
    /// of it when the window stops being a workspace window.
    func updateWorkspaceIndexBinding() {
        let root = indexedWorkspaceRootURL.map(WorkspaceMetadataIndex.canonicalRoot)
        guard root != workspaceIndex?.root else { return }
        releaseWorkspaceIndex()
        guard let root else {
            // Names from the old workspace must not linger in the editor.
            if workspaceCandidates != nil { applyWorkspaceCandidates(.empty()) }
            return
        }
        let index = WorkspaceMetadataIndex.acquire(root: root)
        workspaceIndex = index
        workspaceSnapshotTask = Task { [weak self] in
            for await snapshot in await index.snapshots() {
                self?.applyWorkspaceCandidates(snapshot)
            }
        }
        if hasUnsavedEditorChanges { scheduleWorkspaceOverlay() }
    }

    func releaseWorkspaceIndex() {
        restoreWorkspaceOverlay()
        workspaceSnapshotTask?.cancel()
        workspaceSnapshotTask = nil
        if let index = workspaceIndex {
            WorkspaceMetadataIndex.release(index)
        }
        workspaceIndex = nil
    }

    private func applyWorkspaceCandidates(_ snapshot: WorkspaceMetadataSnapshot) {
        workspaceCandidates = snapshot
        mainSplit?.editorViewController?.setWorkspaceCandidates(snapshot)
    }

    /// Hands the editor's unsaved text to the index shortly after typing
    /// stops, so other windows on the workspace see its names. This window's
    /// own editor already reads them from its buffer.
    func scheduleWorkspaceOverlay() {
        guard workspaceIndex != nil, !isCodeFile else { return }
        workspaceOverlayWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let editor = self.mainSplit?.editorViewController else { return }
            editor.fetchMarkdown { [weak self] markdown in
                guard let self, let markdown, self.hasUnsavedEditorChanges,
                      let index = self.workspaceIndex, let url = self.currentFileURL else { return }
                if let previous = self.workspaceOverlayURL, previous != url {
                    self.restoreWorkspaceOverlay()
                }
                self.workspaceOverlayURL = url
                let owner = self.workspaceOverlayOwner
                self.enqueueWorkspaceIndexUpdate { await index.setOverlay(markdown, for: url, owner: owner) }
            }
        }
        workspaceOverlayWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// Takes this window's unsaved text out of the index; the file on disk
    /// counts again, saved or not.
    func restoreWorkspaceOverlay() {
        workspaceOverlayWork?.cancel()
        workspaceOverlayWork = nil
        guard let url = workspaceOverlayURL, let index = workspaceIndex else { return }
        workspaceOverlayURL = nil
        let owner = workspaceOverlayOwner
        enqueueWorkspaceIndexUpdate { await index.restoreDiskContribution(for: url, owner: owner) }
    }

    private func enqueueWorkspaceIndexUpdate(_ update: @escaping @Sendable () async -> Void) {
        let previous = workspaceIndexUpdates
        workspaceIndexUpdates = Task {
            await previous?.value
            await update()
        }
    }

    func validateWorkspaceMenuItem(_ menuItem: NSMenuItem) -> Bool? {
        switch menuItem.action {
        case #selector(initializeWorkspace(_:)):
            return folderRootURL != nil && !isWorkspace
        case #selector(removeWorkspace(_:)):
            return isWorkspace
        case #selector(rebuildWorkspaceIndex(_:)):
            return workspaceIndex != nil
        default:
            return nil
        }
    }
}
