//
//  DocxThemeStore.swift
//  daisy
//
//  Finds the DOCX themes: the bundled ones, plus the reader's own in
//  `~/.config/daisy/docx-themes/`. App-only.
//
//  A theme is a `docx-theme-<id>.json` file. Bundled ones sit at the root of
//  the app's Resources. Only files whose name matches that pattern, and whose
//  decoded `id` equals the name's suffix, are loaded; other JSON is ignored.
//  A user theme replaces a bundled one with the same id.
//
//  `~/.config/daisy/` is already readable and writable under the sandbox
//  entitlement the keymap file uses, so this adds no capability.
//

import Foundation

nonisolated enum DocxThemeStore {
    static let defaultsKey = "DocxExportTheme"
    private static let prefix = "docx-theme-"

    /// The folder for the reader's own themes. Uses the real home directory:
    /// inside the sandbox `NSHomeDirectory()` is the container.
    static var userDirectory: URL {
        let home = getpwuid(getuid()).flatMap { String(validatingCString: $0.pointee.pw_dir) }
            ?? NSHomeDirectory()
        return URL(fileURLWithPath: home)
            .appendingPathComponent(".config/daisy/docx-themes", isDirectory: true)
    }

    /// Creates the user theme folder (and `~/.config/daisy/`) if missing, so
    /// there is somewhere obvious to drop a theme. Failure is harmless.
    static func ensureUserDirectory() {
        try? FileManager.default.createDirectory(
            at: userDirectory, withIntermediateDirectories: true)
    }

    /// Bundled and user themes sorted by id, or just `.github` when none load.
    static func themes(in bundle: Bundle = .main, userDirectory: URL? = userDirectory) -> [DocxTheme] {
        merged(bundled: themes(inDirectory: bundle.resourceURL), user: loadFiles(in: userDirectory))
    }

    /// User themes win over bundled ones with the same id.
    static func merged(bundled: [DocxTheme], user: [DocxTheme]) -> [DocxTheme] {
        var byID: [String: DocxTheme] = [:]
        for theme in bundled + user { byID[theme.id] = theme }
        let all = byID.values.sorted { $0.id < $1.id }
        return all.isEmpty ? [.github] : all
    }

    static func themes(inDirectory directory: URL?) -> [DocxTheme] {
        let themes = loadFiles(in: directory)
        return themes.isEmpty ? [.github] : themes
    }

    /// Valid `docx-theme-<id>.json` files directly inside `directory`, by id.
    static func loadFiles(in directory: URL?) -> [DocxTheme] {
        guard let directory,
              let urls = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)
        else { return [] }
        var themes: [DocxTheme] = []
        for url in urls {
            let name = url.lastPathComponent
            guard url.pathExtension == "json", name.hasPrefix(prefix) else { continue }
            let suffix = String(name.dropFirst(prefix.count).dropLast(".json".count))
            guard DocxThemeValidation.identifier(suffix) != nil,
                  let data = try? Data(contentsOf: url),
                  let theme = try? JSONDecoder().decode(DocxTheme.self, from: data),
                  theme.id == suffix
            else { continue }
            themes.append(theme)
        }
        return themes.sorted { $0.id < $1.id }
    }

    /// The theme with `id`, else GitHub.
    static func theme(id: String?, in bundle: Bundle = .main) -> DocxTheme {
        guard let id else { return .github }
        return themes(in: bundle).first { $0.id == id } ?? .github
    }

    /// The theme chosen in the export panel.
    static var selectedID: String {
        get { UserDefaults.standard.string(forKey: defaultsKey) ?? DocxTheme.github.id }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    static var selected: DocxTheme { theme(id: selectedID) }

    /// The localised name, falling back to the file's own.
    static func displayName(_ theme: DocxTheme) -> String {
        NSLocalizedString("DocxTheme.\(theme.id)", value: theme.name, comment: "DOCX export theme name")
    }
}
