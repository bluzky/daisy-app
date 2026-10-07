import Foundation

/// Combines app-wide history with project search without changing either ranking.
nonisolated enum FileSearchResults {
    struct Entry: Sendable, Equatable {
        let url: URL
        let candidate: FileSearchMatcher.Candidate
        let projectRoot: URL?
    }

    /// A menu command the palette can run. `id` keys the live `NSMenuItem` the
    /// panel holds on the main actor; everything here is plain data so ranking
    /// can run off it.
    struct CommandCandidate: Sendable, Equatable {
        let id: String
        let title: String
        /// The menus the item sits under, e.g. `View › Sidebar`.
        let menuPath: String
        /// The binding as the menu shows it, e.g. `⌘K`.
        let shortcut: String?
        let candidate: FileSearchMatcher.Candidate

        init(id: String, title: String, menuPath: String, shortcut: String?) {
            self.id = id
            self.title = title
            self.menuPath = menuPath
            self.shortcut = shortcut
            self.candidate = .init(fileName: title, relativePath: title)
        }
    }

    /// The "create it" row offered when no file matches what was typed.
    struct NewFile: Sendable, Equatable {
        /// Project-relative, with the extension filled in.
        let relativePath: String
        let projectRoot: URL

        var fileName: String { (relativePath as NSString).lastPathComponent }
        /// The folder it lands in, relative to the project; empty for the root.
        var directory: String { (relativePath as NSString).deletingLastPathComponent }
    }

    enum Row: Sendable, Equatable {
        case recentHeading
        case filesHeading
        case commandsHeading
        case contentHeading
        case file(Entry)
        case command(CommandCandidate)
        case createFile(NewFile)
        case content(ProjectContentSearcher.Hit)
        /// Stands in the contents section until the scan has found anything.
        case searching

        var entry: Entry? {
            if case .file(let entry) = self { return entry }
            return nil
        }

        var isSelectable: Bool {
            switch self {
            case .recentHeading, .filesHeading, .commandsHeading, .contentHeading, .searching: false
            case .file, .command, .createFile, .content: true
            }
        }
    }

    /// How many commands the mixed view shows. `>` lifts the cap.
    static let mixedCommandLimit = 5

    /// Shared by result deduplication and the current-tab no-op check.
    static func resolvedIdentity(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }

    /// The query with a leading `>` removed, or nil when it is not a command query.
    static func commandQuery(_ query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(">") else { return nil }
        return String(trimmed.dropFirst())
    }

    static func rows(query: String,
                     recentURLs: [URL],
                     snapshot: ProjectFileIndex.Snapshot?,
                     commands: [CommandCandidate] = []) throws -> [Row] {
        if let commandQuery = commandQuery(query) {
            let matched = try rankedCommands(query: commandQuery, commands: commands)
            return matched.isEmpty ? [] : [.commandsHeading] + matched.map { .command($0) }
        }

        let blank = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let recent = recentURLs.map {
            Entry(url: $0, candidate: .init(relativePath: $0.path), projectRoot: nil)
        }
        let rankedRecent = blank ? Array(recent.indices) :
            try FileSearchMatcher.rankCancellably(query: query, candidates: recent.map(\.candidate))
        // Match every path first: an earlier alias may not match the query.
        // The first surviving identity wins by recency (blank) or relevance.
        var seen = Set<URL>()
        let uniqueRecent = rankedRecent.filter { seen.insert(resolvedIdentity(recent[$0].url)).inserted }
        let recentIndices = blank ? Array(uniqueRecent.prefix(10)) : uniqueRecent
        let displayedRecentURLs = Set(recentIndices.map { resolvedIdentity(recent[$0].url) })
        var rows: [Row] = recentIndices.isEmpty ? [] : [.recentHeading]
        rows += recentIndices.map { .file(recent[$0]) }
        guard !blank else { return rows }

        var files: [Row] = []
        if let snapshot {
            let ranked = try FileSearchMatcher.rankCancellably(query: query, candidates: snapshot.candidates)
            files = ranked.compactMap { index -> Row? in
                guard let url = snapshot.url(at: index) else { return nil }
                if !displayedRecentURLs.isEmpty, displayedRecentURLs.contains(resolvedIdentity(url)) { return nil }
                return .file(Entry(url: url, candidate: snapshot.candidates[index], projectRoot: snapshot.root))
            }
        }
        if !files.isEmpty { rows += [.filesHeading] + files }

        let matchedCommands = try rankedCommands(query: query, commands: commands)
            .prefix(mixedCommandLimit)
        if !matchedCommands.isEmpty { rows += [.commandsHeading] + matchedCommands.map { .command($0) } }

        // Offered only once the index has loaded, so it cannot flash up for a
        // file the walk simply has not reached yet, and only when nothing at
        // all matched by name.
        if let snapshot, files.isEmpty, recentIndices.isEmpty,
           let relativePath = ProjectItemName.newFileRelativePath(from: query) {
            rows.insert(.createFile(NewFile(relativePath: relativePath, projectRoot: snapshot.root)), at: 0)
        }
        return rows
    }

    private static func rankedCommands(query: String, commands: [CommandCandidate]) throws -> [CommandCandidate] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return commands }
        return try FileSearchMatcher.rankCancellably(query: query, candidates: commands.map(\.candidate))
            .map { commands[$0] }
    }
}
