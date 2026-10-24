//
//  WorkspaceFileRecord.swift
//  daisy
//
//  What the workspace index keeps for one Markdown file, built from one
//  extractor run: its frontmatter attributes, tokens, links and tasks.
//  Queries (`WorkspaceQuery`) run over these records. Link destinations are
//  resolved against the workspace root here, so a record can say which
//  files it points at. No AppKit, so it links into `tests/swift-tests`.
//

import Foundation

nonisolated struct WorkspaceFileRecord: Equatable, Sendable {
    /// Root-relative, the index's key.
    let path: String
    /// Frontmatter attributes by normalized key.
    var attributes: [String: WorkspaceMetadataAttribute]
    /// Tags, then contexts, then projects, each in reading order.
    var tokens: [WorkspaceTokenOccurrence]
    var links: [WorkspaceLinkOccurrence]
    var tasks: [WorkspaceTaskMetadata]

    init(path: String, attributes: [String: WorkspaceMetadataAttribute] = [:],
         tokens: [WorkspaceTokenOccurrence] = [], links: [WorkspaceLinkOccurrence] = [],
         tasks: [WorkspaceTaskMetadata] = []) {
        self.path = path
        self.attributes = attributes
        self.tokens = tokens
        self.links = links
        self.tasks = tasks
    }

    /// The record for the file at `path` holding what `metadata` read, with
    /// links resolved against `root`.
    init(path: String, metadata: WorkspaceMetadata, root: URL) {
        self.path = path
        var attributes: [String: WorkspaceMetadataAttribute] = [:]
        for attribute in metadata.attributes where attributes[attribute.key] == nil {
            attributes[attribute.key] = WorkspaceMetadataAttribute(
                key: attribute.key, spelling: attribute.spelling, line: attribute.line,
                value: Self.resolved(attribute.value, from: path, root: root))
        }
        self.attributes = attributes
        tokens = WorkspaceMetadataKind.allCases.flatMap { kind in
            metadata.tokens(kind).map { WorkspaceTokenOccurrence(kind: kind, $0) }
        }
        links = metadata.links.map { link in
            WorkspaceLinkOccurrence(destination: link.destination,
                                    target: Self.target(of: link.destination, from: path, root: root),
                                    line: link.line, excerpt: link.excerpt)
        }
        tasks = metadata.tasks
    }

    /// Name occurrences, for completion's counts.
    var contribution: WorkspaceMetadataContribution { WorkspaceMetadataContribution(tokens) }

    private static func resolved(_ value: WorkspaceAttributeValue, from path: String,
                                 root: URL) -> WorkspaceAttributeValue {
        switch value {
        case let .link(destination, _, text):
            .link(destination: destination, target: target(of: destination, from: path, root: root), text: text)
        case let .list(items):
            .list(items.map { resolved($0, from: path, root: root) })
        default:
            value
        }
    }

    // MARK: - Link targets

    /// The root-relative path `destination` points at from the file at
    /// `path`, or nil when it leaves the root. Read the way
    /// `DocumentLink.target(relativeTo:)` reads it: a `file:` URL, a path
    /// starting with `/` or `~/`, or one relative to the file's folder,
    /// percent-decoded, without its `#fragment`.
    static func target(of destination: String, from path: String, root: URL) -> String? {
        var absolute: URL
        if let url = URL(string: destination), url.scheme?.lowercased() == "file" {
            absolute = URL(fileURLWithPath: url.path(percentEncoded: false))
        } else {
            var value = destination
            if let hash = value.firstIndex(of: "#") { value = String(value[..<hash]) }
            value = value.removingPercentEncoding ?? value
            guard !value.isEmpty else { return nil }
            if value.hasPrefix("~/") { value = (value as NSString).expandingTildeInPath }
            if value.hasPrefix("/") {
                absolute = URL(fileURLWithPath: value)
            } else {
                absolute = root
                for component in path.split(separator: "/").dropLast() {
                    absolute.append(path: String(component), directoryHint: .isDirectory)
                }
                absolute.append(path: value, directoryHint: .notDirectory)
            }
        }
        absolute = absolute.standardizedFileURL
        if let relative = relativePath(of: absolute, root: root) { return relative }
        // An absolute path may name the root through a symlink (`/tmp` for
        // `/private/tmp`).
        return relativePath(of: absolute.resolvingSymlinksInPath(), root: root)
    }

    private static func relativePath(of url: URL, root: URL) -> String? {
        let rootComponents = root.standardizedFileURL.pathComponents
        let components = url.pathComponents
        guard components.count > rootComponents.count,
              Array(components.prefix(rootComponents.count)) == rootComponents else { return nil }
        let relative = components.dropFirst(rootComponents.count).joined(separator: "/")
        return WorkspaceIndexStore.isSafeRelativePath(relative) ? relative : nil
    }
}

/// An inline link from a file, as written and as resolved.
nonisolated struct WorkspaceLinkOccurrence: Equatable, Sendable {
    /// As written, for a later rename-rewrite.
    let destination: String
    /// Root-relative, or nil when the destination leaves the root.
    let target: String?
    let line: Int
    let excerpt: String
}

nonisolated extension WorkspaceTaskMetadata {
    /// `due`, `scheduled` and `priority` as attributes, so a query reads a
    /// task the way it reads a file's frontmatter.
    var attributes: [String: WorkspaceMetadataAttribute] {
        var attributes: [String: WorkspaceMetadataAttribute] = [:]
        for (key, value) in [("due", due), ("scheduled", scheduled)] {
            guard let value, let day = JournalDay(string: value) else { continue }
            attributes[key] = WorkspaceMetadataAttribute(key: key, spelling: key, line: line, value: .date(day))
        }
        if let priority {
            attributes["priority"] = WorkspaceMetadataAttribute(key: "priority", spelling: "p", line: line,
                                                                value: .text(priority))
        }
        return attributes
    }
}
