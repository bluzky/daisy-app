//
//  DocumentWindowController+HideCompletedTasks.swift
//  daisy
//
//  View ▸ Hide Completed Tasks and its menu validation.
//

import Cocoa

extension DocumentWindowController {
    private static var hideCompletedTasksExtensionID: String {
        MarkdownHTML.HideCompletedTasksExtension().id
    }

    /// The setting is app-wide, so the toggle goes through the app delegate
    /// and every open window follows.
    @objc func toggleHideCompletedTasks(_ sender: Any?) {
        (NSApp.delegate as? AppDelegate)?.applyHideCompletedTasksSetting(!HideCompletedTasksSetting.isEnabled)
    }

    /// Takes the current setting: called on every open window when it
    /// changes, and once on a window being created.
    func applyHideCompletedTasksSetting() {
        mainSplit?.setExtensionHostState(HideCompletedTasksSetting.isEnabled,
                                         for: Self.hideCompletedTasksExtensionID)
        refreshHideCompletedTasksItem()
    }

    /// Unavailable while the extension is off in Settings, which shows every task.
    private var isHideCompletedTasksAvailable: Bool {
        RenderExtensionPreferences.currentConfiguration.isEnabled(Self.hideCompletedTasksExtensionID)
    }

    func validateHideCompletedTasksMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let isHiding = isHideCompletedTasksAvailable && HideCompletedTasksSetting.isEnabled
        menuItem.state = isHiding ? .on : .off
        menuItem.image = Self.hideCompletedTasksImage(isHiding: isHiding)
        return isHideCompletedTasksAvailable
    }

    /// The toolbar toggle follows the setting and the extension's Settings
    /// toggle; called when either changes.
    func refreshHideCompletedTasksItem() {
        let isAvailable = isHideCompletedTasksAvailable
        hideCompletedTasksItem?.isEnabled = isAvailable
        hideCompletedTasksButton?.isEnabled = isAvailable
        let isHiding = isAvailable && HideCompletedTasksSetting.isEnabled
        hideCompletedTasksButton?.state = isHiding ? .on : .off
        hideCompletedTasksButton?.image = Self.hideCompletedTasksImage(isHiding: isHiding)
    }
}
