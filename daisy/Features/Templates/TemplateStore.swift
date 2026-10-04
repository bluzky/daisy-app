//
//  TemplateStore.swift
//  daisy
//
//  Where the slash-menu templates come from. The reader picks one Markdown
//  file; the sandbox only lets the app read it again later through a
//  security-scoped bookmark, the same way Quick Capture keeps its folder.
//

import Cocoa
import UniformTypeIdentifiers

@MainActor
enum TemplateStore {
    /// Posted whenever the list of templates may have changed: a new file was
    /// chosen, the choice was cleared, or the file was edited on disk.
    static let didChangeNotification = Notification.Name("MarkdownPreview.templatesDidChange")

    private static let bookmarkKey = "MarkdownPreview.templateFileBookmark"

    static var hasFile: Bool {
        UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    static var fileDisplayPath: String? {
        guard let url = resolveFile() else { return nil }
        return (url.path as NSString).abbreviatingWithTildeInPath
    }

    /// Templates in the chosen file. Empty when none is chosen or it can't be
    /// read, which hides the Templates entry from the slash menu.
    static func load() -> [MarkdownTemplate] {
        guard let url = resolveFile(),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return TemplateFileParser.parse(text)
    }

    /// Asks for the template file. Returns whether one was chosen.
    static func chooseFile() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType("net.daringfireball.markdown"), .plainText].compactMap { $0 }
        panel.prompt = NSLocalizedString("Choose", comment: "Template file prompt")
        panel.message = NSLocalizedString("Choose a Markdown file of templates, each starting at a <!-- template: Name --> line or ## heading",
                                          comment: "Template file prompt")
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try setFile(url)
            return true
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
    }

    static func clearFile() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        release()
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    // MARK: - Private

    /// File whose security scope is held open for the app's lifetime, so it
    /// can be re-read whenever a template is inserted or the file changes.
    private static var accessedFile: URL?
    private static var watcher: FileWatcher?

    private static func setFile(_ url: URL) throws {
        let data = try url.bookmarkData(options: .withSecurityScope,
                                        includingResourceValuesForKeys: nil,
                                        relativeTo: nil)
        UserDefaults.standard.set(data, forKey: bookmarkKey)
        release()
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    private static func release() {
        watcher?.cancel()
        watcher = nil
        accessedFile?.stopAccessingSecurityScopedResource()
        accessedFile = nil
    }

    private static func resolveFile() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale { try? setFile(url) }
        if accessedFile?.path != url.path {
            release()
            guard url.startAccessingSecurityScopedResource() else { return nil }
            accessedFile = url
        }
        if watcher == nil {
            let watched = FileWatcher(url: url) {
                NotificationCenter.default.post(name: didChangeNotification, object: nil)
            }
            // A rename or atomic save moves the inode; start over from the bookmark.
            watched.onRename = { _ in
                release()
                NotificationCenter.default.post(name: didChangeNotification, object: nil)
            }
            watcher = watched
        }
        return accessedFile
    }
}
