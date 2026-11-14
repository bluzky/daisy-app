//
//  WorkspaceQueryBlocks.swift
//  daisy
//
//  What a ```tasks or ```notes block asks of the workspace and what the
//  preview shows for it. The page sends a `QueryBlockRequest` per block; the
//  window answers each with a `QueryBlockResult` built here: the parser's
//  problems, then one row per match, grouped and in table cells as the
//  block's display options say. No AppKit, so it links into
//  `tests/swift-tests`.
//

import Foundation

nonisolated struct QueryBlockRequest: Equatable, Sendable {
    enum Source: String, Sendable {
        /// `notes` lists Markdown files.
        case tasks, notes

        var querySource: WorkspaceQuery.Source { self == .tasks ? .tasks : .files }
    }

    /// The page's id for the block, from its source and text.
    let id: String
    let source: Source
    let text: String

    init(id: String, source: Source, text: String) {
        self.id = id
        self.source = source
        self.text = text
    }

    /// One query as a page posts it: `{ id, source, text }`.
    init?(message: [String: Any]) {
        guard let id = message["id"] as? String, let text = message["text"] as? String,
              let source = (message["source"] as? String).flatMap(Source.init(rawValue:)) else { return nil }
        self.init(id: id, source: source, text: text)
    }
}

/// Encoded for the page's `MdPreview.queryResults` and the editor's
/// `setQueryResults`. The host groups the rows and fills the table's cells,
/// so the two pages only draw what they are sent.
nonisolated struct QueryBlockResult: Encodable, Equatable, Sendable {
    nonisolated struct Row: Encodable, Equatable, Sendable {
        let path: String
        let line: Int
        /// A task's text, or a file's `title` or name.
        let text: String
        /// Tasks only.
        let checked: Bool?
        /// The file a task is in, or the folder a file is in.
        let detail: String
        /// A task's line as written, fields and names included, so the page
        /// can show it as the document does; nil for a file.
        var source: String?
        /// A table's cells, one per column; nil in a list.
        var cells: [[Value]]?
    }

    /// One value in a cell or a group's label.
    nonisolated struct Value: Encodable, Equatable, Sendable {
        let text: String
        /// The root-relative file it opens, at its start.
        var path: String?
    }

    /// How the page draws a column's cells or a group's label: `done` (the
    /// checkbox), `text` (the row's text, opening it), `due`, `scheduled`
    /// and `p` (badges), `names` (links to their pages), `value` (text, or
    /// a link when it has a path), and `none` for the group of rows with no
    /// value.
    nonisolated struct Column: Encodable, Equatable, Sendable {
        let kind: String
        let label: String
    }

    nonisolated struct Group: Encodable, Equatable, Sendable {
        /// Nil for a block without `$group:`, whose one group has no header.
        let label: Value?
        let kind: String
        let rows: [Row]
    }

    let id: String
    let source: String
    let problems: [String]
    /// `list` or `table`.
    var view = "list"
    var columns: [Column] = []
    let groups: [Group]
    /// Shown when there are no rows.
    let empty: String

    /// Every row in order; one in several groups is listed once per group.
    var rows: [Row] { groups.flatMap(\.rows) }
}

nonisolated enum QueryBlocks {
    /// Answers each request on `index`, leaving out empty ones, which the
    /// pages never send: an empty block is not a query. `matches` gets what
    /// each row stands for, keyed by `key(path:line:)`.
    static func results(for requests: [QueryBlockRequest], index: WorkspaceMetadataIndex,
                        today: JournalDay = JournalDay(date: Date()))
        async -> (results: [QueryBlockResult], matches: [String: WorkspaceQueryMatch]) {
        let parser = WorkspaceQueryParser(knownKeys: await index.attributeKeys(), today: today)
        var results: [QueryBlockResult] = []
        var matches: [String: WorkspaceQueryMatch] = [:]
        for request in requests where !request.text.allSatisfy(\.isWhitespace) {
            let parsed = parser.parse(request.text, source: request.source.querySource)
            let found = await index.run(parsed.query, fields: fields(of: parsed.display))
            for row in found { matches[key(path: row.match.path, line: row.match.line)] = row.match }
            results.append(result(for: request, parsed: parsed, rows: found))
        }
        return (results, matches)
    }

    /// What the query reads for `display`: its columns', then its group's.
    static func fields(of display: WorkspaceQueryDisplay) -> [WorkspaceQueryField] {
        (display.columns + [display.group].compactMap { $0 }).compactMap(\.queryField)
    }

    static func result(for request: QueryBlockRequest, parsed: WorkspaceQueryParser.Result,
                       rows found: [WorkspaceQueryRow]) -> QueryBlockResult {
        let display = parsed.display
        let isTable = display.view == .table
        var built: [(row: QueryBlockResult.Row, group: [QueryBlockResult.Value], sortValues: [WorkspaceAttributeValue])] = []
        let showsDetail = !(display.group.map { headerShowsDetail($0, source: request.source) } ?? false)
        for match in found {
            var values = match.values.makeIterator()
            var row = makeRow(match.match, detail: showsDetail)
            if isTable {
                row.cells = display.columns.map { column in
                    cell(column, values: column.queryField == nil ? [] : values.next() ?? [], row: row)
                }
            }
            let groupValues = display.group.map { group in
                group.queryField == nil ? [] : values.next() ?? []
            } ?? []
            let labels = display.group.map { cell($0, values: groupValues, row: row) } ?? []
            built.append((row, labels, groupValues))
        }

        let empty = request.source == .tasks
            ? NSLocalizedString("No matching tasks", comment: "Query block with no results")
            : NSLocalizedString("No matching notes", comment: "Query block with no results")
        let columns = isTable ? display.columns.map { column(for: $0, source: request.source) } : []
        let groups: [QueryBlockResult.Group]
        if let group = display.group {
            groups = grouped(built, by: group)
        } else {
            groups = [QueryBlockResult.Group(label: nil, kind: "none", rows: built.map(\.row))]
        }
        return QueryBlockResult(id: request.id, source: request.source.rawValue,
                                problems: parsed.problems.map(\.message), view: display.view.rawValue,
                                columns: columns, groups: groups, empty: empty)
    }

    /// Whether grouping by `field` puts a row's detail, a task's file or a
    /// note's folder, in the group's header, so the row need not repeat it.
    private static func headerShowsDetail(_ field: WorkspaceQueryDisplay.Field,
                                          source: QueryBlockRequest.Source) -> Bool {
        switch (field.kind, source) {
        case (.file, .tasks), (.attribute("file.name"), .tasks), (.attribute("file.path"), _),
             (.attribute("file.folder"), .notes): true
        default: false
        }
    }

    private static func makeRow(_ match: WorkspaceQueryMatch, detail: Bool) -> QueryBlockResult.Row {
        switch match {
        case let .task(task):
            return .init(path: task.path, line: task.task.line, text: task.task.text,
                         checked: task.task.checked, detail: detail ? fileTitle(task.path) : "",
                         source: task.task.source.isEmpty ? nil : task.task.source)
        case let .file(record):
            return .init(path: record.path, line: 1, text: record.title, checked: nil,
                         detail: detail ? (record.path as NSString).deletingLastPathComponent : "")
        }
    }

    // MARK: Cells

    /// The values `field` shows for `row`.
    private static func cell(_ field: WorkspaceQueryDisplay.Field, values: [WorkspaceAttributeValue],
                             row: QueryBlockResult.Row) -> [QueryBlockResult.Value] {
        switch field.kind {
        case .done, .text: return []
        case .file: return [QueryBlockResult.Value(text: fileTitle(row.path), path: row.path)]
        case .names: return values.map { QueryBlockResult.Value(text: $0.text) }
        case let .attribute(key): return values.map { value(of: $0, key: key) }
        }
    }

    private static func value(of attribute: WorkspaceAttributeValue, key: String) -> QueryBlockResult.Value {
        switch attribute {
        case let .link(destination, target, text):
            // The link's text, without its Markdown.
            let label = text.firstMatch(of: /^\[(.*)\]\(/).map { String($0.1) } ?? destination
            return QueryBlockResult.Value(text: label.isEmpty ? destination : label, path: target)
        case let .text(text) where key == "file.folder" && text.isEmpty:
            return QueryBlockResult.Value(text: "/")
        default:
            return QueryBlockResult.Value(text: attribute.text)
        }
    }

    /// How the page draws `field`'s values.
    private static func kind(of field: WorkspaceQueryDisplay.Field) -> String {
        switch field.kind {
        case .done: "done"
        case .text: "text"
        case .file: "value"
        case .names: "names"
        case .attribute("due"): "due"
        case .attribute("scheduled"): "scheduled"
        case .attribute("priority"): "p"
        case .attribute: "value"
        }
    }

    private static func column(for field: WorkspaceQueryDisplay.Field,
                               source: QueryBlockRequest.Source) -> QueryBlockResult.Column {
        let label: String = switch field.kind {
        case .done: NSLocalizedString("Done", comment: "Query table column")
        case .text: source == .tasks ? NSLocalizedString("Task", comment: "Query table column")
            : NSLocalizedString("Title", comment: "Query table column")
        case .file: NSLocalizedString("File", comment: "Query table column")
        case .names(.project): NSLocalizedString("Projects", comment: "Query table column")
        case .names(.context): NSLocalizedString("Contexts", comment: "Query table column")
        case .names(.tag): NSLocalizedString("Tags", comment: "Query table column")
        case .attribute("due"): NSLocalizedString("Due", comment: "Query table column")
        case .attribute("scheduled"): NSLocalizedString("Scheduled", comment: "Query table column")
        case .attribute("priority"): NSLocalizedString("Priority", comment: "Query table column")
        case .attribute("title"): NSLocalizedString("Title", comment: "Query table column")
        case .attribute("file.folder"): NSLocalizedString("Folder", comment: "Query table column")
        case .attribute("file.path"): NSLocalizedString("Path", comment: "Query table column")
        case .attribute("file.name"): NSLocalizedString("Name", comment: "Query table column")
        case .attribute("file.modified"): NSLocalizedString("Modified", comment: "Query table column")
        case .attribute("file.created"): NSLocalizedString("Created", comment: "Query table column")
        case .attribute("file.size"): NSLocalizedString("Size", comment: "Query table column")
        case .attribute: field.spelling
        }
        return QueryBlockResult.Column(kind: kind(of: field), label: label)
    }

    // MARK: Groups

    /// One group per value, ordered by value, then the rows with none. A row
    /// with several values is in each of their groups; rows keep the
    /// query's order inside a group.
    private static func grouped(
        _ built: [(row: QueryBlockResult.Row, group: [QueryBlockResult.Value], sortValues: [WorkspaceAttributeValue])],
        by field: WorkspaceQueryDisplay.Field
    ) -> [QueryBlockResult.Group] {
        struct Bucket {
            let label: QueryBlockResult.Value
            let sortValue: WorkspaceAttributeValue
            var rows: [QueryBlockResult.Row]
        }
        var buckets: [String: Bucket] = [:]
        var none: [QueryBlockResult.Row] = []
        for (row, labels, sortValues) in built {
            if labels.isEmpty {
                none.append(row)
                continue
            }
            var seen: Set<String> = []
            for (index, label) in labels.enumerated() {
                let key = label.path ?? WorkspacePage.key(label.text)
                guard seen.insert(key).inserted else { continue }
                let sortValue = index < sortValues.count ? sortValues[index] : .text(label.text)
                buckets[key, default: Bucket(label: label, sortValue: sortValue, rows: [])].rows.append(row)
            }
        }
        let descending = field.kind == .attribute("priority")
        let ordered = buckets.sorted { lhs, rhs in
            let order = WorkspaceQuery.order(lhs.value.sortValue, rhs.value.sortValue)
            if order != .orderedSame { return descending ? order == .orderedDescending : order == .orderedAscending }
            return lhs.key < rhs.key
        }
        let kind = kind(of: field)
        var groups = ordered.map { QueryBlockResult.Group(label: $0.value.label, kind: kind, rows: $0.value.rows) }
        if !none.isEmpty {
            groups.append(QueryBlockResult.Group(label: QueryBlockResult.Value(text: noValueLabel(field)),
                                                 kind: "none", rows: none))
        }
        return groups
    }

    private static func noValueLabel(_ field: WorkspaceQueryDisplay.Field) -> String {
        switch field.kind {
        case .names(.project): NSLocalizedString("No project", comment: "Query group of rows without one")
        case .names(.context): NSLocalizedString("No context", comment: "Query group of rows without one")
        case .names(.tag): NSLocalizedString("No tag", comment: "Query group of rows without one")
        case .attribute("due"): NSLocalizedString("No due date", comment: "Query group of rows without one")
        case .attribute("scheduled"):
            NSLocalizedString("No scheduled date", comment: "Query group of rows without one")
        case .attribute("priority"): NSLocalizedString("No priority", comment: "Query group of rows without one")
        default:
            String(format: NSLocalizedString("No %@", comment: "Query group of rows without a frontmatter key"),
                   field.spelling)
        }
    }

    static func key(path: String, line: Int) -> String { "\(path)\u{0}\(line)" }

    /// The file name without its extension.
    private static func fileTitle(_ path: String) -> String {
        ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }
}
