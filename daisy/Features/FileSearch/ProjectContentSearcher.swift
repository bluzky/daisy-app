//
//  ProjectContentSearcher.swift
//  daisy
//
//  Finds a phrase inside the project's Markdown files for OmniSearch. A plain
//  streaming scan over the file index rather than a content index of its own:
//  Markdown projects are small, a scan has nothing to keep fresh, and a
//  newer keystroke simply abandons the pass. Free of AppKit so the SPM
//  helper tests can pin the matching and snippet rules down.
//

import Foundation

nonisolated enum ProjectContentSearcher {

    /// Where a query first matched inside one file.
    struct Match: Sendable, Equatable {
        /// The first matching line, trimmed to a window around the match.
        let snippet: String
        /// Occurrences inside `snippet`, as `Character` offsets, ready for
        /// `FileSearchMatcher.nsRanges`.
        let snippetRanges: [Range<Int>]
    }

    struct Hit: Sendable, Equatable {
        let url: URL
        let candidate: FileSearchMatcher.Candidate
        let match: Match
    }

    /// Shorter queries match nearly every file and say nothing about intent.
    static let minimumQueryLength = 3
    /// A Markdown file past this size is not prose a reader is looking up.
    static let maximumFileBytes = 2_000_000
    /// How many hits the palette shows.
    static let displayLimit = 8
    /// Characters kept either side of the match in a snippet.
    static let snippetContext = 40
    /// Files scanned between checks for cancellation.
    static let cancellationCheckInterval = 16

    static func isSearchable(_ query: String) -> Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).count >= minimumQueryLength
    }

    // MARK: - One file

    /// Case-insensitive substring match of `query` in `text`. Finds the first
    /// occurrence only: that is all a row shows, and looking for more would
    /// cost a pass over the rest of every file that matches.
    static func match(query: String, in text: String) -> Match? {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty,
              let first = text.range(of: needle, options: .caseInsensitive) else { return nil }

        let lineRange = text.lineRange(for: first)
        let line = String(text[lineRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let inLine = line.range(of: needle, options: .caseInsensitive) else { return nil }

        let characters = Array(line)
        let start = line.distance(from: line.startIndex, to: inLine.lowerBound)
        let length = line.distance(from: inLine.lowerBound, to: inLine.upperBound)
        let windowStart = max(0, start - snippetContext)
        let windowEnd = min(characters.count, start + length + snippetContext)
        let leading = windowStart > 0 ? "…" : ""
        let trailing = windowEnd < characters.count ? "…" : ""
        let snippet = leading + String(characters[windowStart..<windowEnd]) + trailing

        return Match(snippet: snippet, snippetRanges: occurrences(of: needle, in: snippet))
    }

    private static func occurrences(of needle: String, in string: String) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var from = string.startIndex
        while from < string.endIndex,
              let found = string.range(of: needle, options: .caseInsensitive, range: from..<string.endIndex) {
            let lower = string.distance(from: string.startIndex, to: found.lowerBound)
            let upper = string.distance(from: string.startIndex, to: found.upperBound)
            ranges.append(lower..<upper)
            from = found.upperBound
        }
        return ranges
    }

    // MARK: - The project

    /// Scans the snapshot's files in the project's own order, calling `report`
    /// with the hits so far as each turns up and once more, flagged done. It
    /// stops at `displayLimit` hits: nothing ranks them, so reading the rest of
    /// the project would only find hits that are never shown. Throws
    /// `CancellationError` as soon as the surrounding task is cancelled.
    ///
    /// `skipping` holds files already on screen for another reason — a file
    /// whose name matched should not be listed again for its contents.
    @concurrent
    static func scan(query: String,
                     snapshot: ProjectFileIndex.Snapshot,
                     skipping: Set<URL>,
                     report: @escaping @Sendable ([Hit], Bool) async -> Void) async throws {
        guard isSearchable(query) else {
            await report([], true)
            return
        }
        var hits: [Hit] = []
        for index in snapshot.candidates.indices {
            if index % cancellationCheckInterval == 0 { try Task.checkCancellation() }
            guard let url = snapshot.url(at: index),
                  !skipping.contains(url.standardizedFileURL),
                  let text = readText(at: url),
                  let match = match(query: query, in: text) else { continue }
            hits.append(Hit(url: url, candidate: snapshot.candidates[index], match: match))
            if hits.count >= displayLimit { break }
            await report(hits, false)
        }
        try Task.checkCancellation()
        await report(hits, true)
    }

    private static func readText(at url: URL) -> String? {
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maximumFileBytes {
            return nil
        }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
