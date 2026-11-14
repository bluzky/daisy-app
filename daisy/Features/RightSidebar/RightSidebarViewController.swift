//
//  RightSidebarViewController.swift
//  daisy
//
//  The window's right-hand pane, which shows one panel at a time: the
//  Agenda or References. Both live in the same split view item, so
//  switching between them keeps the pane's width and does not reflow the
//  document. The last panel shown is remembered for every window.
//

import Cocoa
import SwiftUI

enum RightSidebarPanel: String {
    case agenda
    case references
}

final class RightSidebarViewController: NSViewController {
    let agenda = TaskCalendarViewController()
    let references = ReferencesViewController()

    private static let panelKey = "MainSplitView.rightPanel"

    private(set) var panel: RightSidebarPanel =
        UserDefaults.standard.string(forKey: panelKey).flatMap(RightSidebarPanel.init(rawValue:)) ?? .agenda

    override func loadView() {
        view = NSView()
        for child in [agenda, references] as [NSViewController] {
            addChild(child)
            child.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child.view)
            NSLayoutConstraint.activate([
                child.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                child.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                child.view.topAnchor.constraint(equalTo: view.topAnchor),
                child.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
        }
        showPanel()
    }

    func setPanel(_ panel: RightSidebarPanel) {
        guard panel != self.panel else { return }
        self.panel = panel
        UserDefaults.standard.set(panel.rawValue, forKey: Self.panelKey)
        if isViewLoaded { showPanel() }
    }

    /// Tells each panel whether it is on screen, so only that one reads the index.
    func setPaneVisible(_ visible: Bool) {
        agenda.setPaneVisible(visible && panel == .agenda)
        references.setPaneVisible(visible && panel == .references)
    }

    private func showPanel() {
        let focused = view.window?.firstResponder as? NSView
        agenda.view.isHidden = panel != .agenda
        references.view.isHidden = panel != .references
        // Focus must not stay in the panel that was just hidden.
        if let focused, focused.isDescendant(of: view), focused.isHiddenOrHasHiddenAncestor {
            view.window?.makeFirstResponder(nil)
        }
    }
}

/// What a workspace panel shows outside a workspace: why it is empty, and
/// the button to make the window's folder a workspace when it can be one.
struct NoWorkspaceView: View {
    let symbol: String
    let message: String
    let canInitializeWorkspace: Bool
    let onInitializeWorkspace: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if canInitializeWorkspace, let onInitializeWorkspace {
                Button(NSLocalizedString("Initialize Workspace", comment: "Tasks sidebar button")) {
                    onInitializeWorkspace()
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
