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
//  The reading theme is a built-in preset or one of the reader's themes,
//  recorded by id under `ThemePreset.appliedPresetKey`. Applying a reader's
//  theme writes its values into the same stores a preset uses; the app
//  re-reads its file when Daisy becomes active and when View ▸ Theme opens
//  (`refresh`).
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

    /// The reader's own themes in `catalog`, by name (then id).
    static func userThemes(in catalog: [String: Theme]) -> [Theme] {
        let builtInIDs = Set(BuiltInThemes.ids)
        return catalog.values.filter { !builtInIDs.contains($0.id) }.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }

    // MARK: - The reading theme

    /// The reading theme: a built-in preset, or one of the reader's themes.
    enum Applied: Equatable, Sendable {
        case builtIn(ThemePreset)
        case user(Theme)

        /// The id stored under `ThemePreset.appliedPresetKey`.
        var id: String {
            switch self {
            case .builtIn(let preset): preset.id
            case .user(let theme): theme.id
            }
        }

        var name: String {
            switch self {
            case .builtIn(let preset): preset.name
            case .user(let theme): theme.name
            }
        }

        /// The built-in preset; nil for a reader's theme, which can't be
        /// customized and has no gallery card.
        var preset: ThemePreset? {
            if case .builtIn(let preset) = self { return preset }
            return nil
        }

        /// The appearance a light-only or dark-only theme locks the app to.
        var requiredAppearance: AppearanceMode? {
            switch self {
            case .builtIn(let preset): preset.requiredAppearance
            case .user(let theme): theme.requiredAppearance
            }
        }
    }

    /// The reading theme for `id`. A built-in id (the preset's name) wins;
    /// then a reader's theme in `catalog`; anything else, a deleted or
    /// invalid file included, is Original.
    static func applied(id: String?, catalog: () -> [String: Theme]) -> Applied {
        guard let id else { return .builtIn(.defaultPreset) }
        if let preset = ThemePreset.all.first(where: { $0.id == id }) { return .builtIn(preset) }
        if !BuiltInThemes.ids.contains(id), let theme = catalog()[id] { return .user(theme) }
        return .builtIn(.defaultPreset)
    }

    /// The reading theme recorded in `defaults`.
    static func applied(in defaults: UserDefaults = ThemePreset.defaults,
                        userDirectory: URL? = userDirectory) -> Applied {
        applied(id: appliedID(in: defaults), catalog: { catalog(userDirectory: userDirectory) })
    }

    /// The recorded reading theme's id: a preset's name or a reader's theme
    /// id; nil on an install that never picked one (Original).
    static func appliedID(in defaults: UserDefaults = ThemePreset.defaults) -> String? {
        defaults.string(forKey: ThemePreset.appliedPresetKey)
    }

    static func recordApplied(_ theme: Theme, in defaults: UserDefaults = ThemePreset.defaults) {
        defaults.set(theme.id, forKey: ThemePreset.appliedPresetKey)
    }

    /// What applying a reader's theme writes into the stores: its colors and
    /// fonts, the app's default spacing, and its locked appearance or
    /// Automatic.
    static func look(for theme: Theme) -> ThemePreset.SavedLook {
        ThemePreset.SavedLook(colors: ThemeColorsSetting(theme: theme),
                              font: theme.documentFont ?? .system,
                              layout: ReaderLayoutSetting(boldText: theme.boldText),
                              appearance: theme.requiredAppearance ?? .automatic)
    }

    /// What to do after re-reading the reader's theme files.
    enum Refresh: Equatable, Sendable {
        /// Nothing changed, or the reading theme is built in.
        case none
        /// The file changed: apply the theme again.
        case reapply(Theme)
        /// The file is gone, unreadable or now ignored: back to Original.
        case original
    }

    /// Compares the recorded reader's theme, read again from `catalog`,
    /// with `current`, the stores' values. Appearance counts only for a
    /// theme that locks it: under a system theme the reader may pick one.
    static func refresh(appliedID: String?, catalog: [String: Theme],
                        current: ThemePreset.SavedLook) -> Refresh {
        guard let appliedID, !ThemePreset.all.contains(where: { $0.id == appliedID }) else { return .none }
        guard !BuiltInThemes.ids.contains(appliedID), let theme = catalog[appliedID] else {
            return .original
        }
        let look = look(for: theme)
        let unchanged = look.colors == current.colors && look.font == current.font
            && look.layout == current.layout
            && (theme.requiredAppearance == nil || look.appearance == current.appearance)
        return unchanged ? .none : .reapply(theme)
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

nonisolated extension Theme {
    /// The appearance a light-only or dark-only theme locks the app to; nil
    /// for a theme that follows the system.
    var requiredAppearance: AppearanceMode? {
        switch appearance {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }

    /// The document font whose face is the theme's body font; nil when it
    /// sets none or one outside that list (`ThemeColorsSetting.bodyFont`).
    var documentFont: DocumentFontSetting? {
        guard let body = light["font-body"] else { return nil }
        return DocumentFontSetting.allCases.first { $0.fontFamily == body }
    }

    /// Whether the theme reads in the heavier body weight.
    var boldText: Bool { light["body-weight"] == "600" }
}
