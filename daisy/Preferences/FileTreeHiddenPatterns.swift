//
//  FileTreeHiddenPatterns.swift
//  daisy
//
//  Settings ▸ General ▸ "Hide from file tree" and View ▸ Toggle Hidden Files.
//  The patterns are comma-separated globs, read like a `.gitignore` line: one
//  without a `/` matches an item's name at any depth, one with a `/` matches
//  its path from the opened folder, and a trailing `/` limits it to folders.
//  The toggle reveals what the patterns hide together with dot-files.
//

import Foundation

struct FileTreeHiddenPatterns: Equatable {
    static let patternsDefaultsKey = "MarkdownPreview.fileTreeHiddenPatterns"
    static let showsHiddenFilesDefaultsKey = "MarkdownPreview.showHiddenFiles"
    /// Posted when the patterns or the toggle change, so every Files tree re-reads.
    static let didChangeNotification = Notification.Name("MarkdownPreview.fileTreeHiddenPatternsDidChange")

    private struct Pattern: Equatable {
        let glob: String
        let matchesPath: Bool
        let foldersOnly: Bool
    }

    private let patterns: [Pattern]

    var isEmpty: Bool { patterns.isEmpty }

    /// Splits on commas, trims each entry and drops the empty ones.
    init(_ text: String) {
        patterns = text.split(separator: ",").compactMap { entry in
            var glob = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            let foldersOnly = glob.hasSuffix("/")
            while glob.hasSuffix("/") { glob.removeLast() }
            let matchesPath = glob.contains("/")
            while glob.hasPrefix("/") { glob.removeFirst() }
            guard !glob.isEmpty else { return nil }
            return Pattern(glob: glob, matchesPath: matchesPath, foldersOnly: foldersOnly)
        }
    }

    /// `relativePath` is the item's path from the opened folder, `name` its last component.
    /// Case is ignored, as on a default macOS volume. `*` does not cross a `/`.
    func isHidden(name: String, relativePath: String, isDirectory: Bool) -> Bool {
        patterns.contains { pattern in
            if pattern.foldersOnly && !isDirectory { return false }
            return fnmatch(pattern.glob, pattern.matchesPath ? relativePath : name,
                           FNM_PATHNAME | FNM_CASEFOLD) == 0
        }
    }

    /// What the tree lists: everything when the toggle is on, otherwise what the patterns leave.
    func isListed(name: String, relativePath: String, isDirectory: Bool, showsHiddenFiles: Bool) -> Bool {
        showsHiddenFiles || !isHidden(name: name, relativePath: relativePath, isDirectory: isDirectory)
    }

    struct Entry {
        let url: URL
        let isDirectory: Bool
        /// Path from the opened folder.
        let relativePath: String
    }

    /// The entries of one folder the tree lists. Only the folder's children are
    /// tested, so the opened folder itself is never hidden, whatever its name.
    /// `relativePath` is the folder's own path from the opened folder ("" for it).
    static func listedEntries(in folder: URL, relativePath: String) -> [Entry] {
        let showsHidden = showsHiddenFiles
        let patterns = current
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: showsHidden ? [] : [.skipsHiddenFiles])) ?? []
        return urls.compactMap { url in
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let name = url.lastPathComponent
            let path = relativePath.isEmpty ? name : relativePath + "/" + name
            guard patterns.isListed(name: name, relativePath: path,
                                    isDirectory: isDirectory, showsHiddenFiles: showsHidden) else { return nil }
            return Entry(url: url, isDirectory: isDirectory, relativePath: path)
        }
    }

    // MARK: - Stored values

    static var currentText: String {
        get { UserDefaults.standard.string(forKey: patternsDefaultsKey) ?? "" }
        set {
            if newValue.isEmpty {
                UserDefaults.standard.removeObject(forKey: patternsDefaultsKey)
            } else {
                UserDefaults.standard.set(newValue, forKey: patternsDefaultsKey)
            }
        }
    }

    static var current: FileTreeHiddenPatterns { FileTreeHiddenPatterns(currentText) }

    /// Off unless the reader turned it on; one value for every window.
    static var showsHiddenFiles: Bool {
        get { UserDefaults.standard.bool(forKey: showsHiddenFilesDefaultsKey) }
        set {
            if newValue {
                UserDefaults.standard.set(true, forKey: showsHiddenFilesDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: showsHiddenFilesDefaultsKey)
            }
        }
    }
}
