//
//  EditorViewController.swift
//  daisy
//

import Cocoa
import WebKit

/// Inline Typora-style editor for the current document: a CodeMirror 6
/// page (Vendor/CodeMirror/mdedit.min.js) with live-preview decorations —
/// headings, emphasis, quotes and code style themselves as you type, and
/// syntax marks hide unless the cursor is inside them. The buffer is the
/// markdown source itself, so saving is byte-faithful: nothing is
/// reformatted or normalized. The page is fully self-contained (no
/// network), so edit mode works offline and inside the sandbox.
final class EditorViewController: NSViewController, WKNavigationDelegate {

    /// Fired on every document change — the host debounces for autosave.
    var contentDidChange: (() -> Void)?
    var formattingDidChange: ((Int, Set<String>) -> Void)?
    /// Fired after CodeMirror has constructed and painted its initial document.
    /// The split view uses this to avoid replacing the preview with a blank WKWebView.
    var editorDidBecomeReady: (() -> Void)?
    /// Esc pressed in the editor — the host decides whether to confirm
    /// and discard.
    var cancelRequested: (() -> Void)?
    /// A native image was pasted at the editor selection.
    var pasteImageRequested: ((Int, Int) -> Void)?
    var pickImageRequested: ((Int, Int) -> Void)?
    /// The slash menu's Link to File: the host picks a project file and
    /// inserts a link at this range.
    var pickLinkRequested: ((Int, Int) -> Void)?
    /// The slash menu's `/move`: the block on the caret's line, waiting for
    /// the host to pick where it goes. Nothing is removed until
    /// `completeMove` (see docs/technical/move-to-file-proposal.md).
    struct MoveRequest: Equatable {
        let id: Int
        let kind: MarkdownSectionInsertion.BlockKind
        let text: String
        /// 1-based lines of the block in the buffer.
        let firstLine: Int
        let lastLine: Int
    }
    var pickMoveTargetRequested: ((MoveRequest) -> Void)?
    /// The slash menu's `/carryover`: the host moves the earlier days'
    /// unfinished tasks to the caret, where the typed `/carryover` was.
    var insertCarryOverRequested: (() -> Void)?
    /// Files dragged from the Files sidebar and dropped at a document
    /// position; the host inserts them like pasted files. Nil refuses drops.
    var projectFilesDropped: (([URL], Int) -> Void)?
    /// A finished move's id once the buffer changed after it: its Undo
    /// button no longer applies.
    var moveBecameStale: ((Int) -> Void)?
    /// A rendered local image was clicked in the live editor preview.
    var imageClicked: ((URL) -> Void)?
    /// Cmd+click on a link or a metadata token.
    enum LinkRequest {
        /// A link destination as written in the Markdown.
        case destination(String)
        /// A `#tag`, `@context` or `+project` token, marker included.
        case metadata(String)
    }
    var linkActivated: ((LinkRequest) -> Void)?
    /// The document's `tasks`/`notes` blocks, each time they change.
    var queryBlocksRequested: (([QueryBlockRequest]) -> Void)?
    /// A result row clicked in a query block: path and line.
    var queryResultOpened: ((String, Int) -> Void)?
    /// A task's checkbox in a query block: path, line and the new state.
    var queryTaskToggled: ((String, Int, Bool) -> Void)?

    private(set) var hasChanges = false

    private var webView: WKWebView!
    private let bridge = EditorBridge()
    private let assetScheme = MarkdownAssetScheme()
    private var hasLoadedEditorPage = false
    private var pageSupportsMermaid = false
    private var currentAssetBaseURL: URL?
    private var findCompletion: ((FindResult) -> Void)?

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(assetScheme, forURLScheme: MarkdownAssetScheme.scheme)
        config.userContentController.add(bridge, name: EditorBridge.name)
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        let webView = EditorWKWebView(frame: .zero, configuration: config)
        webView.isInspectable = true
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        bridge.owner = self
        self.webView = webView
        NotificationCenter.default.addObserver(
            self, selector: #selector(templatesDidChange),
            name: TemplateStore.didChangeNotification, object: nil)
        // The web view gets a host view of its own, sized by autoresizing
        // rather than constraints: the docked Web Inspector is added to the
        // web view's superview, and WebKit then shrinks the web view's frame
        // to make room. Constraints would reset that frame on every layout
        // pass, covering the inspector until WebKit shrinks it again.
        let host: NSView
        if #available(macOS 26.0, *) {
            host = NSView()
        } else {
            // The preview's white backing disappears when edit mode hides it.
            // Give the transparent editor its own document background.
            host = LegacyEditorBackgroundView()
        }
        webView.frame = host.bounds
        webView.autoresizingMask = [.width, .height]
        host.addSubview(webView)
        view = host
        webView.appearanceDidChange = { [weak self] in
            self?.updateUnderPageBackgroundColor()
        }
        webView.acceptsProjectFiles = { [weak self] in
            guard let self else { return false }
            return self.projectFilesDropped != nil && self.codeLanguage == nil && self.hasLoadedEditorPage
        }
        webView.projectFileDragMoved = { [weak self] point in
            self?.moveFileDragCaret(to: point)
        }
        webView.projectFilesDropped = { [weak self] files, point in
            self?.dropProjectFiles(files, at: point)
        }
        webView.registerForDraggedTypes(webView.registeredDraggedTypes)
        updateUnderPageBackgroundColor()
    }

    /// The caret follows a file dragged from the Files sidebar; nil puts the
    /// selection back when the drag leaves.
    private func moveFileDragCaret(to point: CGPoint?) {
        let script = point.map { "window.__mdEditor && window.__mdEditor.dragFileCaret(\($0.x), \($0.y))" }
            ?? "window.__mdEditor && window.__mdEditor.endFileDrag(false)"
        webView.evaluateJavaScript(script) { _, _ in }
    }

    /// Hands the files to the host at the document position under `point`,
    /// or beeps where a pasted file would not go (code, table cells).
    private func dropProjectFiles(_ files: [URL], at point: CGPoint) {
        let script = """
        (() => {
            const editor = window.__mdEditor;
            if (!editor) return null;
            const pos = editor.fileDropPosition(\(point.x), \(point.y));
            editor.endFileDrag(pos !== null);
            return pos;
        })()
        """
        webView.evaluateJavaScript(script) { [weak self] value, _ in
            guard let self, let position = (value as? NSNumber)?.intValue else {
                NSSound.beep()
                return
            }
            self.projectFilesDropped?(files, position)
        }
    }

    /// A fence name or alias for a source or text file, "" for plain text;
    /// nil edits Markdown. Set by `load`, so a reused page switches mode too.
    private var codeLanguage: String?

    func load(markdown: String, assetBaseURL: URL? = nil, codeLanguage: String? = nil) {
        self.codeLanguage = codeLanguage
        hasChanges = false
        currentAssetBaseURL = assetBaseURL?.standardizedFileURL
        assetScheme.setBaseURL(currentAssetBaseURL)
        // Loaded whenever the extension is on, not only when the document
        // already has a diagram, so one added while editing renders too.
        // Code files edit as plain code; no extension applies, so no Mermaid.
        let needsMermaid = codeLanguage == nil
            && RenderExtensionPreferences.currentConfiguration.isEnabled("mermaid")
        if hasLoadedEditorPage, pageSupportsMermaid || !needsMermaid {
            let baseHref = currentAssetBaseURL.map(MarkdownAssetResolution.baseHref(forFolder:)) ?? ""
            let language = codeLanguage.map(EditorHTML.jsStringLiteral) ?? "undefined"
            let script = "window.__mdLoadEditor && window.__mdLoadEditor(\(EditorHTML.jsStringLiteral(markdown)), \(EditorHTML.jsStringLiteral(baseHref)), \(language))"
            webView.evaluateJavaScript(script) { [weak self] _, error in
                guard let self, error != nil else { return }
                self.loadEditorPage(markdown: markdown,
                                    includesMermaid: needsMermaid,
                                    assetBaseURL: self.currentAssetBaseURL)
            }
            return
        }
        loadEditorPage(markdown: markdown,
                       includesMermaid: needsMermaid,
                       assetBaseURL: currentAssetBaseURL)
    }

    private func loadEditorPage(markdown: String,
                                includesMermaid: Bool,
                                assetBaseURL: URL?) {
        hasLoadedEditorPage = false
        pageSupportsMermaid = includesMermaid
        webView.loadHTMLString(
            Self.editorHTML(markdown: markdown,
                            includesMermaid: includesMermaid,
                            assetBaseURL: assetBaseURL,
                            textScale: textScale,
                            codeLanguage: codeLanguage),
            baseURL: nil
        )
    }

    /// The reader's text size, mirroring the preview: `--mdp-text-scale`
    /// scales type and text spacing, and the page itself is never zoomed, so
    /// the column, gutters and chrome keep their on-screen size.
    private(set) var textScale: CGFloat = 1

    func applyTextScale(_ scale: CGFloat) {
        textScale = scale
        webView.evaluateJavaScript("document.documentElement.style.setProperty('\(MarkdownHTML.textScaleProperty)', '\(max(scale, 0.001))')", completionHandler: nil)
        updateChromeZoom()
    }

    private func updateChromeZoom() {
        guard #available(macOS 26.0, *) else { return }
        webView.evaluateJavaScript("document.documentElement.style.setProperty('--mdp-chrome-zoom', '\(max(webView.pageZoom, 0.001))')", completionHandler: nil)
    }

    /// Rewrites the theme override `<style>` so a color edited in Settings
    /// restyles an open editor live. Fresh loads embed the same CSS in
    /// `editorHTML`.
    func applyThemeColors() {
        updateUnderPageBackgroundColor()
        updateObscuredContentInsets()
        let script = ThemeColorsSetting.styleUpdateScript(
            css: ThemeColorsSetting.current.editorOverrideCSS
        )
        webView.evaluateJavaScript(script) { _, _ in }
    }

    /// Restyles an open editor after a font, reader-layout or alignment
    /// change in Settings, the way the preview page is restyled in place.
    func applyReaderStyle() {
        webView.evaluateJavaScript(
            ReaderLayoutSetting.styleUpdateScript(css: Self.readerStyleCSS())
        ) { _, _ in }
    }

    /// Switches editor modules on or off in an open editor after an
    /// extension toggle in Settings. Fresh loads embed the same state in
    /// `editorHTML`.
    func applyExtensionState() {
        let state = MarkdownHTML.editorExtensionState(
            configuration: RenderExtensionPreferences.currentConfiguration
        )
        webView.evaluateJavaScript(
            "window.__mdEditor && window.__mdEditor.setExtensionState(\(EditorHTML.extensionStateLiteral(state)))"
        ) { _, _ in }
    }

    /// Hands the template file's templates to the slash menu. Called when the
    /// page becomes ready and whenever the file or its choice changes.
    func applySlashTemplates() {
        let templates = TemplateStore.load().map { ["name": $0.name, "body": $0.body] }
        webView.evaluateJavaScript(
            "window.__mdEditor && window.__mdEditor.setSlashTemplates(\(EditorHTML.jsonArrayLiteral(templates)))"
        ) { _, _ in }
    }

    /// The workspace names the `#`, `@` and `+` menus offer besides the
    /// document's own. Kept here and sent again to each fresh page.
    private var workspaceCandidates: WorkspaceMetadataSnapshot?

    /// Whether metadata tokens read as links (workspace windows). Kept here
    /// and sent again to each fresh page, like the candidates.
    private var metadataLinksEnabled = false
    /// Whether the slash menu offers `/move`. Kept like the metadata links.
    private var moveBlocksEnabled = false
    /// Whether the slash menu offers `/carryover`. Kept like the metadata links.
    private var carryOverEnabled = false

    /// Shows `results` in place of their blocks; nil shows every block as code.
    func showQueryResults(_ results: [QueryBlockResult]?) {
        guard hasLoadedEditorPage else { return }
        let json = results.flatMap { try? JSONEncoder().encode($0) }.flatMap { String(data: $0, encoding: .utf8) }
        webView.evaluateJavaScript(
            "window.__mdEditor && window.__mdEditor.setQueryResults(\(json ?? "null"))"
        ) { _, _ in }
    }

    func setMetadataLinksEnabled(_ enabled: Bool) {
        guard enabled != metadataLinksEnabled else { return }
        metadataLinksEnabled = enabled
        guard hasLoadedEditorPage else { return }
        applyMetadataLinksEnabled()
    }

    func setMoveBlocksEnabled(_ enabled: Bool) {
        guard enabled != moveBlocksEnabled else { return }
        moveBlocksEnabled = enabled
        guard hasLoadedEditorPage else { return }
        applyMoveBlocksEnabled()
    }

    private func applyMoveBlocksEnabled() {
        webView.evaluateJavaScript(
            "window.__mdEditor && window.__mdEditor.setMoveBlocks(\(moveBlocksEnabled))"
        ) { _, _ in }
    }

    func setCarryOverEnabled(_ enabled: Bool) {
        guard enabled != carryOverEnabled else { return }
        carryOverEnabled = enabled
        guard hasLoadedEditorPage else { return }
        applyCarryOverEnabled()
    }

    private func applyCarryOverEnabled() {
        webView.evaluateJavaScript(
            "window.__mdEditor && window.__mdEditor.setCarryOver(\(carryOverEnabled))"
        ) { _, _ in }
    }

    /// Removes the move's block once its target holds it, as one undo step.
    /// False when the block changed since it was picked, or the page is gone.
    func completeMove(id: Int) async -> Bool {
        await evaluateMove("completeMove(\(id))")
    }

    /// A move within this buffer: `next` replaces `expected` as one undo
    /// step. False when the buffer is no longer `expected`.
    func applyMove(id: Int, expected: String, next: String) async -> Bool {
        await evaluateMove("applyMove(\(id), \(EditorHTML.jsStringLiteral(expected)), \(EditorHTML.jsStringLiteral(next)))")
    }

    /// The buffer as `completeMove` would leave it, for a move within this
    /// buffer; nil when the block changed.
    func moveRemovalPreview(id: Int) async -> (expected: String, removed: String)? {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript("window.__mdEditor ? window.__mdEditor.removalPreview(\(id)) : null") { value, _ in
                guard let result = value as? [String: Any], let expected = result["expected"] as? String,
                      let removed = result["removed"] as? String else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: (expected, removed))
            }
        }
    }

    /// Another window's write into this buffer (a `/move` target), as one
    /// undoable edit, only while the buffer still holds `expected`.
    func replaceIfUnchanged(expected: String, with next: String) async -> Bool {
        await evaluateMove("replaceIfUnchanged(\(EditorHTML.jsStringLiteral(expected)), \(EditorHTML.jsStringLiteral(next)))")
    }

    /// The Undo button: the move's own undo step, only while the buffer is
    /// as the move left it.
    func undoMove(id: Int) async -> Bool {
        await evaluateMove("undoMove(\(id))")
    }

    func forgetMove(id: Int) {
        webView.evaluateJavaScript("window.__mdEditor && window.__mdEditor.forgetMove(\(id))") { _, _ in }
    }

    private func evaluateMove(_ call: String) async -> Bool {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript("window.__mdEditor ? window.__mdEditor.\(call) : false") { value, _ in
                continuation.resume(returning: (value as? Bool) == true)
            }
        }
    }

    private func applyMetadataLinksEnabled() {
        webView.evaluateJavaScript(
            "window.__mdEditor && window.__mdEditor.setMetadataLinks(\(metadataLinksEnabled))"
        ) { _, _ in }
    }

    func setWorkspaceCandidates(_ snapshot: WorkspaceMetadataSnapshot?) {
        guard snapshot != workspaceCandidates else { return }
        workspaceCandidates = snapshot
        guard hasLoadedEditorPage else { return }
        applyWorkspaceCandidates()
    }

    private func applyWorkspaceCandidates() {
        guard let workspaceCandidates else { return }
        webView.evaluateJavaScript(
            "window.__mdEditor && window.__mdEditor.setWorkspaceCandidates(\(EditorHTML.workspaceCandidatesLiteral(workspaceCandidates)))"
        ) { _, _ in }
    }

    @objc private func templatesDidChange() {
        guard hasLoadedEditorPage else { return }
        applySlashTemplates()
    }

    private static func readerStyleCSS() -> String {
        EditorHTML.readerStyleCSS(documentFont: .current,
                                  readerLayout: .current,
                                  textAlignment: .current)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateObscuredContentInsets()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // The chrome (toolbar, accessories) is final here; layout passes
        // before it attaches see a smaller contentLayoutRect.
        updateObscuredContentInsets()
        observeWindowChrome()
    }

    /// The find bar overlay (permanent, toggled by isHidden) — like the
    /// it hangs below the titlebar over this editor.
    weak var findOverlay: NSView?

    /// Reapplies the page padding; the window controller calls this when
    /// the find overlay is shown or hidden.
    func chromeOverlaysDidChange() {
        updateObscuredContentInsets()
    }

    private var contentLayoutObservation: NSKeyValueObservation?

    /// Titlebar chrome can change without this view getting a layout pass —
    /// the native tab bar appears when another document joins the window's
    /// tab group — so the padding follows contentLayoutRect directly. The
    /// observation only reads state and reapplies the page padding: forcing
    /// layout from here re-enters the layout pass that changed the rect and
    /// breaks the edit-mode reveal machinery.
    private func observeWindowChrome() {
        guard let window = view.window else {
            contentLayoutObservation = nil
            return
        }
        guard contentLayoutObservation == nil else { return }
        contentLayoutObservation = window.observe(\.contentLayoutRect) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.updateObscuredContentInsets()
            }
        }
    }

    /// The whole obscured strip — titlebar, toolbar, tab bar, and visible
    /// bottom accessories. Floating formatting controls are excluded: their
    /// clearance is page padding, not an obscured strip or scrollbar inset.
    /// contentLayoutRect already excludes the titlebar chrome, so the gap
    /// alone is that chrome's height; adding accessory heights on top
    /// double-counted them and left a blank band below the formatting bar.
    private var fullChromeTopInset: CGFloat {
        guard let window = view.window, let contentView = window.contentView else {
            return view.safeAreaInsets.top
        }
        // Whether contentLayoutRect excludes a bottom accessory depends on
        // its scroll-edge style: .hard reserves layout, .automatic floats
        // over the content. Measure the real bottom edge of every visible
        // accessory instead of assuming either, so the buffer always lays
        // out below the lowest piece of chrome.
        var gap = contentView.bounds.height - window.contentLayoutRect.maxY
        if MainSplitViewController.usesNativeChromeAccessories {
            // See ContentViewController.fullChromeTopInset: the safe area
            // lags accessory changes by a layout pass, so measure the bars.
            gap += MainSplitViewController.nativeAccessoryHeight(findOverlay, in: window)
            return max(0, gap)
        }
        for accessory in window.titlebarAccessoryViewControllers
        where accessory.layoutAttribute == .bottom && !accessory.isHidden
            && accessory.view.window === window {
            let rect = contentView.convert(accessory.view.bounds, from: accessory.view)
            gap = max(gap, contentView.bounds.height - rect.minY)
        }
        // The formatting bar and find overlay are content-view chrome
        // hanging directly below the titlebar, so contentLayoutRect never
        // accounts for them. fittingSize instead of the frame: the frame is
        // unresolved between install and the next layout pass, and forcing
        // layout from here would re-enter the pass that called us. With a
        // visible tab bar the stack tucks up into the tab bar's margin
        // (MainSplitViewController.formattingBarTabBarOverlap), so that
        // amount comes back off once.
        var overlays: CGFloat = 0
        if let find = findOverlay, find.window === window, !find.isHidden {
            overlays += find.fittingSize.height
        }
        if overlays > 0 {
            gap += overlays
            gap -= MainSplitViewController.tabBarOverlap(for: window)
        }
        return max(0, gap)
    }

    /// On macOS 26 and later, page scrolling lets WebKit supply the native
    /// backdrop across the toolbar and visible chrome rows.
    private func updateObscuredContentInsets() {
        guard #available(macOS 26.0, *), view.window != nil else { return }
        let inset = fullChromeTopInset
        if webView.obscuredContentInsets.top != inset {
            webView.obscuredContentInsets = NSEdgeInsets(
                top: inset, left: 0, bottom: 0, right: 0
            )
        }
    }

    /// See ContentViewController.updateUnderPageBackgroundColor — set on
    /// theme and appearance changes only, never per layout pass.
    private func updateUnderPageBackgroundColor() {
        if #unavailable(macOS 26.0) {
            view.needsDisplay = true
        }
        guard #available(macOS 26.0, *) else { return }
        // WebKit snapshots the color in the setter. These explicit palette
        // and fallback colors must be reassigned when the appearance changes.
        let isDark = view.effectiveAppearance
            .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let scheme: ThemeColorScheme = isDark ? .dark : .light
        let colors = ThemeColorsSetting.current
        webView.underPageBackgroundColor = colors.color(.editorBackground, scheme)
            ?? colors.color(.windowBackground, scheme)
            ?? .clear
    }

    /// Current buffer contents, or nil if the editor isn't ready.
    func fetchMarkdown(_ completion: @escaping (String?) -> Void) {
        webView.evaluateJavaScript("window.__mdEditor ? window.__mdEditor.getMarkdown() : null") { value, _ in
            completion(value as? String)
        }
    }

    func markdown() async -> String? {
        await withCheckedContinuation { continuation in
            fetchMarkdown { continuation.resume(returning: $0) }
        }
    }

    /// Checks or unchecks a task as one undoable edit of its marker, for the
    /// Tasks sidebar. Completion gets the line used and the updated buffer,
    /// or nil when the editor isn't ready or the task can't be found.
    func setTaskChecked(line: Int, checked: Bool, text: String,
                        completion: @escaping ((line: Int, changed: Bool, markdown: String)?) -> Void) {
        let script = "window.__mdEditor ? window.__mdEditor.setTaskChecked(\(line), \(checked), \(EditorHTML.jsStringLiteral(text))) : null"
        webView.evaluateJavaScript(script) { value, _ in
            guard let result = value as? [String: Any],
                  let line = (result["line"] as? NSNumber)?.intValue,
                  let changed = result["changed"] as? Bool,
                  let markdown = result["markdown"] as? String else {
                completion(nil)
                return
            }
            completion((line, changed, markdown))
        }
    }

    func find(_ query: String,
              backwards: Bool = false,
              options: SearchOptions = SearchOptions(),
              completion: ((FindResult) -> Void)? = nil) {
        findCompletion = completion
        let script = "window.__mdEditor?.find(\(EditorHTML.jsStringLiteral(query)), \(backwards), \(options.javaScriptLiteral))"
        webView.evaluateJavaScript(script) { result, _ in
            completion?(FindResult(scriptResult: result) ?? .none)
        }
    }

    func fetchSelectedText(_ completion: @escaping (String?) -> Void) {
        webView.evaluateJavaScript("window.getSelection().toString()") { value, _ in
            completion(value as? String)
        }
    }

    /// Replaces the current match, then moves to the next. The completion gets
    /// the search state after the edit and how many matches were replaced.
    func replaceCurrent(_ replacement: String,
                        query: String,
                        options: SearchOptions,
                        completion: ((FindResult, Int) -> Void)? = nil) {
        runReplace("replaceCurrent", replacement, query: query, options: options, completion: completion)
    }

    /// Replaces every match in one undoable edit.
    func replaceAll(_ replacement: String,
                    query: String,
                    options: SearchOptions,
                    completion: ((FindResult, Int) -> Void)? = nil) {
        runReplace("replaceAll", replacement, query: query, options: options, completion: completion)
    }

    private func runReplace(_ function: String,
                            _ replacement: String,
                            query: String,
                            options: SearchOptions,
                            completion: ((FindResult, Int) -> Void)?) {
        let script = "window.__mdEditor?.\(function)(\(EditorHTML.jsStringLiteral(replacement)), \(EditorHTML.jsStringLiteral(query)), \(options.javaScriptLiteral))"
        webView.evaluateJavaScript(script) { result, _ in
            let replaced = ((result as? [String: Any])?["replaced"] as? NSNumber)?.intValue ?? 0
            completion?(FindResult(scriptResult: result) ?? .none, replaced)
        }
    }

    /// Focuses the editor. With `appendingEntry`, that text is added as a new
    /// block at the end of the document and the cursor is left after it.
    func focusEditor(appendingEntry entry: String? = nil) {
        view.window?.makeFirstResponder(webView)
        guard let entry else {
            webView.evaluateJavaScript("window.__mdEditor && window.__mdEditor.focus()") { _, _ in }
            return
        }
        // Keep one blank line between the previous content and the new entry.
        // `insertTextAt` focuses and leaves the cursor after the inserted text.
        let script = """
        (function () {
            const editor = window.__mdEditor
            if (!editor) return
            const markdown = editor.getMarkdown()
            const separator = markdown === '' || markdown.endsWith('\\n\\n') ? ''
                : markdown.endsWith('\\n') ? '\\n' : '\\n\\n'
            editor.insertTextAt(separator + \(EditorHTML.jsStringLiteral(entry)), markdown.length, markdown.length)
            // CodeMirror estimates the height of lines it hasn't drawn yet, so
            // the scroll height keeps changing as scrolling renders them. Keep
            // scrolling until it holds still for a few frames.
            const inner = document.querySelector('#editor .cm-scroller')
            if (!inner) return
            // In page-scrolling layouts the inner scroller has overflow: visible
            // and the document itself scrolls instead.
            const scroller = getComputedStyle(inner).overflowY === 'visible'
                ? (document.scrollingElement || document.documentElement) : inner
            let lastHeight = -1, stableFrames = 0, frames = 0
            const settle = () => {
                scroller.scrollTop = scroller.scrollHeight
                stableFrames = scroller.scrollHeight === lastHeight ? stableFrames + 1 : 0
                lastHeight = scroller.scrollHeight
                if (stableFrames < 4 && ++frames < 60) requestAnimationFrame(settle)
            }
            requestAnimationFrame(settle)
        })()
        """
        webView.evaluateJavaScript(script) { _, _ in }
    }

    /// Applies a normalized preview scroll position after CodeMirror has
    /// measured its own scrollable document. The JS promise resolves after a
    /// paint frame so the editor can be revealed at the final position.
    func applyScrollProgress(_ progress: CGFloat,
                             sourceAnchor: SourceScrollAnchor?,
                             completion: @escaping () -> Void) {
        let clamped = min(max(progress, 0), 1)
        let arguments: [String: Any] = [
            "progress": Double(clamped),
            "sourcePosition": sourceAnchor.map { Double($0.sourcePosition) } ?? NSNull(),
            "sourceGap": sourceAnchor.map { Double($0.topGap) } ?? 0,
        ]
        webView.callAsyncJavaScript(
            """
            if (!window.__mdEditor) return false;
            return await window.__mdEditor.setScrollPosition(progress, sourcePosition, sourceGap);
            """,
            arguments: arguments,
            in: nil,
            in: .page
        ) { _ in
            completion()
        }
    }

    /// Scrolls the source to the `index`th heading, as numbered by the outline.
    func scrollToHeading(index: Int) {
        fetchMarkdown { [weak self] markdown in
            guard let self, let markdown,
                  let line = MarkdownTOC.headingSourceLine(index, in: markdown) else { return }
            self.applyScrollProgress(
                0,
                sourceAnchor: SourceScrollAnchor(sourcePosition: CGFloat(line), topGap: 0)
            ) {}
        }
    }

    func fetchScrollAnchor(_ completion: @escaping (SourceScrollAnchor?) -> Void) {
        webView.evaluateJavaScript(
            "window.__mdEditor && window.__mdEditor.getScrollAnchor()"
        ) { [weak self] result, _ in
            completion(SourceScrollAnchor(scriptResult: result))
        }
    }

    /// Run a formatting command (bold, italic, h1, quote, …) on the
    /// current selection. Command names map to the bundle's exec() table.
    func exec(_ command: String) {
        let name = EditorHTML.jsStringLiteral(command)
        webView.evaluateJavaScript("window.__mdEditor && window.__mdEditor.exec(\(name))") { _, _ in }
    }

    func fetchHeadingLevel(_ completion: @escaping (Int) -> Void) {
        webView.evaluateJavaScript("window.__mdEditor && window.__mdEditor.getHeadingLevel()") { result, _ in
            completion(result as? Int ?? 0)
        }
    }

    func fetchListStyle(_ completion: @escaping (String) -> Void) {
        webView.evaluateJavaScript("window.__mdEditor && window.__mdEditor.getListStyle()") { result, _ in
            completion(result as? String ?? "none")
        }
    }

    func fetchBlockStyle(_ completion: @escaping (String) -> Void) {
        webView.evaluateJavaScript("window.__mdEditor && window.__mdEditor.getBlockStyle()") { result, _ in
            completion(result as? String ?? "none")
        }
    }

    func setBlockStyle(_ style: String, language: String) {
        webView.evaluateJavaScript("window.__mdEditor && window.__mdEditor.setBlockStyle(\(EditorHTML.jsStringLiteral(style)), \(EditorHTML.jsStringLiteral(language)))") { _, _ in }
    }

    func setListStyle(_ style: String) {
        webView.evaluateJavaScript("window.__mdEditor && window.__mdEditor.setListStyle(\(EditorHTML.jsStringLiteral(style)))") { _, _ in }
    }

    struct LinkSelection {
        let text: String
        let from: Int
        let to: Int
    }

    func fetchLinkSelection(_ completion: @escaping (LinkSelection?) -> Void) {
        webView.evaluateJavaScript("window.__mdEditor && window.__mdEditor.getLinkSelection(true)") { result, _ in
            guard let value = result as? [String: Any], let text = value["text"] as? String,
                  let from = value["from"] as? Int, let to = value["to"] as? Int else {
                completion(nil)
                return
            }
            completion(LinkSelection(text: text, from: from, to: to))
        }
    }

    func insertLink(text: String, url: String, from: Int, to: Int) {
        let script = "window.__mdEditor && window.__mdEditor.insertLinkFromPopover(\(EditorHTML.jsStringLiteral(text)), \(EditorHTML.jsStringLiteral(url)), \(from), \(to))"
        webView.evaluateJavaScript(script) { _, _ in }
    }

    /// The selection, and whether it starts at a line's start and ends at
    /// a line's end: where a block of lines can go without splitting one.
    func fetchLineInsertionPoint(_ completion: @escaping ((from: Int, to: Int,
                                                           atLineStart: Bool, atLineEnd: Bool)?) -> Void) {
        let script = """
        (() => {
            const editor = window.__mdEditor;
            const selection = editor && editor.getLinkSelection(false);
            if (!selection) return null;
            const markdown = editor.getMarkdown();
            return { from: selection.from, to: selection.to,
                     atLineStart: selection.from === 0 || markdown[selection.from - 1] === "\\n",
                     atLineEnd: selection.to === markdown.length || markdown[selection.to] === "\\n" };
        })()
        """
        webView.evaluateJavaScript(script) { result, _ in
            guard let value = result as? [String: Any], let from = value["from"] as? Int,
                  let to = value["to"] as? Int, let atLineStart = value["atLineStart"] as? Bool,
                  let atLineEnd = value["atLineEnd"] as? Bool else {
                completion(nil)
                return
            }
            completion((from, to, atLineStart, atLineEnd))
        }
    }

    func insertMarkdown(_ markdown: String,
                        from: Int,
                        to: Int,
                        completion: ((Bool) -> Void)? = nil) {
        let script = """
        (() => {
            if (!window.__mdEditor) return false;
            window.__mdEditor.insertTextAt(\(EditorHTML.jsStringLiteral(markdown)), \(from), \(to));
            return true;
        })()
        """
        webView.evaluateJavaScript(script) { result, error in
            completion?(error == nil && (result as? Bool) == true)
        }
    }

    /// Replaces the source after an image rename without rebuilding the page,
    /// preserving the editor's selection and scroll position.
    func replaceMarkdown(_ markdown: String) {
        let script = "window.__mdEditor && window.__mdEditor.replaceMarkdown(\(EditorHTML.jsStringLiteral(markdown)))"
        webView.evaluateJavaScript(script) { _, _ in }
    }

    fileprivate func handle(message: Any) {
        if let message = message as? String {
            switch message {
            case "dirty":
                hasChanges = true
                contentDidChange?()
            case "ready":
                hasLoadedEditorPage = true
                updateChromeZoom()
                // Fresh page — the bar padding lives in the DOM and must be
                // re-applied even when the tracked value hasn't changed,
                // and WebKit re-derives the under-page color from the new
                // page, clobbering the themed value.
                updateUnderPageBackgroundColor()
                updateObscuredContentInsets()
                applySlashTemplates()
                applyWorkspaceCandidates()
                applyMetadataLinksEnabled()
                applyMoveBlocksEnabled()
                applyCarryOverEnabled()
                editorDidBecomeReady?()
            case "cancel":
                cancelRequested?()
            case let error where error.hasPrefix("error:"):
                NSLog("Markdown editor JavaScript error: %@", error)
            default:
                break
            }
            return
        }

        guard let payload = message as? [String: Any],
              let kind = payload["kind"] as? String else { return }
        switch kind {
        case "copyCode":
            guard let text = payload["value"] as? String else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        case "formattingState":
            guard let heading = payload["heading"] as? Int,
                  (0...6).contains(heading),
                  let commands = payload["commands"] as? [String] else { return }
            formattingDidChange?(heading, Set(commands))
        case "findResult":
            guard let result = FindResult(scriptResult: payload) else { return }
            findCompletion?(result)
        case "pasteImage":
            guard let from = payload["from"] as? NSNumber,
                  let to = payload["to"] as? NSNumber else { return }
            pasteImageRequested?(from.intValue, to.intValue)
        case "pickImage":
            guard let from = payload["from"] as? NSNumber,
                  let to = payload["to"] as? NSNumber else { return }
            pickImageRequested?(from.intValue, to.intValue)
        case "pickLink":
            guard let from = payload["from"] as? NSNumber,
                  let to = payload["to"] as? NSNumber else { return }
            pickLinkRequested?(from.intValue, to.intValue)
        case "insertCarryOver":
            insertCarryOverRequested?()
        case "pickMoveTarget":
            guard let id = payload["id"] as? Int,
                  let kind = (payload["blockKind"] as? String).flatMap(MarkdownSectionInsertion.BlockKind.init),
                  let text = payload["text"] as? String,
                  let firstLine = payload["firstLine"] as? Int,
                  let lastLine = payload["lastLine"] as? Int else { return }
            pickMoveTargetRequested?(MoveRequest(id: id, kind: kind, text: text,
                                                 firstLine: firstLine, lastLine: lastLine))
        case "moveStale":
            guard let id = payload["id"] as? Int else { return }
            moveBecameStale?(id)
        case "openLink":
            if let token = payload["token"] as? String {
                linkActivated?(.metadata(token))
            } else if let destination = payload["destination"] as? String, !destination.isEmpty {
                linkActivated?(.destination(destination))
            }
        case "runQueries":
            guard let queries = payload["queries"] as? [[String: Any]] else { return }
            queryBlocksRequested?(queries.compactMap(QueryBlockRequest.init(message:)))
        case "openQueryResult":
            guard let path = payload["path"] as? String, let line = payload["line"] as? Int, line > 0 else { return }
            queryResultOpened?(path, line)
        case "queryTaskCheckbox":
            guard let path = payload["path"] as? String, let line = payload["line"] as? Int, line > 0,
                  let checked = payload["checked"] as? Bool else { return }
            queryTaskToggled?(path, line, checked)
        case "imageClick":
            guard let source = payload["src"] as? String,
                  let url = URL(string: source),
                  let fileURL = MarkdownAssetResolution.fileURL(for: url) else { return }
            imageClicked?(fileURL)
        default:
            break
        }
    }

    // MARK: - Page assembly

    private static func vendorResource(_ name: String, ext: String, subdir: String) -> String? {
        // Synced-folder resources are copied flat into Resources/, so try
        // the subdirectory first and fall back to the bundle root — same
        // lookup MarkdownHTML uses for its vendor files.
        let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdir)
            ?? Bundle.main.url(forResource: name, withExtension: ext)
        return url.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }

    private static let editorJavaScript =
        vendorResource("mdedit.min", ext: "js", subdir: "Vendor/CodeMirror") ?? ""

    private static func editorHTML(markdown: String,
                                   includesMermaid: Bool,
                                   assetBaseURL: URL?,
                                   textScale: CGFloat,
                                   codeLanguage: String?) -> String {
        // Baked into the base stylesheet, not only the override element:
        // WebKit derives the obscured-inset fill from the base stylesheet's
        // html/body background, so a theme color only present in the later
        // override <style> leaves the toolbar strip on stock Canvas (dark
        // #1e1e1e) in edit mode.
        let colors = ThemeColorsSetting.current
        func pageBackground(_ scheme: ThemeColorScheme) -> String {
            let hex = colors.hexValue(.editorBackground, scheme)
                ?? colors.hexValue(.windowBackground, scheme)
            return MarkdownHTML.ThemeOverrides.sanitizedHexColor(hex) ?? "transparent"
        }
        let lightPageBackground = pageBackground(.light)
        let darkPageBackground = pageBackground(.dark)
        let usesPageScrolling: Bool
        if #available(macOS 26.0, *) {
            usesPageScrolling = true
        } else {
            usesPageScrolling = false
        }
        return EditorHTML.render(
            markdown: markdown,
            editorJavaScript: editorJavaScript,
            includesMermaid: includesMermaid,
            assetBaseURL: assetBaseURL,
            configuration: .init(
                fullWidth: ContentWidthSetting.current.columnWidth == nil,
                columnWidth: ContentWidthSetting.current.columnWidth ?? MarkdownHTML.contentColumnWidth,
                textScale: textScale,
                lightPageBackground: lightPageBackground,
                darkPageBackground: darkPageBackground,
                themeOverrideCSS: colors.editorOverrideCSS,
                readerStyleCSS: readerStyleCSS(),
                usesPageScrolling: usesPageScrolling,
                codeLanguage: codeLanguage,
                bridgeName: EditorBridge.name,
                extensionState: MarkdownHTML.editorExtensionState(
                    configuration: RenderExtensionPreferences.currentConfiguration
                ),
                extensionCSS: MarkdownHTML.editorExtensionCSS(),
                extensionOptions: MarkdownHTML.editorExtensionOptions()
            )
        )
    }
}

private final class EditorBridge: NSObject, WKScriptMessageHandler {
    static let name = "mdEditorHost"
    weak var owner: EditorViewController?

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == EditorBridge.name else { return }
        owner?.handle(message: message.body)
    }
}

private final class LegacyEditorBackgroundView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let scheme: ThemeColorScheme = isDark ? .dark : .light
        let colors = ThemeColorsSetting.current
        let background = colors.color(.editorBackground, scheme)
            ?? colors.color(.windowBackground, scheme)
            ?? (isDark ? nil : NSColor.white)
        layer?.backgroundColor = background?.cgColor
    }
}

private final class EditorWKWebView: WKWebView {
    var appearanceDidChange: (() -> Void)?

    /// The Files sidebar's own drag type (see ProjectNavigatorView), which
    /// WebKit doesn't know: its files are taken here and inserted the way
    /// pasted files are, instead of being ignored.
    static let projectFileDragType = NSPasteboard.PasteboardType("doc.daisy.project-navigator.urls")
    /// Whether a file from the sidebar can be dropped now.
    var acceptsProjectFiles: () -> Bool = { false }
    /// The point in page coordinates as the drag moves, nil once it ends.
    var projectFileDragMoved: ((CGPoint?) -> Void)?
    var projectFilesDropped: (([URL], CGPoint) -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        appearanceDidChange?()
    }

    // WebKit registers its own types, again on later loads too; ours stays.
    override func registerForDraggedTypes(_ newTypes: [NSPasteboard.PasteboardType]) {
        super.registerForDraggedTypes(newTypes.contains(Self.projectFileDragType)
            ? newTypes : newTypes + [Self.projectFileDragType])
    }

    /// Regular files only, like a paste: a folder is never dropped.
    private func projectFiles(_ info: NSDraggingInfo) -> [URL]? {
        guard let paths = info.draggingPasteboard.propertyList(forType: Self.projectFileDragType) as? [String]
        else { return nil }
        return paths.map { URL(fileURLWithPath: $0).standardizedFileURL }
    }

    private func acceptsDrop(of files: [URL]) -> Bool {
        acceptsProjectFiles() && !files.isEmpty && files.allSatisfy {
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
        }
    }

    /// The drag's location in CSS pixels from the page's top left.
    private func pagePoint(_ info: NSDraggingInfo) -> CGPoint {
        var point = convert(info.draggingLocation, from: nil)
        if !isFlipped { point.y = bounds.height - point.y }
        let zoom = max(pageZoom * magnification, 0.001)
        return CGPoint(x: point.x / zoom, y: point.y / zoom)
    }

    private func projectFileDrag(_ info: NSDraggingInfo, files: [URL]) -> NSDragOperation {
        guard acceptsDrop(of: files) else { return [] }
        projectFileDragMoved?(pagePoint(info))
        return .copy
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let files = projectFiles(sender) else { return super.draggingEntered(sender) }
        return projectFileDrag(sender, files: files)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let files = projectFiles(sender) else { return super.draggingUpdated(sender) }
        return projectFileDrag(sender, files: files)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        guard let sender, projectFiles(sender) != nil else { return super.draggingExited(sender) }
        projectFileDragMoved?(nil)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let files = projectFiles(sender) else { return super.prepareForDragOperation(sender) }
        return acceptsDrop(of: files)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let files = projectFiles(sender) else { return super.performDragOperation(sender) }
        guard acceptsDrop(of: files) else { return false }
        projectFilesDropped?(files, pagePoint(sender))
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        guard let sender, projectFiles(sender) != nil else { return super.concludeDragOperation(sender) }
    }

    // Left clicks in the transparent titlebar strip stay native (window
    // drag) instead of being consumed by WebKit — see ChromeStripClickThrough.
    override func hitTest(_ point: NSPoint) -> NSView? {
        if declinesChromeStripClick(at: point) { return nil }
        return super.hitTest(point)
    }
}
