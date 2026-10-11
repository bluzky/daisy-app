//
//  LaunchBehaviorSetting.swift
//  daisy
//
//  What Daisy shows when it starts, or when its Dock icon is clicked with no
//  window open, and nothing else asked for a document. Kept free of AppKit so
//  the SPM helper tests can exercise it without a GUI host.
//

import Foundation

enum LaunchBehaviorSetting: String, CaseIterable {
    /// The open panel — what Daisy always did before this was configurable.
    case showOpenPanel
    /// A blank untitled document, ready to type into.
    case newDocument
    /// The folder and file that were open last, falling back to the open
    /// panel when neither can be found any more.
    case reopenLastSession
    /// One file or folder the reader picked in Settings, falling back to the
    /// open panel when it can't be found any more.
    case openChosenItem

    static let defaultValue: LaunchBehaviorSetting = .reopenLastSession
    static let defaultsKey = "MarkdownPreview.launchBehavior"

    static var current: LaunchBehaviorSetting {
        get { read(from: .standard) }
        set { write(newValue, to: .standard) }
    }

    static func read(from defaults: UserDefaults?) -> LaunchBehaviorSetting {
        defaults?.string(forKey: defaultsKey).flatMap(LaunchBehaviorSetting.init(rawValue:))
            ?? defaultValue
    }

    /// The default clears the key rather than storing it, as the other
    /// preferences do: an untouched preference leaves no trace.
    static func write(_ value: LaunchBehaviorSetting, to defaults: UserDefaults?) {
        if value == defaultValue {
            defaults?.removeObject(forKey: defaultsKey)
        } else {
            defaults?.set(value.rawValue, forKey: defaultsKey)
        }
    }

    /// What reopening the last session actually opens. The file is opened
    /// inside the folder's window when it lives there, so the tree keeps it
    /// selected; otherwise each gets a window of its own.
    struct RestorePlan: Equatable {
        var folderURL: URL?
        var fileURL: URL?
        var opensFileInFolderWindow: Bool

        var isEmpty: Bool { folderURL == nil && fileURL == nil }
    }

    /// - Parameters:
    ///   - folderURL: The last folder, if it still exists.
    ///   - fileURL: The last file, if it still exists.
    static func restorePlan(folderURL: URL?, fileURL: URL?) -> RestorePlan {
        let folder = folderURL?.standardizedFileURL
        let file = fileURL?.standardizedFileURL
        var isInsideFolder = false
        if let folder, let file {
            let folderPath = folder.path.hasSuffix("/") ? folder.path : folder.path + "/"
            isInsideFolder = file.path.hasPrefix(folderPath)
        }
        return RestorePlan(folderURL: folder, fileURL: file,
                           opensFileInFolderWindow: isInsideFolder)
    }
}
