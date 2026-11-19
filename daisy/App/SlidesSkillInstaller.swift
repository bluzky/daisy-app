//
//  SlidesSkillInstaller.swift
//  daisy
//

import Foundation

/// Copies the `daisy-slides` agent skill that ships inside the app into a
/// skills folder the user picked.
nonisolated enum SlidesSkillInstaller {
    static let skillFolderName = "daisy-slides"
    static let bundledFolderName = "daisy-slides-skill"

    enum Target: CaseIterable {
        case claudeCode
        case codex
        case custom

        /// The preset's skills folder, or `nil` for a custom folder. Built from
        /// the real home folder: in the sandbox `NSHomeDirectory()` is the
        /// app's container.
        func defaultFolder(home: String) -> URL? {
            let relative: String
            switch self {
            case .claudeCode: relative = ".claude/skills"
            case .codex: relative = ".codex/skills"
            case .custom: return nil
            }
            return URL(fileURLWithPath: home, isDirectory: true)
                .appendingPathComponent(relative, isDirectory: true)
        }
    }

    /// Copies `bundledSkill` to `<folder>/daisy-slides`, replacing a previous
    /// copy. The new copy is built next to the destination first, so a failed
    /// copy leaves an existing install intact. Returns the installed folder.
    @discardableResult
    static func install(bundledSkill: URL, into folder: URL) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        let destination = folder.appendingPathComponent(skillFolderName, isDirectory: true)
        let staging = folder.appendingPathComponent(".\(skillFolderName).\(UUID().uuidString)",
                                                    isDirectory: true)
        // lstat-style check: an existing `daisy-slides` may be a symlink (for
        // example to a checkout), which must be replaced, never written through.
        let hasExisting = (try? fileManager.attributesOfItem(atPath: destination.path)) != nil
        let backup = folder.appendingPathComponent(".\(skillFolderName).old.\(UUID().uuidString)")
        var movedAside = false
        do {
            try fileManager.copyItem(at: bundledSkill, to: staging)
            if hasExisting {
                try fileManager.moveItem(at: destination, to: backup)
                movedAside = true
            }
            try fileManager.moveItem(at: staging, to: destination)
            if movedAside { try? fileManager.removeItem(at: backup) }
        } catch {
            try? fileManager.removeItem(at: staging)
            if movedAside { try? fileManager.moveItem(at: backup, to: destination) }
            throw error
        }
        return destination
    }
}
