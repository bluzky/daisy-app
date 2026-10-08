//
//  ProjectNavigatorView.swift
//  daisy
//

import Cocoa

private final class FileNode {
    let url: URL
    let isDirectory: Bool
    private var loadedChildren: [FileNode]?

    init(url: URL, isDirectory: Bool) {
        self.url = url
        self.isDirectory = isDirectory
    }

    var displayName: String { url.lastPathComponent }

    /// Children if `children()` has populated the cache; nil otherwise.
    var cachedChildren: [FileNode]? { loadedChildren }

    func invalidateCache() { loadedChildren = nil }

    func children() -> [FileNode] {
        if let cached = loadedChildren { return cached }
        guard isDirectory else {
            loadedChildren = []
            return []
        }
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])) ?? []
        let nodes: [FileNode] = entries.compactMap { entry in
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir { return FileNode(url: entry, isDirectory: true) }
            guard ProjectFileIndex.markdownExtensions.contains(entry.pathExtension.lowercased()) else { return nil }
            return FileNode(url: entry, isDirectory: false)
        }
        let sorted = nodes.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
        loadedChildren = sorted
        return sorted
    }
}

/// Header row of the Bookmarks section; a single instance per navigator.
private final class BookmarksGroupNode {}

/// Header row above the project tree, shown while the Bookmarks section is.
private final class FilesHeaderNode {}

private final class BookmarkNode {
    let bookmark: Bookmark
    /// Where the bookmark points now; nil once the target is gone.
    let url: URL?

    init(bookmark: Bookmark, url: URL?) {
        self.bookmark = bookmark
        self.url = url
    }

    var displayName: String { url?.lastPathComponent ?? bookmark.name }
}

final class ProjectNavigatorView: NSView {

    private static let bookmarksExpandedKey = "Sidebar.BookmarksExpanded"

    private static let draggedURLsPasteboardType = NSPasteboard.PasteboardType(
        "doc.daisy.project-navigator.urls"
    )

    var onSelectFile: ((URL) -> Void)?

    private let scrollView = NSScrollView()
    private let outlineView = NSOutlineView()
    private var rootNode: FileNode?
    private let bookmarksGroup = BookmarksGroupNode()
    private let filesHeader = FilesHeaderNode()
    private var bookmarkNodes: [BookmarkNode] = []
    /// The file whose document is actually open. Keep this separate from the
    /// outline's transient click selection so a pending Save/Don't Save/Cancel
    /// decision cannot make the navigator disagree with the editor.
    private var currentFileURL: URL?
    // One watcher per loaded directory; kept in sync with which FileNodes
    // currently have a populated children cache.
    private var watchers: [URL: DirectoryWatcher] = [:]
    /// Security-scoped folder selected through the Open panel. Retain access
    /// for file mutations while this navigator is rooted within it.
    private var accessedDirectoryURL: URL?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUp()
    }

    deinit {
        accessedDirectoryURL?.stopAccessingSecurityScopedResource()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        addSubview(scrollView)

        outlineView.style = .sourceList
        outlineView.headerView = nil
        outlineView.allowsMultipleSelection = false
        outlineView.allowsEmptySelection = true
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.action = #selector(rowClicked)
        outlineView.indentationPerLevel = 14
        outlineView.refusesFirstResponder = true
        outlineView.registerForDraggedTypes([Self.draggedURLsPasteboardType])

        let contextMenu = NSMenu()
        contextMenu.delegate = self
        outlineView.menu = contextMenu

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        column.isEditable = false
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        scrollView.documentView = outlineView

        NotificationCenter.default.addObserver(
            self, selector: #selector(bookmarksDidChange),
            name: BookmarkStore.didChangeNotification, object: nil
        )

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    func setRoot(_ url: URL?) {
        cancelAllWatchers()
        rootNode = url.map { FileNode(url: $0.standardizedFileURL, isDirectory: true) }
        updateSecurityScopedAccess()
        reloadBookmarkNodes()
        outlineView.reloadData()
        expandBookmarksGroupIfNeeded()
        if let rootNode {
            outlineView.expandItem(rootNode)
            syncWatchers()
        }
    }

    // MARK: - Bookmarks

    private func reloadBookmarkNodes() {
        let store = BookmarkStore.shared
        bookmarkNodes = store.bookmarks.map { BookmarkNode(bookmark: $0, url: store.resolve($0)) }
    }

    private func expandBookmarksGroupIfNeeded() {
        guard !bookmarkNodes.isEmpty else { return }
        let stored = UserDefaults.standard.object(forKey: Self.bookmarksExpandedKey) as? Bool
        if stored ?? true { outlineView.expandItem(bookmarksGroup) }
    }

    @objc private func bookmarksDidChange() {
        refreshTree()
        setCurrentFile(currentFileURL)
    }

    @objc private func toggleBookmark(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        let store = BookmarkStore.shared
        if let existing = store.bookmark(for: url) {
            store.remove(id: existing.id)
        } else {
            store.add(url)
        }
    }

    @objc private func removeBookmark(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        BookmarkStore.shared.remove(id: id)
    }

    private func open(_ node: BookmarkNode) {
        guard let url = node.url else {
            NSSound.beep()
            return
        }
        if node.bookmark.isDirectory {
            documentWindowController?.openFolder(url)
        } else if url != currentFileURL {
            onSelectFile?(url)
        }
    }

    // MARK: - Folder watching

    private func syncWatchers() {
        var live: Set<URL> = []
        if let rootNode { collectLoadedDirectories(rootNode, into: &live) }
        for url in live where watchers[url] == nil {
            watchers[url] = DirectoryWatcher(url: url) { [weak self] in
                self?.handleFolderChange()
            }
        }
        for (url, watcher) in watchers where !live.contains(url) {
            watcher.cancel()
            watchers.removeValue(forKey: url)
        }
    }

    private func collectLoadedDirectories(_ node: FileNode, into set: inout Set<URL>) {
        guard node.isDirectory else { return }
        set.insert(node.url.standardizedFileURL)
        guard let kids = node.cachedChildren else { return }
        for child in kids where child.isDirectory {
            collectLoadedDirectories(child, into: &set)
        }
    }

    private func cancelAllWatchers() {
        for watcher in watchers.values { watcher.cancel() }
        watchers.removeAll()
    }

    private func handleFolderChange() {
        let selectedURL = currentlySelectedURL()
        refreshTree()
        if let selectedURL { setCurrentFile(selectedURL) }
    }

    /// Reloads the outline from disk while preserving expansion state.
    /// Selection is left to the caller.
    private func refreshTree() {
        let expandedURLs = collectExpandedURLs()
        if let rootNode { invalidateCaches(rootNode) }
        reloadBookmarkNodes()
        outlineView.reloadData()
        expandBookmarksGroupIfNeeded()
        if let rootNode {
            outlineView.expandItem(rootNode)
            reExpand(rootNode, expanded: expandedURLs)
        }
        syncWatchers()
    }

    private func invalidateCaches(_ node: FileNode) {
        guard node.isDirectory, let kids = node.cachedChildren else { return }
        for child in kids where child.isDirectory {
            invalidateCaches(child)
        }
        node.invalidateCache()
    }

    private func collectExpandedURLs() -> Set<URL> {
        var result: Set<URL> = []
        func walk(_ item: Any?) {
            let count = outlineView.numberOfChildren(ofItem: item)
            for index in 0..<count {
                let child = outlineView.child(index, ofItem: item)
                if let node = child as? FileNode, outlineView.isItemExpanded(node) {
                    result.insert(node.url.standardizedFileURL)
                    walk(child)
                }
            }
        }
        walk(nil)
        return result
    }

    private func currentlySelectedURL() -> URL? {
        let row = outlineView.selectedRow
        guard row >= 0,
              let node = outlineView.item(atRow: row) as? FileNode else { return nil }
        return node.url.standardizedFileURL
    }

    private func reExpand(_ node: FileNode, expanded: Set<URL>) {
        guard node.isDirectory else { return }
        for child in node.children() where child.isDirectory {
            if expanded.contains(child.url.standardizedFileURL) {
                outlineView.expandItem(child)
                reExpand(child, expanded: expanded)
            }
        }
    }

    func setCurrentFile(_ url: URL?) {
        currentFileURL = url?.standardizedFileURL
        guard let url, let rootNode else {
            outlineView.deselectAll(nil)
            return
        }
        let target = url.standardizedFileURL
        var path: [FileNode] = []
        if !collectPath(to: target, from: rootNode, into: &path) {
            // Cache might be stale (file was just renamed and our
            // DirectoryWatcher hasn't fired yet). Refresh from disk once
            // and retry before giving up.
            refreshTree()
            path = []
            guard collectPath(to: target, from: rootNode, into: &path) else {
                outlineView.deselectAll(nil)
                return
            }
        }
        for ancestor in path.dropLast() {
            outlineView.expandItem(ancestor)
        }
        if let leaf = path.last {
            let row = outlineView.row(forItem: leaf)
            if row >= 0 {
                outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                outlineView.scrollRowToVisible(row)
                refreshRowTextColors()
            }
        }
    }

    private func collectPath(to targetURL: URL,
                             from root: FileNode,
                             into path: inout [FileNode]) -> Bool {
        // Skip subtrees that can't contain the target.
        guard targetURL.isDescendantOrSame(of: root.url) else { return false }

        for child in root.children() {
            if child.url.standardizedFileURL == targetURL {
                path.append(child)
                return true
            }
            if child.isDirectory {
                path.append(child)
                if collectPath(to: targetURL, from: child, into: &path) { return true }
                path.removeLast()
            }
        }
        return false
    }

    @objc private func rowClicked() {
        let row = outlineView.clickedRow
        if row >= 0, let bookmarkNode = outlineView.item(atRow: row) as? BookmarkNode {
            open(bookmarkNode)
            return
        }
        guard row >= 0, let node = outlineView.item(atRow: row) as? FileNode else { return }
        if node.isDirectory {
            // Disclosure buttons handle their own clicks in AppKit; this
            // action covers the folder's name, icon, and remaining row area.
            if outlineView.isItemExpanded(node) {
                outlineView.collapseItem(node)
            } else {
                outlineView.expandItem(node)
            }
        } else {
            let requestedURL = node.url.standardizedFileURL
            guard requestedURL != currentFileURL else { return }
            // `shouldSelectItem` keeps the highlight on the committed file,
            // so there's no AppKit selection to undo here — display(markdown:)
            // selects the requested file only after navigation succeeds.
            onSelectFile?(node.url)
        }
    }

    @objc private func showInFinder(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func openInNewTab(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL,
              let controller = documentWindowController else { return }
        controller.openInNewTab(url)
    }

    @objc private func openInNewWindow(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL,
              let controller = documentWindowController else { return }
        controller.openInNewWindow(url)
    }

    @objc private func copyPath(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.path, forType: .string)
    }

    @objc private func copyContents(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        Task { @concurrent in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
            await MainActor.run {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
            }
        }
    }

}

enum ProjectFileCommand {
    case newFile, newFolder, rename, moveToTrash
}

extension ProjectNavigatorView {

    /// The item a file command acts on: the selected row, else the open file,
    /// else the project root. Rename and trash never act on the root.
    private func target(for command: ProjectFileCommand) -> URL? {
        guard let rootURL = rootNode?.url.standardizedFileURL else { return nil }
        let selected = (outlineView.item(atRow: outlineView.selectedRow) as? FileNode)?.url
        let url = (selected ?? currentFileURL ?? rootURL).standardizedFileURL
        switch command {
        case .newFile, .newFolder: return url
        case .rename, .moveToTrash: return url == rootURL ? nil : url
        }
    }

    func canPerform(_ command: ProjectFileCommand) -> Bool {
        !isHidden && target(for: command) != nil
    }

    /// Creates an empty Markdown file at a project-relative path, making any
    /// missing folders on the way, without asking for a name. Hands back the
    /// file's URL — or the existing file's, if one is already there — and
    /// leaves opening it to the caller.
    func createFile(atRelativePath relativePath: String, completion: @escaping (URL?) -> Void) {
        guard let rootURL = rootNode?.url.standardizedFileURL,
              ProjectItemName.newFileRelativePath(from: relativePath) == relativePath else {
            completion(nil)
            return
        }
        let destination = rootURL.appendingPathComponent(relativePath, isDirectory: false)
        // A folder on the way may be a symlink out of the project. Check before
        // anything is created, and again once the folders exist.
        guard ProjectItemName.isContained(destination, in: rootURL) else {
            presentOutsideProjectAlert()
            completion(nil)
            return
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            completion(destination)
            return
        }
        ensureProjectWriteAccess { [weak self] in
            guard let self else { return }
            do {
                try FileManager.default.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                guard ProjectItemName.isContained(destination, in: rootURL) else {
                    self.presentOutsideProjectAlert()
                    completion(nil)
                    return
                }
                // `.withoutOverwriting` cannot be combined with `.atomic`;
                // Foundation traps on the pair.
                try Data().write(to: destination, options: .withoutOverwriting)
            } catch {
                self.presentFileOperationError(error)
                completion(nil)
                return
            }
            Task { await ProjectFileIndex.shared.invalidate(root: rootURL) }
            self.refreshTree()
            completion(destination)
        }
    }

    func perform(_ command: ProjectFileCommand) {
        guard canPerform(command), let url = target(for: command) else {
            NSSound.beep()
            return
        }
        let item = NSMenuItem()
        item.representedObject = url
        switch command {
        case .newFile: createNewFile(item)
        case .newFolder: createNewFolder(item)
        case .rename: renameItem(item)
        case .moveToTrash: deleteItem(item)
        }
    }
}

private extension ProjectNavigatorView {

    @objc private func createNewFile(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        let directory = directoryForNewItem(at: url)
        presentNameAlert(
            title: NSLocalizedString("New File", comment: "Project navigator new file alert title"),
            message: NSLocalizedString(
                "Enter a name for the new Markdown file.",
                comment: "Project navigator new file alert message"
            ),
            buttonTitle: NSLocalizedString("Create", comment: "Project navigator create button"),
            initialName: "Untitled.md"
        ) { [weak self] name in
            self?.createMarkdownFile(named: name, in: directory)
        }
    }

    @objc private func createNewFolder(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        let directory = directoryForNewItem(at: url)
        presentNameAlert(
            title: NSLocalizedString("New Folder", comment: "Project navigator new folder alert title"),
            message: NSLocalizedString(
                "Enter a name for the new folder.",
                comment: "Project navigator new folder alert message"
            ),
            buttonTitle: NSLocalizedString("Create", comment: "Project navigator create button"),
            initialName: "New Folder"
        ) { [weak self] name in
            self?.createFolder(named: name, in: directory)
        }
    }

    @objc private func renameItem(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        presentNameAlert(
            title: NSLocalizedString("Rename", comment: "Project navigator rename alert title"),
            message: NSLocalizedString(
                "Enter a new name.",
                comment: "Project navigator rename alert message"
            ),
            buttonTitle: NSLocalizedString("Rename", comment: "Project navigator rename button"),
            initialName: url.lastPathComponent
        ) { [weak self] name in
            self?.rename(url, to: name)
        }
    }

    private func directoryForNewItem(at url: URL) -> URL {
        url.isExistingDirectory ? url : url.deletingLastPathComponent()
    }

    private func createMarkdownFile(named name: String, in directory: URL) {
        guard let fileName = markdownFileName(from: name) else {
            presentInvalidNameAlert()
            return
        }
        let destination = directory.appendingPathComponent(fileName, isDirectory: false)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            presentItemExistsAlert()
            return
        }

        ensureProjectWriteAccess { [weak self] in
            guard let self else { return }
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                self.presentItemExistsAlert()
                return
            }
            do {
                try Data().write(to: destination, options: .atomic)
            } catch {
                self.presentFileOperationError(error)
                return
            }
            self.refreshTree()
            self.onSelectFile?(destination)
        }
    }

    private func createFolder(named name: String, in directory: URL) {
        guard let folderName = validItemName(name) else {
            presentInvalidNameAlert()
            return
        }
        let destination = directory.appendingPathComponent(folderName, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            presentItemExistsAlert()
            return
        }

        ensureProjectWriteAccess { [weak self] in
            guard let self else { return }
            do {
                try FileManager.default.createDirectory(
                    at: destination,
                    withIntermediateDirectories: false
                )
            } catch {
                self.presentFileOperationError(error)
                return
            }
            self.refreshTree()
            self.selectDirectory(at: destination)
        }
    }

    @objc private func deleteItem(_ sender: NSMenuItem) {
        guard let representedURL = sender.representedObject as? URL,
              let window = outlineView.window else { return }
        let url = representedURL.standardizedFileURL
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(
            format: NSLocalizedString(
                "Move “%@” to the Trash?",
                comment: "Project navigator delete alert title; %@ is the file or folder name"
            ),
            url.lastPathComponent
        )
        alert.informativeText = url.isExistingDirectory
            ? NSLocalizedString(
                "The folder and everything in it will be moved to the Trash.",
                comment: "Project navigator delete folder alert message"
            )
            : NSLocalizedString(
                "You can restore it from the Trash.",
                comment: "Project navigator delete file alert message"
            )
        alert.addButton(withTitle: NSLocalizedString("Move to Trash", comment: "Project navigator delete button"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Alert button"))
        alert.buttons[0].hasDestructiveAction = true
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.ensureProjectWriteAccess { [weak self] in
                self?.trash(url)
            }
        }
    }

    private func trash(_ url: URL) {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            presentFileOperationError(error)
            return
        }
        refreshTree()
    }

    private func rename(_ source: URL, to name: String) {
        let source = source.standardizedFileURL
        guard let fileName = source.isExistingDirectory
            ? validItemName(name)
            : markdownFileName(from: name, defaultExtension: source.pathExtension) else {
            presentInvalidNameAlert()
            return
        }
        let destination = source.deletingLastPathComponent()
            .appendingPathComponent(fileName, isDirectory: source.isExistingDirectory)
            .standardizedFileURL
        guard destination != source else { return }
        // A case-only rename (readme.md -> README.md) resolves to the same
        // file on a case-insensitive volume, so it must not count as a clash.
        let isCaseOnlyRename = destination.path.caseInsensitiveCompare(source.path) == .orderedSame
        guard isCaseOnlyRename || !FileManager.default.fileExists(atPath: destination.path) else {
            presentItemExistsAlert()
            return
        }

        ensureProjectWriteAccess { [weak self] in
            _ = self?.moveItem(from: source, to: destination)
        }
    }

    private func validItemName(_ name: String) -> String? {
        ProjectItemName.validated(name)
    }

    private func markdownFileName(from name: String, defaultExtension: String = "md") -> String? {
        ProjectItemName.markdownFileName(from: name, defaultExtension: defaultExtension)
    }

    private func presentNameAlert(title: String,
                                  message: String,
                                  buttonTitle: String,
                                  initialName: String,
                                  completion: @escaping (String) -> Void) {
        guard let window = outlineView.window else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let field = NSTextField(string: initialName)
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: buttonTitle)
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Alert button"))
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            completion(field.stringValue)
        }
    }

    private func presentInvalidNameAlert() {
        presentAlert(
            title: NSLocalizedString(
                "Invalid Name",
                comment: "Project navigator invalid name alert title"
            ),
            message: NSLocalizedString(
                "Use a valid Markdown file name.",
                comment: "Project navigator invalid name alert message"
            )
        )
    }

    private func presentOutsideProjectAlert() {
        presentAlert(
            title: NSLocalizedString(
                "Can’t Create File Here",
                comment: "Project navigator create file outside project alert title"
            ),
            message: NSLocalizedString(
                "That location leads outside the project folder.",
                comment: "Project navigator create file outside project alert message"
            )
        )
    }

    private func presentItemExistsAlert() {
        presentAlert(
            title: NSLocalizedString(
                "Item Already Exists",
                comment: "Project navigator item exists alert title"
            ),
            message: NSLocalizedString(
                "Choose a different name.",
                comment: "Project navigator item exists alert message"
            )
        )
    }

    private func presentFileOperationError(_ error: Error) {
        guard let window = outlineView.window else { return }
        NSAlert(error: error).beginSheetModal(for: window)
    }

    private func presentAlert(title: String, message: String) {
        guard let window = outlineView.window else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "Alert button"))
        alert.beginSheetModal(for: window)
    }

    private func selectDirectory(at url: URL) {
        guard let rootNode else { return }
        var path: [FileNode] = []
        guard collectPath(to: url.standardizedFileURL, from: rootNode, into: &path) else { return }
        for ancestor in path.dropLast() {
            outlineView.expandItem(ancestor)
        }
        if let node = path.last {
            let row = outlineView.row(forItem: node)
            if row >= 0 {
                outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                outlineView.scrollRowToVisible(row)
            }
        }
    }

    private func didMoveItem(from source: URL, to destination: URL) {
        let movedCurrentURL = documentWindowController?.currentFileURL.flatMap {
            movedURL($0, from: source, to: destination)
        }
        if let movedCurrentURL {
            documentWindowController?.handleRename(to: movedCurrentURL)
        }
        refreshTree()
        if destination.isExistingDirectory {
            selectDirectory(at: destination)
        } else if let movedCurrentURL {
            setCurrentFile(movedCurrentURL)
        }
    }

    private func draggedURLs(from pasteboard: NSPasteboard) -> [URL] {
        guard let paths = pasteboard.propertyList(forType: Self.draggedURLsPasteboardType) as? [String] else {
            return []
        }
        return paths.map { URL(fileURLWithPath: $0).standardizedFileURL }
    }

    private func dropTargetDirectory(for item: Any?) -> URL? {
        if let node = item as? FileNode {
            return node.isDirectory ? node.url : node.url.deletingLastPathComponent()
        }
        if item is BookmarksGroupNode || item is BookmarkNode { return nil }
        return rootNode?.url
    }

    private func canMove(_ source: URL, to directory: URL) -> Bool {
        guard let rootURL = rootNode?.url.standardizedFileURL else { return false }
        let source = source.standardizedFileURL
        let directory = directory.standardizedFileURL
        guard source != rootURL,
              source.isDescendantOrSame(of: rootURL),
              !directory.isDescendantOrSame(of: source),
              FileManager.default.fileExists(atPath: source.path) else { return false }
        let destination = directory.appendingPathComponent(source.lastPathComponent)
            .standardizedFileURL
        return destination != source && !FileManager.default.fileExists(atPath: destination.path)
    }

    private func movedURL(_ url: URL, from source: URL, to destination: URL) -> URL? {
        let url = url.standardizedFileURL
        let source = source.standardizedFileURL
        guard url.isDescendantOrSame(of: source) else { return nil }
        let relativePath = String(url.path.dropFirst(source.path.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !relativePath.isEmpty else { return destination }
        return destination.appendingPathComponent(relativePath).standardizedFileURL
    }

    private func updateSecurityScopedAccess() {
        guard let rootURL = rootNode?.url.standardizedFileURL else {
            stopAccessingDirectory()
            return
        }
        if let accessedDirectoryURL,
           rootURL.isDescendantOrSame(of: accessedDirectoryURL) { return }
        stopAccessingDirectory()
        if rootURL.startAccessingSecurityScopedResource() {
            accessedDirectoryURL = rootURL
        }
    }

    private func stopAccessingDirectory() {
        accessedDirectoryURL?.stopAccessingSecurityScopedResource()
        accessedDirectoryURL = nil
    }

    private func hasProjectWriteAccess() -> Bool {
        guard let rootURL = rootNode?.url.standardizedFileURL,
              let accessedDirectoryURL else { return false }
        return rootURL.isDescendantOrSame(of: accessedDirectoryURL)
    }

    private func ensureProjectWriteAccess(_ completion: @escaping () -> Void) {
        guard !hasProjectWriteAccess(),
              let rootURL = rootNode?.url.standardizedFileURL,
              let window = outlineView.window else {
            completion()
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = rootURL
        panel.message = NSLocalizedString(
            "Allow Daisy to manage files in this folder.",
            comment: "Project navigator folder permission prompt"
        )
        panel.prompt = NSLocalizedString("Allow Access", comment: "Project navigator folder permission button")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let selectedURL = panel.url else { return }
            let selectedDirectoryURL = selectedURL.standardizedFileURL
            guard rootURL.isDescendantOrSame(of: selectedDirectoryURL) else {
                self.presentAlert(
                    title: NSLocalizedString(
                        "Choose Project Folder",
                        comment: "Project navigator folder permission error title"
                    ),
                    message: NSLocalizedString(
                        "Choose this project folder or a folder that contains it.",
                        comment: "Project navigator folder permission error message"
                    )
                )
                return
            }
            guard selectedDirectoryURL.startAccessingSecurityScopedResource() else {
                self.presentAlert(
                    title: NSLocalizedString(
                        "Access Not Granted",
                        comment: "Project navigator folder permission error title"
                    ),
                    message: NSLocalizedString(
                        "Daisy needs write access to manage files in this folder.",
                        comment: "Project navigator folder permission error message"
                    )
                )
                return
            }
            self.stopAccessingDirectory()
            self.accessedDirectoryURL = selectedDirectoryURL
            completion()
        }
    }

    private func moveItem(from source: URL, to destination: URL) -> Bool {
        do {
            try FileManager.default.moveItem(at: source, to: destination)
        } catch {
            presentFileOperationError(error)
            return false
        }
        didMoveItem(from: source, to: destination)
        return true
    }
}

extension ProjectNavigatorView: NSMenuDelegate {

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = outlineView.clickedRow
        if row >= 0, let bookmarkNode = outlineView.item(atRow: row) as? BookmarkNode {
            addBookmarkNodeItems(to: menu, for: bookmarkNode)
            return
        }
        guard row >= 0, let node = outlineView.item(atRow: row) as? FileNode else { return }
        let url = node.url

        menu.addItem(makeMenuItem(title: NSLocalizedString("Show in Finder", comment: "Project navigator context menu"),
                                  symbol: "folder",
                                  action: #selector(showInFinder(_:)),
                                  url: url))
        menu.addItem(.separator())
        addCreationItems(to: menu, for: url)

        if !node.isDirectory {
            menu.addItem(.separator())
            menu.addItem(makeMenuItem(
                title: NSLocalizedString("Open in New Tab", comment: "Project navigator context menu"),
                symbol: "macwindow",
                action: #selector(openInNewTab(_:)),
                url: url
            ))
            menu.addItem(makeMenuItem(
                title: NSLocalizedString("Open in New Window", comment: "Project navigator context menu"),
                symbol: "macwindow.badge.plus",
                action: #selector(openInNewWindow(_:)),
                url: url
            ))
            if let controller = documentWindowController {
                for item in controller.contextMenuEditorItems(for: url) {
                    menu.addItem(item)
                }
            }
            menu.addItem(.separator())
            menu.addItem(makeMenuItem(title: NSLocalizedString("Copy", comment: "Project navigator context menu"),
                                      symbol: "document.on.clipboard",
                                      action: #selector(copyContents(_:)),
                                      url: url))
        }

        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: NSLocalizedString("Copy Path", comment: "Project navigator context menu"),
                                  symbol: "document.on.document",
                                  action: #selector(copyPath(_:)),
                                  url: url))
        menu.addItem(.separator())
        let isBookmarked = BookmarkStore.shared.isBookmarked(url)
        menu.addItem(makeMenuItem(
            title: isBookmarked
                ? NSLocalizedString("Remove Bookmark", comment: "Project navigator context menu")
                : NSLocalizedString("Bookmark", comment: "Project navigator context menu"),
            symbol: isBookmarked ? "bookmark.slash" : "bookmark",
            action: #selector(toggleBookmark(_:)),
            url: url
        ))
    }

    private func addBookmarkNodeItems(to menu: NSMenu, for node: BookmarkNode) {
        if let url = node.url {
            menu.addItem(makeMenuItem(title: NSLocalizedString("Show in Finder", comment: "Project navigator context menu"),
                                      symbol: "folder",
                                      action: #selector(showInFinder(_:)),
                                      url: url))
            menu.addItem(.separator())
        }
        let remove = NSMenuItem(title: NSLocalizedString("Remove Bookmark", comment: "Project navigator context menu"),
                                action: #selector(removeBookmark(_:)),
                                keyEquivalent: "")
        remove.target = self
        remove.representedObject = node.bookmark.id
        remove.image = NSImage(systemSymbolName: "bookmark.slash", accessibilityDescription: nil)
        menu.addItem(remove)
    }

    private func addCreationItems(to menu: NSMenu, for url: URL) {
        menu.addItem(makeMenuItem(title: NSLocalizedString("New File", comment: "Project navigator context menu"),
                                  symbol: "doc.badge.plus",
                                  action: #selector(createNewFile(_:)),
                                  url: url))
        menu.addItem(makeMenuItem(title: NSLocalizedString("New Folder", comment: "Project navigator context menu"),
                                  symbol: "folder.badge.plus",
                                  action: #selector(createNewFolder(_:)),
                                  url: url))
        guard url.standardizedFileURL != rootNode?.url.standardizedFileURL else { return }
        menu.addItem(makeMenuItem(title: NSLocalizedString("Rename", comment: "Project navigator context menu"),
                                  symbol: "pencil",
                                  action: #selector(renameItem(_:)),
                                  url: url))
        menu.addItem(makeMenuItem(title: NSLocalizedString("Move to Trash", comment: "Project navigator context menu"),
                                  symbol: "trash",
                                  action: #selector(deleteItem(_:)),
                                  url: url))
    }

    private func makeMenuItem(title: String,
                              symbol: String,
                              action: Selector,
                              url: URL) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = url
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return item
    }

    private var documentWindowController: DocumentWindowController? {
        outlineView.window?.windowController as? DocumentWindowController
    }

    /// Theme accent for the selected file row — the link color, matching
    /// the TOC outline's treatment. Nil without a link override.
    fileprivate var themeAccent: NSColor? {
        let isDark = effectiveAppearance
            .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return ThemeColorsSetting.current.color(.linkColor, isDark ? .dark : .light)
    }

    func refreshRowTextColors() {
        let accent = themeAccent ?? .controlAccentColor
        let selected = outlineView.selectedRow
        for row in 0..<outlineView.numberOfRows {
            guard let cell = outlineView.view(
                atColumn: 0, row: row, makeIfNecessary: false
            ) as? NSTableCellView, let textField = cell.textField else { continue }
            textField.textColor = row == selected ? accent : .labelColor
        }
    }
}

extension ProjectNavigatorView: NSOutlineViewDataSource {

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let node = item as? FileNode { return node.children().count }
        if item is BookmarksGroupNode { return bookmarkNodes.count }
        guard item == nil else { return 0 }
        return topLevelItems.count
    }

    private var topLevelItems: [Any] {
        var items: [Any] = []
        if !bookmarkNodes.isEmpty {
            items.append(bookmarksGroup)
            if rootNode != nil { items.append(filesHeader) }
        }
        if let rootNode { items.append(rootNode) }
        return items
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let node = item as? FileNode { return node.children()[index] }
        if item is BookmarksGroupNode { return bookmarkNodes[index] }
        return topLevelItems[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if item is BookmarksGroupNode { return true }
        guard let node = item as? FileNode else { return false }
        return node.isDirectory && !node.children().isEmpty
    }

    func outlineView(_ outlineView: NSOutlineView,
                     writeItems items: [Any],
                     to pasteboard: NSPasteboard) -> Bool {
        guard items.count == 1,
              let node = items.first as? FileNode,
              let rootURL = rootNode?.url.standardizedFileURL,
              node.url.standardizedFileURL != rootURL else { return false }
        return pasteboard.setPropertyList(
            [node.url.standardizedFileURL.path],
            forType: Self.draggedURLsPasteboardType
        )
    }

    func outlineView(_ outlineView: NSOutlineView,
                     validateDrop info: NSDraggingInfo,
                     proposedItem item: Any?,
                     proposedChildIndex index: Int) -> NSDragOperation {
        let sources = draggedURLs(from: info.draggingPasteboard)
        guard sources.count == 1,
              let directory = dropTargetDirectory(for: item),
              canMove(sources[0], to: directory) else { return [] }
        // Dropping on a file moves into its folder, so highlight that folder.
        let target = (item as? FileNode).flatMap { $0.isDirectory ? item : outlineView.parent(forItem: $0) } ?? item
        outlineView.setDropItem(target, dropChildIndex: NSOutlineViewDropOnItemIndex)
        return .move
    }

    func outlineView(_ outlineView: NSOutlineView,
                     acceptDrop info: NSDraggingInfo,
                     item: Any?,
                     childIndex index: Int) -> Bool {
        let sources = draggedURLs(from: info.draggingPasteboard)
        guard sources.count == 1,
              let directory = dropTargetDirectory(for: item),
              canMove(sources[0], to: directory) else { return false }
        let source = sources[0]
        let destination = directory.appendingPathComponent(
            source.lastPathComponent,
            isDirectory: source.isExistingDirectory
        ).standardizedFileURL
        if hasProjectWriteAccess() {
            return moveItem(from: source, to: destination)
        }
        ensureProjectWriteAccess { [weak self] in
            _ = self?.moveItem(from: source, to: destination)
        }
        return false
    }
}

extension ProjectNavigatorView: NSOutlineViewDelegate {

    func outlineView(_ outlineView: NSOutlineView,
                     viewFor tableColumn: NSTableColumn?,
                     item: Any) -> NSView? {
        if item is BookmarksGroupNode {
            return sectionHeaderCell(title: NSLocalizedString("Bookmarks", comment: "Project navigator section header"),
                                     identifier: "BookmarksHeaderCell")
        }
        if item is FilesHeaderNode { return sectionHeaderCell(title: NSLocalizedString("Files", comment: "Project navigator section header"), identifier: "FilesHeaderCell") }
        let name: String
        let iconPath: String
        let isSelectedRow: Bool
        if let node = item as? FileNode {
            name = node.displayName
            iconPath = node.url.path
            let row = outlineView.row(forItem: node)
            isSelectedRow = row >= 0 && row == outlineView.selectedRow
        } else if let node = item as? BookmarkNode {
            name = node.displayName
            iconPath = node.url?.path ?? node.bookmark.path
            isSelectedRow = false
        } else {
            return nil
        }
        let identifier = NSUserInterfaceItemIdentifier("FileCell")
        let cell: NSTableCellView
        if let recycled = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            cell = recycled
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier

            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.imageScaling = .scaleProportionallyDown
            cell.addSubview(imageView)
            cell.imageView = imageView

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingTail
            textField.cell?.usesSingleLineMode = true
            textField.maximumNumberOfLines = 1
            cell.addSubview(textField)
            cell.textField = textField

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 16),
                imageView.heightAnchor.constraint(equalToConstant: 16),
                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        cell.textField?.stringValue = name
        let icon = NSWorkspace.shared.icon(forFile: iconPath)
        icon.size = NSSize(width: 16, height: 16)
        cell.imageView?.image = icon
        let isMissing = (item as? BookmarkNode).map { $0.url == nil } ?? false
        cell.imageView?.alphaValue = isMissing ? 0.4 : 1
        cell.textField?.textColor = isSelectedRow
            ? (themeAccent ?? .controlAccentColor)
            : (isMissing ? .tertiaryLabelColor : .labelColor)
        return cell
    }

    private func sectionHeaderCell(title: String, identifier rawIdentifier: String) -> NSView {
        let identifier = NSUserInterfaceItemIdentifier(rawIdentifier)
        if let recycled = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            return recycled
        }
        let cell = NSTableCellView()
        cell.identifier = identifier
        let textField = NSTextField(labelWithString: title)
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.font = .systemFont(ofSize: 11, weight: .semibold)
        textField.textColor = .secondaryLabelColor
        cell.addSubview(textField)
        cell.textField = textField
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            textField.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -6),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        item is BookmarksGroupNode || item is FilesHeaderNode
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        if item is BookmarksGroupNode || item is FilesHeaderNode { return nil }
        return QuietSelectionRowView()
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        return item is FilesHeaderNode ? 30 : 24
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        refreshRowTextColors()
    }

    /// A click must not move the selection away from the committed file:
    /// the highlight only follows after navigation actually succeeds
    /// (`setCurrentFile`). Preventing the native selection here is what
    /// stops the O → X → O bounce on file switches. Directories stay
    /// selectable — they have no navigation side effect.
    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        guard let node = item as? FileNode else { return false }
        if node.isDirectory { return true }
        return node.url.standardizedFileURL == currentFileURL?.standardizedFileURL
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        if notification.userInfo?["NSObject"] is BookmarksGroupNode {
            UserDefaults.standard.set(true, forKey: Self.bookmarksExpandedKey)
            return
        }
        // Newly-loaded subtree needs its own watcher.
        syncWatchers()
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        if notification.userInfo?["NSObject"] is BookmarksGroupNode {
            UserDefaults.standard.set(false, forKey: Self.bookmarksExpandedKey)
        }
    }
}

private final class DirectoryWatcher {
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var debounce: DispatchWorkItem?

    init(url: URL, onChange: @escaping () -> Void) {
        self.onChange = onChange
        let descriptor = Darwin.open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        fileDescriptor = descriptor

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .delete, .rename, .revoke],
            queue: .main
        )
        source.setEventHandler { [weak self] in self?.scheduleChange() }
        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.fileDescriptor >= 0 {
                Darwin.close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }
        self.source = source
        source.resume()
    }

    /// FS events arrive in bursts (Finder rewrites + xattr updates). Coalesce.
    private func scheduleChange() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    func cancel() {
        debounce?.cancel()
        source?.cancel()
        source = nil
    }
}
