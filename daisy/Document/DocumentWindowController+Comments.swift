//
//  DocumentWindowController+Comments.swift
//  daisy
//
//  Edit ▸ Copy Comments for AI, and the Comments panel's toolbar button,
//  View menu item and edits.
//

import Cocoa

extension DocumentWindowController {

    /// Puts a plain-text brief of every comment on the pasteboard: line,
    /// highlighted text and note, ready to paste into a prompt. It reads the
    /// text as it is now: while editing, the editor's buffer, unsaved edits
    /// included, not the last saved text.
    @objc func copyCommentsForAI(_ sender: Any?) {
        currentSourceMarkdown { [weak self] markdown in
            guard let self else { return }
            let comments = markdown.map(MarkdownComments.comments(in:)) ?? []
            guard !comments.isEmpty else {
                NSSound.beep()
                return
            }
            let brief = MarkdownComments.brief(for: comments, fileName: self.currentFileURL?.lastPathComponent)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(brief, forType: .string)
        }
    }

    /// Menu validation cannot wait for the editor's buffer, and the saved text
    /// is not what the editor holds, so while editing the item stays available
    /// and Copy itself beeps if there turns out to be nothing to copy. Outside
    /// editing it is available only while the document has a comment.
    func validateCopyCommentsMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if isEditing { return true }
        return currentMarkdown.map { !MarkdownComments.comments(in: $0).isEmpty } ?? false
    }

    // MARK: - Comments panel

    /// Wires the panel to this window. Safe to call again.
    func configureCommentsPanel() {
        mainSplit?.setCommentAddedHandler { [weak self] selection, note in
            self?.addCommentInReadMode(note: note, selection: selection)
        }
        mainSplit?.setCommentClickedHandler { [weak self] index in
            guard let self, self.isCommentsVisible else { return }
            self.mainSplit?.commentsViewController?.store.reveal(index)
        }
        guard let store = mainSplit?.commentsViewController?.store else { return }
        store.onJump = { [weak self] line in self?.mainSplit?.scrollToTaskLine(line) }
        store.onCopy = { [weak self] in self?.copyCommentsForAI(nil) }
        store.onResolve = { [weak self] index, snapshot in
            self?.applyCommentEdit(snapshot: snapshot) { MarkdownComments.resolveEdit(commentAt: index, in: $0) }
        }
        store.onReply = { [weak self] index, note, snapshot in
            self?.applyCommentEdit(snapshot: snapshot) {
                MarkdownComments.replyEdit(toCommentAt: index, note: note, in: $0)
            }
        }
    }

    /// The document's text as it is now: the editor buffer while editing.
    func currentSourceMarkdown(_ completion: @escaping (String?) -> Void) {
        if isEditing, let editor = mainSplit?.editorViewController {
            editor.fetchMarkdown(completion)
        } else {
            completion(currentMarkdown)
        }
    }

    func refreshCommentsPanel() {
        currentSourceMarkdown { [weak self] markdown in
            self?.mainSplit?.commentsViewController?.setMarkdown(markdown)
        }
    }

    /// Applies one change to a comment. `snapshot` is the text the panel's
    /// list was read from: when the document has moved on, nothing changes
    /// and the list catches up instead, so a click never lands on another
    /// comment.
    private func applyCommentEdit(snapshot: String,
                                  _ makeEdit: @escaping (String) -> MarkdownComments.Edit?) {
        currentSourceMarkdown { [weak self] current in
            guard let self, let current else { return }
            guard current == snapshot, let edit = makeEdit(current) else {
                NSSound.beep()
                self.mainSplit?.commentsViewController?.setMarkdown(current)
                return
            }
            if self.isEditing, let editor = self.mainSplit?.editorViewController {
                // The editor's change notification refreshes the panel.
                editor.replaceRange(edit.replacement, from: edit.range.lowerBound, to: edit.range.upperBound)
            } else {
                self.saveReadModeMarkdown(edit.applied(to: current), baseline: current) { [weak self] saved in
                    if saved == nil { self?.refreshCommentsPanel() }
                }
            }
        }
    }

    // MARK: Toggle

    var isCommentsVisible: Bool {
        (documentWindow.contentViewController as? MainSplitViewController)?.isCommentsVisible ?? false
    }

    @objc func toggleCommentsAction(_ sender: Any) {
        configureCommentsPanel()
        let isVisible = (documentWindow.contentViewController as? MainSplitViewController)?
            .toggleRightPanel(.comments) ?? false
        if isVisible { refreshCommentsPanel() }
        refreshRightPanelToggleItems()
    }

    /// View ▸ Comments: the same toggle as the toolbar button.
    func toggleCommentsFromMenu() {
        toggleCommentsAction(self)
    }

    func refreshCommentsToggleItem() {
        isCommentsToggleSelected = isCommentsVisible
        commentsButton?.state = isCommentsToggleSelected ? .on : .off
    }

    func makeCommentsItem(willBeInsertedIntoToolbar: Bool) -> NSToolbarItem {
        let label = NSLocalizedString("Comments", comment: "Comments toolbar item label")
        let image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: label) ?? NSImage()
        image.isTemplate = true
        let (item, button) = makeToggleButtonItem(
            identifier: .comments,
            image: image,
            label: label,
            action: #selector(toggleCommentsAction(_:))
        )
        item.autovalidates = false
        item.toolTip = NSLocalizedString("Show comments", comment: "Comments toolbar item tooltip")
        button.toolTip = item.toolTip
        if willBeInsertedIntoToolbar {
            commentsItem = item
            commentsButton = button
            refreshCommentsToggleItem()
        } else {
            button.state = isCommentsToggleSelected ? .on : .off
        }
        return item
    }

    private static let didAddCommentsItemKey = "Toolbar.DidAddComments"

    /// One-time addition of the Comments button to a toolbar that already
    /// exists, after References (or the Agenda), as for References.
    func addCommentsToolbarItemIfNeeded() {
        insertToolbarItemOnce(.comments, key: Self.didAddCommentsItemKey) { identifiers in
            identifiers.firstIndex(of: .references).map { $0 + 1 }
                ?? identifiers.firstIndex(of: .tasks).map { $0 + 1 }
                ?? identifiers.firstIndex(of: .share) ?? identifiers.count
        }
    }

    // MARK: - Add Comment in Read mode

    /// Read mode can comment on a saved Markdown file while comments are on.
    private var canCommentInReadMode: Bool {
        !isEditing && !isCodeFile && currentFileURL != nil && currentMarkdown != nil
            && RenderExtensionPreferences.currentConfiguration.isEnabled(MarkdownHTML.CommentsExtension().id)
    }

    /// The page's comment bubble sent a note for the text selected on it:
    /// write the comment into the file at that text.
    func addCommentInReadMode(note: String, selection: MarkdownComments.PageSelection) {
        guard canCommentInReadMode, let baseline = currentMarkdown,
              let edit = MarkdownComments.addEdit(note: note, selection: selection, in: baseline) else {
            NSSound.beep()
            return
        }
        saveReadModeMarkdown(edit.applied(to: baseline), baseline: baseline) { [weak self] saved in
            if saved == nil { self?.refreshCommentsPanel() }
        }
    }
}
