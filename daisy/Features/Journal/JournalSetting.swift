//
//  JournalSetting.swift
//  daisy
//
//  The Journal extension's settings (Settings → Extensions): whether it is
//  on, and which template from the template file new entries start from.
//  Off hides the toolbar calendar and the Go menu's journal items; entries
//  already written stay where they are.
//

import Foundation

enum JournalSetting {
    static let enabledDefaultsKey = "MarkdownPreview.journalEnabled"
    static let templateNameDefaultsKey = "MarkdownPreview.journalTemplateName"

    /// On unless the reader turned it off.
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledDefaultsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledDefaultsKey) }
    }

    /// The chosen template's name, or nil for none (just the date heading).
    static var templateName: String? {
        get { UserDefaults.standard.string(forKey: templateNameDefaultsKey) }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: templateNameDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: templateNameDefaultsKey)
            }
        }
    }
}
