//
//  PresentationWindowController.swift
//  daisy
//
//  View ▸ Present: a document shown full screen as slides, one at a time,
//  with a presenter view on the other display when there is one.
//

import Cocoa
import WebKit

/// Takes every key before the web view does, so arrows and Space move
/// between slides instead of scrolling the page.
private final class PresentationWindow: NSWindow {
    var keyHandler: ((NSEvent) -> Bool)?

    // A borderless window can't take keys unless it says so.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }
}

/// Owns the presentation's windows and its `PresentationSession`. The
/// session is the source of truth; each page is told which slide and step
/// to show after every change and after every load.
///
/// - The audience window shows the slide full screen, on an external
///   display when there is one.
/// - With two displays, the presenter window on the document's display
///   shows the current slide with its notes, the next slide, the slide
///   number and the elapsed time.
///
/// The audience window is a borderless window covering its display, above
/// the menu bar and Dock, rather than native full screen: entering a
/// full-screen Space animates the window growing from its frame, and a
/// presentation should simply appear. It fades in once its first slide is
/// ready, and drops to a normal level while another app is active.
///
/// Esc, closing the audience window or closing the document ends the
/// presentation. Closing only the presenter window, or
/// unplugging a display, keeps presenting on one screen.
@MainActor
final class PresentationWindowController: NSObject, NSWindowDelegate {
    /// The file being presented, so its updates reach the presentation.
    let sourceURL: URL?
    /// Called once the presentation has ended and its windows are closed.
    var onEnd: (() -> Void)?

    private let session: PresentationSession
    private let assetBaseURL: URL?
    private weak var documentWindow: NSWindow?
    private let audienceWindow: PresentationWindow
    private let audienceView = MarkdownWebView(frame: .zero)
    private var presenterWindow: PresentationWindow?
    private var presenterView: MarkdownWebView?
    private var presenterStatusLabel: NSTextField?
    private var presenterClockLabel: NSTextField?
    private var clockTimer: Timer?
    private var displaySleepActivity: NSObjectProtocol?
    private var observers: [NSObjectProtocol] = []
    private var hasEnded = false

    init(markdown: String, sourceURL: URL?, assetBaseURL: URL?, documentWindow: NSWindow?,
         startSlide: Int = 0) {
        self.sourceURL = sourceURL
        self.assetBaseURL = assetBaseURL
        self.documentWindow = documentWindow
        session = PresentationSession(stepCounts: Self.stepCounts(of: markdown), index: startSlide)

        let documentScreen = documentWindow?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let externalScreen = NSScreen.screens.first { $0 != documentScreen }
        let audienceScreen = externalScreen ?? documentScreen
        audienceWindow = PresentationWindow(
            contentRect: audienceScreen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        super.init()

        Self.configureWindow(audienceWindow, title: Self.title(for: sourceURL))
        audienceWindow.backgroundColor = .black
        audienceWindow.level = Self.presentingLevel
        audienceWindow.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        audienceWindow.animationBehavior = .none
        audienceWindow.alphaValue = 0
        audienceWindow.setFrame(audienceScreen.frame, display: false)
        audienceWindow.delegate = self
        audienceWindow.keyHandler = { [weak self] event in self?.handleKey(event) ?? false }
        configureView(audienceView, hostStateID: MarkdownHTML.slidesPresentingStateID)
        audienceWindow.contentView = audienceView

        if externalScreen != nil {
            makePresenterWindow(on: documentScreen)
        }

        session.onChange = { [weak self] in self?.showCurrentSlide() }
        session.onEnd = { [weak self] in self?.end() }
        display(markdown)

        let center = NotificationCenter.default
        if let documentWindow {
            observers.append(center.addObserver(
                forName: NSWindow.willCloseNotification, object: documentWindow, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.end() }
            })
        }
        observers.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensDidChange() }
        })
        // Above the menu bar only while Daisy is active, so switching to
        // another app doesn't leave the slides covering it.
        observers.append(center.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.audienceWindow.level = .normal }
        })
        observers.append(center.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.audienceWindow.level = Self.presentingLevel }
        })
    }

    /// Above the menu bar and the Dock.
    private static let presentingLevel = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)

    /// Shows the windows; the audience window fades in with its first slide.
    func start() {
        displaySleepActivity = ProcessInfo.processInfo.beginActivity(
            options: [.idleDisplaySleepDisabled, .userInitiated],
            reason: "Presenting slides"
        )
        presenterWindow?.makeKeyAndOrderFront(nil)
        audienceWindow.makeKeyAndOrderFront(nil)
        startClock()
    }

    /// The presented file changed on disk: show the new text, staying on
    /// the same slide where it still exists.
    func update(markdown: String) {
        guard !hasEnded else { return }
        display(markdown)
        session.updateStepCounts(Self.stepCounts(of: markdown))
    }

    /// Ends the presentation and closes its windows.
    func end() {
        guard !hasEnded else { return }
        hasEnded = true
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        clockTimer?.invalidate()
        clockTimer = nil
        if let displaySleepActivity {
            ProcessInfo.processInfo.endActivity(displaySleepActivity)
            self.displaySleepActivity = nil
        }
        closePresenter()
        audienceWindow.close()
        documentWindow?.makeKeyAndOrderFront(nil)
        onEnd?()
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === audienceWindow {
            end()
        } else if window === presenterWindow {
            closePresenter()
        }
    }

    // MARK: Windows

    private static func title(for sourceURL: URL?) -> String {
        sourceURL?.lastPathComponent
            ?? NSLocalizedString("Untitled", comment: "Window title when no document is open")
    }

    private static func configureWindow(_ window: NSWindow, title: String) {
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
    }

    private func configureView(_ view: MarkdownWebView, hostStateID: String) {
        view.forcesSlides = true
        view.extensionHostState = [hostStateID: true]
        // Hidden until the first slide is chosen, so the slide strip never
        // flashes before the presenting state applies.
        view.alphaValue = 0
        view.contentDidReplace = { [weak self] in self?.showCurrentSlide() }
    }

    private func makePresenterWindow(on screen: NSScreen) {
        let window = PresentationWindow(
            contentRect: screen.visibleFrame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        Self.configureWindow(window, title: NSLocalizedString("Presenter", comment: "Presenter window title"))
        window.backgroundColor = .windowBackgroundColor
        window.delegate = self
        window.keyHandler = { [weak self] event in self?.handleKey(event) ?? false }

        let status = NSTextField(labelWithString: "")
        status.font = .systemFont(ofSize: 15, weight: .semibold)
        let clock = NSTextField(labelWithString: "0:00")
        clock.font = .monospacedDigitSystemFont(ofSize: 22, weight: .medium)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let bar = NSStackView(views: [status, spacer, clock])
        bar.orientation = .horizontal
        bar.edgeInsets = NSEdgeInsets(top: 0, left: 24, bottom: 0, right: 24)

        let view = MarkdownWebView(frame: .zero)
        configureView(view, hostStateID: MarkdownHTML.slidesPresenterStateID)

        let content = NSView()
        for subview in [bar, view] as [NSView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: content.safeAreaLayoutGuide.topAnchor, constant: 8),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: 32),
            view.topAnchor.constraint(equalTo: bar.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        window.contentView = content
        window.setFrame(screen.visibleFrame, display: false)

        presenterWindow = window
        presenterView = view
        presenterStatusLabel = status
        presenterClockLabel = clock
    }

    /// Keeps presenting on the audience window alone.
    private func closePresenter() {
        guard let window = presenterWindow else { return }
        presenterWindow = nil
        presenterView = nil
        presenterStatusLabel = nil
        presenterClockLabel = nil
        window.delegate = nil
        window.close()
        if !hasEnded { audienceWindow.makeKeyAndOrderFront(nil) }
    }

    /// With one display left, the presenter view would cover the slides;
    /// macOS moves the audience window to the remaining display.
    /// A display was unplugged or changed resolution: keep the slides
    /// covering a display that still exists, and with one display left,
    /// close the presenter view, which would cover the slides.
    private func screensDidChange() {
        if NSScreen.screens.count < 2 { closePresenter() }
        let screen = audienceWindow.screen.flatMap { current in NSScreen.screens.first { $0 == current } }
            ?? NSScreen.screens.first { $0 != presenterWindow?.screen }
            ?? NSScreen.main
        if let screen { audienceWindow.setFrame(screen.frame, display: true) }
    }

    // MARK: Showing the session

    private func display(_ markdown: String) {
        audienceView.display(markdown: markdown, assetBaseURL: assetBaseURL, documentID: "presentation")
        presenterView?.display(markdown: markdown, assetBaseURL: assetBaseURL, documentID: "presentation")
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
        let show = "MdPreviewSlides.show(\(session.index), \(session.step));"
        reveal(audienceView, script: "\(show) MdPreviewSlides.blank(\(blank));")
        if let presenterView { reveal(presenterView, script: show) }
        updatePresenterStatus()
    }

    private func reveal(_ view: MarkdownWebView, script: String) {
        view.webView.evaluateJavaScript("if (window.MdPreviewSlides) { \(script) }") { [weak self, weak view] _, _ in
            view?.alphaValue = 1
            guard let self, view === self.audienceView, self.audienceWindow.alphaValue < 1 else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                self.audienceWindow.animator().alphaValue = 1
            }
        }
    }

    private func updatePresenterStatus() {
        guard let presenterStatusLabel else { return }
        var status = String(
            format: NSLocalizedString("Slide %1$d of %2$d", comment: "Presenter view slide number"),
            session.index + 1, session.slideCount
        )
        let steps = session.stepCounts[session.index]
        if steps > 0 {
            status += "  ·  " + String(
                format: NSLocalizedString("Step %1$d of %2$d", comment: "Presenter view step number"),
                session.step, steps
            )
        }
        if session.blank != nil {
            status += "  ·  " + NSLocalizedString("Screen blanked", comment: "Presenter view blank state")
        }
        presenterStatusLabel.stringValue = status
    }

    private func startClock() {
        guard presenterClockLabel != nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateClock() }
        }
        RunLoop.main.add(timer, forMode: .common)
        clockTimer = timer
        updateClock()
    }

    private func updateClock() {
        let seconds = Int(Date().timeIntervalSince(session.startDate))
        presenterClockLabel?.stringValue = seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private static func stepCounts(of markdown: String) -> [Int] {
        MarkdownHTML.slideStepCounts(
            markdown: markdown,
            configuration: RenderExtensionPreferences.currentConfiguration
        )
    }
}
