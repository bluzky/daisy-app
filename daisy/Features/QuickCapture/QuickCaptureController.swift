//
//  QuickCaptureController.swift
//  daisy
//
//  Owns the global hotkey and what it does: open `Inbox.md` in the main app,
//  in edit mode, with a fresh dated heading at the end and the cursor under it.
//

import Cocoa

@MainActor
final class QuickCaptureController {
    static let shared = QuickCaptureController()

    private init() {
        QuickCaptureHotKey.shared.onTrigger = { [weak self] in self?.openInbox() }
    }

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: QuickCaptureSetting.enabledDefaultsKey)
    }

    /// Registers or releases the global hotkey to match the stored setting.
    /// Returns false when the shortcut is enabled but couldn't be claimed.
    @discardableResult
    func applyEnabledSetting() -> Bool {
        guard Self.isEnabled else {
            QuickCaptureHotKey.shared.unregister()
            return true
        }
        return QuickCaptureHotKey.shared.register(QuickCaptureShortcut.current())
    }

    /// Opens the inbox, asking for a capture folder first if none is set.
    func openInbox() {
        if !QuickCaptureStore.hasFolder {
            guard QuickCaptureStore.chooseFolder() else { return }
        }
        let url: URL
        do {
            url = try QuickCaptureStore.inboxURL()
        } catch {
            NSAlert(error: error).runModal()
            return
        }
        let entry = QuickCaptureSetting.newEntry(at: Date())
        NSApp.activate(ignoringOtherApps: true)
        // Returns the existing document when the inbox is already open.
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { document, _, error in
            if let error {
                NSAlert(error: error).runModal()
                return
            }
            guard let controller = document?.windowControllers.first as? DocumentWindowController else { return }
            if controller.isEditing {
                // Already editing: add the entry to the live buffer so nothing
                // typed so far is lost, and show that window.
                controller.window?.makeKeyAndOrderFront(nil)
                controller.mainSplit?.editorViewController?.focusEditor(appendingEntry: entry)
            } else if controller.currentMarkdown != nil {
                controller.enterEditMode(autofocus: true, appendingEntry: entry)
            } else {
                // Still loading; the loader enters edit mode once the text arrives.
                controller.pendingEditModeAppendedEntry = entry
                controller.pendingEditModeURL = url.standardizedFileURL
            }
        }
    }
}
