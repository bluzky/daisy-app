//
//  WorkspaceQueryBlocks.swift
//  daisy
//
//  What a ```tasks or ```notes block asks of the workspace and what the
//  preview shows for it. The page sends a `QueryBlockRequest` per block; the
//  window answers each with a `QueryBlockResult` built here: the parser's
//  problems, then one row per match. No AppKit, so it links into
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

/// Encoded for the page's `MdPreview.queryResults`.
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
    }

    let id: String
    let source: String
    let problems: [String]
    let rows: [Row]
    /// Shown when there are no rows.
    let empty: String
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
            let found = await index.run(parsed.query)
            for match in found { matches[key(path: match.path, line: match.line)] = match }
            results.append(result(for: request, parsed: parsed, matches: found))
        }
        return (results, matches)
    }

    static func result(for request: QueryBlockRequest, parsed: WorkspaceQueryParser.Result,
                       matches: [WorkspaceQueryMatch]) -> QueryBlockResult {
        let rows = matches.map { match -> QueryBlockResult.Row in
            switch match {
            case let .task(task):
                return .init(path: task.path, line: task.task.line, text: task.task.text,
                             checked: task.task.checked, detail: fileTitle(task.path),
                             source: task.task.source.isEmpty ? nil : task.task.source)
            case let .file(record):
                let title = record.attributes["title"].map(\.value.text).flatMap { $0.isEmpty ? nil : $0 }
                return .init(path: record.path, line: 1, text: title ?? fileTitle(record.path), checked: nil,
                             detail: (record.path as NSString).deletingLastPathComponent)
            }
        }
        let empty = request.source == .tasks
            ? NSLocalizedString("No matching tasks", comment: "Query block with no results")
            : NSLocalizedString("No matching notes", comment: "Query block with no results")
        return QueryBlockResult(id: request.id, source: request.source.rawValue,
                                problems: parsed.problems.map(\.message), rows: rows, empty: empty)
    }

    static func key(path: String, line: Int) -> String { "\(path)\u{0}\(line)" }

    /// The file name without its extension.
    private static func fileTitle(_ path: String) -> String {
        ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }
}
