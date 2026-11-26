//
//  BuiltInThemes.swift
//  daisy
//
//  The themes that ship with Daisy: `Resources/Themes/<id>.css`, the same
//  format as the reader's own theme files, bundled in the app and in
//  Quick Look. Only the ids listed here are read, so other CSS in the
//  bundle is never taken for a theme.
//

import Foundation

nonisolated enum BuiltInThemes {
    /// The reading themes the aA popover's gallery shows, in gallery order.
    static let galleryIDs = ["original", "quiet", "paper", "pitch", "calm", "focus", "ember", "dusk", "midnight"]
    /// Every built-in theme: the gallery's, then the other former slide themes.
    static let ids = galleryIDs + ["paper-warm", "midnight-navy"]

    static let files: [Theme.File] = files(in: directory)

    /// Built-in themes by id.
    static let catalog: [String: Theme] = Theme.catalog(builtIns: files)

    /// Built-in themes in `ids` order.
    static var all: [Theme] { ids.compactMap { catalog[$0] } }

    /// The theme files for `ids` found in `directory`, directly or in its
    /// `Themes` folder.
    static func files(in directory: URL?) -> [Theme.File] {
        guard let directory else { return [] }
        return ids.compactMap { id in
            let candidates = [directory.appendingPathComponent("Themes/\(id).css"),
                              directory.appendingPathComponent("\(id).css")]
            guard let css = candidates.lazy.compactMap({ try? String(contentsOf: $0, encoding: .utf8) }).first
            else { return nil }
            return Theme.File(id: id, css: css)
        }
    }

    /// Where the bundle keeps the files: the app's and Quick Look's
    /// Resources, flattened, or the test package's `Themes` folder.
    private static var directory: URL? {
        #if SWIFT_PACKAGE
        return Bundle.module.resourceURL
        #else
        return Bundle.main.resourceURL
        #endif
    }
}
