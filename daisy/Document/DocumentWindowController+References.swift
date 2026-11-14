//
//  DocumentWindowController+References.swift
//  daisy
//
//  What the References panel asks of its window: which file to list
//  references for, and how to open a referring file at its line or reveal
//  it in Files. Opening goes through `openWorkspaceFile`, as the Agenda's
//  tasks do.
//

import Cocoa

extension DocumentWindowController {
    /// Wires the panel to this window. Called whenever the window's
    /// workspace may have changed.
    func configureReferencesSidebar() {
        guard let panel = mainSplit?.referencesViewController else { return }
        // Does nothing when already bound to this index or file.
        panel.bind(index: workspaceIndex)
        panel.setFile(currentFileURL)
        panel.canInitializeWorkspace = folderRootURL != nil && !isWorkspace
        panel.onInitializeWorkspace = { [weak self] in self?.initializeWorkspace(nil) }
        panel.onOpen = { [weak self] path, line, inNewTab in
            self?.openWorkspaceFile(path, line: line, inNewTab: inNewTab)
        }
        panel.onReveal = { [weak self] path in
            guard let self, let url = self.workspaceFileURL(path) else {
                NSSound.beep()
                return
            }
            self.mainSplit?.revealFileInSidebar(url)
        }
    }
}
