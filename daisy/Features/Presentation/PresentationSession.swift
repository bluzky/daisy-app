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

    /// Each slide's number of `<!-- step -->` clicks.
    private(set) var stepCounts: [Int]
    /// Zero-based.
    private(set) var index: Int
    /// Steps revealed on the current slide; 0 shows none of them.
    private(set) var step = 0
    private(set) var blank: Blank?
    /// Digits typed since the last jump.
    private(set) var typedNumber = ""
    let startDate = Date()

    /// Called after every change of slide, step or blanking.
    var onChange: (() -> Void)?
    /// Called when the presenter asks to stop.
    var onEnd: (() -> Void)?

    var slideCount: Int { stepCounts.count }

    init(stepCounts: [Int], index: Int = 0) {
        self.stepCounts = stepCounts.isEmpty ? [0] : stepCounts
        self.index = 0
        self.index = clamped(index)
    }

    convenience init(slideCount: Int, index: Int = 0) {
        self.init(stepCounts: Array(repeating: 0, count: max(1, slideCount)), index: index)
    }

    func perform(_ command: PresentationCommand) {
        switch command {
        case .next:
            if step < stepCounts[index] {
                show(index, step: step + 1)
            } else if index < slideCount - 1 {
                show(index + 1, step: 0)
            } else {
                show(index, step: step)
            }
        case .previous:
            if step > 0 {
                show(index, step: step - 1)
            } else if index > 0 {
                // Back to the previous slide as it was left: fully built.
                show(index - 1, step: stepCounts[index - 1])
            } else {
                show(index, step: 0)
            }
        case .first: show(0, step: 0)
        case .last: show(slideCount - 1, step: 0)
        case .digit(let digit):
            typedNumber = String((typedNumber + String(digit)).suffix(4))
        case .confirm:
            if let number = Int(typedNumber) {
                show(number - 1, step: 0)
            } else {
                perform(.next)
            }
        case .blankBlack: toggleBlank(.black)
        case .blankWhite: toggleBlank(.white)
        case .end:
            onEnd?()
        }
    }

    /// The document changed: keep the slide and step, clamped to the new
    /// counts, so deleting the current slide moves to the one before it.
    func updateStepCounts(_ counts: [Int]) {
        stepCounts = counts.isEmpty ? [0] : counts
        index = clamped(index)
        step = min(step, stepCounts[index])
        onChange?()
    }

    func updateSlideCount(_ count: Int) {
        updateStepCounts(Array(repeating: 0, count: max(1, count)))
    }

    private func show(_ target: Int, step targetStep: Int) {
        typedNumber = ""
        blank = nil
        index = clamped(target)
        step = min(max(0, targetStep), stepCounts[index])
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
