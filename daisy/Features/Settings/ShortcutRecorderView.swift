//
//  ShortcutRecorderView.swift
//  daisy
//
//  Click-to-record control for a global shortcut. While recording it takes
//  the next key press that has a usable modifier; Esc cancels.
//

import Carbon.HIToolbox
import SwiftUI

struct ShortcutRecorderView: NSViewRepresentable {
    var shortcut: QuickCaptureShortcut
    var onChange: (QuickCaptureShortcut) -> Void

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.onChange = onChange
        button.shortcut = shortcut
        return button
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        button.onChange = onChange
        button.shortcut = shortcut
    }

    final class RecorderButton: NSButton {
        var onChange: ((QuickCaptureShortcut) -> Void)?
        var shortcut = QuickCaptureShortcut.default { didSet { refreshTitle() } }

        private var monitor: Any?
        private var isRecording = false { didSet { refreshTitle() } }

        override init(frame: NSRect) {
            super.init(frame: frame)
            bezelStyle = .rounded
            target = self
            action = #selector(toggleRecording)
            setContentHuggingPriority(.required, for: .horizontal)
            refreshTitle()
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override var intrinsicContentSize: NSSize {
            var size = super.intrinsicContentSize
            size.width = max(size.width, 130)
            return size
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { stopRecording() }
        }

        private func refreshTitle() {
            title = isRecording
                ? NSLocalizedString("Type shortcut…", comment: "Shortcut recorder prompt")
                : shortcut.displayString
        }

        @objc private func toggleRecording() {
            isRecording ? stopRecording() : startRecording()
        }

        private func startRecording() {
            isRecording = true
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
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }
            let candidate = QuickCaptureShortcut(
                keyCode: UInt32(event.keyCode),
                modifiers: Self.modifiers(from: event.modifierFlags),
                keyLabel: Self.label(for: event))
            guard candidate.isValid else {
                NSSound.beep()   // e.g. a bare letter; wait for a valid combination
                return nil
            }
            stopRecording()
            onChange?(candidate)
            return nil
        }

        private static func modifiers(from flags: NSEvent.ModifierFlags) -> QuickCaptureShortcut.Modifiers {
            var out: QuickCaptureShortcut.Modifiers = []
            if flags.contains(.control) { out.insert(.control) }
            if flags.contains(.option) { out.insert(.option) }
            if flags.contains(.shift) { out.insert(.shift) }
            if flags.contains(.command) { out.insert(.command) }
            return out
        }

        private static let specialKeys: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
            kVK_ForwardDelete: "⌦", kVK_LeftArrow: "←", kVK_RightArrow: "→",
            kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘",
            kVK_PageUp: "⇞", kVK_PageDown: "⇟",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
            kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
            kVK_F11: "F11", kVK_F12: "F12",
        ]

        private static func label(for event: NSEvent) -> String {
            specialKeys[Int(event.keyCode)]
                ?? (event.charactersIgnoringModifiers ?? "").uppercased()
        }
    }
}
