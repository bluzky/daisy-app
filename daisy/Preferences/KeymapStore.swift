//
//  KeymapStore.swift
//  daisy
//

import Cocoa

extension Notification.Name {
    static let keymapDidChange = Notification.Name("Daisy.keymapDidChange")
}

extension KeyBinding {
    init?(event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var keymapModifiers: Modifiers = []
        if modifiers.contains(.control) { keymapModifiers.insert(.control) }
        if modifiers.contains(.option) { keymapModifiers.insert(.option) }
        if modifiers.contains(.shift) { keymapModifiers.insert(.shift) }
        if modifiers.contains(.command) { keymapModifiers.insert(.command) }

        let namedKeys: [UInt16: String] = [
            36: "return", 48: "tab", 49: "space", 51: "delete", 53: "escape", 76: "return",
            117: "forwarddelete", 115: "home", 119: "end", 116: "pageup", 121: "pagedown",
            123: "left", 124: "right", 125: "down", 126: "up",
            122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 97: "f6",
            98: "f7", 100: "f8", 101: "f9", 109: "f10", 103: "f11", 111: "f12",
            105: "f13", 107: "f14", 113: "f15", 106: "f16", 64: "f17", 79: "f18",
            80: "f19", 90: "f20"
        ]
        guard let key = namedKeys[event.keyCode] ?? event.charactersIgnoringModifiers?.lowercased() else {
            return nil
        }
        var parts: [String] = []
        if keymapModifiers.contains(.control) { parts.append("ctrl") }
        if keymapModifiers.contains(.option) { parts.append("opt") }
        if keymapModifiers.contains(.shift) { parts.append("shift") }
        if keymapModifiers.contains(.command) { parts.append("cmd") }
        parts.append(key)
        guard let binding = KeyBinding(string: parts.joined(separator: "+")) else { return nil }
        self = binding
    }

    var keyEquivalent: String {
        switch key {
        case "up": String(UnicodeScalar(NSUpArrowFunctionKey)!)
        case "down": String(UnicodeScalar(NSDownArrowFunctionKey)!)
        case "left": String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        case "right": String(UnicodeScalar(NSRightArrowFunctionKey)!)
        case "pageup": String(UnicodeScalar(NSPageUpFunctionKey)!)
        case "pagedown": String(UnicodeScalar(NSPageDownFunctionKey)!)
        case "home": String(UnicodeScalar(NSHomeFunctionKey)!)
        case "end": String(UnicodeScalar(NSEndFunctionKey)!)
        case "space": " "
        case "return": "\r"
        case "escape": "\u{1B}"
        case "tab": "\t"
        case "delete": "\u{8}"
        case "forwarddelete": String(UnicodeScalar(NSDeleteFunctionKey)!)
        default: key
        }
    }

    var modifierMask: NSEvent.ModifierFlags {
        var mask: NSEvent.ModifierFlags = []
        if modifiers.contains(.control) { mask.insert(.control) }
        if modifiers.contains(.option) { mask.insert(.option) }
        if modifiers.contains(.shift) { mask.insert(.shift) }
        if modifiers.contains(.command) { mask.insert(.command) }
        return mask
    }
}

@MainActor
final class KeymapStore {
    static let shared = KeymapStore()

    private(set) var keymap = Keymap()
    private(set) var file: KeymapFile?
    private(set) var errorMessage: String?
    private var watcher: KeymapDirectoryWatcher?
    private var lastPublishedState: String?

    private init() { reload() }

    var url: URL {
        let home = getpwuid(getuid()).flatMap { String(validatingCString: $0.pointee.pw_dir) }
            ?? NSHomeDirectory()
        return URL(fileURLWithPath: home)
            .appendingPathComponent(".config/daisy/keymap.json", isDirectory: false)
    }

    func reload() {
        let directory = url.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: directory.path) else {
            watcher?.cancel()
            watcher = nil
            file = nil
            keymap = Keymap()
            errorMessage = nil
            postChange()
            return
        }
        watch(directory)
        guard FileManager.default.fileExists(atPath: url.path) else {
            file = nil
            keymap = Keymap()
            errorMessage = nil
            postChange()
            return
        }
        do {
            let parsed = try KeymapFile(data: Data(contentsOf: url))
            file = parsed
            keymap = Keymap(file: parsed)
            errorMessage = keymap.diagnostics.isEmpty ? nil : keymap.diagnostics.joined(separator: "\n")
            postChange()
        } catch {
            // Preserve last good map and never write corrupt input.
            errorMessage = error.localizedDescription
            postChange()
        }
    }

    func checkForExternalChanges() { reload() }

    func rebind(_ command: KeymapCommand, to binding: KeyBinding?) throws {
        let defaults = Keymap.defaultBindings(for: command)
        if binding != nil, defaults.contains(binding!) { try reset(command); return }
        try modifyFile { file in
            try file.removeOverrides(for: command.rawValue, in: command.context)
            for defaultBinding in defaults {
                try file.set(defaultBinding, commandID: nil, in: command.context)
            }
            if let binding { try file.set(binding, commandID: command.rawValue, in: command.context) }
        }
    }

    func reset(_ command: KeymapCommand) throws {
        try modifyFile { file in
            try file.removeOverrides(for: command.rawValue, in: command.context)
            for binding in Keymap.defaultBindings(for: command) {
                try file.removeOverride(for: binding, in: command.context)
            }
        }
    }

    func resetAll() throws {
        try modifyFile { file in
            for command in KeymapCommand.allCases {
                try file.removeOverrides(for: command.rawValue, in: command.context)
                for binding in Keymap.defaultBindings(for: command) {
                    try file.removeOverride(for: binding, in: command.context)
                }
            }
        }
    }

    func exportDefaults() throws {
        var file = KeymapFile()
        for command in KeymapCommand.allCases {
            for binding in Keymap.defaultBindings(for: command) {
                try file.set(binding, commandID: command.rawValue, in: command.context)
            }
        }
        try write(file)
    }

    private func modifyFile(_ mutation: (inout KeymapFile) throws -> Void) throws {
        var next = file ?? KeymapFile()
        try mutation(&next)
        try write(next)
    }

    private func write(_ next: KeymapFile) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = url.resolvingSymlinksInPath()
        try next.serialized().write(to: target, options: .atomic)
        file = next
        keymap = Keymap(file: next)
        errorMessage = keymap.diagnostics.isEmpty ? nil : keymap.diagnostics.joined(separator: "\n")
        watch(directory)
        postChange()
    }

    private func watch(_ directory: URL) {
        guard watcher?.url == directory, watcher?.isWatching == true else {
            watcher?.cancel()
            watcher = KeymapDirectoryWatcher(url: directory) { [weak self] in self?.reload() }
            return
        }
    }

    private func postChange() {
        let state = keymap.changeToken + "\nerror=\(errorMessage ?? "")"
        guard state != lastPublishedState else { return }
        lastPublishedState = state
        NotificationCenter.default.post(name: .keymapDidChange, object: self)
    }
}

@MainActor
private final class KeymapDirectoryWatcher {
    let url: URL
    private(set) var isWatching = false
    private var descriptor: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    private var debounce: DispatchWorkItem?

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        let descriptor = Darwin.open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        self.descriptor = descriptor
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .delete, .rename, .revoke],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let events = source.data
            if !events.intersection([.delete, .rename, .revoke]).isEmpty {
                self.cancel()
            }
            self.debounce?.cancel()
            let work = DispatchWorkItem(block: onChange)
            self.debounce = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
        }
        source.setCancelHandler { [weak self] in
            guard let self else { return }
            self.isWatching = false
            guard self.descriptor >= 0 else { return }
            Darwin.close(self.descriptor)
            self.descriptor = -1
        }
        self.source = source
        isWatching = true
        source.resume()
    }

    func cancel() {
        debounce?.cancel()
        source?.cancel()
        source = nil
        isWatching = false
    }
}
