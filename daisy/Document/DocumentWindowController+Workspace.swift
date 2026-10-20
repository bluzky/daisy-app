//
//  DocumentWindowController+Workspace.swift
//  daisy
//
//  A workspace window is a folder window whose folder has a workspace
//  marker. The window decides membership, never a file's location: only the
//  window's own folder is checked, and a window opened on a file never
//  becomes one.
//

import Cocoa

extension DocumentWindowController {
    /// The workspace this window's documents get suggestions from, or nil.
    var workspaceRootURL: URL? { isWorkspace ? folderRootURL : nil }

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
        guard let root = workspaceRootURL else {
            NSSound.beep()
            return
        }
        do {
            try WorkspaceMarker.remove(root: root)
        } catch {
            NSAlert(error: error).beginSheetModal(for: documentWindow)
        }
        Self.refreshWorkspaceStates(onRoot: root)
    }

    func validateWorkspaceMenuItem(_ menuItem: NSMenuItem) -> Bool? {
        switch menuItem.action {
        case #selector(initializeWorkspace(_:)):
            return folderRootURL != nil && !isWorkspace
        case #selector(removeWorkspace(_:)):
            return isWorkspace
        default:
            return nil
        }
    }
}
