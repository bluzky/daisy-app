//
//  JournalSetting.swift
//  daisy
//
//  The Journal extension's settings (Settings → Extensions): whether it is
//  on, which template from the template file new entries start from, and
//  whether today's new entry takes the unfinished tasks of the days before
//  it (see `JournalCarryOver`).
//  Off hides the toolbar calendar and the Go menu's journal items; entries
//  already written stay where they are.
//

import Foundation

enum JournalSetting {
    static let enabledDefaultsKey = "MarkdownPreview.journalEnabled"
    static let templateNameDefaultsKey = "MarkdownPreview.journalTemplateName"
    static let carryOverEnabledDefaultsKey = "MarkdownPreview.journalCarryOverEnabled"
    static let carryOverDaysDefaultsKey = "MarkdownPreview.journalCarryOverDays"
    static let carryOverDayRange = 1...30
    static let defaultCarryOverDays = 7

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

    /// Off unless the reader turned it on: it rewrites entries they wrote.
    static var carryOverEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: carryOverEnabledDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: carryOverEnabledDefaultsKey) }
    }

    /// How many days before today carry-over looks back.
    static var carryOverDays: Int {
        get {
            let stored = UserDefaults.standard.object(forKey: carryOverDaysDefaultsKey) as? Int ?? defaultCarryOverDays
            return min(max(stored, carryOverDayRange.lowerBound), carryOverDayRange.upperBound)
        }
        set { UserDefaults.standard.set(newValue, forKey: carryOverDaysDefaultsKey) }
    }
}
