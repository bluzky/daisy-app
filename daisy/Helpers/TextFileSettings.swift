//
//  TextFileSettings.swift
//  daisy
//
//  Which files Daisy edits as code or plain text. A built-in list, plus the
//  extensions and file names the reader adds in Settings. Free of AppKit so
//  `FileKind` can ask from the index walk, off the main actor.
//

import Foundation
import Synchronization

nonisolated enum TextFileSettings {
    /// Same key and comma-separated format as the earlier text-file option, so
    /// a list a reader already saved keeps working.
    static let defaultsKey = "MarkdownPreview.textFileExtensions"

    static let defaultExtensions: Set<String> = [
        "txt", "text", "log", "ini", "cfg", "conf",
        "sh", "bash", "zsh", "py", "js", "mjs", "cjs", "jsx", "ts", "tsx",
        "json", "jsonc", "yaml", "yml", "toml", "sql", "swift", "go", "rs", "rb",
        "c", "h", "cpp", "cc", "hpp", "java", "kt", "cs", "m",
        "css", "scss", "html", "htm", "xml", "tf", "hcl", "ex", "exs", "org",
    ]

    /// Matched against the whole file name, lowercased.
    static let defaultFileNames: Set<String> = [
        "makefile", "dockerfile", ".gitignore", ".gitattributes", ".editorconfig",
        ".env", ".bashrc", ".zshrc", ".zprofile", ".profile",
    ]

    /// The reader's additions, parsed once and shared. Reads come from the
    /// walk on a background task, so this is a snapshot, not a defaults read
    /// per file.
    private static let customEntries = Mutex<Set<String>>(
        parse(UserDefaults.standard.string(forKey: defaultsKey) ?? "")
    )

    /// "sh, .py  Makefile" becomes `["sh", ".py", "makefile"]`: split on commas,
    /// whitespace and newlines, lowercased, with a leading `*.` removed.
    static func parse(_ raw: String) -> Set<String> {
        let separators = CharacterSet(charactersIn: ",;").union(.whitespacesAndNewlines)
        var entries = Set<String>()
        for piece in raw.components(separatedBy: separators) {
            var entry = piece.lowercased()
            if entry.hasPrefix("*.") { entry.removeFirst(2) }
            if !entry.isEmpty, entry != "." { entries.insert(entry) }
        }
        return entries
    }

    /// The reader's additions as shown in Settings.
    static var customText: String {
        customEntries.withLock { $0 }.sorted().joined(separator: ", ")
    }

    /// Stores the reader's additions and makes them current at once.
    static func setCustomText(_ raw: String, defaults: UserDefaults = .standard) {
        let entries = parse(raw)
        customEntries.withLock { $0 = entries }
        defaults.set(entries.sorted().joined(separator: ", "), forKey: defaultsKey)
    }

    static func isText(fileName: String) -> Bool {
        isText(fileName: fileName, custom: customEntries.withLock { $0 })
    }

    static func isText(fileName: String, custom: Set<String>) -> Bool {
        let name = fileName.lowercased()
        let ext = (name as NSString).pathExtension
        if defaultFileNames.contains(name) || (!ext.isEmpty && defaultExtensions.contains(ext)) { return true }
        if custom.contains(name) || (!ext.isEmpty && custom.contains(ext)) { return true }
        // ".py" means the extension; ".env" is also a whole name, checked above.
        return name.hasPrefix(".") ? false : custom.contains("." + ext)
    }
}
