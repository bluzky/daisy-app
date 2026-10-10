//
//  WebInspector.swift
//  daisy
//
//  The View › Developer Tools toggle. WebKit has no public call to show the
//  inspector, so this reaches `WKWebView._inspector` (private) and does
//  nothing if the selectors ever disappear.
//

import AppKit
import WebKit

enum WebInspector {
    /// The web view the inspector should attach to: the visible one in the
    /// window, since the preview and the editor swap with `isHidden`.
    ///
    /// A detached inspector is a window of its own whose content is itself a
    /// `WKWebView`, and it can be the key window. It is skipped so the toggle
    /// keeps acting on the document it belongs to.
    static func targetWebView(in window: NSWindow?) -> WKWebView? {
        let candidates = [window].compactMap { $0 } + NSApp.orderedWindows
        for candidate in candidates where !isInspectorWindow(candidate) {
            if let root = candidate.contentView, let found = visibleWebView(in: root) {
                return found
            }
        }
        return nil
    }

    static func isVisible(_ webView: WKWebView) -> Bool {
        guard let inspector = inspector(of: webView),
              inspector.responds(to: Selector(("isVisible"))) else { return false }
        return inspector.value(forKey: "isVisible") as? Bool ?? false
    }

    static func toggle(_ webView: WKWebView) {
        guard let inspector = inspector(of: webView) else { return }
        let selector = Selector(isVisible(webView) ? "close" : "show")
        guard inspector.responds(to: selector) else { return }
        _ = inspector.perform(selector)
    }

    private static func isInspectorWindow(_ window: NSWindow) -> Bool {
        String(describing: type(of: window)).contains("Inspector")
    }

    private static func inspector(of webView: WKWebView) -> NSObject? {
        guard webView.responds(to: Selector(("_inspector"))) else { return nil }
        return webView.value(forKey: "_inspector") as? NSObject
    }

    private static func visibleWebView(in view: NSView) -> WKWebView? {
        if view.isHidden { return nil }
        if let webView = view as? WKWebView { return webView }
        for subview in view.subviews {
            if let found = visibleWebView(in: subview) { return found }
        }
        return nil
    }
}
