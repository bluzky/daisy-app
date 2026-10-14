//
//  CodeDocument.swift
//  daisy
//
//  What a source or text file needs that a Markdown file does not: the
//  highlighting language, a preview stand-in, and the limits past which Daisy
//  leaves the file to another app. Free of AppKit.
//

import Foundation

nonisolated enum CodeDocument {
    /// Larger files open in the default app instead of the editor.
    static let maximumBytes = 5 * 1024 * 1024

    private static let languageOverrides: [String: String] = [
        "m": "objective-c", "mjs": "javascript", "cjs": "javascript",
        "bashrc": "bash", "zshrc": "bash", "zprofile": "bash", "profile": "bash",
    ]

    /// A `CodeLanguageCatalog` id for the file, or "" to edit it as plain text.
    static func language(forFileName fileName: String) -> String {
        let name = fileName.lowercased()
        var ext = (name as NSString).pathExtension
        // A dotfile such as `.zshrc` has no extension; its name is the key.
        if ext.isEmpty, name.hasPrefix(".") { ext = String(name.dropFirst()) }
        if let override = languageOverrides[ext] { return override }
        guard !ext.isEmpty else { return "" }
        let match = CodeLanguageCatalog.all.first { option in
            option.id == ext || option.aliases.split(separator: " ").contains { $0 == ext }
        }
        guard let match, match.id != "text" else { return "" }
        return match.id
    }

    /// True when Daisy can edit the file at `url`: small enough and valid
    /// UTF-8. Saving a file read any other way could corrupt it.
    static func isEditable(at url: URL) -> Bool {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= maximumBytes,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return false }
        return String(data: data, encoding: .utf8) != nil
    }
}
