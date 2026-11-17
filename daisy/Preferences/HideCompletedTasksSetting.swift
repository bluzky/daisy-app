//
//  HideCompletedTasksSetting.swift
//  daisy
//
//  Storage behind View ▸ Hide Completed Tasks.
//

import Foundation

enum HideCompletedTasksSetting {
    /// Like Always on Top, one stored value drives every document window:
    /// the ones open now, the ones opened later and after a relaunch. Each
    /// window hands it to the `hide-completed-tasks` render extension as host
    /// state.
    static let defaultsKey = "MarkdownPreview.hideCompletedTasks"

    static var isEnabled: Bool {
        get { read(from: .standard) }
        set { write(newValue, to: .standard) }
    }

    static func read(from defaults: UserDefaults?) -> Bool {
        defaults?.bool(forKey: defaultsKey) ?? false
    }

    /// Off clears the key, like Always on Top.
    static func write(_ isEnabled: Bool, to defaults: UserDefaults?) {
        if isEnabled {
            defaults?.set(true, forKey: defaultsKey)
        } else {
            defaults?.removeObject(forKey: defaultsKey)
        }
    }
}
