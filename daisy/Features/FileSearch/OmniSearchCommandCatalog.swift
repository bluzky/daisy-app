//
//  OmniSearchCommandCatalog.swift
//  daisy
//
//  The commands OmniSearch offers, read straight from the main menu so the
//  list can never drift from what the menus do: a new menu item is searchable
//  the day it is added, and a disabled one is simply absent.
//
//  Built before the palette appears, while the document window is still key.
//  Once the panel is up the responder chain starts at the panel, so asking
//  the menu "is this enabled?" then would answer for the wrong window.
//

import Cocoa

@MainActor
final class OmniSearchCommandCatalog {

    private(set) var candidates: [FileSearchResults.CommandCandidate] = []
    private var items: [String: NSMenuItem] = [:]

    /// Reads the current main menu. Safe to call with no menu; the catalog is
    /// then empty.
    init(mainMenu: NSMenu?) {
        guard let mainMenu else { return }
        for top in mainMenu.items {
            guard let submenu = top.submenu, !isExcluded(submenu) else { continue }
            collect(from: submenu, path: [top.title])
        }
    }

    /// Runs the command the way a menu click would: validated, and delivered
    /// through the responder chain from the key window.
    @discardableResult
    func perform(id: String) -> Bool {
        guard let item = items[id], let menu = item.menu,
              let index = menu.items.firstIndex(of: item) else { return false }
        menu.update()
        guard item.isEnabled else {
            NSSound.beep()
            return false
        }
        menu.performActionForItem(at: index)
        return true
    }

    private func collect(from menu: NSMenu, path: [String]) {
        menu.update()
        for item in menu.items {
            if let submenu = item.submenu {
                guard !isExcluded(submenu), !item.isHidden else { continue }
                collect(from: submenu, path: path + [item.title])
                continue
            }
            guard isOffered(item) else { continue }
            let id = "menu.\(candidates.count)"
            items[id] = item
            candidates.append(.init(id: id,
                                    title: item.title,
                                    menuPath: path.joined(separator: " › "),
                                    shortcut: Self.shortcut(for: item)))
        }
    }

    private func isOffered(_ item: NSMenuItem) -> Bool {
        guard !item.isSeparatorItem, !item.isHidden, item.isEnabled,
              !item.title.isEmpty, let action = item.action else { return false }
        // The palette's own entry would just reopen the palette.
        if action == #selector(DocumentWindowController.searchForDocument(_:)) { return false }
        // Open Recent has a section of its own.
        if NSStringFromSelector(action).contains("RecentDocument") { return false }
        // Scrolling and heading-to-heading keys are for the keyboard, not a list.
        if let raw = item.identifier?.rawValue, KeymapCommand(rawValue: raw)?.context == .reading {
            return false
        }
        return true
    }

    private func isExcluded(_ menu: NSMenu) -> Bool {
        menu === NSApp.servicesMenu || menu === NSApp.windowsMenu
    }

    // MARK: - Shortcut text

    static func shortcut(for item: NSMenuItem) -> String? {
        let key = item.keyEquivalent
        guard !key.isEmpty else { return nil }
        let mask = item.keyEquivalentModifierMask
        var text = ""
        if mask.contains(.control) { text += "⌃" }
        if mask.contains(.option) { text += "⌥" }
        if mask.contains(.shift) || key != key.lowercased() { text += "⇧" }
        if mask.contains(.command) { text += "⌘" }
        return text + glyph(for: key)
    }

    private static func glyph(for key: String) -> String {
        switch key {
        case "\r", "\u{3}": return "↩"
        case "\t": return "⇥"
        case " ": return "Space"
        case "\u{8}", "\u{7f}": return "⌫"
        case "\u{1b}": return "⎋"
        case String(UnicodeScalar(NSUpArrowFunctionKey)!): return "↑"
        case String(UnicodeScalar(NSDownArrowFunctionKey)!): return "↓"
        case String(UnicodeScalar(NSLeftArrowFunctionKey)!): return "←"
        case String(UnicodeScalar(NSRightArrowFunctionKey)!): return "→"
        default: return key.uppercased()
        }
    }
}
