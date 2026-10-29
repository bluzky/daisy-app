//
//  DocumentWindowController+Move.swift
//  daisy
//
//  `/move` (see docs/technical/move-to-file-proposal.md): the editor hands over the
//  block on the caret's line, OmniSearch picks a Markdown file in the
//  project and a place in it, the block is written there, and only then is
//  it removed from this buffer, as one undo step of its own. A banner says
//  where it went, with Undo, which reverses both files, and Open.
//
//  The target is written the way the Agenda checks a task off:
//
//  - Open in Edit Mode or with unsaved edits: that window's buffer or draft.
//  - Open in Read Mode with nothing unsaved: saved through that window.
//  - Not open: `WorkspaceFileWriter`, only while it still holds what was read.
//
//  A move within this document is a single edit of this buffer.
//

import Cocoa

/// A finished move the banner's Undo button can still reverse.
struct MoveRecord {
    let id: Int
    /// Nil for a move within this document: undoing it is this buffer's own
    /// undo step and nothing else.
    let target: MoveTarget?
}

struct MoveTarget {
    let url: URL
    let relativePath: String
    let root: URL
    let identity: WorkspaceFileWriter.RootIdentity
    let insertion: MarkdownSectionInsertion.Insertion
}

/// How a write into a project file went.
enum ProjectFileEdit<Value> {
    case done(Value)
    /// The file no longer holds what the change was worked out from, or the
    /// change doesn't apply to it any more.
    case changed
    case failed
}

/// The headings the picker last showed, to find the chosen one again in the
/// text the move is made against.
@MainActor
private final class ShownHeadings {
    var headings: [MarkdownSectionInsertion.Heading] = []
}

extension DocumentWindowController {
    /// A saved Markdown document inside a project folder.
    var canMoveBlocks: Bool {
        !isCodeFile && projectRootURL != nil && currentFileURL.map { FileKind.classify($0) == .markdown } == true
    }

    // MARK: - Picking

    func pickMoveTarget(_ request: EditorViewController.MoveRequest) {
        guard canFormatMarkdown, canMoveBlocks, let projectRoot = projectRootURL, let source = currentFileURL,
              documentWindow.attachedSheet == nil, fileSearchPalette == nil else {
            mainSplit?.editorViewController?.forgetMove(id: request.id)
            NSSound.beep()
            return
        }
        // The writer walks from the real folder, refusing symlinks on the way.
        let root = FileSearchResults.resolvedIdentity(projectRoot)
        guard let identity = try? WorkspaceFileWriter.RootIdentity(root: root) else {
            mainSplit?.editorViewController?.forgetMove(id: request.id)
            NSSound.beep()
            return
        }
        dismissMoveBanner()
        let shown = ShownHeadings()
        let palette = FileSearchPanelController(projectRoot: projectRoot, mode: .moveTarget)
        palette.loadMoveSections = { [weak self] url in
            guard let self, let markdown = await self.moveTargetText(url, root: root, identity: identity) else {
                return nil
            }
            var headings = MarkdownSectionInsertion.headings(in: markdown)
            if Self.sameFile(url, source), request.kind == .section {
                // A section can't go into itself.
                headings.removeAll { (request.firstLine...request.lastLine).contains($0.line) }
            }
            shown.headings = headings
            return headings
        }
        palette.onMoveTarget = { [weak self] destination in
            guard let self else { return }
            Task {
                await self.performMove(request, to: destination, shown: shown.headings,
                                       source: source, root: root, identity: identity)
            }
        }
        palette.onDismiss = { [weak self] in self?.fileSearchPalette = nil }
        fileSearchPalette = palette
        palette.present(relativeTo: documentWindow)
    }

    /// The file's text as its window holds it, or as it is on disk.
    private func moveTargetText(_ url: URL, root: URL, identity: WorkspaceFileWriter.RootIdentity) async -> String? {
        if let open = Self.controller(showingWorkspaceFile: url) {
            if let editor = open.mainSplit?.editorViewController { return await editor.markdown() }
            return open.editorDraftMarkdown ?? open.currentMarkdown
        }
        guard let path = Self.projectRelativePath(of: url, root: root) else { return nil }
        let read = await Task.detached(priority: .userInitiated) { () -> Result<Data, Error> in
            Result { try WorkspaceFileWriter.read(relativePath: path, root: root, expectedRootIdentity: identity) }
        }.value
        guard case let .success(data) = read else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Moving

    private func performMove(_ request: EditorViewController.MoveRequest,
                             to destination: FileSearchPanelController.MoveDestination,
                             shown: [MarkdownSectionInsertion.Heading],
                             source: URL, root: URL, identity: WorkspaceFileWriter.RootIdentity) async {
        guard let editor = mainSplit?.editorViewController,
              currentFileURL.map({ Self.sameFile($0, source) }) == true else {
            showMoveBanner(Self.moveFailedMessage, symbol: Self.warningSymbol)
            return
        }
        let target: URL
        var heading: MarkdownSectionInsertion.Heading?
        switch destination {
        case let .file(url, chosen):
            target = url
            heading = chosen
        case let .newFile(relativePath):
            guard FileKind.classify(fileName: relativePath) == .markdown,
                  let url = await createMoveTarget(atRelativePath: relativePath) else {
                editor.forgetMove(id: request.id)
                showMoveBanner(Self.moveFailedMessage, symbol: Self.warningSymbol)
                return
            }
            target = url
        }
        let text = MarkdownSectionInsertion.rebasingLinks(in: request.text, from: source, to: target)
        let place = heading.map { "\(target.lastPathComponent) › \(Self.title(of: $0))" } ?? target.lastPathComponent

        if Self.sameFile(target, source) {
            await moveWithinDocument(request, text: text, heading: heading, shown: shown, editor: editor, place: place)
            return
        }
        guard let relativePath = Self.projectRelativePath(of: target, root: root) else {
            editor.forgetMove(id: request.id)
            showMoveBanner(Self.moveFailedMessage, symbol: Self.warningSymbol)
            return
        }
        let kind = request.kind
        let outcome = await editProjectFile(target, relativePath: relativePath, root: root,
                                            identity: identity) { (markdown: String) -> (String, MarkdownSectionInsertion.Insertion)? in
            guard let placement = Self.placement(for: heading, shown: shown, in: markdown) else { return nil }
            let insertion = MarkdownSectionInsertion.inserting(text, kind: kind, into: markdown, under: placement.heading)
            return (insertion.markdown, insertion)
        }
        switch outcome {
        case .failed:
            editor.forgetMove(id: request.id)
            showMoveBanner(String(format: NSLocalizedString("“%@” couldn’t be changed. Nothing was moved.",
                                                            comment: "Move banner; %@ is the target file"),
                                  target.lastPathComponent), symbol: Self.warningSymbol)
        case .changed:
            editor.forgetMove(id: request.id)
            showMoveBanner(String(format: NSLocalizedString("%@ changed while you chose where to move. Nothing was moved.",
                                                            comment: "Move banner; %@ is the target file"),
                                  target.lastPathComponent), symbol: Self.warningSymbol)
        case let .done(insertion):
            let line = Self.firstLine(of: insertion)
            let open = MoveBannerView.Action(title: NSLocalizedString("Open", comment: "Move banner button")) {
                [weak self] in self?.openMoveTarget(target, line: line)
            }
            guard mainSplit?.editorViewController === editor, await editor.completeMove(id: request.id) else {
                showMoveBanner(String(format: NSLocalizedString("Copied to %@; the original was left in place.",
                                                                comment: "Move banner; %@ is where the block went"),
                                      place), symbol: Self.warningSymbol, actions: [open])
                return
            }
            showMoveBanner(String(format: NSLocalizedString("Moved to %@", comment: "Move banner; %@ is where the block went"),
                                  place), actions: [undoAction, open])
            moveRecord = MoveRecord(id: request.id, target: MoveTarget(url: target, relativePath: relativePath, root: root,
                                                                       identity: identity, insertion: insertion))
        }
    }

    /// Takes the block out and puts it back elsewhere in one edit, worked
    /// out from the buffer as `completeMove` would leave it.
    private func moveWithinDocument(_ request: EditorViewController.MoveRequest, text: String,
                                    heading: MarkdownSectionInsertion.Heading?,
                                    shown: [MarkdownSectionInsertion.Heading],
                                    editor: EditorViewController, place: String) async {
        guard let preview = await editor.moveRemovalPreview(id: request.id),
              let placement = Self.placement(for: heading, shown: shown, in: preview.removed) else {
            editor.forgetMove(id: request.id)
            showMoveBanner(Self.moveFailedMessage, symbol: Self.warningSymbol)
            return
        }
        let insertion = MarkdownSectionInsertion.inserting(text, kind: request.kind, into: preview.removed,
                                                           under: placement.heading)
        guard await editor.applyMove(id: request.id, expected: preview.expected, next: insertion.markdown) else {
            showMoveBanner(Self.moveFailedMessage, symbol: Self.warningSymbol)
            return
        }
        showMoveBanner(String(format: NSLocalizedString("Moved to %@", comment: "Move banner; %@ is where the block went"),
                              place), actions: [undoAction])
        moveRecord = MoveRecord(id: request.id, target: nil)
    }

    private func createMoveTarget(atRelativePath relativePath: String) async -> URL? {
        guard let split = mainSplit else { return nil }
        return await withCheckedContinuation { continuation in
            split.createProjectFile(atRelativePath: relativePath) { continuation.resume(returning: $0) }
        }
    }

    private func openMoveTarget(_ url: URL, line: Int) {
        if let existing = Self.controller(showingWorkspaceFile: url) {
            existing.documentWindow.makeKeyAndOrderFront(nil)
            existing.mainSplit?.scrollToTaskLine(line)
            return
        }
        openInNewTab(url) { $0.mainSplit?.scrollToTaskLine(line) }
    }

    // MARK: - Undo

    private var undoAction: MoveBannerView.Action {
        MoveBannerView.Action(title: NSLocalizedString("Undo", comment: "Move banner button")) { [weak self] in
            self?.undoLastMove()
        }
    }

    /// The Undo button: this buffer's undo step for the move, then the copy
    /// taken out of the target. This file goes first, so a failure leaves
    /// the block in both files rather than in neither.
    private func undoLastMove() {
        guard let record = moveRecord, let editor = mainSplit?.editorViewController else { return }
        moveRecord = nil
        removeMoveBanner()
        Task { [weak self] in
            guard let self else { return }
            guard await editor.undoMove(id: record.id) else {
                self.showMoveBanner(NSLocalizedString("This document changed since the move, so it can’t be undone.",
                                                      comment: "Move banner"), symbol: Self.warningSymbol)
                return
            }
            guard let target = record.target else { return }
            let inserted = target.insertion
            let outcome = await self.editProjectFile(target.url, relativePath: target.relativePath,
                                                     root: target.root, identity: target.identity) { markdown in
                MarkdownSectionInsertion.removing(inserted.inserted, at: inserted.offset, from: markdown).map { ($0, ()) }
            }
            if case .done = outcome { return }
            self.showMoveBanner(String(format: NSLocalizedString("%@ was changed since the move; its copy was left in place.",
                                                                 comment: "Move banner; %@ is the target file"),
                                       target.url.lastPathComponent), symbol: Self.warningSymbol)
        }
    }

    /// The buffer changed after move `id`: its Undo button no longer applies.
    func moveBecameStale(_ id: Int) {
        guard moveRecord?.id == id else { return }
        moveRecord = nil
        removeMoveBanner()
    }

    // MARK: - Banner

    func showMoveBanner(_ message: String, symbol: String = "arrow.right.doc.on.clipboard",
                        actions: [MoveBannerView.Action] = []) {
        dismissMoveBanner()
        guard let container = documentWindow.contentView else { return }
        let banner = MoveBannerView(message: message, symbol: symbol, actions: actions)
        banner.onClose = { [weak self] in self?.dismissMoveBanner() }
        banner.show(in: container)
        moveBanner = banner
        // A message with nothing to press goes by itself.
        guard actions.isEmpty else { return }
        Task { [weak self, weak banner] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, let banner, self.moveBanner === banner else { return }
            self.removeMoveBanner()
        }
    }

    /// Closes the banner, and with it the chance to undo the last move.
    func dismissMoveBanner() {
        removeMoveBanner()
        if let record = moveRecord {
            mainSplit?.editorViewController?.forgetMove(id: record.id)
            moveRecord = nil
        }
    }

    private func removeMoveBanner() {
        moveBanner?.removeFromSuperview()
        moveBanner = nil
    }

    // MARK: - Writing project files

    /// Applies `transform` to a project file, in the window that has it open
    /// or on disk; `transform` returns the new text and what to hand back,
    /// or nil when the change no longer applies.
    func editProjectFile<Value>(_ url: URL, relativePath: String, root: URL,
                                identity: WorkspaceFileWriter.RootIdentity,
                                transform: (String) -> (String, Value)?) async -> ProjectFileEdit<Value> {
        if let outcome = await Self.editInOpenWindow(url, transform: transform) { return outcome }
        // Read off the main actor; nothing is written yet.
        let read = await Task.detached(priority: .userInitiated) { () -> Result<Data, Error> in
            Result { try WorkspaceFileWriter.read(relativePath: relativePath, root: root, expectedRootIdentity: identity) }
        }.value
        guard case let .success(data) = read, let markdown = String(data: data, encoding: .utf8) else { return .failed }
        guard let change = transform(markdown) else { return .changed }
        // Opened while it was being read: its window owns the text now.
        if let outcome = await Self.editInOpenWindow(url, transform: transform) { return outcome }
        let updated = change.0
        let written = await Task.detached(priority: .userInitiated) { () -> Result<Bool, Error> in
            Result {
                try WorkspaceFileWriter.replace(relativePath: relativePath, root: root, expected: data, with: updated,
                                                expectedRootIdentity: identity)
            }
        }.value
        switch written {
        case .success(true):
            await workspaceIndex?.recordTaskWrite(markdown: updated, for: url)
            return .done(change.1)
        case .success(false):
            return .changed
        case .failure:
            return .failed
        }
    }

    /// Nil when no window shows the file.
    private static func editInOpenWindow<Value>(_ url: URL,
                                                transform: (String) -> (String, Value)?) async -> ProjectFileEdit<Value>? {
        guard let open = controller(showingWorkspaceFile: url) else { return nil }
        guard await open.settleEditSession() else { return .failed }
        // Settling may have closed the window or moved it to another file.
        guard let settled = controller(showingWorkspaceFile: url) else { return nil }
        return await settled.editOpenDocument(url, transform: transform)
    }

    /// The file is this window's document, with no commit or editor exit
    /// under way.
    private func editOpenDocument<Value>(_ url: URL, transform: (String) -> (String, Value)?) async -> ProjectFileEdit<Value> {
        if let editor = mainSplit?.editorViewController {
            // One undoable edit in the buffer, saved like any other.
            guard let buffer = await editor.markdown(), let change = transform(buffer),
                  await editor.replaceIfUnchanged(expected: buffer, with: change.0) else { return .changed }
            if let index = workspaceIndex { updateTaskOverlay(change.0, url: url, index: index) }
            return .done(change.1)
        }
        if hasPendingEditorChanges, let draft = editorDraftMarkdown ?? currentMarkdown {
            // Read Mode showing an unsaved draft: the change joins the draft.
            guard let change = transform(draft) else { return .changed }
            guard (editorDraftMarkdown ?? currentMarkdown) == draft, hasUnsavedEditorChanges,
                  !isEditorCommitInFlight, !isEditing else { return .changed }
            let next = change.0
            editorDraftMarkdown = next
            currentMarkdown = next
            hasUnsavedEditorChanges = next != editorBaselineMarkdown
            markdownDocument?.replaceContents(markdown: next, fileURL: url)
            renderCurrentDocument(text: next, fileURL: url)
            updateTabEditedIndicator()
            if let index = workspaceIndex { updateTaskOverlay(next, url: url, index: index) }
            return .done(change.1)
        }
        guard let markdown = currentMarkdown, !isEditing, let change = transform(markdown) else { return .changed }
        let saved = await withCheckedContinuation { continuation in
            saveReadModeMarkdown(change.0, baseline: markdown) { continuation.resume(returning: $0) }
        }
        guard let saved else { return .changed }
        await workspaceIndex?.recordTaskWrite(markdown: saved, for: url)
        return .done(change.1)
    }

    // MARK: - Helpers

    private struct Placement {
        let heading: MarkdownSectionInsertion.Heading?
    }

    /// `heading` as it stands in `markdown`: the heading with its title and
    /// level, counted the same way among those the picker showed. Nil when
    /// it is gone; the end of the file is always there.
    private static func placement(for heading: MarkdownSectionInsertion.Heading?,
                                  shown: [MarkdownSectionInsertion.Heading], in markdown: String) -> Placement? {
        guard let heading else { return Placement(heading: nil) }
        let same = { (other: MarkdownSectionInsertion.Heading) in
            other.title == heading.title && other.level == heading.level
        }
        let ordinal = shown.prefix { $0 != heading }.filter(same).count
        let found = MarkdownSectionInsertion.headings(in: markdown).filter(same)
        return ordinal < found.count ? Placement(heading: found[ordinal]) : nil
    }

    /// The 1-based line the moved block starts on in its new file.
    private static func firstLine(of insertion: MarkdownSectionInsertion.Insertion) -> Int {
        let newline = UInt8(ascii: "\n")
        let before = insertion.markdown.utf8.prefix(insertion.offset).filter { $0 == newline }.count
        let leading = insertion.inserted.utf8.prefix { $0 == newline || $0 == UInt8(ascii: "\r") }
            .filter { $0 == newline }.count
        return before + leading + 1
    }

    private static func title(of heading: MarkdownSectionInsertion.Heading) -> String {
        heading.title.isEmpty
            ? NSLocalizedString("Untitled heading", comment: "OmniSearch move mode row for an empty heading")
            : heading.title
    }

    static func projectRelativePath(of url: URL, root: URL) -> String? {
        let base = FileSearchResults.resolvedIdentity(root).pathComponents
        let path = FileSearchResults.resolvedIdentity(url).pathComponents
        guard path.count > base.count, Array(path.prefix(base.count)) == base else { return nil }
        return path.dropFirst(base.count).joined(separator: "/")
    }

    private static func sameFile(_ first: URL, _ second: URL) -> Bool {
        FileSearchResults.resolvedIdentity(first) == FileSearchResults.resolvedIdentity(second)
    }

    private static var moveFailedMessage: String {
        NSLocalizedString("The block couldn’t be moved.", comment: "Move banner")
    }

    private static let warningSymbol = "exclamationmark.triangle"
}
