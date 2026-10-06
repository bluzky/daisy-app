//
//  KeymapSettingsView.swift
//  daisy
//

import SwiftUI

struct KeymapSettingsView: View {
    @State private var revision = 0
    @State private var errorMessage: String?
    private let store = KeymapStore.shared

    var body: some View {
        Form {
            if let message = store.errorMessage {
                Section {
                    Text(message).foregroundStyle(.red)
                }
            }
            ForEach(KeymapContext.allCases, id: \.self) { context in
                Section(context.title) {
                    ForEach(KeymapCommand.allCases.filter { $0.context == context }, id: \.self) { command in
                        shortcutRow(command)
                    }
                }
            }
            Section {
                HStack {
                    Button(L("Reset All")) { resetAll() }
                    Button(L("Export All Defaults")) { exportDefaults() }
                    Spacer()
                    Button(L("Reveal in Finder")) { reveal() }
                    Button(L("Open in Editor")) { open() }
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { store.checkForExternalChanges(); revision += 1 }
        .onReceive(NotificationCenter.default.publisher(for: .keymapDidChange)) { _ in revision += 1 }
    }

    private func shortcutRow(_ command: KeymapCommand) -> some View {
        let binding = store.keymap.bindings(for: command).first
        return LabeledContent(L(command.titleKey)) {
            HStack {
                KeyBindingRecorderView(binding: binding, validation: validation(for: command.context)) { binding in
                    rebind(command, binding)
                }
                Button(L("Clear")) { rebind(command, nil) }
                    .disabled(binding == nil)
                Button(L("Reset")) { reset(command) }
                    .disabled(binding == Keymap.defaultBindings(for: command).first)
            }
        }
        .id("\(command.rawValue)-\(revision)")
    }

    private func validation(for context: KeymapContext) -> KeyBindingRecorderView.Validation {
        switch context {
        case .editing: .requiresModifier
        case .global: .requiresModifier
        case .reading, .search: .any
        }
    }

    private func rebind(_ command: KeymapCommand, _ binding: KeyBinding?) {
        do { try store.rebind(command, to: binding); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }

    private func reset(_ command: KeymapCommand) {
        do { try store.reset(command); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }

    private func resetAll() {
        do { try store.resetAll(); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }

    private func exportDefaults() {
        do { try store.exportDefaults(); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }

    private func reveal() {
        let url = store.url
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func open() {
        NSWorkspace.shared.open(store.url)
    }
}

struct KeyBindingRecorderView: NSViewRepresentable {
    enum Validation {
        case any
        case requiresModifier
    }

    var binding: KeyBinding?
    var validation: Validation
    var onChange: (KeyBinding) -> Void

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton(title: binding?.displayString ?? L("Type shortcut…"), target: nil, action: nil)
        button.validation = validation
        button.onChange = onChange
        return button
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        button.validation = validation
        button.onChange = onChange
        if !button.isRecording { button.title = binding?.displayString ?? L("Type shortcut…") }
    }

    final class RecorderButton: NSButton {
        var validation: Validation = .any
        var onChange: ((KeyBinding) -> Void)?
        fileprivate var isRecording = false
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { stopRecording() }
        }

        override func mouseDown(with event: NSEvent) {
            if isRecording { stopRecording() } else { startRecording() }
        }

        private func startRecording() {
            isRecording = true
            title = L("Type shortcut…")
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        private func stopRecording() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            isRecording = false
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            if event.keyCode == 53 { stopRecording(); return nil }
            guard let binding = KeyBinding(event: event), isValid(binding) else {
                NSSound.beep()
                return nil
            }
            stopRecording()
            onChange?(binding)
            return nil
        }

        private func isValid(_ binding: KeyBinding) -> Bool {
            switch validation {
            case .any: true
            case .requiresModifier:
                !binding.modifiers.isDisjoint(with: [.control, .option, .command])
            }
        }
    }
}

private extension KeymapContext {
    var title: String {
        switch self {
        case .global: L("Global")
        case .reading: L("Reading")
        case .editing: L("Editing")
        case .search: L("Search")
        }
    }
}
