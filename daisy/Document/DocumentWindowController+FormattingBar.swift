//
//  DocumentWindowController+FormattingBar.swift
//  daisy
//
//  Edit-mode commands: Insert menu actions and Save.
//

import Cocoa

extension DocumentWindowController {
    // MARK: Insert

    /// Insert > Image: asks for a file and inserts it at the editor selection.
    func insertImageFromMenu() {
        guard isEditing, let editor = mainSplit?.editorViewController else { return }
        editor.fetchLinkSelection { [weak self] selection in
            guard let selection else { return }
            self?.pickImage(at: selection.from, replacing: selection.to)
        }
    }

    /// Insert > Code Block: wraps the current block in an empty fenced block.
    func insertCodeBlockFromMenu() {
        guard isEditing else { return }
        mainSplit?.editorViewController?.setBlockStyle("fenced", language: "")
    }

    /// Insert > Table: turns the current block into a table.
    func insertTableFromMenu() {
        guard isEditing else { return }
        mainSplit?.editorViewController?.setBlockStyle("table", language: "")
    }


    /// Leaves edit-mode chrome: refreshes the toolbar pencil state.
    func dismissEditChrome() {
        updateEditToolbarItem()
    }

    /// File > Save (⌘S): save pending edits in either mode without switching modes.
    /// Intercepts the responder chain ahead of MarkdownDocument, whose
    /// NSDocument save machinery stays disabled.
    @IBAction func saveDocument(_ sender: Any?) {
        guard isEditing || hasPendingEditorChanges else {
            NSSound.beep()
            return
        }
        commitEdits(exitAfter: false)
    }
}
