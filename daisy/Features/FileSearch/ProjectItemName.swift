import Foundation

/// Naming rules for files and folders created inside a project. Shared by the
/// project navigator's New File / New Folder and by OmniSearch's create-file
/// row, so the two can never disagree about what a valid name is.
nonisolated enum ProjectItemName {

    /// The trimmed name, or nil when it cannot be one path component.
    static func validated(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed != ".",
              trimmed != "..",
              !trimmed.contains("/"),
              !trimmed.contains("\\"),
              !trimmed.unicodeScalars.contains(where: { $0.value == 0 }) else { return nil }
        return trimmed
    }

    /// A valid Markdown file name. A name with no extension gets
    /// `defaultExtension`; one whose extension is not Markdown is refused.
    static func markdownFileName(from name: String, defaultExtension: String = "md") -> String? {
        guard var fileName = validated(name) else { return nil }
        if URL(fileURLWithPath: fileName).pathExtension.isEmpty {
            fileName += ".\(defaultExtension)"
        }
        guard ProjectFileIndex.markdownExtensions.contains(
            URL(fileURLWithPath: fileName).pathExtension.lowercased()
        ) else { return nil }
        return fileName
    }

    /// The project-relative path OmniSearch would create for what was typed,
    /// or nil when the text cannot name a Markdown file the index would find.
    ///
    /// `notes/roadmap` becomes `notes/roadmap.md`. A leading `/` means the
    /// project root. Hidden components are refused because the index skips
    /// them: the file would be created and then never turn up in a search.
    /// The same goes for folders the index prunes and for paths deeper than it
    /// walks.
    static func newFileRelativePath(from query: String) -> String? {
        var text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasPrefix("/") { text.removeFirst() }
        guard !text.isEmpty else { return nil }

        let parts = text.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard let last = parts.last, let fileName = markdownFileName(from: last) else { return nil }
        var components: [String] = []
        for part in parts.dropLast() {
            guard let component = validated(part) else { return nil }
            components.append(component)
        }
        components.append(fileName)
        guard !components.contains(where: { $0.hasPrefix(".") }),
              !components.contains(where: { ProjectFileIndex.prunedDirectoryNames.contains($0) }),
              components.count <= ProjectFileIndex.maximumDepth else { return nil }
        return components.joined(separator: "/")
    }

    /// Whether writing at `destination` would stay inside `root` once symlinks
    /// are followed. The deepest folder that already exists is the one that
    /// decides: anything below it is about to be created as a plain folder.
    /// A symlink that leads nowhere is refused, because creating folders
    /// through it would create them at wherever it points.
    static func isContained(_ destination: URL, in root: URL) -> Bool {
        let fileManager = FileManager.default
        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL.path
        var ancestor = destination.standardizedFileURL.deletingLastPathComponent()
        // `attributesOfItem` does not follow symlinks, so a dangling one still
        // counts as present here.
        while (try? fileManager.attributesOfItem(atPath: ancestor.path)) == nil, ancestor.path != "/" {
            ancestor = ancestor.deletingLastPathComponent()
        }
        let attributes = try? fileManager.attributesOfItem(atPath: ancestor.path)
        if attributes?[.type] as? FileAttributeType == .typeSymbolicLink,
           !fileManager.fileExists(atPath: ancestor.path) {
            return false
        }
        let resolved = ancestor.resolvingSymlinksInPath().standardizedFileURL.path
        return resolved == resolvedRoot || resolved.hasPrefix(resolvedRoot + "/")
    }
}
