//
//  JournalCarryOver.swift
//  daisy
//
//  Moving unfinished tasks forward: when today's journal entry is created,
//  each unchecked `- [ ]` task in the entries of the days before it (seven
//  by default, see `JournalSetting`) moves into the new entry, with
//  everything nested under it, and is removed from the day it was on.
//
//  A task under a checked task stays with its parent, and tasks in a
//  blockquote, a code block or frontmatter are not tasks here. Moved tasks
//  keep their text and are dedented to the top level.
//
//  The new entry is written before any old one changes, and an old entry is
//  rewritten only while it still holds what was read, so a failure leaves a
//  task in both entries rather than in neither.
//
//  No AppKit, so it links into `tests/swift-tests`.
//

import Foundation
import Markdown

enum JournalCarryOver {
    /// An entry that loses tasks: what it held when read, and what it keeps.
    struct Source: Equatable {
        let day: JournalDay
        let original: Data
        let remaining: String
    }

    struct Plan: Equatable {
        /// The moved tasks, oldest day first, each line ending in a newline.
        let tasks: String
        let sources: [Source]
    }

    /// What moves into `day`'s new entry from the `lookBack` days before it.
    /// Nil when nothing would. `excluding` skips an entry by its URL, as one
    /// open with unsaved edits is skipped.
    static func plan(for day: JournalDay, lookBack: Int, root: URL,
                     excluding: (URL) -> Bool = { _ in false }) -> Plan? {
        let earliest = day.adding(days: -max(lookBack, 0))
        let days = WorkspaceJournal.entryDays(root: root).filter { $0 >= earliest && $0 < day }.sorted()
        var tasks = ""
        var sources: [Source] = []
        for sourceDay in days {
            guard let url = try? WorkspaceJournal.resolve(day: sourceDay, root: root), !excluding(url),
                  let data = WorkspaceJournal.readEntry(day: sourceDay, root: root),
                  let text = String(data: data, encoding: .utf8),
                  let split = extract(from: text) else { continue }
            tasks += split.tasks
            sources.append(Source(day: sourceDay, original: data, remaining: split.remaining))
        }
        return sources.isEmpty ? nil : Plan(tasks: tasks, sources: sources)
    }

    /// Removes the moved tasks from their entries, once the new entry holds
    /// them. Returns the days that still hold theirs: changed since they
    /// were read, or not writable.
    static func apply(_ plan: Plan, root: URL) -> [JournalDay] {
        plan.sources.filter { source in
            let replaced = try? WorkspaceJournal.replaceEntry(day: source.day, root: root,
                                                              expected: source.original,
                                                              with: source.remaining)
            return replaced != true
        }.map(\.day)
    }

    /// The unchecked tasks in `markdown`, and `markdown` without them. Nil
    /// when it has none, or has a lone carriage return, whose line numbering
    /// the parser and this splitter could disagree on.
    static func extract(from markdown: String) -> (tasks: String, remaining: String)? {
        let bytes = Array(markdown.utf8)
        for (index, byte) in bytes.enumerated() where byte == 0x0D {
            guard index + 1 < bytes.count, bytes[index + 1] == 0x0A else { return nil }
        }
        let lines = splitLines(markdown)
        let bodyStart = frontmatterLineCount(lines)
        let document = Document(parsing: markdown)
        var spans: [(lines: Range<Int>, indent: Int)] = []
        collect(document, into: &spans)

        var moved = IndexSet()
        var tasks = ""
        for span in spans {
            var range = span.lines.clamped(to: 0..<lines.count)
            guard range.lowerBound >= bodyStart, !range.isEmpty,
                  isIndent(lines[range.lowerBound].utf8.prefix(span.indent)) else { continue }
            while range.count > 1, isBlank(lines[range.upperBound - 1]) {
                range = range.lowerBound..<(range.upperBound - 1)
            }
            guard !moved.contains(integersIn: range) else { continue }
            moved.insert(integersIn: range)
            for line in lines[range] {
                tasks += dedent(line, by: span.indent)
            }
        }
        guard !moved.isEmpty else { return nil }
        let remaining = lines.indices.filter { !moved.contains($0) }.map { lines[$0] }.joined()
        return (tasks, remaining)
    }

    /// Unchecked task items, outermost only: a task's children move with it,
    /// a checked task's stay. Blockquotes are not entered.
    private static func collect(_ markup: Markup, into spans: inout [(lines: Range<Int>, indent: Int)]) {
        for child in markup.children {
            if let item = child as? ListItem, let checkbox = item.checkbox {
                if checkbox == .unchecked, let range = item.range {
                    spans.append((range.lowerBound.line - 1..<range.upperBound.line,
                                  range.lowerBound.column - 1))
                }
                continue
            }
            if child is BlockQuote { continue }
            collect(child, into: &spans)
        }
    }

    /// Lines with their own line endings, `\r\n` kept whole.
    private static func splitLines(_ text: String) -> [String] {
        var lines: [String] = []
        var current = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            current.append(scalar)
            if scalar == "\n" {
                lines.append(String(current))
                current = String.UnicodeScalarView()
            }
        }
        if !current.isEmpty { lines.append(String(current)) }
        return lines
    }

    /// The lines a leading `---` or `+++` block takes, delimiters included;
    /// 0 when there is none or it never closes (see `MarkdownFrontmatter`).
    private static func frontmatterLineCount(_ lines: [String]) -> Int {
        guard let first = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{FEFF}", with: ""),
              first == "---" || first == "+++" else { return 0 }
        let closers: Set<String> = first == "---" ? ["---", "..."] : ["+++"]
        guard let close = lines.dropFirst().firstIndex(where: {
            closers.contains($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }) else { return 0 }
        return close + 1
    }

    private static func isIndent<S: Sequence>(_ bytes: S) -> Bool where S.Element == UInt8 {
        bytes.allSatisfy { $0 == 0x20 || $0 == 0x09 }
    }

    private static func isBlank(_ line: String) -> Bool {
        line.allSatisfy(\.isWhitespace)
    }

    /// Up to `count` leading spaces or tabs removed, the line ending made `\n`.
    private static func dedent(_ line: String, by count: Int) -> String {
        var scalars = Substring(line).unicodeScalars[...]
        var removed = 0
        while removed < count, let first = scalars.first, first == " " || first == "\t" {
            scalars = scalars.dropFirst()
            removed += 1
        }
        var text = String(String.UnicodeScalarView(scalars))
        if text.hasSuffix("\r\n") {
            text.removeLast()
            text += "\n"
        } else if !text.hasSuffix("\n") {
            text += "\n"
        }
        return text
    }
}
