//
//  FileKind.swift
//  daisy
//
//  The one answer to "what do we do with this file?". The sidebar, OmniSearch,
//  recents and the open panel all ask here instead of keeping an extension
//  list each. Free of AppKit so the SPM helper tests and the off-main-actor
//  index walk can use it.
//

import Foundation

nonisolated enum FileKind: Sendable, Equatable {
    /// Rendered and edited as Markdown.
    case markdown
    /// Source or plain text, edited as code with no preview.
    case text
    /// Anything Daisy does not edit. Handed to the system's default app.
    case external

    /// Same list as `ProjectFileIndex.markdownExtensions`, plus `mkdn`, which
    /// links already treat as Markdown.
    static let markdownExtensions: Set<String> = ProjectFileIndex.markdownExtensions.union(["mkdn"])

    static func classify(_ url: URL) -> FileKind {
        classify(fileName: url.lastPathComponent)
    }

    static func classify(fileName: String) -> FileKind {
        let ext = (fileName as NSString).pathExtension.lowercased()
        if markdownExtensions.contains(ext) { return .markdown }
        if TextFileSettings.isText(fileName: fileName) { return .text }
        return .external
    }

    /// Files Daisy opens itself rather than handing to another app.
    var opensInDaisy: Bool { self != .external }
}
