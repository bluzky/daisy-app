//
//  QuickCaptureStore.swift
//  daisy
//
//  Where the inbox lives. The sandbox only allows writes inside a folder the
//  reader picked, so the choice is persisted as a security-scoped bookmark.
//  `Inbox.md` in that folder is the one file Quick Capture opens.
//

import Cocoa

enum QuickCaptureError: LocalizedError {
    case noFolder
    case folderUnavailable

    var errorDescription: String? {
        switch self {
        case .noFolder:
            return NSLocalizedString("Choose a Quick Capture folder first.", comment: "Quick Capture error")
        case .folderUnavailable:
            return NSLocalizedString("The Quick Capture folder can’t be reached. Choose it again in Settings.", comment: "Quick Capture error")
        }
    }
}

@MainActor
enum QuickCaptureStore {
    private static let bookmarkKey = "MarkdownPreview.quickCaptureFolderBookmark"

    static var hasFolder: Bool {
        UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    static var folderDisplayPath: String? {
        guard let url = try? resolveFolder() else { return nil }
        return (url.path as NSString).abbreviatingWithTildeInPath
    }

    private static func setFolder(_ url: URL) throws {
        let data = try url.bookmarkData(options: .withSecurityScope,
                                        includingResourceValuesForKeys: nil,
                                        relativeTo: nil)
        UserDefaults.standard.set(data, forKey: bookmarkKey)
    }

    /// Asks for the capture folder. Returns whether one was chosen.
    static func chooseFolder() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = NSLocalizedString("Choose", comment: "Quick Capture folder prompt")
        panel.message = NSLocalizedString("Choose where Quick Capture keeps Inbox.md",
                                          comment: "Quick Capture folder prompt")
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try setFolder(url)
            return true
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
    }

    /// URL of `Inbox.md` in the capture folder, creating it on first use.
    static func inboxURL() throws -> URL {
        let inbox = try resolveFolder().appendingPathComponent(QuickCaptureSetting.inboxFileName)
        if !FileManager.default.fileExists(atPath: inbox.path) {
            try "# Inbox\n\n".write(to: inbox, atomically: true, encoding: .utf8)
        }
        return inbox
    }

    // MARK: - Private

    /// Folder whose security scope is held open for the app's lifetime, so a
    /// note written here can still be opened as a document afterwards.
    private static var accessedFolder: URL?

    private static func resolveFolder() throws -> URL {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else {
            throw QuickCaptureError.noFolder
        }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else {
            throw QuickCaptureError.folderUnavailable
        }
        if stale { try? setFolder(url) }
        if accessedFolder?.path != url.path {
            accessedFolder?.stopAccessingSecurityScopedResource()
            accessedFolder = url.startAccessingSecurityScopedResource() ? url : nil
        }
        guard accessedFolder != nil else { throw QuickCaptureError.folderUnavailable }
        return url
    }
}
