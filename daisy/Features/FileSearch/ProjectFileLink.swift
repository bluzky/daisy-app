//
//  ProjectFileLink.swift
//  daisy
//
//  The Markdown link Insert > Link to File… writes for a file picked from the
//  project: a path relative to the document, so the link keeps working when
//  the project folder moves or is opened on another machine.
//

import Foundation

nonisolated enum ProjectFileLink {

    /// `target` relative to the folder holding `documentURL`, percent-encoded
    /// per component so spaces and parentheses cannot end the link early.
    static func destination(to target: URL, from documentURL: URL) -> String {
        let base = components(of: documentURL.deletingLastPathComponent())
        let path = components(of: target)
        var shared = 0
        while shared < base.count, shared < path.count, base[shared] == path[shared] {
            shared += 1
        }
        let parts = Array(repeating: "..", count: base.count - shared) + path[shared...]
        return parts.map(encode).joined(separator: "/")
    }

    /// The text shown for the link when nothing is selected: the file's name,
    /// without the extension for Markdown, since that reads as a page title.
    static func defaultText(for target: URL) -> String {
        FileKind.classify(target) == .markdown
            ? target.deletingPathExtension().lastPathComponent
            : target.lastPathComponent
    }

    /// Resolves symlinks so `/tmp` and `/private/tmp` share their prefix.
    private static func components(of url: URL) -> [String] {
        url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
    }

    private static let allowed: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove(charactersIn: "/()")
        return set
    }()

    private static func encode(_ component: String) -> String {
        component == ".." ? component
            : component.addingPercentEncoding(withAllowedCharacters: allowed) ?? component
    }
}
