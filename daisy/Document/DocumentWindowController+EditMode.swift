//
//  DocumentWindowController+EditMode.swift
//  daisy
//
//  Entering and leaving edit mode from the toolbar.
//

import Cocoa

extension DocumentWindowController {
    // MARK: - Edit mode

    var mainSplit: MainSplitViewController? {
        documentWindow.contentViewController as? MainSplitViewController
    }

    var isEditing: Bool {
        mainSplit?.isEditingDocument ?? false
    }

    /// A source or text file: edited as code, with no preview to switch to.
    var isCodeFile: Bool {
        currentFileURL.map(FileKind.classify) == .text
    }

    var canToggleEditMode: Bool {
        !isCodeFile && (isEditing || currentMarkdown != nil)
    }

    var canFormatMarkdown: Bool { isEditing && !isCodeFile }

    func formatMarkdown(_ command: String) {
        guard canFormatMarkdown else { return }
        mainSplit?.editorViewController?.exec(command)
    }

    var hasPendingEditorChanges: Bool {
        hasUnsavedEditorChanges || isEditorCommitInFlight
    }

    func commitPendingEditsForTermination(completion: @escaping (Bool) -> Void) {
        guard isEditing || hasPendingEditorChanges else {
            completion(true)
            return
        }
        requestEndEditing(completion: completion)
    }

    func makeEditItem(willBeInsertedIntoToolbar: Bool) -> NSToolbarItem {
        let edit = NSLocalizedString("Edit", comment: "Edit toolbar item label")
        let image = editToolbarImage(editing: isEditing)

        let (item, button) = makeToggleButtonItem(identifier: .editDocument,
                                                  image: image,
                                                  label: edit,
                                                  action: #selector(toggleEditAction(_:)))
        item.autovalidates = false
        button.setButtonType(.momentaryPushIn)
        button.widthAnchor.constraint(equalToConstant: 30).isActive = true
        button.heightAnchor.constraint(equalToConstant: 30).isActive = true

        if willBeInsertedIntoToolbar {
            editButton = button
        }
        applyEditToolbarState(to: button)
        return item
    }

    func updateEditToolbarItem() {
        guard let editButton else { return }
        applyEditToolbarState(to: editButton)
    }

    private func applyEditToolbarState(to button: NSButton) {
        let editing = isEditing
        button.image = editToolbarImage(editing: editing)
        button.state = .off
        button.toolTip = editing
            ? NSLocalizedString("Stop editing and return to preview", comment: "Edit toolbar item tooltip while editing")
            : NSLocalizedString("Edit document", comment: "Edit toolbar item tooltip")
        button.isEnabled = canToggleEditMode
    }

    private func editToolbarImage(editing: Bool) -> NSImage {
        let symbol = editing ? "play.tv" : "highlighter"
        let description = editing
            ? NSLocalizedString("Preview document", comment: "Edit toolbar play TV image")
            : NSLocalizedString("Edit document", comment: "Edit toolbar highlighter image")
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description) ?? NSImage()
        image.isTemplate = true
        return image
    }

    @objc private func toggleEditAction(_ sender: Any?) {
        toggleEditMode()
    }

    func toggleEditMode() {
        guard !isCodeFile else { return }
        if isEditing {
            previewPendingEdits()
        } else {
            // Enter without placing a caret or selecting the toolbar search
            // field. Clicking the document will focus the editor explicitly.
            window?.makeFirstResponder(nil)
            enterEditMode()
        }
    }
}
