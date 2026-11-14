//
//  DocumentLinks.swift
//  daisy
//
//  The inline links a document makes, `[text](destination)`, in reading
//  order: web and mail links, links to other files, and links to a section
//  of this document. Autolinks (`<https://…>`), reference links
//  (`[text][ref]`), bare URLs and images are left out. The editor's
//  Cmd+click resolves a destination with `DocumentLink.target(relativeTo:)`.
//

import Foundation
import Markdown

struct DocumentLink: Equatable, Identifiable {
    enum Kind: Equatable {
        /// Has a scheme other than `file:` — opened by the system.
        case web
        /// A path, relative to the document or absolute, or a `file:` URL.
        case file
        /// `#fragment` — a heading or anchor in this document.
        case section
    }

    let id: Int
    let text: String
    let destination: String

    var kind: Kind {
        if destination.hasPrefix("#") { return .section }
        if let scheme = URL(string: destination)?.scheme, scheme.lowercased() != "file", scheme.count > 1 {
            // One letter is a Windows drive (`C:\…`), not a scheme.
            return .web
        }
        return .file
    }

    /// What activating the link should do. Nil when it cannot be resolved:
    /// a relative path in a document that has not been saved anywhere.
    func target(relativeTo documentURL: URL?) -> LinkTarget? {
        switch kind {
        case .section:
            let fragment = String(destination.dropFirst())
            return .section(fragment.removingPercentEncoding ?? fragment)
        case .web:
            return URL(string: destination).map(LinkTarget.external)
        case .file:
            var path = destination
            var fragment: String?
            if let hash = path.firstIndex(of: "#") {
                fragment = String(path[path.index(after: hash)...])
                fragment = fragment?.removingPercentEncoding ?? fragment
                path = String(path[..<hash])
            }
            if let url = URL(string: path), url.scheme?.lowercased() == "file" {
                return .file(url.standardizedFileURL, fragment: fragment)
            }
            path = path.removingPercentEncoding ?? path
            if path.hasPrefix("~/") {
                path = (path as NSString).expandingTildeInPath
            }
            if path.hasPrefix("/") {
                return .file(URL(fileURLWithPath: path).standardizedFileURL, fragment: fragment)
            }
            guard let folder = documentURL?.deletingLastPathComponent() else { return nil }
            return .file(folder.appendingPathComponent(path).standardizedFileURL, fragment: fragment)
        }
    }

    /// Every inline link in `markdown` (frontmatter already removed), first
    /// to last. A link repeated with the same text is listed once.
    static func collect(from markdown: String) -> [DocumentLink] {
        var collector = Collector(lines: markdown.split(separator: "\n", omittingEmptySubsequences: false))
        collector.visit(Document(parsing: markdown))
        return collector.links
    }

    private struct Collector: MarkupWalker {
        let lines: [Substring]
        var links: [DocumentLink] = []
        private var seen = Set<[String]>()

        init(lines: [Substring]) {
            self.lines = lines
        }

        /// The parser reports every link kind as `Link`. Only the inline form
        /// ends in `)`: an autolink ends in `>`, a reference link in `]`.
        private func isInline(_ link: Link) -> Bool {
            guard let end = link.range?.upperBound, lines.indices.contains(end.line - 1) else { return false }
            let line = lines[end.line - 1].utf8
            // Columns are 1-based UTF-8 offsets; the end is exclusive.
            let last = end.column - 2
            guard last >= 0, last < line.count else { return false }
            return line[line.index(line.startIndex, offsetBy: last)] == UInt8(ascii: ")")
        }

        mutating func visitLink(_ link: Link) {
            guard isInline(link),
                  let destination = link.destination?.trimmingCharacters(in: .whitespaces),
                  !destination.isEmpty else { return }
            let text = link.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard seen.insert([text, destination]).inserted else { return }
            links.append(DocumentLink(id: links.count, text: text, destination: destination))
        }
    }
}
