//
//  LastSessionStore.swift
//  daisy
//
//  The folder and file the reader had open last, for the "Reopen last folder
//  and file" launch behaviour. Both come from the same window — its document
//  and the root of its file tree — so the tree reopens as it was on screen.
//  Reads work anywhere in the sandbox, but saving needs the scope the reader
//  granted when they first opened the item, so a security-scoped bookmark is
//  stored whenever the sandbox allows it.
//

import Foundation

@MainActor
enum LastSessionStore {
    private static let folderKey = "MarkdownPreview.lastSessionFolderBookmark"
    private static let fileKey = "MarkdownPreview.lastSessionFileBookmark"

    /// Scoped URLs whose access is held open so restored documents can save.
    private static var accessed: [URL] = []

    /// Records what one window shows. A window with neither leaves the last
    /// session alone, so a blank untitled document doesn't erase it.
    static func record(fileURL: URL?, folderURL: URL?) {
        guard fileURL != nil || folderURL != nil else { return }
        store(folderURL, forKey: folderKey)
        store(fileURL, forKey: fileKey)
    }

    /// The last folder and file that still exist. Holds their security scope
    /// open for the app's lifetime.
    static func restorePlan() -> LaunchBehaviorSetting.RestorePlan {
        LaunchBehaviorSetting.restorePlan(folderURL: resolve(forKey: folderKey, isDirectory: true),
                                          fileURL: resolve(forKey: fileKey, isDirectory: false))
    }

    // MARK: - Private

    private struct Entry: Codable {
        var data: Data
        var isSecurityScoped: Bool
    }

    private static func store(_ url: URL?, forKey key: String) {
        guard let url = url?.standardizedFileURL else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        let scoped = try? url.bookmarkData(options: .withSecurityScope,
                                           includingResourceValuesForKeys: nil,
                                           relativeTo: nil)
        // Without access the sandbox refuses a scoped bookmark; the plain one
        // is still enough to find the item again for reading.
        guard let data = scoped ?? (try? url.bookmarkData()),
              let encoded = try? JSONEncoder().encode(Entry(data: data, isSecurityScoped: scoped != nil))
        else { return }
        UserDefaults.standard.set(encoded, forKey: key)
    }

    private static func resolve(forKey key: String, isDirectory: Bool) -> URL? {
        guard let encoded = UserDefaults.standard.data(forKey: key),
              let entry = try? JSONDecoder().decode(Entry.self, from: encoded) else { return nil }
        var stale = false
        let options: URL.BookmarkResolutionOptions = entry.isSecurityScoped ? [.withSecurityScope] : []
        guard let url = try? URL(resolvingBookmarkData: entry.data, options: options,
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if entry.isSecurityScoped, url.startAccessingSecurityScopedResource() {
            accessed.append(url)
        }
        var isExistingDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isExistingDirectory),
              isExistingDirectory.boolValue == isDirectory else { return nil }
        if stale { store(url, forKey: key) }
        return url.standardizedFileURL
    }
}
