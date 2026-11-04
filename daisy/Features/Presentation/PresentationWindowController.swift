//
//  PresentationWindowController.swift
//  daisy
//
//  View ▸ Present: a document shown full screen as slides, one at a time.
//

import Cocoa
import WebKit

/// Takes every key before the web view does, so arrows and Space move
/// between slides instead of scrolling the page.
private final class PresentationWindow: NSWindow {
    var keyHandler: ((NSEvent) -> Bool)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }
}

/// Owns the presentation window and its `PresentationSession`. The session
/// is the source of truth; the page is told which slide to show after every
/// change and after every load.
@MainActor
final class PresentationWindowController: NSWindowController, NSWindowDelegate {
    /// The file being presented, so its updates reach the presentation.
    let sourceURL: URL?
    /// Called once the presentation has ended and its window is closed.
    var onEnd: (() -> Void)?

    private let markdownView = MarkdownWebView(frame: .zero)
    private let session: PresentationSession
    private let assetBaseURL: URL?
    private weak var documentWindow: NSWindow?
    private nonisolated(unsafe) var documentWindowObserver: NSObjectProtocol?
    private var hasEnded = false

    init(markdown: String, sourceURL: URL?, assetBaseURL: URL?, documentWindow: NSWindow?) {
        self.sourceURL = sourceURL
        self.assetBaseURL = assetBaseURL
        self.documentWindow = documentWindow
        session = PresentationSession(slideCount: Self.slideCount(of: markdown))

        let screen = Self.presentationScreen(besides: documentWindow)
        let window = PresentationWindow(
            contentRect: screen.frame,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = sourceURL?.lastPathComponent
            ?? NSLocalizedString("Untitled", comment: "Window title when no document is open")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .black
        window.collectionBehavior = [.fullScreenPrimary]
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.keyHandler = { [weak self] event in self?.handleKey(event) ?? false }

        markdownView.forcesSlides = true
        markdownView.extensionHostState = [MarkdownHTML.slidesPresentingStateID: true]
        // Hidden until the first slide is chosen, so the slide strip never
        // flashes before the presenting state applies.
        markdownView.alphaValue = 0
        markdownView.contentDidReplace = { [weak self] in self?.showCurrentSlide() }
        window.contentView = markdownView

        session.onChange = { [weak self] in self?.showCurrentSlide() }
        session.onEnd = { [weak self] in self?.end() }
        markdownView.display(markdown: markdown, assetBaseURL: assetBaseURL, documentID: "presentation")

        if let documentWindow {
            documentWindowObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: documentWindow,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.end() }
            }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        if let documentWindowObserver {
            NotificationCenter.default.removeObserver(documentWindowObserver)
        }
    }

    /// Shows the window on its screen and enters full screen there.
    func start() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        window.toggleFullScreen(nil)
    }

    /// The presented file changed on disk: show the new text, staying on
    /// the same slide where it still exists.
    func update(markdown: String) {
        guard !hasEnded else { return }
        markdownView.display(markdown: markdown, assetBaseURL: assetBaseURL, documentID: "presentation")
        session.updateSlideCount(Self.slideCount(of: markdown))
    }

    /// Ends the presentation and closes its window.
    func end() {
        guard !hasEnded else { return }
        hasEnded = true
        if let documentWindowObserver {
            NotificationCenter.default.removeObserver(documentWindowObserver)
            self.documentWindowObserver = nil
        }
        // Closing a full-screen window also removes its Space.
        window?.close()
        documentWindow?.makeKeyAndOrderFront(nil)
        onEnd?()
    }

    func windowWillClose(_ notification: Notification) {
        end()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        // Leaving full screen from the green button or ⌃⌘F ends it too.
        end()
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard let command = PresentationCommand(
            keyCode: event.keyCode,
            characters: event.charactersIgnoringModifiers,
            hasCommandOrControl: !modifiers.isDisjoint(with: [.command, .control])
        ) else { return false }
        NSCursor.setHiddenUntilMouseMoves(true)
        session.perform(command)
        return true
    }

    private func showCurrentSlide() {
        let blank = session.blank.map { "'\($0.rawValue)'" } ?? "null"
        markdownView.webView.evaluateJavaScript("""
        if (window.MdPreviewSlides) {
            MdPreviewSlides.show(\(session.index));
            MdPreviewSlides.blank(\(blank));
        }
        """) { [weak self] _, _ in
            self?.markdownView.alphaValue = 1
        }
    }

    private static func slideCount(of markdown: String) -> Int {
        MarkdownHTML.slideCount(
            markdown: markdown,
            configuration: RenderExtensionPreferences.currentConfiguration
        )
    }

    /// An external display when there is one, so the document stays on the
    /// laptop; otherwise the document's own screen.
    private static func presentationScreen(besides documentWindow: NSWindow?) -> NSScreen {
        let documentScreen = documentWindow?.screen ?? NSScreen.main
        return NSScreen.screens.first { $0 != documentScreen }
            ?? documentScreen
            ?? NSScreen.screens[0]
    }
}
