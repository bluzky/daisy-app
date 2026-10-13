//
//  LaunchItemStore.swift
//  daisy
//
//  The file or folder the "Open a specific file or folder" launch behaviour
//  opens. The sandbox only lets the app reach it again on a later launch
//  through a security-scoped bookmark, the same way Quick Capture keeps its
//  folder.
//

import Cocoa
import UniformTypeIdentifiers

@MainActor
enum LaunchItemStore {
    private static let bookmarkKey = "MarkdownPreview.launchItemBookmark"
    private static let markdownFileExtensions = ["md", "markdown", "mdown", "mdx", "txt"]

    static var hasItem: Bool {
        UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    static var displayPath: String? {
        guard let url = resolve() else { return nil }
        return (url.path as NSString).abbreviatingWithTildeInPath
    }

    /// Asks for the file or folder. Returns whether one was chosen.
    static func choose() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = markdownFileExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.prompt = NSLocalizedString("Choose", comment: "Launch item prompt")
        panel.message = NSLocalizedString("Choose the Markdown file or folder Daisy opens when it starts",
                                          comment: "Launch item prompt")
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            let data = try url.bookmarkData(options: .withSecurityScope,
                                            includingResourceValuesForKeys: nil,
                                            relativeTo: nil)
            UserDefaults.standard.set(data, forKey: bookmarkKey)
            return true
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
    }

    /// The chosen item while it still exists. Holds its security scope open
    /// for the app's lifetime so an opened document can be saved.
    static func resolve() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &stale),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        if accessedItem?.path != url.path {
            accessedItem?.stopAccessingSecurityScopedResource()
            accessedItem = url.startAccessingSecurityScopedResource() ? url : nil
        }
        if stale, let refreshed = try? url.bookmarkData(options: .withSecurityScope,
                                                        includingResourceValuesForKeys: nil,
                                                        relativeTo: nil) {
            UserDefaults.standard.set(refreshed, forKey: bookmarkKey)
        }
        return url.standardizedFileURL
    }

    // MARK: - Private

    private static var accessedItem: URL?
}
