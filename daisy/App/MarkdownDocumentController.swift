//
//  MarkdownDocumentController.swift
//  daisy
//

import Cocoa

final class MarkdownDocumentController: NSDocumentController {
    static let recentDocumentsDidClear = Notification.Name("MarkdownDocumentController.recentDocumentsDidClear")

    override func clearRecentDocuments(_ sender: Any?) {
        super.clearRecentDocuments(sender)
        NotificationCenter.default.post(name: Self.recentDocumentsDidClear, object: self)
    }

    override func beginOpenPanel(
        _ openPanel: NSOpenPanel,
        forTypes inTypes: [String]?
    ) async -> Int {
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = true
        openPanel.message = NSLocalizedString(
            "Choose a file or folder",
            comment: "Open panel prompt"
        )
        // Any file: the ones Daisy does not edit open in their default app.
        openPanel.allowedContentTypes = []
        return await super.beginOpenPanel(openPanel, forTypes: inTypes)
    }

    override func openDocument(
        withContentsOf url: URL,
        display displayDocument: Bool,
        completionHandler: @escaping (NSDocument?, Bool, Error?) -> Void
    ) {
        if url.isExistingDirectory,
           let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.openFolder(url)
            completionHandler(nil, false, nil)
            return
        }

        let kind = FileKind.classify(url)
        if kind == .external || (kind == .text && !CodeDocument.isEditable(at: url)) {
            NSWorkspace.shared.open(url)
            completionHandler(nil, false, nil)
            return
        }

        super.openDocument(
            withContentsOf: url,
            display: displayDocument,
            completionHandler: completionHandler
        )
    }

    /// Source and text files have no document type of their own: they open as
    /// the one document class, so the type cannot depend on whether the system
    /// knows the extension (`Makefile`, `.env` and added entries do not).
    override func typeForContents(of url: URL) throws -> String {
        if FileKind.classify(url) == .text, let type = defaultType { return type }
        return try super.typeForContents(of: url)
    }

    override func openUntitledDocumentAndDisplay(_ displayDocument: Bool) throws -> NSDocument {
        let document = try super.openUntitledDocumentAndDisplay(displayDocument)
        if displayDocument {
            (document.windowControllers.first as? DocumentWindowController)?
                .enterEditMode(autofocus: true)
        }
        return document
    }
}
