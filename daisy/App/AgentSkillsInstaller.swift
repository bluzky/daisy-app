//
//  AgentSkillsInstaller.swift
//  daisy
//

import Foundation

/// Copies the agent skills that ship inside the app into a skills folder the
/// user picked: `daisy-slides` for decks and `daisy-dashboard` for dashboards,
/// charts and cards in ordinary documents.
nonisolated enum AgentSkillsInstaller {

    /// One bundled skill: the folder it is installed as, and the folder the
    /// build phase copies it to in the app's resources.
    struct Skill: Equatable, Sendable {
        let folderName: String
        var bundledFolderName: String { "\(folderName)-skill" }
    }

    /// Every skill the menu item installs, in order.
    static let skills = [Skill(folderName: "daisy-slides"), Skill(folderName: "daisy-dashboard")]

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

    /// Copies `bundledSkill` to `<folder>/<skillFolderName>`, replacing a
    /// previous copy. The new copy is built next to the destination first, so
    /// a failed copy leaves an existing install intact. Returns the installed
    /// folder.
    @discardableResult
    static func install(bundledSkill: URL, named skillFolderName: String, into folder: URL) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        let destination = folder.appendingPathComponent(skillFolderName, isDirectory: true)
        let staging = folder.appendingPathComponent(".\(skillFolderName).\(UUID().uuidString)",
                                                    isDirectory: true)
        // lstat-style check: an existing skill folder may be a symlink (for
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

    /// Installs every skill in `skills` into `folder`, finding each bundled
    /// copy with `bundled`. Stops at the first failure; skills installed
    /// before it stay installed. Returns the installed folders.
    static func installAll(into folder: URL, bundled: (Skill) -> URL?) throws -> [URL] {
        try skills.map { skill in
            guard let source = bundled(skill) else { throw MissingSkill(name: skill.folderName) }
            return try install(bundledSkill: source, named: skill.folderName, into: folder)
        }
    }

    /// A skill the app should ship but does not.
    struct MissingSkill: LocalizedError {
        let name: String
        var errorDescription: String? {
            String(format: NSLocalizedString("The bundled “%@” skill could not be found.",
                                             comment: "Agent skill install error; %@ is a skill name"), name)
        }
    }
}
