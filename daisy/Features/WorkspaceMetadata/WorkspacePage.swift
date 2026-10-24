//
//  WorkspacePage.swift
//  daisy
//
//  The page a `#tag`, `@context` or `+project` opens: a Markdown file in the
//  workspace's `pages/` folder, named after the token with its marker, so
//  `#daisy`, `@daisy` and `+daisy` are three pages. A `/` in a hierarchical
//  name becomes `--`: `#area/sub` is `pages/#area--sub.md`. An existing page
//  is found ignoring case; a missing one is created holding only `# <token>`.
//
//  Creating a page is, with creating a journal entry (`WorkspaceJournal`),
//  the only write into a workspace besides the marker, and happens only when
//  the user opens a token. No AppKit, so it links into
//  `tests/swift-tests`.
//

import Foundation

nonisolated enum WorkspacePage {
    static let folderName = "pages"

    enum PageError: LocalizedError {
        case invalidToken(String)
        case outsideWorkspace

        var errorDescription: String? {
            switch self {
            case .invalidToken(let token):
                String(format: NSLocalizedString("“%@” is not a tag, context or project.",
                                                 comment: "Workspace page error"), token)
            case .outsideWorkspace:
                NSLocalizedString("The pages folder is outside the workspace.", comment: "Workspace page error")
            }
        }
    }

    /// `<marker><name>.md`, or nil when `token` is not a valid token. The rules
    /// match `scripts/editor-bundle/src/metadata-names.js`.
    static func fileName(for token: String) -> String? {
        guard let marker = token.unicodeScalars.first, "#@+".unicodeScalars.contains(marker) else { return nil }
        let name = String(token.unicodeScalars.dropFirst())
        guard let first = name.unicodeScalars.first, isTokenStart(first),
              name.unicodeScalars.allSatisfy(isTokenCharacter),
              name.unicodeScalars.contains(where: isLetter),
              name.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty })
        else { return nil }
        return String(marker) + name.replacingOccurrences(of: "/", with: "--") + ".md"
    }

    /// The existing page for `token`, or nil. An exact spelling wins; then
    /// any spelling that differs only in case or Unicode form, in name order.
    static func resolve(token: String, root: URL) throws -> URL? {
        guard let fileName = fileName(for: token) else { throw PageError.invalidToken(token) }
        let folder = try pagesFolder(root: root)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return nil }
        let wanted = key(fileName)
        let exact = fileName.precomposedStringWithCanonicalMapping
        let matches = names.filter { name in
            guard key(name) == wanted else { return false }
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: folder.appendingPathComponent(name).path,
                                                  isDirectory: &isDirectory) && !isDirectory.boolValue
        }.sorted()
        guard let name = matches.first(where: { $0.precomposedStringWithCanonicalMapping == exact }) ?? matches.first
        else { return nil }
        let page = folder.appendingPathComponent(name)
        // A page that is a symlink must still land in the pages folder.
        guard page.resolvingSymlinksInPath().deletingLastPathComponent().path
                == folder.resolvingSymlinksInPath().path else { throw PageError.outsideWorkspace }
        return page
    }

    /// The page for `token`, created with its H1 when there is none. Never
    /// replaces a file; a failed write leaves nothing behind.
    static func openOrCreate(token: String, root: URL) throws -> URL {
        if let page = try resolve(token: token, root: root) { return page }
        guard let fileName = fileName(for: token) else { throw PageError.invalidToken(token) }
        let folder = try pagesFolder(root: root)
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        let createdFolder = !fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory)
        if createdFolder {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: false)
        }
        let page = folder.appendingPathComponent(fileName)
        do {
            try Data("# \(token)\n".utf8).write(to: page, options: .withoutOverwriting)
        } catch {
            // Another writer got there first: open its page.
            if let existing = try? resolve(token: token, root: root) { return existing }
            if createdFolder { try? fileManager.removeItem(at: folder) }
            throw error
        }
        return page
    }

    /// `<root>/pages`, refused when it resolves outside the root.
    private static func pagesFolder(root: URL) throws -> URL {
        let folder = root.appendingPathComponent(folderName, isDirectory: true)
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL.path
        let resolved = folder.resolvingSymlinksInPath().standardizedFileURL.path
        guard resolved.hasPrefix(resolvedRoot.hasSuffix("/") ? resolvedRoot : resolvedRoot + "/") else {
            throw PageError.outsideWorkspace
        }
        return folder
    }

    /// The extractor's lookup key: NFKC, then lowercase.
    static func key(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping.lowercased(with: Locale(identifier: "en_US"))
    }

    private static func isLetter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter: true
        default: false
        }
    }

    private static func isNumber(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .decimalNumber, .letterNumber, .otherNumber: true
        default: false
        }
    }

    private static func isMark(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: true
        default: false
        }
    }

    private static func isTokenStart(_ scalar: Unicode.Scalar) -> Bool {
        isLetter(scalar) || isNumber(scalar) || scalar == "_" || scalar == "-"
    }

    private static func isTokenCharacter(_ scalar: Unicode.Scalar) -> Bool {
        isTokenStart(scalar) || isMark(scalar) || scalar == "/"
    }
}
