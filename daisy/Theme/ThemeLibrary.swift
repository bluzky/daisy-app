//
//  ThemeLibrary.swift
//  daisy
//
//  The themes the app can use: the built-in ones, plus the reader's own
//  `.css` files in `~/.config/daisy/themes/`. App-only; Quick Look uses the
//  built-ins.
//
//  A theme's id is its file name without `.css`, lowercased. A file with a
//  built-in theme's id is ignored. Files are read on every deck render, so a
//  changed theme shows on the next update of the document.
//

import Foundation

nonisolated enum ThemeLibrary {
    /// The folder for the reader's own themes. Uses the real home directory:
    /// inside the sandbox `NSHomeDirectory()` is the container.
    static var userDirectory: URL {
        let home = getpwuid(getuid()).flatMap { String(validatingCString: $0.pointee.pw_dir) }
            ?? NSHomeDirectory()
        return URL(fileURLWithPath: home)
            .appendingPathComponent(".config/daisy/themes", isDirectory: true)
    }

    /// Built-in and the reader's themes by id.
    static func catalog(userDirectory: URL? = userDirectory) -> [String: Theme] {
        Theme.catalog(builtIns: BuiltInThemes.files, user: userFiles(in: userDirectory))
    }

    /// Each `.css` file directly inside `directory`.
    static func userFiles(in directory: URL?) -> [Theme.File] {
        guard let directory,
              let urls = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        else { return [] }
        return urls.filter { $0.pathExtension.lowercased() == "css" }.compactMap { url in
            guard let css = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return Theme.File(id: url.deletingPathExtension().lastPathComponent, css: css)
        }
    }
}
