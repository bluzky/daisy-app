//
//  WorkspaceReferences.swift
//  daisy
//
//  What the References panel lists for one file: the files that point at
//  it, each with the lines that do. "Linked" holds Markdown links to it;
//  "Mentions" holds the tokens whose page it is, so it is empty unless the
//  file is a page in `pages/`. Built from the records the References query
//  matched. No AppKit, so it links into `tests/swift-tests`.
//

import Foundation

nonisolated struct WorkspaceReferences: Equatable, Sendable {
    /// One line of a source file, as written.
    nonisolated struct Occurrence: Equatable, Sendable {
        let line: Int
        let excerpt: String
    }

    /// A file that refers to the target, with the lines that do, in order.
    nonisolated struct Source: Equatable, Sendable {
        /// Root-relative.
        let path: String
        let occurrences: [Occurrence]
    }

    var linked: [Source] = []
    var mentions: [Source] = []

    var isEmpty: Bool { linked.isEmpty && mentions.isEmpty }

    init(linked: [Source] = [], mentions: [Source] = []) {
        self.linked = linked
        self.mentions = mentions
    }

    /// The references to `path` among `records`, which are the matches of
    /// `WorkspaceQuery.references(to:tokens:)`. `pageTokens` are the names
    /// whose page `path` is. Several links or tokens on one line make one
    /// occurrence.
    init(to path: String, records: [WorkspaceFileRecord],
         pageTokens: [(kind: WorkspaceMetadataKind, key: String)]) {
        let names = Set(pageTokens.map { Name(kind: $0.kind, key: $0.key) })
        for record in records where record.path != path {
            let links: [Occurrence] = record.links.compactMap { link in
                link.target == path ? Occurrence(line: link.line, excerpt: link.excerpt) : nil
            }
            if let source = Self.source(record.path, links) { linked.append(source) }
            let tokens: [Occurrence] = record.tokens.compactMap { token in
                names.contains(Name(kind: token.kind, key: token.key))
                    ? Occurrence(line: token.line, excerpt: token.excerpt) : nil
            }
            if let source = Self.source(record.path, tokens) { mentions.append(source) }
        }
        linked.sort { $0.path < $1.path }
        mentions.sort { $0.path < $1.path }
    }

    private nonisolated struct Name: Hashable {
        let kind: WorkspaceMetadataKind
        let key: String
    }

    private static func source(_ path: String, _ occurrences: [Occurrence]) -> Source? {
        var seen = Set<Int>()
        let lines = occurrences.sorted { $0.line < $1.line }.filter { seen.insert($0.line).inserted }
        return lines.isEmpty ? nil : Source(path: path, occurrences: lines)
    }
}
