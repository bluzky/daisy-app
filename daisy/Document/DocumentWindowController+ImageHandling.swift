//
//  DocumentWindowController+ImageHandling.swift
//  Daisy
//

import AppKit
import UniformTypeIdentifiers

extension DocumentWindowController {
    /// Images or files going into the editor, from the clipboard or the picker.
    private struct ImageInsertion {
        enum Origin { case pasted, pastedFiles, droppedFiles, picked }

        let origin: Origin
        let markdownURL: URL
        let editor: EditorViewController
        let from: Int
        let to: Int
        /// Produces the files to link. `isNew` marks a file created for this
        /// insertion, which is removed again if the editor rejects the text.
        let obtain: () throws -> [(url: URL, isNew: Bool)]

        var placementError: String {
            switch origin {
            case .pasted:
                NSLocalizedString(
                    "The pasted image could not be placed next to the Markdown file.",
                    comment: "Image paste destination error"
                )
            case .pastedFiles:
                NSLocalizedString(
                    "The pasted files could not be placed next to the Markdown file.",
                    comment: "File paste destination error"
                )
            case .droppedFiles:
                NSLocalizedString(
                    "The dropped files could not be placed next to the Markdown file.",
                    comment: "File drop destination error"
                )
            case .picked:
                NSLocalizedString(
                    "The image could not be placed next to the Markdown file.",
                    comment: "Image insert destination error"
                )
            }
        }

        var insertionError: String {
            switch origin {
            case .pasted:
                NSLocalizedString(
                    "The pasted image could not be inserted into the document.",
                    comment: "Image paste insertion error"
                )
            case .pastedFiles:
                NSLocalizedString(
                    "The pasted files could not be inserted into the document.",
                    comment: "File paste insertion error"
                )
            case .droppedFiles:
                NSLocalizedString(
                    "The dropped files could not be inserted into the document.",
                    comment: "File drop insertion error"
                )
            case .picked:
                NSLocalizedString(
                    "The image could not be inserted into the document.",
                    comment: "Image insert insertion error"
                )
            }
        }

        var permissionMessage: String {
            switch origin {
            case .pasted:
                NSLocalizedString(
                    "Choose the folder containing this Markdown file to save the pasted image.",
                    comment: "Image paste permission message"
                )
            case .pastedFiles:
                NSLocalizedString(
                    "Choose the folder containing this Markdown file to save the pasted files.",
                    comment: "File paste permission message"
                )
            case .droppedFiles:
                NSLocalizedString(
                    "Choose the folder containing this Markdown file to save the dropped files.",
                    comment: "File drop permission message"
                )
            case .picked:
                NSLocalizedString(
                    "Choose the folder containing this Markdown file to save the image.",
                    comment: "Image insert permission message"
                )
            }
        }
    }

    /// Files copied in Finder are linked like picked ones — copied into the
    /// assets folder unless already inside the document's folder — so the
    /// original bytes are kept instead of Finder's icon rendition. Images
    /// become image Markdown, any other file a plain link. Raw image data
    /// (screenshots, images copied from apps) is saved as a numbered PNG.
    func pasteImage(at from: Int, replacing to: Int) {
        guard isEditing,
              let markdownURL = currentFileURL,
              let editor = mainSplit?.editorViewController else { return }

        let files = clipboardFileURLs()
        if !files.isEmpty {
            insertImage(ImageInsertion(
                origin: .pastedFiles,
                markdownURL: markdownURL,
                editor: editor,
                from: from,
                to: to,
                obtain: { try Self.placeFiles(files, forMarkdownFile: markdownURL) }
            ))
            return
        }

        guard let data = clipboardPNGData() else {
            presentImageError(
                NSError(domain: "MarkdownPreview.ImagePaste", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: NSLocalizedString(
                        "The clipboard does not contain an image or file.",
                        comment: "Image paste error"
                    )
                ])
            )
            return
        }

        insertImage(ImageInsertion(
            origin: .pasted,
            markdownURL: markdownURL,
            editor: editor,
            from: from,
            to: to,
            obtain: { [(try MarkdownAssetResolution.savePastedImage(data, forMarkdownFile: markdownURL), true)] }
        ))
    }

    /// Files dragged from the Files sidebar and dropped at `position`, placed
    /// and linked exactly as pasted ones are.
    func insertDroppedFiles(_ files: [URL], at position: Int) {
        guard isEditing,
              let markdownURL = currentFileURL,
              let editor = mainSplit?.editorViewController else {
            NSSound.beep()
            return
        }
        insertImage(ImageInsertion(
            origin: .droppedFiles,
            markdownURL: markdownURL,
            editor: editor,
            from: position,
            to: position,
            obtain: { try Self.placeFiles(files, forMarkdownFile: markdownURL) }
        ))
    }

    /// Links files inside the document's folder in place and copies the rest
    /// into the assets folder. A failure removes the copies already made.
    private static func placeFiles(_ files: [URL],
                                   forMarkdownFile markdownURL: URL) throws -> [(url: URL, isNew: Bool)] {
        var placed: [(url: URL, isNew: Bool)] = []
        do {
            for file in files {
                if MarkdownAssetResolution.isInsideFolder(file, ofMarkdownFile: markdownURL) {
                    placed.append((file, false))
                } else {
                    placed.append((try MarkdownAssetResolution.importFile(
                        from: file,
                        forMarkdownFile: markdownURL
                    ), true))
                }
            }
        } catch {
            for (url, isNew) in placed where isNew {
                try? FileManager.default.removeItem(at: url)
            }
            throw error
        }
        return placed
    }

    /// `/image` in the editor: choose a file, then insert it like a paste.
    /// An image already inside the document's folder is linked in place;
    /// anything else is copied into the assets folder.
    func pickImage(at from: Int, replacing to: Int) {
        guard isEditing,
              let markdownURL = currentFileURL,
              let editor = mainSplit?.editorViewController else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.message = NSLocalizedString("Choose an image to insert.", comment: "Image picker message")
        panel.beginSheetModal(for: documentWindow) { [weak self] response in
            guard let self, response == .OK, let chosen = panel.url else { return }
            self.insertImage(ImageInsertion(
                origin: .picked,
                markdownURL: markdownURL,
                editor: editor,
                from: from,
                to: to,
                obtain: {
                    if MarkdownAssetResolution.isInsideFolder(chosen, ofMarkdownFile: markdownURL) {
                        return [(chosen, false)]
                    }
                    return [(try MarkdownAssetResolution.importFile(
                        from: chosen,
                        forMarkdownFile: markdownURL
                    ), true)]
                }
            ))
        }
    }

    private func insertImage(_ insertion: ImageInsertion) {
        do {
            try performInsertion(insertion)
        } catch {
            presentImagePermissionPanel(insertion)
        }
    }

    private func performInsertion(_ insertion: ImageInsertion) throws {
        let files = try insertion.obtain()
        let removeNewFiles = {
            for (url, isNew) in files where isNew {
                try? FileManager.default.removeItem(at: url)
            }
        }
        let links = files.compactMap { file in
            Self.isImageFile(file.url)
                ? MarkdownAssetResolution.imageMarkdown(for: file.url, from: insertion.markdownURL)
                : MarkdownAssetResolution.fileLinkMarkdown(for: file.url, from: insertion.markdownURL)
        }
        guard !links.isEmpty, links.count == files.count else {
            removeNewFiles()
            throw NSError(domain: "MarkdownPreview.ImagePaste",
                          code: 2,
                          userInfo: [NSLocalizedDescriptionKey: insertion.placementError])
        }
        insertion.editor.insertMarkdown(
            links.joined(separator: "\n"),
            from: insertion.from,
            to: insertion.to
        ) { [weak self] inserted in
            guard inserted else {
                removeNewFiles()
                self?.presentImageError(
                    NSError(domain: "MarkdownPreview.ImagePaste",
                            code: 4,
                            userInfo: [NSLocalizedDescriptionKey: insertion.insertionError])
                )
                return
            }
            guard let self else { return }
            self.hasUnsavedEditorChanges = true
            self.commitEdits(exitAfter: false)
        }
    }

    private func presentImagePermissionPanel(_ insertion: ImageInsertion) {
        let parentDirectory = insertion.markdownURL.deletingLastPathComponent().standardizedFileURL
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = parentDirectory
        panel.message = insertion.permissionMessage
        panel.beginSheetModal(for: documentWindow) { [weak self] response in
            guard let self, response == .OK, let chosen = panel.url else { return }
            guard chosen.standardizedFileURL == parentDirectory else {
                self.presentImageError(
                    NSError(domain: "MarkdownPreview.ImagePaste",
                            code: 3,
                            userInfo: [NSLocalizedDescriptionKey: NSLocalizedString(
                                "Choose the folder containing this Markdown file.",
                                comment: "Image paste folder validation error"
                            )])
                )
                return
            }
            do {
                try self.performInsertion(insertion)
            } catch {
                self.presentImageError(error)
            }
        }
    }

    private static func isImageFile(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
    }

    /// Regular files on the clipboard, as Finder's Copy puts them there.
    /// Folders are skipped: copying a whole tree on paste is never intended.
    private func clipboardFileURLs() -> [URL] {
        let urls = NSPasteboard.general.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        return urls.filter {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
        }
    }

    private func clipboardPNGData() -> Data? {
        let pasteboard = NSPasteboard.general
        if let data = pasteboard.data(forType: .png) {
            return data
        }
        if let tiff = pasteboard.data(forType: .tiff),
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            return png
        }
        if let image = NSImage(pasteboard: pasteboard),
           let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff) {
            return bitmap.representation(using: .png, properties: [:])
        }
        return nil
    }

    private func presentImageError(_ error: Error) {
        NSAlert(error: error).beginSheetModal(for: documentWindow)
    }

    func renameImage(at imageURL: URL) {
        guard !isEditorCommitInFlight else {
            commitEdits(exitAfter: false) { [weak self] success in
                guard success else { return }
                self?.renameImage(at: imageURL)
            }
            return
        }
        guard let markdownURL = currentFileURL else { return }
        let renameableDirectories = [
            MarkdownAssetResolution.assetsDirectory(forMarkdownFile: markdownURL),
            MarkdownAssetResolution.legacyPicturesDirectory(forMarkdownFile: markdownURL),
        ].map(\.standardizedFileURL)
        guard renameableDirectories.contains(imageURL.standardizedFileURL.deletingLastPathComponent()),
              FileManager.default.fileExists(atPath: imageURL.path) else { return }

        let presentRename: (String) -> Void = { [weak self] markdown in
            guard let self else { return }
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("Rename Image", comment: "Image rename alert title")
            alert.informativeText = NSLocalizedString(
                "Choose a new name for this image.",
                comment: "Image rename alert message"
            )
            let field = NSTextField(string: imageURL.deletingPathExtension().lastPathComponent)
            field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
            alert.accessoryView = field
            alert.addButton(withTitle: NSLocalizedString("Rename", comment: "Image rename button"))
            alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Alert button"))
            alert.window.initialFirstResponder = field
            alert.beginSheetModal(for: self.documentWindow) { [weak self] response in
                guard let self, response == .alertFirstButtonReturn else { return }
                self.applyImageRename(
                    imageURL,
                    newName: field.stringValue,
                    markdownURL: markdownURL,
                    markdown: markdown
                )
            }
        }

        if let editor = mainSplit?.editorViewController {
            editor.fetchMarkdown { markdown in
                guard let markdown else { return }
                presentRename(markdown)
            }
        } else if let markdown = currentMarkdown {
            presentRename(markdown)
        }
    }

    private func applyImageRename(_ imageURL: URL,
                                  newName: String,
                                  markdownURL: URL,
                                  markdown: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("/"),
              !trimmed.contains("\\") else {
            NSSound.beep()
            return
        }
        let extensionName = imageURL.pathExtension
        let enteredExtension = URL(fileURLWithPath: trimmed).pathExtension
        guard enteredExtension.isEmpty
                || enteredExtension.caseInsensitiveCompare(extensionName) == .orderedSame else {
            NSSound.beep()
            return
        }
        let fileName = enteredExtension.isEmpty
            ? "\(trimmed).\(extensionName)"
            : trimmed
        let imageDirectory = imageURL.deletingLastPathComponent().standardizedFileURL
        let destination = imageDirectory
            .appendingPathComponent(fileName, isDirectory: false)
        guard destination.standardizedFileURL != imageURL.standardizedFileURL,
              destination.standardizedFileURL.deletingLastPathComponent() == imageDirectory,
              !FileManager.default.fileExists(atPath: destination.path),
              let oldPath = MarkdownAssetResolution.markdownPath(
                for: imageURL,
                from: markdownURL
              ),
              let newPath = MarkdownAssetResolution.markdownPath(
                for: destination,
                from: markdownURL
              ),
              let updated = MarkdownAssetResolution.replacingImagePath(
                in: markdown,
                from: oldPath,
                to: newPath
              ),
              updated != markdown else {
            NSSound.beep()
            return
        }

        do {
            try FileManager.default.moveItem(at: imageURL, to: destination)
        } catch {
            presentImageError(error)
            return
        }

        let diskState = diskFileState(
            for: currentFileURL,
            expectedMarkdown: editorBaselineMarkdown ?? currentMarkdown
        )
        saveEditedMarkdown(updated, diskState: diskState) { [weak self] result in
            guard let self else { return }
            switch result {
            case .saved:
                self.currentMarkdown = updated
                self.markdownDocument?.replaceContents(markdown: updated, fileURL: markdownURL)
                if let editor = self.mainSplit?.editorViewController {
                    editor.replaceMarkdown(updated)
                    self.editorDraftMarkdown = nil
                    self.editorBaselineMarkdown = updated
                    self.editorChangeRevision = 0
                    self.hasUnsavedEditorChanges = false
                }
                self.renderCurrentDocument(text: updated, fileURL: markdownURL)
            case let .reloaded(externalMarkdown):
                self.restoreRenamedImage(from: destination, to: imageURL)
                self.adoptExternalMarkdown(
                    externalMarkdown,
                    editor: self.mainSplit?.editorViewController,
                    exitAfter: false
                )
            case .cancelled:
                self.restoreRenamedImage(from: destination, to: imageURL)
                self.rerenderCurrentPreview()
            }
        }
    }

    private func restoreRenamedImage(from destination: URL, to original: URL) {
        do {
            try FileManager.default.moveItem(at: destination, to: original)
        } catch {
            presentImageError(error)
        }
    }
}
