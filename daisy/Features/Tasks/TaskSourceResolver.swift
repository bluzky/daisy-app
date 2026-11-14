//
//  TaskSourceResolver.swift
//  daisy
//
//  Finds an indexed task in a file's current text, whose line number may be
//  stale: the indexed line when it still holds a task with the indexed text,
//  otherwise the only task with that text. None, or more than one, and the
//  task is not found, so nothing is written. Tasks are read with the shared
//  extractor, so a task in a code block is never matched.
//
//  No AppKit, so it links into `tests/swift-tests`.
//

import Foundation

nonisolated enum TaskSourceResolver {
    /// The task as it is in `markdown` now, or nil.
    static func find(_ task: WorkspaceTaskMetadata, in markdown: String) -> WorkspaceTaskMetadata? {
        guard let tasks = WorkspaceMetadataExtractor.extract(markdown)?.tasks else { return nil }
        if let same = tasks.first(where: { $0.line == task.line && $0.text == task.text }) { return same }
        let matches = tasks.filter { $0.text == task.text }
        return matches.count == 1 ? matches[0] : nil
    }

    nonisolated struct Change: Equatable, Sendable {
        let line: Int
        /// The whole text with the marker set; unchanged when it already was.
        let markdown: String
        let isChange: Bool
    }

    /// `markdown` with the task's checkbox set to `checked`, or nil when the
    /// task can't be found unambiguously.
    static func settingChecked(_ checked: Bool, task: WorkspaceTaskMetadata, in markdown: String) -> Change? {
        guard let found = find(task, in: markdown) else { return nil }
        guard found.checked != checked else {
            return Change(line: found.line, markdown: markdown, isChange: false)
        }
        guard let updated = TaskCheckboxSource.settingChecked(checked, onLine: found.line, in: markdown) else {
            return nil
        }
        return Change(line: found.line, markdown: updated, isChange: true)
    }

    // The extractor parses the whole file, so callers on the main actor use
    // these to keep a large file from stalling the UI.

    @concurrent
    static func findConcurrently(_ task: WorkspaceTaskMetadata, in markdown: String) async -> WorkspaceTaskMetadata? {
        find(task, in: markdown)
    }

    @concurrent
    static func settingCheckedConcurrently(_ checked: Bool, task: WorkspaceTaskMetadata,
                                           in markdown: String) async -> Change? {
        settingChecked(checked, task: task, in: markdown)
    }
}
