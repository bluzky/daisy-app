//
//  SlideThemeStore.swift
//  daisy
//
//  Finds slide themes: the built-in ones, plus the reader's own in
//  `~/.config/daisy/slide-themes/`. App-only; Quick Look uses the built-ins.
//
//  A theme is a `.yaml` or `.yml` file in Kova's shape. Its id is its `id:`
//  value, or the file name without the extension. A file theme replaces a
//  built-in with the same id. Files are read on every deck render, so a
//  changed theme shows on the next update of the document.
//
//  `~/.config/daisy/` is already readable and writable under the sandbox
//  entitlement the keymap file uses, so this adds no capability.
//

import Foundation

nonisolated enum SlideThemeStore {
    /// The folder for the reader's own themes. Uses the real home directory:
    /// inside the sandbox `NSHomeDirectory()` is the container.
    static var userDirectory: URL {
        let home = getpwuid(getuid()).flatMap { String(validatingCString: $0.pointee.pw_dir) }
            ?? NSHomeDirectory()
        return URL(fileURLWithPath: home)
            .appendingPathComponent(".config/daisy/slide-themes", isDirectory: true)
    }

    /// Built-in and file themes by id.
    static func catalog(userDirectory: URL? = userDirectory) -> [String: SlideTheme] {
        SlideTheme.catalog(files: themeFiles(in: userDirectory))
    }

    /// The text of each `.yaml` / `.yml` file directly inside `directory`,
    /// keyed by file name without the extension.
    static func themeFiles(in directory: URL?) -> [String: String] {
        guard let directory,
              let urls = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else { return [:] }
        var files: [String: String] = [:]
        for url in urls where ["yaml", "yml"].contains(url.pathExtension.lowercased()) {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            files[url.deletingPathExtension().lastPathComponent.lowercased()] = text
        }
        return files
    }
}
