//
//  WorkspaceQuery.swift
//  daisy
//
//  A question about a workspace's files or tasks, as a value apart from any
//  syntax: `WorkspaceQueryParser` builds one from a `tasks`/`notes` block,
//  the Agenda and References build theirs in code. `evaluate` answers it
//  over file records in memory. No AppKit, so it links into
//  `tests/swift-tests`.
//

import Foundation

nonisolated struct WorkspaceQuery: Equatable, Sendable {
    enum Source: Equatable, Sendable { case files, tasks }

    var source: Source
    var filter: WorkspacePredicate = .and([])
    /// Applied in order; path, then line, breaks the remaining ties.
    var sort: [WorkspaceSortKey] = []
    var limit: Int?

    /// Every task, by path and line: what the Agenda reads.
    static let allTasks = WorkspaceQuery(source: .tasks)
}

nonisolated struct WorkspaceSortKey: Equatable, Sendable {
    /// An attribute key, or `path`, `line`, `text`.
    let key: String
    var descending = false
}

nonisolated enum WorkspaceComparison: Equatable, Sendable {
    case equal, less, lessOrEqual, greater, greaterOrEqual
}

nonisolated indirect enum WorkspacePredicate: Equatable, Sendable {
    case and([WorkspacePredicate])
    case or([WorkspacePredicate])
    case not(WorkspacePredicate)
    /// A list attribute matches when any item does.
    case attribute(String, WorkspaceComparison, WorkspaceAttributeValue)
    case hasAttribute(String)
    /// With `includingDescendants`, `#area` also matches `#area/sub`.
    case hasToken(WorkspaceMetadataKind, key: String, includingDescendants: Bool)
    /// A Markdown link to the root-relative `path`; for a task, on its line.
    case linksTo(path: String)
    /// In the root-relative folder or below it; "" is the whole root.
    case inFolder(String)
    /// A task's checkbox. Never true for a file.
    case checked(Bool)
    /// A task's text, or a file's name, contains the text, ignoring case.
    case textContains(String)
}

nonisolated enum WorkspaceQueryMatch: Equatable, Sendable {
    case file(WorkspaceFileRecord)
    case task(WorkspaceIndexedTask)

    var path: String {
        switch self {
        case let .file(record): record.path
        case let .task(task): task.path
        }
    }

    /// The line to open: a task's, or the file's start.
    var line: Int {
        switch self {
        case .file: 1
        case let .task(task): task.task.line
        }
    }
}

/// A value a query block shows of each match besides its row: the key it
/// groups by, or a table column.
nonisolated enum WorkspaceQueryField: Equatable, Sendable {
    /// For a task, its line's names and its file's frontmatter names; for a
    /// file, all of its names.
    case names(WorkspaceMetadataKind)
    /// A task field, a built-in or a frontmatter key, read the way a
    /// predicate reads it.
    case attribute(String)
}

/// A match with the values of the fields asked for, in their order. A list
/// attribute gives its items; a missing one gives none.
nonisolated struct WorkspaceQueryRow: Equatable, Sendable {
    let match: WorkspaceQueryMatch
    var values: [[WorkspaceAttributeValue]] = []
}

/// What the walk knows about a file and its record does not: computed, never
/// stored, read as `file.modified`, `file.created`, `file.size`.
nonisolated struct WorkspaceFileInfo: Equatable, Sendable {
    var modified: Date?
    var created: Date?
    var size: Int?
}

// MARK: - Evaluating

nonisolated extension WorkspaceQuery {
    /// The matches among `records`, sorted and limited. `info` gives each
    /// path's built-in attributes; `calendar` turns their dates into days.
    func evaluate(_ records: [WorkspaceFileRecord],
                  info: (String) -> WorkspaceFileInfo = { _ in WorkspaceFileInfo() },
                  calendar: Calendar = .current) -> [WorkspaceQueryMatch] {
        items(records, info: info, calendar: calendar).map(\.match)
    }

    /// The same matches, each with the values of `fields`.
    func evaluate(_ records: [WorkspaceFileRecord], fields: [WorkspaceQueryField],
                  info: (String) -> WorkspaceFileInfo = { _ in WorkspaceFileInfo() },
                  calendar: Calendar = .current) -> [WorkspaceQueryRow] {
        items(records, info: info, calendar: calendar).map { item in
            WorkspaceQueryRow(match: item.match, values: fields.map(item.values))
        }
    }

    /// Orders two values the way `sort:` does; a missing value comes last.
    static func order(_ lhs: WorkspaceAttributeValue?, _ rhs: WorkspaceAttributeValue?) -> ComparisonResult {
        Item.compare(lhs, rhs)
    }

    private func items(_ records: [WorkspaceFileRecord], info: (String) -> WorkspaceFileInfo,
                       calendar: Calendar) -> [Item] {
        var items: [Item] = []
        for record in records {
            let file = info(record.path)
            switch source {
            case .files:
                items.append(Item(record: record, task: nil, info: file, calendar: calendar))
            case .tasks:
                for task in record.tasks {
                    items.append(Item(record: record, task: task, info: file, calendar: calendar))
                }
            }
        }
        var matches = items.filter { $0.matches(filter) }
        matches.sort { lhs, rhs in
            for key in sort {
                let order = Item.compare(lhs.sortValue(key.key), rhs.sortValue(key.key))
                if order != .orderedSame {
                    // Missing values sort last either way.
                    if lhs.sortValue(key.key) == nil || rhs.sortValue(key.key) == nil {
                        return order == .orderedAscending
                    }
                    return key.descending ? order == .orderedDescending : order == .orderedAscending
                }
            }
            if lhs.record.path != rhs.record.path { return lhs.record.path < rhs.record.path }
            return (lhs.task?.line ?? 0) < (rhs.task?.line ?? 0)
        }
        if let limit { matches = Array(matches.prefix(max(0, limit))) }
        return matches
    }

    /// Files that link to `path` or, when `path` is a page in `pages/`, use
    /// a token whose page it is. `tokens` are the workspace's names; a key
    /// matches when `WorkspacePage.fileName(for:)` gives the page's name,
    /// ignoring case, so `#area/sub` and `#area--sub` share a page. A file
    /// never lists itself.
    static func references(to path: String,
                           tokens: [(kind: WorkspaceMetadataKind, key: String)]) -> WorkspaceQuery {
        references(to: path, pageTokens: pageTokens(of: path, among: tokens))
    }

    /// The same, given the names whose page `path` is (`pageTokens(of:among:)`).
    static func references(to path: String,
                           pageTokens: [(kind: WorkspaceMetadataKind, key: String)]) -> WorkspaceQuery {
        let anyOf: [WorkspacePredicate] = [.linksTo(path: path)] + pageTokens.map {
            .hasToken($0.kind, key: $0.key, includingDescendants: false)
        }
        return WorkspaceQuery(source: .files,
                              filter: .and([.or(anyOf), .not(.attribute("file.path", .equal, .text(path)))]))
    }

    /// The names among `tokens` whose page is `path`; none unless `path` is
    /// a page in `pages/`.
    static func pageTokens(of path: String, among tokens: [(kind: WorkspaceMetadataKind, key: String)])
        -> [(kind: WorkspaceMetadataKind, key: String)] {
        let components = path.split(separator: "/")
        guard components.count == 2, components[0] == WorkspacePage.folderName else { return [] }
        let page = WorkspacePage.key(String(components[1]))
        return tokens.filter { kind, key in
            WorkspacePage.fileName(for: kind.marker + key).map(WorkspacePage.key) == page
        }
    }
}

nonisolated extension WorkspaceMetadataKind {
    var marker: String {
        switch self {
        case .tag: "#"
        case .context: "@"
        case .project: "+"
        }
    }
}

/// One file or one task with what a predicate can ask of it.
nonisolated private struct Item {
    let record: WorkspaceFileRecord
    let task: WorkspaceTaskMetadata?
    let info: WorkspaceFileInfo
    let calendar: Calendar

    private static let priorityRank = ["low": 1, "medium": 2, "high": 3]

    var match: WorkspaceQueryMatch {
        if let task { return .task(WorkspaceIndexedTask(path: record.path, task: task)) }
        return .file(record)
    }

    /// A task has its line's names and the file's frontmatter names.
    private var tokens: [WorkspaceTokenOccurrence] {
        task.map { $0.tokens + record.frontmatterTokens } ?? record.tokens
    }

    func values(_ field: WorkspaceQueryField) -> [WorkspaceAttributeValue] {
        switch field {
        case let .names(kind):
            var seen: Set<String> = []
            return tokens.filter { $0.kind == kind && seen.insert($0.key).inserted }.map { .text($0.source) }
        case let .attribute(key):
            switch value(key) {
            case nil: return []
            case let .list(items)?: return items
            case let value?: return [value]
            }
        }
    }

    func matches(_ predicate: WorkspacePredicate) -> Bool {
        switch predicate {
        case let .and(predicates): return predicates.allSatisfy(matches)
        case let .or(predicates): return predicates.contains(where: matches)
        case let .not(predicate): return !matches(predicate)
        case let .attribute(key, comparison, value):
            guard let attribute = self.value(key) else { return false }
            return Self.matches(attribute, comparison, value, key: key)
        case let .hasAttribute(key):
            return self.value(key) != nil
        case let .hasToken(kind, key, descendants):
            return tokens.contains { token in
                token.kind == kind && (token.key == key || (descendants && token.key.hasPrefix(key + "/")))
            }
        case let .linksTo(path):
            return record.links.contains { $0.target == path && (task == nil || $0.line == task?.line) }
        case let .inFolder(folder):
            let trimmed = folder.split(separator: "/").joined(separator: "/")
            return trimmed.isEmpty || record.path.hasPrefix(trimmed + "/")
        case let .checked(checked):
            return task?.checked == checked
        case let .textContains(text):
            let haystack = task?.text ?? (record.path as NSString).lastPathComponent
            return text.isEmpty || haystack.range(of: text, options: [.caseInsensitive]) != nil
        }
    }

    /// A task's own attributes first, then the file's built-ins, then its
    /// frontmatter. `title` is a built-in that reads the frontmatter's,
    /// falling back to the file name, so every file has one.
    func value(_ key: String) -> WorkspaceAttributeValue? {
        let key = WorkspacePage.key(key)
        if let attribute = task?.attributes[key] { return attribute.value }
        switch key {
        case "title": return .text(record.title)
        case "file.name": return .text((record.path as NSString).lastPathComponent)
        case "file.folder": return .text((record.path as NSString).deletingLastPathComponent)
        case "file.path": return .text(record.path)
        case "file.modified": return info.modified.map { .date(JournalDay(date: $0, calendar: calendar)) }
        case "file.created": return info.created.map { .date(JournalDay(date: $0, calendar: calendar)) }
        case "file.size": return info.size.map { .number(Double($0), text: String($0)) }
        default: return record.attributes[key]?.value
        }
    }

    func sortValue(_ key: String) -> WorkspaceAttributeValue? {
        switch key {
        case "path": .text(record.path)
        case "line": .number(Double(task?.line ?? 0), text: "")
        case "text": .text(task?.text ?? (record.path as NSString).lastPathComponent)
        default: value(key)
        }
    }

    // MARK: Comparing values

    static func matches(_ attribute: WorkspaceAttributeValue, _ comparison: WorkspaceComparison,
                        _ wanted: WorkspaceAttributeValue, key: String) -> Bool {
        if case let .list(items) = attribute {
            return items.contains { matches($0, comparison, wanted, key: key) }
        }
        if case let .list(items) = wanted {
            return items.contains { matches(attribute, comparison, $0, key: key) }
        }
        let order: ComparisonResult?
        if WorkspacePage.key(key) == "priority", case let .text(have) = attribute,
           let lhs = priorityRank[have], let rhs = priorityRank[wanted.text.lowercased()] {
            order = compare(lhs, rhs)
        } else {
            order = compare(attribute, coercing: wanted)
        }
        guard let order else { return false }
        switch comparison {
        case .equal: return order == .orderedSame
        case .less: return order == .orderedAscending
        case .lessOrEqual: return order != .orderedDescending
        case .greater: return order == .orderedDescending
        case .greaterOrEqual: return order != .orderedAscending
        }
    }

    /// Compares `wanted`, read as the attribute's type, with `attribute`;
    /// nil when it cannot be read that way.
    private static func compare(_ attribute: WorkspaceAttributeValue,
                                coercing wanted: WorkspaceAttributeValue) -> ComparisonResult? {
        switch attribute {
        case let .number(value, _):
            if case let .number(other, _) = wanted { return compare(value, other) }
            return Double(wanted.text).map { compare(value, $0) }
        case let .date(day):
            if case let .date(other) = wanted { return compare(day, other) }
            return JournalDay(string: wanted.text).map { compare(day, $0) }
        case let .bool(value, _):
            let other: Bool? = switch wanted {
            case let .bool(other, _): other
            default: ["true": true, "false": false][wanted.text.lowercased()]
            }
            guard let other else { return nil }
            return value == other ? .orderedSame : (value ? .orderedDescending : .orderedAscending)
        case let .link(_, target, text):
            return compareText(target ?? text, wanted.text)
        case let .text(text):
            return compareText(text, wanted.text)
        case .list:
            return nil
        }
    }

    private static func compareText(_ lhs: String, _ rhs: String) -> ComparisonResult {
        WorkspacePage.key(lhs).compare(WorkspacePage.key(rhs))
    }

    private static func compare<Value: Comparable>(_ lhs: Value, _ rhs: Value) -> ComparisonResult {
        lhs < rhs ? .orderedAscending : (lhs > rhs ? .orderedDescending : .orderedSame)
    }

    /// For sorting: values of one type compare; a missing value sorts after
    /// any present one.
    static func compare(_ lhs: WorkspaceAttributeValue?, _ rhs: WorkspaceAttributeValue?) -> ComparisonResult {
        guard let lhs else { return rhs == nil ? .orderedSame : .orderedDescending }
        guard let rhs else { return .orderedAscending }
        switch (lhs, rhs) {
        case let (.number(left, _), .number(right, _)): return compare(left, right)
        case let (.date(left), .date(right)): return compare(left, right)
        case let (.text(left), .text(right)):
            if let left = priorityRank[left], let right = priorityRank[right] { return compare(left, right) }
            return compareText(left, right)
        case let (.list(left), .list(right)): return compare(left.first, right.first)
        case let (.list(left), _): return compare(left.first, rhs)
        case let (_, .list(right)): return compare(lhs, right.first)
        default: return compareText(lhs.text, rhs.text)
        }
    }
}
