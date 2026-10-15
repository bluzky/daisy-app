//
//  VendorResource.swift
//  daisy
//
//  Locates bundled JavaScript shared by the app and CLI exporter.
//

import Foundation

nonisolated enum VendorResource {
    /// CLI exporter sets this to its installed resource directory. App and
    /// SwiftPM tests keep using their normal bundles.
    nonisolated(unsafe) static var directory: URL?

    static func configure(directory: URL?) {
        self.directory = directory
    }

    static func string(_ name: String, ext: String, subdir: String) -> String? {
        url(name, ext: ext, subdir: subdir).flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }

    static func url(_ name: String, ext: String, subdir: String) -> URL? {
        if let directory {
            let nested = directory.appendingPathComponent(subdir)
                .appendingPathComponent("\(name).\(ext)")
            if FileManager.default.fileExists(atPath: nested.path) { return nested }
            let flat = directory.appendingPathComponent("\(name).\(ext)")
            if FileManager.default.fileExists(atPath: flat.path) { return flat }
        }

        var bundles = [Bundle.main]
        #if SWIFT_PACKAGE
        let moduleSubdir = subdir.hasPrefix("Vendor/") ? String(subdir.dropFirst(7)) : subdir
        if let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: moduleSubdir) {
            return url
        }
        bundles.append(Bundle.module)
        #endif
        for bundle in bundles {
            if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: subdir) {
                return url
            }
            if let url = bundle.url(forResource: name, withExtension: ext) { return url }
        }
        return nil
    }
}
