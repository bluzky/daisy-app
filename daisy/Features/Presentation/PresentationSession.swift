//
//  PresentationSession.swift
//  daisy
//
//  The state of a running presentation, owned natively; the web view only
//  shows it.
//

import Foundation

/// What a key does while presenting.
enum PresentationCommand: Equatable {
    case next
    case previous
    case first
    case last
    /// A typed digit, collected until Return jumps to that slide.
    case digit(Int)
    /// Return: jump to the typed slide number, or advance when none is typed.
    case confirm
    case blankBlack
    case blankWhite
    case end

    private enum KeyCode {
        static let returnKey: UInt16 = 36
        static let space: UInt16 = 49
        static let delete: UInt16 = 51
        static let escape: UInt16 = 53
        static let keypadEnter: UInt16 = 76
        static let home: UInt16 = 115
        static let pageUp: UInt16 = 116
        static let end: UInt16 = 119
        static let pageDown: UInt16 = 121
        static let left: UInt16 = 123
        static let right: UInt16 = 124
        static let down: UInt16 = 125
        static let up: UInt16 = 126
    }

    /// Presentation clickers send Page Up and Page Down, so they work
    /// without setup. Keys with Command or Control are left to the menus.
    init?(keyCode: UInt16, characters: String?, hasCommandOrControl: Bool = false) {
        guard !hasCommandOrControl else { return nil }
        switch keyCode {
        case KeyCode.right, KeyCode.down, KeyCode.pageDown, KeyCode.space: self = .next
        case KeyCode.left, KeyCode.up, KeyCode.pageUp, KeyCode.delete: self = .previous
        case KeyCode.home: self = .first
        case KeyCode.end: self = .last
        case KeyCode.returnKey, KeyCode.keypadEnter: self = .confirm
        case KeyCode.escape: self = .end
        default:
            switch characters?.lowercased() {
            case "b": self = .blankBlack
            case "w": self = .blankWhite
            case let text? where text.count == 1:
                guard let digit = text.first?.wholeNumberValue,
                      text.first?.isASCII == true else { return nil }
                self = .digit(digit)
            default: return nil
            }
        }
    }
}

@MainActor
final class PresentationSession {
    enum Blank: String {
        case black
        case white
    }

    private(set) var slideCount: Int
    /// Zero-based.
    private(set) var index: Int
    private(set) var blank: Blank?
    /// Digits typed since the last jump.
    private(set) var typedNumber = ""

    /// Called after every change of slide or blanking.
    var onChange: (() -> Void)?
    /// Called when the presenter asks to stop.
    var onEnd: (() -> Void)?

    init(slideCount: Int, index: Int = 0) {
        self.slideCount = max(1, slideCount)
        self.index = 0
        self.index = clamped(index)
    }

    func perform(_ command: PresentationCommand) {
        switch command {
        case .next: go(to: index + 1)
        case .previous: go(to: index - 1)
        case .first: go(to: 0)
        case .last: go(to: slideCount - 1)
        case .digit(let digit):
            typedNumber = String((typedNumber + String(digit)).suffix(4))
        case .confirm:
            if let number = Int(typedNumber) {
                go(to: number - 1)
            } else {
                go(to: index + 1)
            }
        case .blankBlack: toggleBlank(.black)
        case .blankWhite: toggleBlank(.white)
        case .end:
            onEnd?()
        }
    }

    /// The document changed: keep the slide, clamped to the new count, so
    /// deleting the current slide moves to the one before it.
    func updateSlideCount(_ count: Int) {
        slideCount = max(1, count)
        index = clamped(index)
        onChange?()
    }

    private func go(to target: Int) {
        typedNumber = ""
        blank = nil
        index = clamped(target)
        onChange?()
    }

    private func toggleBlank(_ mode: Blank) {
        typedNumber = ""
        blank = blank == mode ? nil : mode
        onChange?()
    }

    private func clamped(_ value: Int) -> Int {
        min(max(0, value), slideCount - 1)
    }
}
