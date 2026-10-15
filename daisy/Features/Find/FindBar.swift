//
//  FindBar.swift
//  daisy
//

import Cocoa

/// The find and replace bar shown beneath the toolbar: query field, match
/// options (case, word, regex), match count, previous / next chevrons and a
/// close button. In edit mode a disclosure button reveals a second row with
/// the replacement field.
final class FindBar: NSView, NSSearchFieldDelegate {

    static let rowHeight: CGFloat = 36
    static let replaceRowHeight: CGFloat = 28

    var onQueryChanged: ((String) -> Void)?
    var onNavigate: ((_ backwards: Bool) -> Void)?
    var onOptionsChanged: (() -> Void)?
    var onReplace: (() -> Void)?
    var onReplaceAll: (() -> Void)?
    var onClose: (() -> Void)?
    /// The bar's height changed (replace row shown or hidden).
    var onHeightChanged: (() -> Void)?

    private let disclosureButton = NSButton()
    private let queryField = NSSearchField()
    private let replacementField = NSSearchField()
    private let caseButton = NSButton()
    private let wordButton = NSButton()
    private let regexButton = NSButton()
    private let countLabel = NSTextField(labelWithString: "")
    private let navigationControl = NSSegmentedControl()
    private let closeButton = NSButton()
    private let replaceButton = NSButton(
        title: NSLocalizedString("Replace", comment: "Find bar replace button"),
        target: nil,
        action: nil
    )
    private let replaceAllButton = NSButton(
        title: NSLocalizedString("Replace All", comment: "Find bar replace all button"),
        target: nil,
        action: nil
    )

    /// "N replaced" outlives the zero-match update the edit itself triggers.
    private var replacedCount: Int?

    private enum NavigationSegment: Int {
        case previous = 0
        case next = 1
    }

    /// The replace row is only for the editable source; the preview has none.
    var isReplaceAvailable = false {
        didSet {
            guard isReplaceAvailable != oldValue else { return }
            updateReplaceRow()
        }
    }

    private(set) var isReplaceExpanded = false

    var query: String {
        get { queryField.stringValue }
        set { queryField.stringValue = newValue }
    }

    var replacement: String { replacementField.stringValue }

    var options: SearchOptions {
        SearchOptions(
            mode: regexButton.state == .on ? .regex : wordButton.state == .on ? .word : .substring,
            caseSensitive: caseButton.state == .on
        )
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    // MARK: - Public

    func focusQuery(selectingText: Bool = true) {
        window?.makeFirstResponder(queryField)
        if selectingText { queryField.selectText(nil) }
    }

    func focusReplacement() {
        guard isReplaceExpanded else { return }
        window?.makeFirstResponder(replacementField)
    }

    func setReplaceExpanded(_ expanded: Bool) {
        let expanded = expanded && isReplaceAvailable
        guard expanded != isReplaceExpanded else { return }
        isReplaceExpanded = expanded
        updateReplaceRow()
    }

    /// Whether `responder` is one of this bar's controls (including the field
    /// editor while a field is being edited).
    func contains(firstResponder responder: NSResponder?) -> Bool {
        guard let responder else { return false }
        if let editor = responder as? NSTextView, editor.isFieldEditor,
           let owner = editor.delegate as? NSView {
            return owner.isDescendant(of: self)
        }
        return (responder as? NSView)?.isDescendant(of: self) ?? false
    }

    func update(_ result: FindResult) {
        let label: String
        if query.isEmpty {
            label = ""
        } else if result.error {
            label = NSLocalizedString("Invalid pattern", comment: "Find bar invalid regular expression")
        } else if result.total == 0, let replacedCount {
            label = String(
                format: NSLocalizedString("%d replaced", comment: "Find bar replace all result"),
                replacedCount
            )
        } else if result.total == 0 {
            label = NSLocalizedString("Not found", comment: "Find bar empty result")
        } else if result.capped {
            label = String(
                format: NSLocalizedString("%d of %d+", comment: "Find bar current and capped match count"),
                result.index,
                result.total
            )
        } else {
            label = String(
                format: NSLocalizedString("%d of %d", comment: "Find bar current and total match count"),
                result.index,
                result.total
            )
        }
        countLabel.stringValue = label
        countLabel.textColor = result.error ? .systemRed : .secondaryLabelColor
        let hasMatches = result.total > 0
        navigationControl.setEnabled(hasMatches, forSegment: NavigationSegment.previous.rawValue)
        navigationControl.setEnabled(hasMatches, forSegment: NavigationSegment.next.rawValue)
        replaceButton.isEnabled = hasMatches
        replaceAllButton.isEnabled = hasMatches
    }

    /// Remembers a Replace All so the count reads "N replaced" once nothing
    /// matches any more.
    func noteReplaced(_ count: Int) {
        replacedCount = count > 0 ? count : nil
    }

    func clearReplacedNote() {
        replacedCount = nil
    }

    // MARK: - Layout

    private var showsReplaceRow: Bool { isReplaceAvailable && isReplaceExpanded }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.rowHeight
            + (showsReplaceRow ? Self.replaceRowHeight : 0))
    }

    private func setUp() {
        configureDisclosureButton()
        configureQueryField()
        configureReplacementField()
        configureOptionButtons()
        configureNavigationControl()
        configureCloseButton()
        configureReplaceButtons()

        countLabel.font = .systemFont(ofSize: NSFont.systemFontSize)
        countLabel.textColor = .secondaryLabelColor
        countLabel.alignment = .right
        countLabel.lineBreakMode = .byTruncatingHead
        countLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let controls: [NSView] = [
            disclosureButton, queryField, replacementField, caseButton, wordButton, regexButton,
            countLabel, navigationControl, closeButton, replaceButton, replaceAllButton,
        ]
        for control in controls {
            control.translatesAutoresizingMaskIntoConstraints = false
            addSubview(control)
        }

        let rowCenter = Self.rowHeight / 2
        let replaceCenter = Self.rowHeight + Self.replaceRowHeight / 2 - 2
        let countWidth = countLabel.widthAnchor.constraint(equalToConstant: 84)
        countWidth.priority = .defaultHigh
        let queryWidth = queryField.widthAnchor.constraint(greaterThanOrEqualToConstant: 120)
        queryWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            disclosureButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            disclosureButton.widthAnchor.constraint(equalToConstant: 18),
            disclosureButton.centerYAnchor.constraint(equalTo: topAnchor, constant: rowCenter),

            queryField.leadingAnchor.constraint(equalTo: disclosureButton.trailingAnchor, constant: 4),
            queryField.centerYAnchor.constraint(equalTo: topAnchor, constant: rowCenter),
            queryWidth,

            caseButton.leadingAnchor.constraint(equalTo: queryField.trailingAnchor, constant: 8),
            wordButton.leadingAnchor.constraint(equalTo: caseButton.trailingAnchor, constant: 4),
            regexButton.leadingAnchor.constraint(equalTo: wordButton.trailingAnchor, constant: 4),
            countLabel.leadingAnchor.constraint(equalTo: regexButton.trailingAnchor, constant: 10),
            countWidth,
            navigationControl.leadingAnchor.constraint(equalTo: countLabel.trailingAnchor, constant: 8),
            closeButton.leadingAnchor.constraint(equalTo: navigationControl.trailingAnchor, constant: 8),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            closeButton.widthAnchor.constraint(equalToConstant: 20),

            replacementField.leadingAnchor.constraint(equalTo: queryField.leadingAnchor),
            replacementField.trailingAnchor.constraint(equalTo: queryField.trailingAnchor),
            replacementField.centerYAnchor.constraint(equalTo: topAnchor, constant: replaceCenter),
            replaceButton.leadingAnchor.constraint(equalTo: caseButton.leadingAnchor),
            replaceAllButton.leadingAnchor.constraint(equalTo: replaceButton.trailingAnchor, constant: 8),
            replaceButton.centerYAnchor.constraint(equalTo: replacementField.centerYAnchor),
            replaceAllButton.centerYAnchor.constraint(equalTo: replacementField.centerYAnchor),
        ])
        for control in [caseButton, wordButton, regexButton, countLabel, navigationControl, closeButton] {
            control.centerYAnchor.constraint(equalTo: topAnchor, constant: rowCenter).isActive = true
        }
        updateReplaceRow()
        update(.none)
    }

    private func updateReplaceRow() {
        disclosureButton.isHidden = !isReplaceAvailable
        replacementField.isHidden = !showsReplaceRow
        replaceButton.isHidden = !showsReplaceRow
        replaceAllButton.isHidden = !showsReplaceRow
        let name = isReplaceExpanded ? "chevron.down" : "chevron.right"
        disclosureButton.image = NSImage(
            systemSymbolName: name,
            accessibilityDescription: NSLocalizedString("Toggle Replace", comment: "Find bar replace disclosure")
        )
        disclosureButton.state = isReplaceExpanded ? .on : .off
        invalidateIntrinsicContentSize()
        onHeightChanged?()
    }

    // MARK: - Controls

    private func configureDisclosureButton() {
        disclosureButton.isBordered = false
        disclosureButton.imagePosition = .imageOnly
        disclosureButton.contentTintColor = .secondaryLabelColor
        disclosureButton.toolTip = NSLocalizedString("Toggle Replace", comment: "Find bar replace disclosure")
        disclosureButton.target = self
        disclosureButton.action = #selector(disclosureTapped)
    }

    private func configureQueryField() {
        queryField.placeholderString = NSLocalizedString("Find", comment: "Find bar query placeholder")
        queryField.sendsSearchStringImmediately = true
        queryField.sendsWholeSearchString = false
        queryField.delegate = self
        queryField.target = self
        queryField.action = #selector(queryChanged)
        queryField.setAccessibilityLabel(NSLocalizedString("Find", comment: "Find bar query placeholder"))
    }

    private func configureReplacementField() {
        replacementField.placeholderString = NSLocalizedString("Replace", comment: "Find bar replace placeholder")
        // The same rounded field as the query, minus its search affordances,
        // so the two rows match in shape and height.
        if let cell = replacementField.cell as? NSSearchFieldCell {
            cell.searchButtonCell = nil
            cell.cancelButtonCell = nil
        }
        replacementField.usesSingleLineMode = true
        replacementField.delegate = self
        replacementField.setAccessibilityLabel(NSLocalizedString("Replace", comment: "Find bar replace placeholder"))
    }

    private func configureOptionButtons() {
        configure(caseButton, title: "Aa",
                  label: NSLocalizedString("Match Case", comment: "Find bar option"), shortcut: "⌥⌘C")
        let word = NSMutableAttributedString(string: "ab", attributes: [
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
        ])
        configure(wordButton, title: "ab",
                  label: NSLocalizedString("Word", comment: "Find bar option: whole words only"),
                  shortcut: "⌥⌘W")
        wordButton.attributedTitle = word
        configure(regexButton, title: ".*",
                  label: NSLocalizedString("Regex", comment: "Find bar option: regular expression"),
                  shortcut: "⌥⌘R")
    }

    private func configure(_ button: NSButton, title: String, label: String, shortcut: String) {
        button.title = title
        button.bezelStyle = .flexiblePush
        if #unavailable(macOS 26.0) {
            button.bezelStyle = .accessoryBar
        }
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        useCapsuleShape(for: button)
        button.setButtonType(.pushOnPushOff)
        button.showsBorderOnlyWhileMouseInside = true
        button.setAccessibilitySubrole(.toggle)
        button.setAccessibilityLabel(label)
        button.toolTip = "\(label) (\(shortcut))"
        button.target = self
        button.action = #selector(optionToggled(_:))
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true
        updateLegacyAppearance(of: button)
    }

    /// Matches the pill-shaped query and replacement fields.
    private func useCapsuleShape(for button: NSButton) {
        if #available(macOS 26.0, *) {
            button.borderShape = .capsule
        }
    }

    private func updateLegacyAppearance(of button: NSButton) {
        guard #unavailable(macOS 26.0) else { return }
        // Keep an enabled option visible after the pointer leaves it.
        button.showsBorderOnlyWhileMouseInside = button.state != .on
    }

    private func configureNavigationControl() {
        let previousMatch = NSLocalizedString("Previous match", comment: "Find bar navigation button")
        let nextMatch = NSLocalizedString("Next match", comment: "Find bar navigation button")
        let previous = NSImage(systemSymbolName: "chevron.left",
                               accessibilityDescription: previousMatch) ?? NSImage()
        let next = NSImage(systemSymbolName: "chevron.right",
                           accessibilityDescription: nextMatch) ?? NSImage()
        previous.isTemplate = true
        next.isTemplate = true

        navigationControl.segmentStyle = .rounded
        navigationControl.trackingMode = .momentary
        navigationControl.segmentCount = 2
        navigationControl.setImage(previous, forSegment: NavigationSegment.previous.rawValue)
        navigationControl.setImage(next, forSegment: NavigationSegment.next.rawValue)
        navigationControl.setToolTip(previousMatch, forSegment: NavigationSegment.previous.rawValue)
        navigationControl.setToolTip(nextMatch, forSegment: NavigationSegment.next.rawValue)
        navigationControl.setImageScaling(.scaleProportionallyDown,
                                          forSegment: NavigationSegment.previous.rawValue)
        navigationControl.setImageScaling(.scaleProportionallyDown,
                                          forSegment: NavigationSegment.next.rawValue)
        navigationControl.target = self
        navigationControl.action = #selector(navigationTapped(_:))
    }

    private func configureCloseButton() {
        let label = NSLocalizedString("Close", comment: "Find bar close button")
        closeButton.isBordered = false
        closeButton.imagePosition = .imageOnly
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: label)
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.toolTip = label
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
    }

    private func configureReplaceButtons() {
        for button in [replaceButton, replaceAllButton] {
            button.bezelStyle = .rounded
            button.controlSize = .small
            useCapsuleShape(for: button)
        }
        replaceButton.target = self
        replaceButton.action = #selector(replaceTapped)
        replaceAllButton.target = self
        replaceAllButton.action = #selector(replaceAllTapped)
        replaceAllButton.toolTip = "\(replaceAllButton.title) (⌥⌘↩)"
    }

    // MARK: - Actions

    @objc private func disclosureTapped() {
        setReplaceExpanded(!isReplaceExpanded)
        if isReplaceExpanded { focusReplacement() }
    }

    @objc private func queryChanged() {
        clearReplacedNote()
        onQueryChanged?(queryField.stringValue)
    }

    @objc private func optionToggled(_ sender: NSButton) {
        // Word and regex are alternatives to each other; case is independent.
        if sender === wordButton, wordButton.state == .on { regexButton.state = .off }
        if sender === regexButton, regexButton.state == .on { wordButton.state = .off }
        for button in [caseButton, wordButton, regexButton] { updateLegacyAppearance(of: button) }
        clearReplacedNote()
        onOptionsChanged?()
    }

    @objc private func navigationTapped(_ sender: NSSegmentedControl) {
        clearReplacedNote()
        switch NavigationSegment(rawValue: sender.selectedSegment) {
        case .previous: onNavigate?(true)
        case .next: onNavigate?(false)
        case .none: break
        }
    }

    @objc private func closeTapped() { onClose?() }
    @objc private func replaceTapped() { onReplace?() }
    @objc private func replaceAllTapped() { onReplaceAll?() }

    // MARK: - Keyboard

    func controlTextDidChange(_ notification: Notification) {
        if (notification.object as? NSTextField) === queryField { queryChanged() }
    }

    func control(_ control: NSControl,
                 textView: NSTextView,
                 doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.cancelOperation(_:)):
            onClose?()
            return true
        case #selector(NSResponder.insertNewline(_:)):
            if control === replacementField {
                onReplace?()
            } else {
                clearReplacedNote()
                onNavigate?(NSEvent.modifierFlags.contains(.shift))
            }
            return true
        default:
            return false
        }
    }

    /// Option-Command shortcuts, live only while a bar control has focus:
    /// ⌥⌘W would otherwise be the Window menu's Close All.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard !isHidden, contains(firstResponder: window?.firstResponder),
              event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                .isSuperset(of: [.option, .command]) else {
            return super.performKeyEquivalent(with: event)
        }
        let others: NSEvent.ModifierFlags = [.control, .shift]
        guard event.modifierFlags.intersection(others).isEmpty else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "c": caseButton.performClick(nil)
        case "w": wordButton.performClick(nil)
        case "r": regexButton.performClick(nil)
        case "\r":
            guard isReplaceAvailable, isReplaceExpanded else { return true }
            onReplaceAll?()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }
}
