//
//  WorkspaceMarker.swift
//  daisy
//
//  The `.daisy/config.json` file that makes a folder a workspace. Only the
//  folder itself is checked, never its parents or subfolders, and only
//  Initialize Workspace and Remove Workspace write it. The file's presence is
//  what counts; its contents are not read.
//

import Foundation

enum WorkspaceMarker {
    static let directoryName = ".daisy"
    static let fileName = "config.json"
    static let contents = Data("{\n  \"version\": 1\n}\n".utf8)

    /// Posted after open windows re-read their markers: on Initialize and
    /// Remove Workspace, and when Daisy becomes active. Any folder may have
    /// gained or lost its marker.
    static let didChangeNotification = Notification.Name("WorkspaceMarkerDidChange")

    static func markerURL(root: URL) -> URL {
        root.appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    static func isWorkspace(root: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: markerURL(root: root).path,
                                              isDirectory: &isDirectory)
            && !isDirectory.boolValue
    }

    /// Writes the marker, keeping one that is already there. A failure
    /// leaves the folder as it was.
    static func initialize(root: URL) throws {
        guard !isWorkspace(root: root) else { return }
        let fileManager = FileManager.default
        let directory = root.appendingPathComponent(directoryName, isDirectory: true)
        let createsDirectory = !fileManager.fileExists(atPath: directory.path)
        // Throws when `.daisy` exists as a file.
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            try contents.write(to: markerURL(root: root), options: .atomic)
        } catch {
            if createsDirectory { try? fileManager.removeItem(at: directory) }
            throw error
        }
    }

    /// Deletes the marker, and `.daisy` too once nothing else is left in it,
    /// so files someone else put there survive.
    static func remove(root: URL) throws {
        let fileManager = FileManager.default
        let marker = markerURL(root: root)
        if isWorkspace(root: root) {
            try fileManager.removeItem(at: marker)
        }
        let directory = marker.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              try fileManager.contentsOfDirectory(atPath: directory.path).isEmpty
        else { return }
        try fileManager.removeItem(at: directory)
    }
}
