//
//  QuickCaptureShortcut.swift
//  daisy
//
//  Quick Capture's settings keys and its user-definable global shortcut. Plain value type
//  with no AppKit or Carbon dependency so persistence and validation are unit
//  tested; the hotkey and the recorder translate to and from it.
//

import Foundation

enum QuickCaptureSetting {
    static let inboxFileName = "Inbox.md"
    static let enabledDefaultsKey = "MarkdownPreview.quickCaptureEnabled"

    /// The block added to the inbox each time it is opened: a dated heading
    /// and an empty line for the cursor.
    static func newEntry(at date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return "## \(formatter.string(from: date))\n\n"
    }
}

struct QuickCaptureShortcut: Codable, Equatable {
    /// Modifier bits owned by this type, so storage never depends on the
    /// numeric values of AppKit or Carbon flags.
    struct Modifiers: OptionSet, Codable {
        let rawValue: Int
        static let control = Modifiers(rawValue: 1 << 0)
        static let option = Modifiers(rawValue: 1 << 1)
        static let shift = Modifiers(rawValue: 1 << 2)
        static let command = Modifiers(rawValue: 1 << 3)
    }

    /// Virtual key code (`kVK_*`), layout independent.
    var keyCode: UInt32
    var modifiers: Modifiers
    /// What the key printed when it was recorded, for display only.
    var keyLabel: String

    static let defaultsKey = "MarkdownPreview.quickCaptureShortcut"
    static let `default` = QuickCaptureShortcut(keyCode: 49, modifiers: [.control, .option],
                                                keyLabel: "Space")

    /// A global shortcut needs control, option or command; shift alone would
    /// swallow ordinary typing in every app.
    var isValid: Bool {
        !modifiers.isDisjoint(with: [.control, .option, .command]) && !keyLabel.isEmpty
    }

    var displayString: String {
        var out = ""
        if modifiers.contains(.control) { out += "⌃" }
        if modifiers.contains(.option) { out += "⌥" }
        if modifiers.contains(.shift) { out += "⇧" }
        if modifiers.contains(.command) { out += "⌘" }
        return out + keyLabel
    }

    static func current(from defaults: UserDefaults = .standard) -> QuickCaptureShortcut {
        guard let data = defaults.data(forKey: defaultsKey),
              let stored = try? JSONDecoder().decode(QuickCaptureShortcut.self, from: data),
              stored.isValid else { return .default }
        return stored
    }

    static func store(_ shortcut: QuickCaptureShortcut, in defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(shortcut) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}
