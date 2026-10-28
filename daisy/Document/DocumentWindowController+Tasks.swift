//
//  DocumentWindowController+Tasks.swift
//  daisy
//
//  What the Tasks sidebar asks of its window: open a task's file at the
//  task, reveal it in Files, and check it off or back on. A check-off goes
//  one of three ways (see docs/tasks-sidebar-proposal.md):
//
//  - The file is open in Edit Mode or has unsaved edits: the marker is
//    flipped in that window's buffer, and saves with everything else.
//  - The file is open in Read Mode with nothing unsaved: the same path as
//    clicking the checkbox in the preview.
//  - The file is not open: `WorkspaceFileWriter` rewrites it, only while it
//    still holds what was read.
//
//  The index is told straight away after a write, so the list does not
//  flicker; the watcher confirms it when it re-reads the file.
//

import Cocoa

extension DocumentWindowController {
    /// Wires the sidebar's callbacks to this window. Called whenever the
    /// window's workspace may have changed.
    func configureTaskSidebar() {
        guard let sidebar = mainSplit?.taskCalendarViewController else { return }
        // Does nothing when already bound to this index.
        sidebar.bind(index: workspaceIndex)
        sidebar.canInitializeWorkspace = folderRootURL != nil && !isWorkspace
        sidebar.onInitializeWorkspace = { [weak self] in self?.initializeWorkspace(nil) }
        sidebar.onOpenTask = { [weak self] task, inNewTab in self?.openTask(task, inNewTab: inNewTab) }
        sidebar.onRevealTask = { [weak self] task in self?.revealTask(task) }
        sidebar.onSetTaskChecked = { [weak self] task, checked, completion in
            guard let self else {
                completion(Self.taskWriteFailedMessage)
                return
            }
            self.setTaskChecked(task, checked: checked, completion: completion)
        }
    }

    private static var taskWriteFailedMessage: String {
        NSLocalizedString("The task couldn’t be changed.", comment: "Tasks sidebar error")
    }

    private static func taskChangedMessage(_ task: WorkspaceIndexedTask) -> String {
        String(format: NSLocalizedString("%@ changed. Open to check it off.", comment: "Tasks sidebar error"),
               (task.path as NSString).lastPathComponent)
    }

    private func taskURL(_ task: WorkspaceIndexedTask) -> URL? {
        workspaceFileURL(task.path)
    }

    private static func controller(showingTaskFile url: URL) -> DocumentWindowController? {
        controller(showingWorkspaceFile: url)
    }

    // MARK: - Opening

    /// A window that already has the file finds the task in its text, which
    /// may have moved since the index read it.
    func openTask(_ task: WorkspaceIndexedTask, inNewTab: Bool) {
        openWorkspaceFile(task.path, line: task.task.line, inNewTab: inNewTab) { controller in
            controller.scrollToTask(task.task)
        }
    }

    /// Scrolls to the task as this window's text holds it now, or to the
    /// indexed line when it can't be found there.
    private func scrollToTask(_ task: WorkspaceTaskMetadata) {
        let scroll = { [weak self] (markdown: String?) -> Void in
            Task { [weak self] in
                var line = task.line
                if let markdown, let found = await TaskSourceResolver.findConcurrently(task, in: markdown) {
                    line = found.line
                }
                self?.mainSplit?.scrollToTaskLine(line)
            }
        }
        if let editor = mainSplit?.editorViewController {
            editor.fetchMarkdown(scroll)
        } else {
            scroll(currentMarkdown)
        }
    }

    func revealTask(_ task: WorkspaceIndexedTask) {
        guard let url = taskURL(task) else {
            NSSound.beep()
            return
        }
        mainSplit?.revealFileInSidebar(url)
    }

    // MARK: - Checking off

    /// `completion` gets nil once the change is made, or the reason it wasn't.
    func setTaskChecked(_ task: WorkspaceIndexedTask, checked: Bool,
                        completion: @escaping (String?) -> Void) {
        guard let index = workspaceIndex, let url = taskURL(task) else {
            completion(Self.taskWriteFailedMessage)
            return
        }
        // One at a time, so a quick uncheck reads what the check wrote.
        let previous = taskWrites
        taskWrites = Task { [weak self] in
            await previous?.value
            guard let self else {
                completion(Self.taskWriteFailedMessage)
                return
            }
            let error = await self.performTaskWrite(task, checked: checked, url: url, index: index)
            completion(error)
        }
    }

    private func performTaskWrite(_ task: WorkspaceIndexedTask, checked: Bool, url: URL,
                                  index: WorkspaceMetadataIndex) async -> String? {
        if let error = await Self.setTaskCheckedInOpenWindow(task, checked: checked, url: url, index: index) {
            return error
        }
        guard let identity = taskRootIdentity else {
            // Without the identity captured at bind time the writer can't
            // tell the workspace folder from one swapped in at its path.
            return WorkspaceFileWriter.WriterError.rootChanged.localizedDescription
        }
        let root = index.root
        let path = task.path
        // Read off the main actor; nothing is written yet.
        let read = await Task.detached(priority: .userInitiated) { () -> Result<Data, Error> in
            Result { try WorkspaceFileWriter.read(relativePath: path, root: root, expectedRootIdentity: identity) }
        }.value
        guard case let .success(data) = read, let markdown = String(data: data, encoding: .utf8) else {
            return Self.taskWriteFailedMessage
        }
        guard let change = await TaskSourceResolver.settingCheckedConcurrently(checked, task: task.task,
                                                                                in: markdown) else {
            return Self.taskChangedMessage(task)
        }
        guard change.isChange else { return nil }
        // Opened while it was being read: its window owns the text now.
        if let error = await Self.setTaskCheckedInOpenWindow(task, checked: checked, url: url, index: index) {
            return error
        }
        let updated = change.markdown
        let written = await Task.detached(priority: .userInitiated) { () -> Result<Bool, Error> in
            Result {
                try WorkspaceFileWriter.replace(relativePath: path, root: root, expected: data, with: updated,
                                                expectedRootIdentity: identity)
            }
        }.value
        switch written {
        case .success(true):
            await index.recordTaskWrite(markdown: updated, for: url)
            return nil
        case .success(false):
            return Self.taskChangedMessage(task)
        case .failure(let error):
            return error.localizedDescription
        }
    }

    /// Checks the task off in the window showing its file, once that window
    /// has no save or editor exit under way. `.none` when no window shows it,
    /// `.some(nil)` once it is done there, or the reason it wasn't.
    private static func setTaskCheckedInOpenWindow(_ task: WorkspaceIndexedTask, checked: Bool, url: URL,
                                                   index: WorkspaceMetadataIndex) async -> String?? {
        guard let open = controller(showingTaskFile: url) else { return .none }
        guard await open.settleEditSession() else { return .some(taskWriteFailedMessage) }
        // Settling may have closed the window or moved it to another file.
        guard let settled = controller(showingTaskFile: url) else { return .none }
        return .some(await settled.setOpenTaskChecked(task, checked: checked, url: url, index: index))
    }

    /// Waits out a commit in flight and an editor that is closing. Changing
    /// the buffer or draft under either would be overwritten when they
    /// finish. False when the commit failed.
    func settleEditSession() async -> Bool {
        while true {
            if isEditorCommitInFlight {
                let committed = await withCheckedContinuation { continuation in
                    commitEdits(exitAfter: false) { continuation.resume(returning: $0) }
                }
                guard committed else { return false }
            } else if let split = mainSplit, split.isEditorExitInProgress {
                await withCheckedContinuation { continuation in
                    split.afterEditorExit { continuation.resume() }
                }
            } else {
                return true
            }
        }
    }

    /// The task's file is this window's document, with no commit or editor
    /// exit under way.
    private func setOpenTaskChecked(_ task: WorkspaceIndexedTask, checked: Bool, url: URL,
                                    index: WorkspaceMetadataIndex) async -> String? {
        if let editor = mainSplit?.editorViewController {
            return await setTaskCheckedInEditor(editor, task, checked: checked, url: url, index: index)
        }
        if hasPendingEditorChanges, let draft = editorDraftMarkdown ?? currentMarkdown {
            return await setTaskCheckedInDraft(draft, task, checked: checked, url: url, index: index)
        }
        guard let markdown = currentMarkdown,
              let change = await TaskSourceResolver.settingCheckedConcurrently(checked, task: task.task,
                                                                               in: markdown) else {
            return Self.taskChangedMessage(task)
        }
        guard change.isChange else { return nil }
        // The line was found in that text; anything since may have moved it.
        guard currentMarkdown == markdown, !isEditing, !hasPendingEditorChanges else {
            return Self.taskChangedMessage(task)
        }
        let saved = await withCheckedContinuation { continuation in
            toggleTaskCheckbox(onLine: change.line, checked: checked) { continuation.resume(returning: $0) }
        }
        guard let saved else { return Self.taskChangedMessage(task) }
        await index.recordTaskWrite(markdown: saved, for: url)
        return nil
    }

    /// Edit Mode: one undoable edit in the buffer, saved like any other.
    private func setTaskCheckedInEditor(_ editor: EditorViewController, _ task: WorkspaceIndexedTask,
                                        checked: Bool, url: URL, index: WorkspaceMetadataIndex) async -> String? {
        let result = await withCheckedContinuation { continuation in
            editor.setTaskChecked(line: task.task.line, checked: checked, text: task.task.text) {
                continuation.resume(returning: $0)
            }
        }
        guard let result else { return Self.taskChangedMessage(task) }
        if result.changed { updateTaskOverlay(result.markdown, url: url, index: index) }
        return nil
    }

    /// Read Mode showing an unsaved draft: the change joins the draft.
    private func setTaskCheckedInDraft(_ draft: String, _ task: WorkspaceIndexedTask, checked: Bool,
                                       url: URL, index: WorkspaceMetadataIndex) async -> String? {
        guard let change = await TaskSourceResolver.settingCheckedConcurrently(checked, task: task.task,
                                                                                in: draft) else {
            return Self.taskChangedMessage(task)
        }
        guard change.isChange else { return nil }
        // Replacing a draft that moved on, or one a commit or the editor now
        // holds, would lose that work.
        guard (editorDraftMarkdown ?? currentMarkdown) == draft, hasUnsavedEditorChanges,
              !isEditorCommitInFlight, !isEditing else {
            return Self.taskChangedMessage(task)
        }
        editorDraftMarkdown = change.markdown
        currentMarkdown = change.markdown
        hasUnsavedEditorChanges = change.markdown != editorBaselineMarkdown
        markdownDocument?.replaceContents(markdown: change.markdown, fileURL: url)
        renderCurrentDocument(text: change.markdown, fileURL: url)
        updateTabEditedIndicator()
        updateTaskOverlay(change.markdown, url: url, index: index)
        return nil
    }

    /// The new buffer stands in for the file in the index until it is saved
    /// or discarded, so the Agenda keeps the check rather than showing the
    /// saved file's. Typed text never does; the index otherwise follows
    /// saved files. Only when this window counts it in the sidebar's index;
    /// another workspace sees it once it is saved.
    func updateTaskOverlay(_ markdown: String, url: URL, index: WorkspaceMetadataIndex) {
        guard workspaceIndex === index else { return }
        if let previous = workspaceOverlayURL, previous != url { restoreWorkspaceOverlay() }
        workspaceOverlayURL = url
        let owner = workspaceOverlayOwner
        enqueueWorkspaceIndexUpdate { await index.setOverlay(markdown, for: url, owner: owner) }
    }
}
