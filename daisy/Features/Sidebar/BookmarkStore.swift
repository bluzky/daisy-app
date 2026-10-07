//
//  BookmarkStore.swift
//  daisy
//
//  Files and folders the reader pinned in the Project Navigator. Reads work
//  anywhere in the sandbox, but writes (rename, delete, new file) need a
//  security-scoped bookmark, so one is stored whenever the sandbox allows it.
//

import Foundation

struct Bookmark: Codable, Equatable, Identifiable {
    let id: UUID
    let isDirectory: Bool
    /// Last path the bookmark resolved to; refreshed when the target moves.
    var path: String
    var data: Data
    /// Whether `data` is a security-scoped bookmark (see `resolve`).
    var isSecurityScoped: Bool

    var name: String { (path as NSString).lastPathComponent }
}

@MainActor
final class BookmarkStore {
    static let shared = BookmarkStore()

    static let didChangeNotification = Notification.Name("MarkdownPreview.bookmarksDidChange")
    static let defaultsKey = "MarkdownPreview.bookmarks"

    private let defaults: UserDefaults
    private(set) var bookmarks: [Bookmark]
    /// Scoped URLs whose access is held open so writes keep working.
    private var accessed: [UUID: URL] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        bookmarks = defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode([Bookmark].self, from: $0) } ?? []
    }

    func bookmark(for url: URL) -> Bookmark? {
        let path = url.standardizedFileURL.path
        return bookmarks.first { $0.path == path }
    }

    func isBookmarked(_ url: URL) -> Bool { bookmark(for: url) != nil }

    @discardableResult
    func add(_ url: URL) -> Bool {
        let url = url.standardizedFileURL
        guard !isBookmarked(url), FileManager.default.fileExists(atPath: url.path) else { return false }
        let scoped = try? url.bookmarkData(options: .withSecurityScope,
                                           includingResourceValuesForKeys: nil,
                                           relativeTo: nil)
        // Without access the sandbox refuses a scoped bookmark; the plain one
        // is still enough to find the item again for reading.
        guard let data = scoped ?? (try? url.bookmarkData()) else { return false }
        bookmarks.append(Bookmark(id: UUID(),
                                  isDirectory: (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                                  path: url.path,
                                  data: data,
                                  isSecurityScoped: scoped != nil))
        save()
        return true
    }

    func remove(id: UUID) {
        guard let index = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        accessed.removeValue(forKey: id)?.stopAccessingSecurityScopedResource()
        bookmarks.remove(at: index)
        save()
    }

    /// The bookmarked item's current location, or nil once it is gone.
    func resolve(_ bookmark: Bookmark) -> URL? {
        var stale = false
        let options: URL.BookmarkResolutionOptions = bookmark.isSecurityScoped
            ? [.withSecurityScope] : []
        guard let url = try? URL(resolvingBookmarkData: bookmark.data, options: options,
                                 relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if bookmark.isSecurityScoped, accessed[bookmark.id] == nil,
           url.startAccessingSecurityScopedResource() {
            accessed[bookmark.id] = url
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        refresh(bookmark, resolvedTo: url, stale: stale)
        return url.standardizedFileURL
    }

    // MARK: - Private

    /// Keeps the stored path and data current. Quiet on purpose: this runs
    /// while the navigator draws, so it must not post a change notification.
    private func refresh(_ bookmark: Bookmark, resolvedTo url: URL, stale: Bool) {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) else { return }
        var updated = bookmarks[index]
        updated.path = url.standardizedFileURL.path
        if stale {
            let options: URL.BookmarkCreationOptions = updated.isSecurityScoped ? [.withSecurityScope] : []
            if let data = try? url.bookmarkData(options: options) { updated.data = data }
        }
        guard updated != bookmarks[index] else { return }
        bookmarks[index] = updated
        persist()
    }

    private func save() {
        persist()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
