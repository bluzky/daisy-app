//
//  ReferencesViewController.swift
//  daisy
//
//  The References panel of the right-hand pane: the workspace files that
//  link to the open file, or use the tag, context or project whose page it
//  is (`WorkspaceReferences`). Like the Agenda, it reads the workspace index
//  only while it is on screen, and asks again whenever the index's records
//  change or the window moves to another file. Opening a row goes through
//  `onOpen`; the window controller does the opening.
//

import Cocoa
import Combine
import SwiftUI

@MainActor
final class ReferencesStore: ObservableObject {
    enum Content: Equatable {
        /// The window shows no saved file.
        case noFile
        /// The file is not one the index reads: outside the root, hidden or
        /// not Markdown.
        case notIndexed
        /// Not fetched yet for this file.
        case loading
        case references(WorkspaceReferences)
    }

    @Published var isWorkspace = false
    @Published var canInitializeWorkspace = false
    @Published var isIndexing = false
    /// The scan stopped at the file limit, so some referring files may be missing.
    @Published var isTruncated = false
    @Published var content: Content = .noFile
    @Published var collapsedSections: Set<ReferencesSection> = []

    /// Root-relative path, line, and whether to open it in a new tab.
    var onOpen: ((String, Int, Bool) -> Void)?
    var onReveal: ((String) -> Void)?
    var onInitializeWorkspace: (() -> Void)?
}

enum ReferencesSection: String, CaseIterable {
    case linked
    case mentions
}

final class ReferencesViewController: NSViewController {
    let store = ReferencesStore()

    var onOpen: ((String, Int, Bool) -> Void)? {
        get { store.onOpen }
        set { store.onOpen = newValue }
    }
    var onReveal: ((String) -> Void)? {
        get { store.onReveal }
        set { store.onReveal = newValue }
    }
    var onInitializeWorkspace: (() -> Void)? {
        get { store.onInitializeWorkspace }
        set { store.onInitializeWorkspace = newValue }
    }
    var canInitializeWorkspace: Bool {
        get { store.canInitializeWorkspace }
        set { store.canInitializeWorkspace = newValue }
    }

    /// The pane reads the theme accent while drawing; redraw it on a theme change.
    func themeColorsDidChange() {
        store.objectWillChange.send()
    }

    private var index: WorkspaceMetadataIndex?
    private var fileURL: URL?
    private var isPaneVisible = false
    /// Bumped on every bind, file and visibility change, so a stream or
    /// fetch from an earlier one is ignored.
    private var generation = 0
    private var observationTasks: [Task<Void, Never>] = []
    private var fetchTask: Task<Void, Never>?
    /// When the first revision not yet fetched arrived.
    private var pendingSince: ContinuousClock.Instant?
    private var fetchSequence = 0
    private var appliedFetch = 0

    /// A fetch waits for the index to go quiet this long, but never longer
    /// than `maximumWait` after the first change, so a long scan still shows
    /// its progress.
    private static let quietPeriod: Duration = .milliseconds(150)
    private static let maximumWait: Duration = .seconds(1)

    override func loadView() {
        let host = NSHostingView(rootView: ReferencesView(store: store))
        host.translatesAutoresizingMaskIntoConstraints = false
        view = host
    }

    isolated deinit {
        observationTasks.forEach { $0.cancel() }
        fetchTask?.cancel()
    }

    /// The workspace index of the window, or nil outside a workspace.
    func bind(index: WorkspaceMetadataIndex?) {
        guard index !== self.index else { return }
        self.index = index
        store.isWorkspace = index != nil
        store.isIndexing = false
        store.isTruncated = false
        restart(clearing: true)
    }

    /// The file the window shows, or nil for none or an unsaved document.
    func setFile(_ url: URL?) {
        guard url?.standardizedFileURL != fileURL?.standardizedFileURL else { return }
        fileURL = url
        restart(clearing: true)
    }

    func setPaneVisible(_ visible: Bool) {
        guard visible != isPaneVisible else { return }
        isPaneVisible = visible
        restart()
    }

    /// `clearing` drops the list shown, which belongs to another file or index.
    private func restart(clearing: Bool = false) {
        generation += 1
        observationTasks.forEach { $0.cancel() }
        observationTasks = []
        fetchTask?.cancel()
        fetchTask = nil
        pendingSince = nil
        if clearing || fileURL == nil { store.content = fileURL == nil ? .noFile : .loading }
        guard isPaneVisible, let index, let fileURL else { return }
        let generation = generation
        observationTasks.append(Task { [weak self] in
            for await _ in await index.recordChanges() {
                guard let self, self.generation == generation else { return }
                self.scheduleFetch(fileURL, from: index, generation: generation)
            }
        })
        observationTasks.append(Task { [weak self] in
            for await snapshot in await index.snapshots() {
                guard let self, self.generation == generation else { return }
                self.store.isIndexing = !snapshot.isComplete
                self.store.isTruncated = snapshot.isTruncated
            }
        })
    }

    /// Fetches once the revisions stop for `quietPeriod`, or `maximumWait`
    /// after the first one, so a burst, as during a scan, costs few queries.
    private func scheduleFetch(_ url: URL, from index: WorkspaceMetadataIndex, generation: Int) {
        let now = ContinuousClock.now
        let since = pendingSince ?? now
        pendingSince = since
        let delay = min(Self.quietPeriod, max(.zero, since + Self.maximumWait - now))
        // Only the wait is cancelled; a query already running finishes.
        fetchTask?.cancel()
        fetchTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, self.generation == generation, !Task.isCancelled else { return }
            // Cleared before reading, so a revision from here on waits again.
            self.fetchTask = nil
            self.pendingSince = nil
            self.fetchSequence += 1
            let sequence = self.fetchSequence
            let references = await index.referenceList(toFile: url)
            guard self.generation == generation, sequence > self.appliedFetch else { return }
            self.appliedFetch = sequence
            self.store.content = references.map { .references($0) } ?? .notIndexed
        }
    }
}
