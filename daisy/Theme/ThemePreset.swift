//
//  ThemePreset.swift
//  daisy
//
//  Named built-in theme presets. Each theme remembers its customized look.
//  First selection uses the built-in defaults; Reset restores those defaults.
//  Applying a fixed preset also locks the app's appearance to the preset's
//  flavor so the native chrome (sidebar,
//  toolbar) matches. Original and Ember remember their adjustable appearance
//  and carry a separate dark palette, so both schemes stay readable while
//  the app keeps tracking the system look. The accent color maps to the
//  link slot — syntax highlighting keeps its own colors.
//

import Foundation
import Darwin

nonisolated struct ThemePreset: Identifiable, Equatable, Sendable {

    /// One scheme's colors ("#RRGGBB" each).
    struct Palette: Equatable, Sendable {
        /// Page background — window, gutters, and (via fallback) the
        /// editor page.
        let pageBackground: String
        /// Code block background.
        let codeBackground: String
        /// Body text.
        let text: String
        /// Accent — the link color, and the card sample's highlight.
        let accent: String
        /// Heading color; nil leaves headings in the text color.
        var heading: String? = nil
        /// Colors for H1–H6, in order; nil or fewer than six leaves the
        /// text color for the rest. `heading` overrides them all.
        var headingLevels: [String]? = nil
        /// Table colors; nil leaves the plain look.
        var tableHeader: String? = nil
        var tableBorder: String? = nil
        var tableStripe: String? = nil
    }

    /// What applying the preset does to the app appearance: pin light,
    /// pin dark, or keep Automatic (`.system`).
    enum Flavor: Sendable {
        case light
        case dark
        case system
    }

    /// Display name; also the localization key.
    let name: String
    let flavor: Flavor
    /// The reading face the preset applies. A preset is a whole reading
    /// look, not only a palette — Books' themes carry a typeface too, and
    /// the gallery card draws its "Aa" in this face so the cards differ the
    /// way the pages will.
    let font: DocumentFontSetting
    /// Whether the preset reads in a heavier body weight.
    let boldText: Bool
    /// The palette; for a `.system` preset, the light-scheme palette.
    let palette: Palette
    /// Dark-scheme palette for `.system` presets. Nil reuses `palette`,
    /// which is right for presets that pin their flavor.
    let darkPalette: Palette?
    /// The preset expanded into slot values for both schemes. Precomputed:
    /// the settings pane compares the stored colors against it on every
    /// update, and expansion sanitizes each value through a regex.
    let setting: ThemeColorsSetting

    /// A built-in theme as a gallery and Customize preset. Original sets no
    /// tokens: applying it clears the overrides, so it leaves the same
    /// native chrome as a fresh install.
    init(theme: Theme) {
        name = theme.name
        switch theme.appearance {
        case .light: flavor = .light
        case .dark: flavor = .dark
        case .system: flavor = .system
        }
        let bodyFont = theme.light["font-body"]
        font = DocumentFontSetting.allCases.first { $0.fontFamily == bodyFont } ?? .system
        boldText = theme.light["body-weight"] == "600"
        palette = Palette(tokens: theme.palette(for: theme.appearance == .dark ? .dark : .light),
                          swatches: Self.defaultSwatches(dark: theme.appearance == .dark))
        darkPalette = theme.appearance == .system
            ? Palette(tokens: theme.palette(for: .dark), swatches: Self.defaultSwatches(dark: true))
            : nil
        setting = theme.usesDefaultLook ? ThemeColorsSetting() : ThemeColorsSetting(theme: theme)
    }

    /// The default stylesheet's colors, for the gallery swatches of a theme
    /// that doesn't set them.
    private static func defaultSwatches(dark: Bool) -> Palette {
        dark
            ? Palette(pageBackground: "#1C1C1C", codeBackground: "#2A2828", text: "#F5F5F7", accent: "#2997FF")
            : Palette(pageBackground: "#FFFFFF", codeBackground: "#F5F5F7", text: "#1D1D1F", accent: "#0066CC")
    }

    var id: String { name }

    /// Fixed palettes must keep matching native chrome. Original follows the
    /// user's appearance choice. Editing colors never changes theme identity.
    var requiredAppearance: AppearanceMode? {
        switch flavor {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }

    static let appliedPresetKey = "MarkdownPreview.theme.appliedPreset"

    // Identity and saved looks must have the same owner as the active colors,
    // font, layout, and appearance, including across release/debug builds.
    static var defaults: UserDefaults { AppearanceMode.sharedDefaults() ?? .standard }

    static var migrationLockURL: URL? {
        let manager = FileManager.default
        if let group = Bundle.main.object(forInfoDictionaryKey: AppearanceMode.appGroupInfoKey) as? String,
           !group.isEmpty {
            // Never fall back to a process-local lock when preferences are shared.
            return manager.containerURL(forSecurityApplicationGroupIdentifier: group)?
                .appendingPathComponent("theme-migration.lock")
        }
        return manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Markdown Preview/theme-migration.lock")
    }

    static func migrateLegacyValues(from legacy: UserDefaults = .standard,
                                    to shared: UserDefaults = defaults,
                                    lockURL: URL? = migrationLockURL) {
        // Release and debug can launch together. An actor only protects one
        // process, so serialize the read/merge/write in the shared container.
        // Failure leaves legacy data intact for a subsequent launch to retry.
        guard let lockURL else { return }
        do {
            try FileManager.default.createDirectory(at: lockURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
        } catch { return }
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        while flock(descriptor, LOCK_EX) != 0 {
            if errno != EINTR { return }
        }
        defer { flock(descriptor, LOCK_UN) }
        // Refresh after acquiring the lock, and publish before releasing it.
        shared.synchronize()
        defer { shared.synchronize() }

        // Each missing look migrates independently of the selected identity.
        for preset in builtIn where shared.data(forKey: preset.savedLookKey) == nil {
            if let data = legacy.data(forKey: preset.savedLookKey) {
                shared.set(data, forKey: preset.savedLookKey)
            }
        }
        if shared.string(forKey: appliedPresetKey) == nil,
           let legacyID = legacy.string(forKey: appliedPresetKey),
           builtIn.contains(where: { $0.id == legacyID }) {
            shared.set(legacyID, forKey: appliedPresetKey)
        }
    }

    func recordApplied(in defaults: UserDefaults = Self.defaults) {
        defaults.set(id, forKey: Self.appliedPresetKey)
    }

    /// Identity is explicit: custom colors never select a preset by coincidence.
    /// Older installs with no gallery selection belong to Original.
    static func applied(in defaults: UserDefaults = Self.defaults) -> ThemePreset {
        builtIn.first { $0.id == defaults.string(forKey: appliedPresetKey) } ?? defaultPreset
    }

    struct SavedLook: Codable, Equatable {
        var colors: ThemeColorsSetting
        var font: DocumentFontSetting
        var layout: ReaderLayoutSetting
        var appearance: AppearanceMode
    }

    private var savedLookKey: String { "MarkdownPreview.theme.savedLook.v1.\(id)" }

    func save(_ look: SavedLook, in defaults: UserDefaults = Self.defaults) {
        guard let data = try? JSONEncoder().encode(look) else { return }
        defaults.set(data, forKey: savedLookKey)
    }

    func restoredLook(in defaults: UserDefaults = Self.defaults) -> SavedLook {
        if let data = defaults.data(forKey: savedLookKey),
           var look = try? JSONDecoder().decode(SavedLook.self, from: data) {
            look.appearance = requiredAppearance ?? look.appearance
            return look
        }
        return SavedLook(colors: setting, font: font,
                         layout: ReaderLayoutSetting(boldText: boldText),
                         appearance: requiredAppearance ?? .automatic)
    }

    /// The default theme: Reset Colors returns to it, and it leads the
    /// gallery.
    static var defaultPreset: ThemePreset { builtIn[0] }

    /// The built-in starter set, in gallery order — three rows of three:
    /// the Apple Books set (Original, Quiet, Paper / Bold, Calm, Focus)
    /// first, then Ember and the remaining dark themes. Original leads — it is
    /// the default theme. The looks live in `Resources/Themes/<id>.css`.
    static let builtIn: [ThemePreset] = BuiltInThemes.galleryIDs.compactMap { id in
        BuiltInThemes.catalog[id].map(ThemePreset.init(theme:))
    }

    /// Every built-in theme: the gallery's, then the former slide themes.
    static let all: [ThemePreset] = BuiltInThemes.all.map(ThemePreset.init(theme:))
}

nonisolated extension ThemePreset.Palette {
    /// One scheme of a theme's tokens, with `swatches` where it sets none.
    init(tokens: [String: String], swatches: Self) {
        pageBackground = tokens["bg"] ?? swatches.pageBackground
        codeBackground = tokens["code-bg"] ?? swatches.codeBackground
        text = tokens["text"] ?? swatches.text
        accent = tokens["link"] ?? swatches.accent
        heading = tokens["heading"]
        let levels = (1...6).map { tokens["heading-\($0)"] }
        headingLevels = levels.allSatisfy { $0 == nil } ? nil : levels.map { $0 ?? text }
        tableHeader = tokens["table-header-bg"]
        tableBorder = tokens["table-border"]
        tableStripe = tokens["table-stripe"]
    }
}
