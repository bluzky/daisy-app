//
//  EmptyWindowHintsView.swift
//  daisy
//
//  The watermark a window shows while it has no document: a few commands
//  and their shortcuts, read from the main menu so a rebinding shows up.
//

import Cocoa

final class EmptyWindowHintsView: NSView {

    private struct Hint {
        let title: String
        let action: Selector
    }

    private static let hints = [
        Hint(title: NSLocalizedString("Search Files", comment: "Empty window hint"),
             action: #selector(DocumentWindowController.searchForDocument(_:))),
        Hint(title: NSLocalizedString("New File", comment: "Empty window hint"),
             action: #selector(NSDocumentController.newDocument(_:))),
        Hint(title: NSLocalizedString("Open File or Folder", comment: "Empty window hint"),
             action: #selector(NSDocumentController.openDocument(_:))),
        Hint(title: NSLocalizedString("Toggle Sidebar", comment: "Empty window hint"),
             action: #selector(DocumentWindowController.toggleSidebarFromMenu(_:))),
    ]

    private let grid = NSGridView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 12
        grid.columnSpacing = 16
        addSubview(grid)
        NSLayoutConstraint.activate([
            grid.centerXAnchor.constraint(equalTo: centerXAnchor),
            grid.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keymapDidChange(_:)),
                                               name: .keymapDidChange,
                                               object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// A watermark, not a control: clicks and scrolls reach the page below.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reloadHints()
    }

    override var isHidden: Bool {
        didSet { if !isHidden { reloadHints() } }
    }

    /// AppDelegate re-applies the keymap to the menus on the same
    /// notification; read them once it has.
    @objc private func keymapDidChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.reloadHints() }
    }

    private func reloadHints() {
        while grid.numberOfRows > 0 { grid.removeRow(at: 0) }
        for hint in Self.hints {
            guard let shortcut = Self.shortcut(for: hint.action) else { continue }
            let title = Self.label(hint.title, font: .systemFont(ofSize: 13))
            title.alignment = .right
            let keys = Self.label(shortcut, font: .monospacedSystemFont(ofSize: 13, weight: .regular))
            grid.addRow(with: [title, keys])
        }
        guard grid.numberOfColumns == 2 else { return }
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
    }

    private static func label(_ text: String, font: NSFont) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = .secondaryLabelColor
        return label
    }

    /// The menu item's key equivalent as the menu draws it (`⇧⌘P`), or nil
    /// when the command has none.
    private static func shortcut(for action: Selector) -> String? {
        guard let item = menuItem(for: action, in: NSApp.mainMenu),
              !item.keyEquivalent.isEmpty else { return nil }
        var modifiers = item.keyEquivalentModifierMask
        // An upper-case key equivalent carries an implied Shift.
        if item.keyEquivalent != item.keyEquivalent.lowercased() { modifiers.insert(.shift) }
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + item.keyEquivalent.uppercased()
    }

    private static func menuItem(for action: Selector, in menu: NSMenu?) -> NSMenuItem? {
        for item in menu?.items ?? [] {
            if item.action == action { return item }
            if let found = menuItem(for: action, in: item.submenu) { return found }
        }
        return nil
    }
}
