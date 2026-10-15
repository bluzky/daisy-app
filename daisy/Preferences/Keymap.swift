//
//  Keymap.swift
//  daisy
//
//  User-configurable app shortcut model and keymap file parser.
//

import Foundation

enum KeymapContext: String, CaseIterable, Hashable {
    case global
    case reading
    case editing
    case search
}

enum KeymapCommand: String, CaseIterable, Hashable {
    case fileOmniSearch = "file.omniSearch"
    case viewToggleSidebar = "view.toggleSidebar"
    case viewHideSidebar = "view.hideSidebar"
    case viewShowOutline = "view.showOutline"
    case viewShowProjectNavigator = "view.showProjectNavigator"
    case viewToggleEditMode = "view.toggleEditMode"
    case viewToggleToolbar = "view.toggleToolbar"
    case viewToggleAlwaysOnTop = "view.toggleAlwaysOnTop"

    case editPasteAndMatchStyle = "edit.pasteAndMatchStyle"
    case findFind = "find.find"
    case findReplace = "find.replace"
    case findNext = "find.next"
    case findPrevious = "find.previous"
    case findJumpToSelection = "find.jumpToSelection"

    case goBack = "go.back"
    case goForward = "go.forward"

    case goLineUp = "go.lineUp"
    case goLineDown = "go.lineDown"
    case goPageUp = "go.pageUp"
    case goPageDown = "go.pageDown"
    case goPreviousItem = "go.previousItem"
    case goNextItem = "go.nextItem"
    case goTop = "go.top"
    case goBottom = "go.bottom"

    case formatBody = "format.body"
    case formatHeading1 = "format.heading1"
    case formatHeading2 = "format.heading2"
    case formatHeading3 = "format.heading3"
    case formatBold = "format.bold"
    case formatItalic = "format.italic"
    case formatStrikethrough = "format.strikethrough"
    case formatInlineCode = "format.inlineCode"
    case formatLink = "format.link"
    case formatBulletList = "format.bulletList"
    case formatOrderedList = "format.orderedList"
    case formatChecklist = "format.checklist"
    case formatQuote = "format.quote"

    case searchSelectPrevious = "search.selectPrevious"
    case searchSelectNext = "search.selectNext"
    case searchOpenResult = "search.openResult"
    case searchOpenResultInNewTab = "search.openResultInNewTab"
    case searchOpenResultInNewWindow = "search.openResultInNewWindow"

    var context: KeymapContext {
        switch self {
        case .fileOmniSearch,
             .viewToggleSidebar, .viewHideSidebar, .viewShowOutline,
             .viewShowProjectNavigator, .viewToggleEditMode, .viewToggleToolbar,
             .viewToggleAlwaysOnTop, .findFind, .findReplace, .findNext,
             .findPrevious, .findJumpToSelection, .goBack, .goForward:
            .global
        case .goLineUp, .goLineDown, .goPageUp, .goPageDown,
             .goPreviousItem, .goNextItem, .goTop, .goBottom:
            .reading
        case .editPasteAndMatchStyle, .formatBody, .formatHeading1, .formatHeading2, .formatHeading3,
             .formatBold, .formatItalic, .formatStrikethrough,
             .formatInlineCode, .formatLink, .formatBulletList,
             .formatOrderedList, .formatChecklist, .formatQuote:
            .editing
        case .searchSelectPrevious, .searchSelectNext, .searchOpenResult,
             .searchOpenResultInNewTab, .searchOpenResultInNewWindow:
            .search
        }
    }

    var titleKey: String {
        switch self {
        case .fileOmniSearch: "OmniSearch…"
        case .viewToggleSidebar: "Toggle Sidebar"
        case .viewHideSidebar: "Hide Sidebar"
        case .viewShowOutline: "Table of Contents"
        case .viewShowProjectNavigator: "Project Navigator"
        case .viewToggleEditMode: "Toggle Edit Mode"
        case .viewToggleToolbar: "Show Toolbar"
        case .viewToggleAlwaysOnTop: "Always on Top"
        case .editPasteAndMatchStyle: "Paste and Match Style"
        case .findFind: "Find…"
        case .findReplace: "Find and Replace…"
        case .findNext: "Find Next"
        case .findPrevious: "Find Previous"
        case .findJumpToSelection: "Jump to Selection"
        case .goBack: "Back"
        case .goForward: "Forward"
        case .goLineUp: "Up"
        case .goLineDown: "Down"
        case .goPageUp: "Page Up"
        case .goPageDown: "Page Down"
        case .goPreviousItem: "Previous Item"
        case .goNextItem: "Next Item"
        case .goTop: "Top of Document"
        case .goBottom: "Bottom of Document"
        case .formatBody: "Body"
        case .formatHeading1: "Heading 1"
        case .formatHeading2: "Heading 2"
        case .formatHeading3: "Heading 3"
        case .formatBold: "Bold"
        case .formatItalic: "Italic"
        case .formatStrikethrough: "Strikethrough"
        case .formatInlineCode: "Inline Code"
        case .formatLink: "Link"
        case .formatBulletList: "Bulleted List"
        case .formatOrderedList: "Numbered List"
        case .formatChecklist: "Checklist"
        case .formatQuote: "Block Quote"
        case .searchSelectPrevious: "Previous Result"
        case .searchSelectNext: "Next Result"
        case .searchOpenResult: "Open Result"
        case .searchOpenResultInNewTab: "Open Result in New Tab"
        case .searchOpenResultInNewWindow: "Open Result in New Window"
        }
    }
}

struct KeyBinding: Hashable, Comparable, CustomStringConvertible {
    struct Modifiers: OptionSet, Hashable {
        let rawValue: UInt8
        static let control = Modifiers(rawValue: 1 << 0)
        static let option = Modifiers(rawValue: 1 << 1)
        static let shift = Modifiers(rawValue: 1 << 2)
        static let command = Modifiers(rawValue: 1 << 3)
    }

    let key: String
    let modifiers: Modifiers

    init(key: String, modifiers: Modifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }

    init?(string: String) {
        let parts = string.lowercased().split(separator: "+", omittingEmptySubsequences: false)
        guard let keyPart = parts.last, !keyPart.isEmpty else { return nil }
        var modifiers: Modifiers = []
        for part in parts.dropLast() {
            let modifier: Modifiers
            switch part {
            case "ctrl": modifier = .control
            case "opt": modifier = .option
            case "shift": modifier = .shift
            case "cmd": modifier = .command
            default: return nil
            }
            guard !modifiers.contains(modifier) else { return nil }
            modifiers.insert(modifier)
        }
        guard Self.isSupportedKey(String(keyPart)) else { return nil }
        self.init(key: String(keyPart), modifiers: modifiers)
    }

    var description: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.option) { parts.append("opt") }
        if modifiers.contains(.shift) { parts.append("shift") }
        if modifiers.contains(.command) { parts.append("cmd") }
        parts.append(key)
        return parts.joined(separator: "+")
    }

    static func < (lhs: KeyBinding, rhs: KeyBinding) -> Bool { lhs.description < rhs.description }

    /// The binding as a menu shows it: `⌘↩`, `⌥↑`, `⇧⌘P`.
    var displayString: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + Self.glyph(for: key)
    }

    private static func glyph(for key: String) -> String {
        switch key {
        case "up": "↑"
        case "down": "↓"
        case "left": "←"
        case "right": "→"
        case "return": "↩"
        case "escape": "Esc"
        case "tab": "⇥"
        case "space": "Space"
        case "delete": "⌫"
        case "forwarddelete": "⌦"
        case "pageup": "⇞"
        case "pagedown": "⇟"
        case "home": "↖"
        case "end": "↘"
        default: key.uppercased()
        }
    }

    private static func isSupportedKey(_ key: String) -> Bool {
        if key.count == 1, key.unicodeScalars.allSatisfy({ $0.isASCII && !$0.properties.isWhitespace }) {
            return true
        }
        if let number = Int(key.dropFirst()), key.hasPrefix("f"), (1...20).contains(number) {
            return true
        }
        return ["up", "down", "left", "right", "pageup", "pagedown", "home", "end",
                "space", "return", "escape", "tab", "delete", "forwarddelete"].contains(key)
    }
}

struct KeymapEntry: Equatable {
    let rawKey: String
    var commandID: String?

    var binding: KeyBinding? { KeyBinding(string: rawKey) }
}

enum KeymapFileError: LocalizedError, Equatable {
    case invalidJSON(String)
    case invalidVersion

    var errorDescription: String? {
        switch self {
        case .invalidJSON(let message): "Invalid keymap JSON: \(message)"
        case .invalidVersion: "Keymap version must be a positive integer."
        }
    }
}

/// Retains entries and unknown JSON content so Settings never discards a newer
/// Daisy version's data. Serialization intentionally normalizes whitespace.
struct KeymapFile {
    static let supportedVersion = 1

    private var root: RawJSON
    let version: Int
    let isReadOnly: Bool
    let diagnostics: [String]
    let hasDuplicateKeys: Bool

    init(data: Data) throws {
        let root: RawJSON
        do {
            var parser = RawJSONParser(data: data)
            root = try parser.parse()
        } catch {
            throw KeymapFileError.invalidJSON(error.localizedDescription)
        }
        guard case let .object(pairs) = root else {
            throw KeymapFileError.invalidJSON("root must be an object")
        }

        var diagnostics: [String] = []
        var duplicates = false
        let topDuplicates = Self.duplicateKeys(in: pairs)
        if !topDuplicates.isEmpty {
            diagnostics.append("Duplicate top-level key: \(topDuplicates.joined(separator: ", "))")
            duplicates = true
        }
        let version: Int
        if let rawVersion = pairs.last(where: { $0.0 == "version" })?.1 {
            guard case let .number(value) = rawVersion, let parsed = Int(value), parsed > 0 else {
                throw KeymapFileError.invalidVersion
            }
            version = parsed
        } else {
            version = 1
        }

        for context in KeymapContext.allCases {
            guard let value = pairs.last(where: { $0.0 == context.rawValue })?.1 else { continue }
            guard case let .object(entries) = value else {
                diagnostics.append("\(context.rawValue) must be an object")
                continue
            }
            let sectionDuplicates = Self.duplicateKeys(in: entries)
            if !sectionDuplicates.isEmpty {
                diagnostics.append("Duplicate key in \(context.rawValue): \(sectionDuplicates.joined(separator: ", "))")
                duplicates = true
            }
        }

        self.root = root
        self.version = version
        self.isReadOnly = version > Self.supportedVersion
        self.diagnostics = diagnostics + (version > Self.supportedVersion
            ? ["Keymap was created by a newer Daisy version; it is read-only."] : [])
        self.hasDuplicateKeys = duplicates
    }

    init() {
        root = .object([("version", .number("1"))])
        version = 1
        isReadOnly = false
        diagnostics = []
        hasDuplicateKeys = false
    }

    func entries(in context: KeymapContext) -> [KeymapEntry] {
        guard case let .object(pairs) = root,
              case let .object(entries)? = pairs.last(where: { $0.0 == context.rawValue })?.1
        else { return [] }
        return entries.compactMap { key, value in
            switch value {
            case .null: KeymapEntry(rawKey: key, commandID: nil)
            case .string(let id): KeymapEntry(rawKey: key, commandID: id)
            default: nil
            }
        }
    }

    mutating func removeOverrides(for commandID: String, in context: KeymapContext) throws {
        guard !isReadOnly else { throw KeymapFileError.invalidJSON("keymap is read-only") }
        guard !hasDuplicateKeys else { throw KeymapFileError.invalidJSON("duplicate keys must be fixed before writing") }
        guard case var .object(rootPairs) = root,
              let index = rootPairs.lastIndex(where: { $0.0 == context.rawValue }),
              case var .object(entries) = rootPairs[index].1 else { return }
        entries.removeAll { entry in
            if case let .string(value) = entry.1 { return value == commandID }
            return false
        }
        rootPairs[index].1 = .object(entries)
        root = .object(rootPairs)
    }

    mutating func removeOverride(for binding: KeyBinding, in context: KeymapContext) throws {
        guard !isReadOnly else { throw KeymapFileError.invalidJSON("keymap is read-only") }
        guard !hasDuplicateKeys else { throw KeymapFileError.invalidJSON("duplicate keys must be fixed before writing") }
        guard case var .object(rootPairs) = root,
              let index = rootPairs.lastIndex(where: { $0.0 == context.rawValue }),
              case var .object(entries) = rootPairs[index].1 else { return }
        entries.removeAll { $0.0 == binding.description }
        rootPairs[index].1 = .object(entries)
        root = .object(rootPairs)
    }

    /// Changes known section only. Unknown values and top-level entries remain.
    mutating func set(_ binding: KeyBinding, commandID: String?, in context: KeymapContext) throws {
        guard !isReadOnly else { throw KeymapFileError.invalidJSON("keymap is read-only") }
        guard !hasDuplicateKeys else { throw KeymapFileError.invalidJSON("duplicate keys must be fixed before writing") }
        guard case var .object(rootPairs) = root else { return }
        let entry = (binding.description, commandID.map(RawJSON.string) ?? .null)
        if let index = rootPairs.lastIndex(where: { $0.0 == context.rawValue }),
           case var .object(entries) = rootPairs[index].1 {
            entries.removeAll { $0.0 == binding.description }
            entries.append(entry)
            rootPairs[index].1 = .object(entries)
        } else {
            rootPairs.append((context.rawValue, .object([entry])))
        }
        root = .object(rootPairs)
    }

    func serialized() -> Data { Data(root.serialized(pretty: true).utf8) }

    private static func duplicateKeys(in pairs: [(String, RawJSON)]) -> [String] {
        var seen = Set<String>()
        return pairs.compactMap { seen.insert($0.0).inserted ? nil : $0.0 }
    }
}

struct Keymap {
    private var bindings: [KeymapContext: [(KeyBinding, KeymapCommand)]]
    let diagnostics: [String]

    init(file: KeymapFile? = nil) {
        var bindings = Self.defaultBindings
        var diagnostics = file?.diagnostics ?? []
        guard let file else {
            self.bindings = bindings
            self.diagnostics = diagnostics
            return
        }

        for context in KeymapContext.allCases {
            for entry in file.entries(in: context) {
                guard let binding = entry.binding else {
                    diagnostics.append("Invalid key in \(context.rawValue): \(entry.rawKey)")
                    continue
                }
                guard let commandID = entry.commandID else {
                    bindings[context]?.removeAll { $0.0 == binding }
                    continue
                }
                guard let command = KeymapCommand(rawValue: commandID) else {
                    diagnostics.append("Unknown command: \(commandID)")
                    continue
                }
                guard command.context == context else {
                    diagnostics.append("\(commandID) does not belong in \(context.rawValue)")
                    continue
                }
                bindings[context]?.removeAll { $0.0 == binding }
                bindings[context, default: []].append((binding, command))
            }
        }
        self.bindings = bindings
        self.diagnostics = diagnostics
    }

    func command(for binding: KeyBinding, in context: KeymapContext) -> KeymapCommand? {
        if let global = bindings[.global]?.first(where: { $0.0 == binding })?.1 { return global }
        guard context != .global else { return nil }
        return bindings[context]?.first(where: { $0.0 == binding })?.1
    }

    func bindings(for command: KeymapCommand) -> [KeyBinding] {
        bindings[command.context, default: []].compactMap { $0.1 == command ? $0.0 : nil }
    }

    static func defaultBindings(for command: KeymapCommand) -> [KeyBinding] {
        defaultBindings[command.context, default: []].compactMap { $0.1 == command ? $0.0 : nil }
    }

    func conflicts(for binding: KeyBinding, in context: KeymapContext) -> [KeymapCommand] {
        let contexts: [KeymapContext] = context == .global ? KeymapContext.allCases : [.global, context]
        return contexts.flatMap { bindings[$0, default: []] }
            .compactMap { $0.0 == binding ? $0.1 : nil }
    }

    var changeToken: String {
        KeymapContext.allCases.map { context in
            bindings[context, default: []]
                .map { "\($0.0.description)=\($0.1.rawValue)" }
                .joined(separator: ",")
        }.joined(separator: "|") + "|" + diagnostics.joined(separator: "\n")
    }

    private static let defaultBindings: [KeymapContext: [(KeyBinding, KeymapCommand)]] = [
        .global: pairs([
            ("cmd+k", .fileOmniSearch), ("cmd+l", .viewToggleSidebar),
            ("ctrl+cmd+1", .viewHideSidebar), ("ctrl+cmd+2", .viewShowOutline),
            ("ctrl+cmd+3", .viewShowProjectNavigator), ("cmd+e", .viewToggleEditMode),
            ("opt+cmd+t", .viewToggleToolbar), ("ctrl+cmd+t", .viewToggleAlwaysOnTop),
            ("cmd+f", .findFind), ("opt+cmd+f", .findReplace), ("cmd+g", .findNext),
            ("shift+cmd+g", .findPrevious), ("cmd+j", .findJumpToSelection),
            ("cmd+[", .goBack), ("cmd+]", .goForward)
        ]),
        .reading: pairs([
            ("up", .goLineUp), ("down", .goLineDown), ("pageup", .goPageUp),
            ("pagedown", .goPageDown), ("opt+up", .goPreviousItem),
            ("opt+down", .goNextItem), ("cmd+up", .goTop), ("cmd+down", .goBottom)
        ]),
        .editing: pairs([
            ("opt+shift+cmd+v", .editPasteAndMatchStyle),
            ("opt+cmd+0", .formatBody), ("opt+cmd+1", .formatHeading1),
            ("opt+cmd+2", .formatHeading2), ("opt+cmd+3", .formatHeading3),
            ("cmd+b", .formatBold), ("cmd+i", .formatItalic),
            ("shift+cmd+x", .formatStrikethrough), ("shift+cmd+m", .formatInlineCode),
            ("shift+cmd+7", .formatBulletList),
            ("shift+cmd+9", .formatOrderedList), ("shift+cmd+l", .formatChecklist),
            ("cmd+'", .formatQuote)
        ]),
        .search: pairs([
            ("up", .searchSelectPrevious), ("down", .searchSelectNext),
            ("return", .searchOpenResult), ("cmd+return", .searchOpenResultInNewTab),
            ("opt+return", .searchOpenResultInNewWindow)
        ])
    ]

    private static func pairs(_ values: [(String, KeymapCommand)]) -> [(KeyBinding, KeymapCommand)] {
        values.compactMap { pair in
            KeyBinding(string: pair.0).map { ($0, pair.1) }
        }
    }
}

private indirect enum RawJSON {
    case object([(String, RawJSON)])
    case array([RawJSON])
    case string(String)
    case number(String)
    case bool(Bool)
    case null

    func serialized(pretty: Bool, depth: Int = 0) -> String {
        let indent = String(repeating: "  ", count: depth)
        let nextIndent = String(repeating: "  ", count: depth + 1)
        switch self {
        case .null: return "null"
        case .bool(let value): return value ? "true" : "false"
        case .number(let value): return value
        case .string(let value): return "\"\(Self.escaped(value))\""
        case .array(let values):
            guard !values.isEmpty else { return "[]" }
            if !pretty { return "[" + values.map { $0.serialized(pretty: false) }.joined(separator: ",") + "]" }
            return "[\n" + values.map { nextIndent + $0.serialized(pretty: true, depth: depth + 1) }
                .joined(separator: ",\n") + "\n" + indent + "]"
        case .object(let pairs):
            guard !pairs.isEmpty else { return "{}" }
            if !pretty {
                return "{" + pairs.map { "\"\(Self.escaped($0.0))\":" + $0.1.serialized(pretty: false) }
                    .joined(separator: ",") + "}"
            }
            return "{\n" + pairs.map { nextIndent + "\"\(Self.escaped($0.0))\": "
                + $0.1.serialized(pretty: true, depth: depth + 1) }.joined(separator: ",\n")
                + "\n" + indent + "}"
        }
    }

    private static func escaped(_ string: String) -> String {
        string.unicodeScalars.map { scalar in
            switch scalar.value {
            case 0x22: "\\\""
            case 0x5C: "\\\\"
            case 0x08: "\\b"
            case 0x0C: "\\f"
            case 0x0A: "\\n"
            case 0x0D: "\\r"
            case 0x09: "\\t"
            case 0...0x1F: String(format: "\\u%04X", scalar.value)
            default: String(scalar)
            }
        }.joined()
    }
}

private struct RawJSONParser {
    private let scalars: [UnicodeScalar]
    private var index = 0

    init(data: Data) {
        scalars = Array(String(decoding: data, as: UTF8.self).unicodeScalars)
    }

    mutating func parse() throws -> RawJSON {
        skipWhitespace()
        let value = try parseValue()
        skipWhitespace()
        guard index == scalars.count else { throw error("unexpected content") }
        return value
    }

    private mutating func parseValue() throws -> RawJSON {
        guard let scalar = current else { throw error("unexpected end of file") }
        switch scalar {
        case "{": return try parseObject()
        case "[": return try parseArray()
        case "\"": return .string(try parseString())
        case "t": try consume("true"); return .bool(true)
        case "f": try consume("false"); return .bool(false)
        case "n": try consume("null"); return .null
        case "-", "0"..."9": return .number(try parseNumber())
        default: throw error("unexpected character '\(scalar)'")
        }
    }

    private mutating func parseObject() throws -> RawJSON {
        try expect("{")
        skipWhitespace()
        var pairs: [(String, RawJSON)] = []
        if consumeIf("}") { return .object(pairs) }
        while true {
            skipWhitespace()
            guard current == "\"" else { throw error("object key must be a string") }
            let key = try parseString()
            skipWhitespace(); try expect(":"); skipWhitespace()
            pairs.append((key, try parseValue()))
            skipWhitespace()
            if consumeIf("}") { return .object(pairs) }
            try expect(",")
        }
    }

    private mutating func parseArray() throws -> RawJSON {
        try expect("[")
        skipWhitespace()
        var values: [RawJSON] = []
        if consumeIf("]") { return .array(values) }
        while true {
            skipWhitespace(); values.append(try parseValue()); skipWhitespace()
            if consumeIf("]") { return .array(values) }
            try expect(",")
        }
    }

    private mutating func parseString() throws -> String {
        try expect("\"")
        var output = String.UnicodeScalarView()
        while let scalar = current {
            index += 1
            if scalar == "\"" { return String(output) }
            guard scalar != "\\" else {
                guard let escaped = current else { throw error("unfinished escape") }
                index += 1
                switch escaped {
                case "\"", "\\", "/": output.append(escaped)
                case "b": output.append("\u{08}")
                case "f": output.append("\u{0C}")
                case "n": output.append("\n")
                case "r": output.append("\r")
                case "t": output.append("\t")
                case "u": output.append(try parseUnicodeEscape())
                default: throw error("invalid escape")
                }
                continue
            }
            guard scalar.value >= 0x20 else { throw error("unescaped control character") }
            output.append(scalar)
        }
        throw error("unterminated string")
    }

    private mutating func parseUnicodeEscape() throws -> UnicodeScalar {
        guard index + 4 <= scalars.count else { throw error("short unicode escape") }
        let hex = String(String.UnicodeScalarView(scalars[index..<(index + 4)]))
        index += 4
        guard let value = UInt32(hex, radix: 16), let scalar = UnicodeScalar(value) else {
            throw error("invalid unicode escape")
        }
        return scalar
    }

    private mutating func parseNumber() throws -> String {
        let start = index
        if consumeIf("-") {}
        if consumeIf("0") {
        } else {
            try consumeDigits(requireOne: true)
        }
        if consumeIf(".") { try consumeDigits(requireOne: true) }
        if current == "e" || current == "E" {
            index += 1
            if current == "+" || current == "-" { index += 1 }
            try consumeDigits(requireOne: true)
        }
        return String(String.UnicodeScalarView(scalars[start..<index]))
    }

    private mutating func consumeDigits(requireOne: Bool) throws {
        let start = index
        while let scalar = current, scalar.value >= 48 && scalar.value <= 57 { index += 1 }
        if requireOne && index == start { throw error("expected digit") }
    }

    private var current: UnicodeScalar? { index < scalars.count ? scalars[index] : nil }

    private mutating func skipWhitespace() {
        while let scalar = current, scalar == " " || scalar == "\n" || scalar == "\r" || scalar == "\t" { index += 1 }
    }

    private mutating func expect(_ value: UnicodeScalar) throws {
        guard consumeIf(value) else { throw error("expected '\(value)'") }
    }

    private mutating func consume(_ string: String) throws {
        for scalar in string.unicodeScalars { try expect(scalar) }
    }

    @discardableResult
    private mutating func consumeIf(_ scalar: UnicodeScalar) -> Bool {
        guard current == scalar else { return false }
        index += 1
        return true
    }

    private func error(_ message: String) -> KeymapParseError {
        KeymapParseError(message: "\(message) at character \(index + 1)")
    }
}

private struct KeymapParseError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
