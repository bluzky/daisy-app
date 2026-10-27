//
//  MoveBannerView.swift
//  daisy
//
//  The message `/move` leaves at the bottom of the window: where the block
//  went, or why it didn't, with the buttons that still apply (Undo, Open)
//  and a close button. The window decides when it goes; see
//  DocumentWindowController+Move.swift.
//

import Cocoa

final class MoveBannerView: NSView {
    struct Action {
        let title: String
        let handler: () -> Void
    }

    var onClose: (() -> Void)?
    private var handlers: [() -> Void] = []
    /// The buttons, which show the pointing hand. The banner floats over the
    /// editor's web view, whose own cursor would otherwise win.
    private var buttons: [NSButton] = []

    init(message: String, symbol: String, actions: [Action]) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(message)

        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .withinWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.layer?.masksToBounds = true
        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)

        wantsLayer = true
        shadow = NSShadow()
        layer?.shadowOpacity = 0.18
        layer?.shadowRadius = 6
        layer?.shadowOffset = CGSize(width: 0, height: -1)

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.contentTintColor = .secondaryLabelColor
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.lineBreakMode = .byTruncatingMiddle
        label.toolTip = message
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        var views: [NSView] = [icon, label]
        for (index, action) in actions.enumerated() {
            let button = NSButton(title: action.title, target: self, action: #selector(performAction(_:)))
            button.bezelStyle = .push
            button.controlSize = .small
            button.tag = index
            button.setContentHuggingPriority(.required, for: .horizontal)
            handlers.append(action.handler)
            buttons.append(button)
            views.append(button)
        }
        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription:
                                                NSLocalizedString("Close", comment: "Move banner close button"))!,
                             target: self, action: #selector(closeTapped))
        close.isBordered = false
        close.contentTintColor = .secondaryLabelColor
        close.setContentHuggingPriority(.required, for: .horizontal)
        buttons.append(close)
        views.append(close)

        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)

        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: background.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -8),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Pins the banner to the bottom centre of `container`.
    func show(in container: NSView) {
        container.addSubview(self, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            centerXAnchor.constraint(equalTo: container.centerXAnchor),
            bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
            widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, constant: -32),
            widthAnchor.constraint(lessThanOrEqualToConstant: 560),
        ])
        NSAccessibility.post(element: self, notification: .announcementRequested,
                             userInfo: [.announcement: accessibilityLabel() ?? "", .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    // MARK: - Cursor

    private func cursor(at point: NSPoint) -> NSCursor {
        buttons.contains { $0.convert($0.bounds, to: self).contains(point) } ? .pointingHand : .arrow
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .arrow)
        for button in buttons {
            addCursorRect(button.convert(button.bounds, to: self), cursor: .pointingHand)
        }
    }

    override func layout() {
        super.layout()
        window?.invalidateCursorRects(for: self)
    }

    override func cursorUpdate(with event: NSEvent) {
        cursor(at: convert(event.locationInWindow, from: nil)).set()
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        cursorUpdate(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        cursorUpdate(with: event)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.cursorUpdate, .mouseEnteredAndExited, .mouseMoved,
                                                 .activeInKeyWindow, .enabledDuringMouseDrag],
                                       owner: self))
    }

    @objc private func performAction(_ sender: NSButton) {
        guard handlers.indices.contains(sender.tag) else { return }
        handlers[sender.tag]()
    }

    @objc private func closeTapped() {
        onClose?()
    }
}
