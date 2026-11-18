//
//  DocumentWindowController+HiddenFiles.swift
//  daisy
//
//  View ▸ Toggle Hidden Files and its menu validation.
//

import Cocoa

extension DocumentWindowController {
    /// The setting is app-wide, so the toggle goes through the app delegate;
    /// every Files tree follows its notification.
    @objc func toggleHiddenFiles(_ sender: Any?) {
        (NSApp.delegate as? AppDelegate)?.applyShowHiddenFilesSetting(!FileTreeHiddenPatterns.showsHiddenFiles)
    }

    func validateToggleHiddenFilesMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.state = FileTreeHiddenPatterns.showsHiddenFiles ? .on : .off
        return true
    }
}
