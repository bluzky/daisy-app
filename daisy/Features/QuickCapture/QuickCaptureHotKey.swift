//
//  QuickCaptureHotKey.swift
//  daisy
//
//  The system-wide Quick Capture shortcut via Carbon's RegisterEventHotKey. Unlike an NSEvent
//  global monitor it needs no Accessibility permission and works in the
//  sandbox.
//

import Carbon.HIToolbox
import Cocoa

@MainActor
final class QuickCaptureHotKey {
    static let shared = QuickCaptureHotKey()

    var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Registers `shortcut`, replacing any earlier registration. Returns false
    /// when another app already owns the combination.
    @discardableResult
    func register(_ shortcut: QuickCaptureShortcut) -> Bool {
        unregister()
        if handlerRef == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                     eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { QuickCaptureHotKey.shared.onTrigger?() }
                return noErr
            }, 1, &spec, nil, &handlerRef)
        }
        let id = EventHotKeyID(signature: OSType(0x44415359), id: 1) // 'DASY'
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, id,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr { hotKeyRef = nil }
        return status == noErr
    }

    func unregister() {
        guard let hotKeyRef else { return }
        UnregisterEventHotKey(hotKeyRef)
        self.hotKeyRef = nil
    }
}

extension QuickCaptureShortcut {
    var carbonModifiers: UInt32 {
        var out = 0
        if modifiers.contains(.control) { out |= controlKey }
        if modifiers.contains(.option) { out |= optionKey }
        if modifiers.contains(.shift) { out |= shiftKey }
        if modifiers.contains(.command) { out |= cmdKey }
        return UInt32(out)
    }
}
