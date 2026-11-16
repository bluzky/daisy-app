//
//  DocumentWindow.swift
//  daisy
//
//  The window of a document. It makes a double-click on the window's title
//  zoom the window, as a double-click anywhere else on the titlebar already
//  does.
//
//  On macOS 26 the title of a window that represents a file is a control of
//  its own, and it fills all the empty space of the toolbar (a 764-point
//  wide text element between the sidebar button and the right-hand groups).
//  A double-click there is taken by that control, and the window never sees
//  it as a titlebar double-click: the gaps between toolbar items zoom, the
//  space under the title does not.
//

import AppKit

final class DocumentWindow: NSWindow {

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, event.clickCount == 2,
           doubleClickOnTitle(at: event.locationInWindow) {
            return
        }
        super.sendEvent(event)
    }

    /// Carries out the system's "double-click a window's title bar to" action
    /// when the click is on the title text, and says whether it did. Clicks
    /// anywhere else, in the toolbar's buttons or in its gaps, are left to
    /// AppKit, which already handles them.
    private func doubleClickOnTitle(at point: NSPoint) -> Bool {
        guard #available(macOS 26.0, *), titlebarAppearsTransparent,
              point.y > contentLayoutRect.maxY,
              let frameView = contentView?.superview else { return false }
        let hit = frameView.hitTest(frameView.convert(point, from: nil))
        guard Self.isTitleText(hit, stoppingAt: frameView) else { return false }

        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
        case "None": break
        case "Minimize": performMiniaturize(nil)
        default: performZoom(nil)
        }
        return true
    }

    /// The view is the toolbar's title: AppKit's title container and the title
    /// views inside it. Found by name, since they are private classes (a live
    /// double-click lands on `NSToolbarPrimaryTitleContainerView`, inside
    /// `NSToolbarTitleView`), with the static-text role as a second way in.
    /// A click on a toolbar button or on the gaps between items never has
    /// these in its chain, and a renamed class only means no extra zoom.
    private static func isTitleText(_ view: NSView?, stoppingAt frameView: NSView) -> Bool {
        var current = view
        for _ in 0..<4 {
            guard let candidate = current, candidate !== frameView else { return false }
            let name = String(describing: type(of: candidate))
            if name.contains("ToolbarPrimaryTitle") || name.contains("ToolbarTitle")
                || candidate.accessibilityRole() == .staticText {
                return true
            }
            // The toolbar itself is above the title: a click that reaches it
            // without passing a title view is on a gap or an item.
            if name.contains("NSToolbarView") { return false }
            current = candidate.superview
        }
        return false
    }
}
