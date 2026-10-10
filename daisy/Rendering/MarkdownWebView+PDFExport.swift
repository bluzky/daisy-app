//
//  MarkdownWebView+PDFExport.swift
//  daisy
//
//  Printing and document export. App-only: the Quick Look extension compiles
//  MarkdownWebView.swift but not this file.
//

import Cocoa
import PDFKit
import os
import UniformTypeIdentifiers
import WebKit

private let printSizeStyleElementID = "md-print-size"
private let previewPrintStyleElementID = "daisy-print-style"

private extension UTType {
    static let wordDocument = UTType(
        importedAs: "org.openxmlformats.wordprocessingml.document",
        conformingTo: .data)
}

private enum AccessoryRowMetrics {
    static let height: CGFloat = 30
    static let spacing: CGFloat = 8
    static let horizontalInset: CGFloat = 16
}

/// `Theme: [ GitHub ]` — the look of a Word export, shown in the Export as
/// Word… save panel.
private final class ExportThemeRowView: NSView {
    var onChange: ((DocxTheme) -> Void)?
    private(set) var selectedTheme: DocxTheme

    private let themes: [DocxTheme]
    private let popup = NSPopUpButton()

    var isEnabled: Bool {
        get { popup.isEnabled }
        set { popup.isEnabled = newValue }
    }

    init(width: CGFloat, themes: [DocxTheme], selectedID: String) {
        self.themes = themes
        selectedTheme = themes.first { $0.id == selectedID } ?? themes[0]
        super.init(frame: NSRect(x: 0, y: 0,
                                 width: width, height: AccessoryRowMetrics.height))
        autoresizingMask = [.width]

        let label = NSTextField(labelWithString: NSLocalizedString(
            "Theme:", comment: "Word export theme field label"))
        popup.addItems(withTitles: themes.map(DocxThemeStore.displayName))
        popup.selectItem(at: themes.firstIndex { $0.id == selectedTheme.id } ?? 0)
        popup.target = self
        popup.action = #selector(themeChanged(_:))

        let spacer = NSView()
        spacer.setContentHuggingPriority(
            NSLayoutConstraint.Priority(1), for: .horizontal)

        let stack = NSStackView(views: [label, spacer, popup])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: AccessoryRowMetrics.height),
            popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 190),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: AccessoryRowMetrics.horizontalInset),
            stack.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -AccessoryRowMetrics.horizontalInset),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func themeChanged(_ sender: NSPopUpButton) {
        guard themes.indices.contains(sender.indexOfSelectedItem) else { return }
        selectedTheme = themes[sender.indexOfSelectedItem]
        onChange?(selectedTheme)
    }
}

/// Printed body size, persisted so the panel reopens with the last choice.
private enum PrintSizeOptions {
    private static let defaultsKey = "PrintBodyPointSize"
    static let minimumPointSize = 6
    static let maximumPointSize = 48

    static var pointSize: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: defaultsKey)
            guard stored != 0 else {
                return clamped(MarkdownHTML.defaultPrintPointSize)
            }
            return clamped(stored)
        }
        set { UserDefaults.standard.set(clamped(newValue), forKey: defaultsKey) }
    }

    static func clamped(_ points: Int) -> Int {
        min(max(points, minimumPointSize), maximumPointSize)
    }

    static func localizedLabel(for points: Int) -> String {
        String(
            format: NSLocalizedString("%d pt", comment: "Print font size, in points"),
            points
        )
    }
}

/// `Font Size: … [ 12 pt ] ⇅` — an editable field paired with a stepper, the
/// same pairing the print panel's own Copies field uses.
private final class PrintSizeRowView: NSView {
    /// Called with the committed, clamped size. Persistence already happened.
    var onChange: ((Int) -> Void)?

    private var pointSize: Int
    private let sizeField = NSTextField()
    private let stepper = NSStepper()

    init(width: CGFloat) {
        pointSize = PrintSizeOptions.pointSize
        super.init(frame: NSRect(x: 0, y: 0,
                                 width: width, height: AccessoryRowMetrics.height))
        autoresizingMask = [.width]

        let caption = NSTextField(labelWithString: NSLocalizedString(
            "Font Size:", comment: "Print font size field label"))

        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.allowsFloats = false
        let pointUnit = NSLocalizedString(
            "pt", comment: "Abbreviation for typographic points")
        formatter.positiveSuffix = " \(pointUnit)"
        // Keep direct numeric entry convenient: both `13` and `13 pt` commit
        // to the same value, while the resting presentation always shows `pt`.
        formatter.isLenient = true

        sizeField.formatter = formatter
        sizeField.alignment = .right
        sizeField.integerValue = pointSize
        sizeField.target = self
        sizeField.action = #selector(sizeFieldChanged(_:))
        // Commit on Return *and* on focus loss, so a typed value isn't lost by
        // clicking straight into the surrounding panel's controls.
        sizeField.cell?.sendsActionOnEndEditing = true

        stepper.minValue = Double(PrintSizeOptions.minimumPointSize)
        stepper.maxValue = Double(PrintSizeOptions.maximumPointSize)
        stepper.increment = 1
        stepper.valueWraps = false
        stepper.integerValue = pointSize
        stepper.target = self
        stepper.action = #selector(stepperChanged(_:))

        // A low-hugging spacer pushes the controls to the far edge, matching
        // the print panel's other accessory rows.
        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)

        let stack = NSStackView(views: [caption, spacer, sizeField, stepper])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.distribution = .fill
        stack.setCustomSpacing(8, after: caption)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: AccessoryRowMetrics.height),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            sizeField.widthAnchor.constraint(equalToConstant: 74),
            stack.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: AccessoryRowMetrics.horizontalInset),
            stack.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -AccessoryRowMetrics.horizontalInset),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func sizeFieldChanged(_ sender: NSTextField) {
        commit(sender.integerValue)
    }

    @objc private func stepperChanged(_ sender: NSStepper) {
        commit(sender.integerValue)
    }

    private func commit(_ requested: Int) {
        let size = PrintSizeOptions.clamped(requested)
        // Echo the clamp back so the field never shows an out-of-range value,
        // and keep the two controls in step.
        sizeField.integerValue = size
        stepper.integerValue = size
        guard size != pointSize else { return }
        pointSize = size
        PrintSizeOptions.pointSize = size
        onChange?(size)
    }
}

/// Adds a "Daisy" pane to the system print panel holding the font
/// size control, so the panel's own page thumbnails act as the preview.
private final class PrintSizeAccessoryController: NSViewController, NSPrintPanelAccessorizing {
    /// Applies a size to the document, calling back once the page has actually
    /// taken the change.
    var applySize: ((Int, @escaping () -> Void) -> Void)?

    /// AppKit repaginates the preview when this changes. It is bumped *after*
    /// the stylesheet injection completes rather than when the field changes,
    /// so the repagination never races ahead of the CSS it is meant to show.
    @objc private dynamic var previewRevision = 0

    private var pointSize = PrintSizeOptions.pointSize

    init() {
        super.init(nibName: nil, bundle: nil)
        title = NSLocalizedString("Daisy",
                                  comment: "Print panel accessory pane title")
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        var rows: [NSView] = []
        let sizeRow = PrintSizeRowView(width: 620)
        sizeRow.onChange = { [weak self] size in
            guard let self else { return }
            self.willChangeValue(forKey: "localizedSummaryItems")
            self.pointSize = size
            self.didChangeValue(forKey: "localizedSummaryItems")
            self.applySize?(size) { [weak self] in
                self?.previewRevision += 1
            }
        }
        rows.append(sizeRow)

        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = AccessoryRowMetrics.spacing
        stack.translatesAutoresizingMaskIntoConstraints = false

        let rowCount = CGFloat(rows.count)
        let height = rowCount * AccessoryRowMetrics.height
            + max(0, rowCount - 1) * AccessoryRowMetrics.spacing
        let container = NSView(
            frame: NSRect(x: 0, y: 0, width: 620, height: height))
        container.addSubview(stack)
        var constraints = [
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ]
        constraints.append(contentsOf: rows.map {
            $0.widthAnchor.constraint(equalTo: container.widthAnchor)
        })
        NSLayoutConstraint.activate(constraints)

        view = container
        preferredContentSize = container.frame.size
    }

    // MARK: NSPrintPanelAccessorizing

    func localizedSummaryItems() -> [[NSPrintPanel.AccessorySummaryKey: String]] {
        [[
            .itemName: NSLocalizedString(
                "Font Size", comment: "Print panel summary item name"),
            .itemDescription: PrintSizeOptions.localizedLabel(for: pointSize),
        ]]
    }

    func keyPathsForValuesAffectingPreview() -> Set<String> {
        ["previewRevision"]
    }
}

/// A print panel adapted for PDF export.
///
/// AppKit publicly supports changing the default button title, but it has no
/// option for hiding the printer/preset section. On current macOS that section
/// is exposed by `PMPrintPanelController` as `printersSectionStackView`; look it
/// up dynamically and guard every lookup so a future AppKit change cannot
/// crash the app.
///
/// The controller also owns the PDF-services action that the panel's “Save as
/// PDF” menu item uses. Pointing the relabelled default button at that same
/// action gives it the exact native save behaviour without pre-setting a save
/// disposition (which would make `NSPrintOperation` skip this panel).
private final class ExportPrintPanel: NSPrintPanel {
    private weak var parentWindow: NSWindow?
    private weak var printSheetWindow: NSWindow?
    private weak var printSheetController: NSWindowController?
    private var isObservingPrintSheet = false
    private var didRemoveTopPocket = false

    override func beginSheet(
        using printInfo: NSPrintInfo,
        on parentWindow: NSWindow,
        completionHandler handler: ((NSPrintPanel.Result) -> Void)? = nil
    ) {
        self.parentWindow = parentWindow
        didRemoveTopPocket = false
        observePrintSheet()

        super.beginSheet(using: printInfo, on: parentWindow) { [weak self] result in
            self?.stopObservingPrintSheet()
            handler?(result)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func observePrintSheet() {
        guard !isObservingPrintSheet else { return }
        isObservingPrintSheet = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(printSheetDidUpdate(_:)),
            name: NSWindow.didUpdateNotification,
            object: nil
        )
    }

    private func stopObservingPrintSheet() {
        guard isObservingPrintSheet else { return }
        NotificationCenter.default.removeObserver(self)
        parentWindow = nil
        printSheetWindow = nil
        printSheetController = nil
        didRemoveTopPocket = false
        isObservingPrintSheet = false
    }

    @objc private func printSheetDidUpdate(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.isSheet,
              window.sheetParent === parentWindow,
              let controller = window.windowController,
              NSStringFromClass(type(of: controller))
                == "PMPrintPanelController"
        else { return }

        printSheetWindow = window
        printSheetController = controller

        // PrintingUI posts its first update synchronously while the sheet is
        // still invisible and unordered, but after windowDidLoad has installed
        // all controls and scroll pockets. Discover and transform the sheet at
        // that point so Printer/Presets never reach a composited frame.
        // PrintingUI revalidates its default button whenever print settings or
        // pagination change. With no selected printer that pass disables the
        // button, even though file export needs no printer. Reapply the native
        // PDF-services target after every sheet update for the sheet's entire
        // lifetime, rather than only when it first appears.
        configure(controller: controller)
    }

    private func configure(controller: NSWindowController) {
        if let scrollView = privateObject(
            named: "printOptionsScrollView", on: controller) as? NSScrollView {
            removeTopPocketIfNeeded(from: scrollView, controller: controller)
        }
        configureSaveButton(on: controller)
    }

    private func removeTopPocketIfNeeded(
        from scrollView: NSScrollView,
        controller: NSWindowController
    ) {
        guard !didRemoveTopPocket,
              let printerSection = privateObject(
                named: "printersSectionStackView", on: controller) as? NSView
        else { return }

        let collapsedTopInset = max(
            0,
            scrollView.additionalSafeAreaInsets.top
                - printerSection.frame.height
        )

        // PrintingUI separately registers this private view as the top
        // `NSScrollView` pocket. Edge 1 is the button pocket and must remain
        // intact for Save/Cancel.
        guard destroyTopScrollPocket(
            registeredFor: printerSection,
            from: scrollView,
            observer: controller
        ) else { return }

        let container = printerSection.superview
        printerSection.removeFromSuperview()
        container?.needsLayout = true
        container?.layoutSubtreeIfNeeded()

        var optionsInsets = scrollView.additionalSafeAreaInsets
        optionsInsets.top = collapsedTopInset
        scrollView.additionalSafeAreaInsets = optionsInsets
        scrollView.tile()
        scrollView.layoutSubtreeIfNeeded()
        didRemoveTopPocket = true
    }

    private func configureSaveButton(on controller: NSWindowController) {
        guard let saveButton = privateObject(
            named: "printButton", on: controller) as? NSButton
        else { return }

        saveButton.title = NSLocalizedString(
            "Save", comment: "Export button title")
        // Fail closed if a future PrintingUI version removes the private
        // PDF service rather than leaving a stale action attached.
        saveButton.target = nil
        saveButton.action = nil
        saveButton.isEnabled = false
        guard let pdfServicesController = privateObject(
            named: "pdfServicesController", on: controller)
        else { return }
        let saveAction = NSSelectorFromString("doSaveAsPDF:")
        guard pdfServicesController.responds(to: saveAction) else { return }

        // Use the same private action as the panel's native “Save as PDF”
        // item. It opens Apple's NSSavePanel, updates the print
        // disposition/URL, and lets NSPrintOperation render the selected
        // pages to that file.
        saveButton.target = pdfServicesController
        saveButton.action = saveAction
        saveButton.isEnabled = true
    }

    private func destroyTopScrollPocket(
        registeredFor printerSection: NSView,
        from scrollView: NSScrollView,
        observer: AnyObject
    ) -> Bool {
        let topEdge = 0
        let unregisterSelector = NSSelectorFromString(
            "unregisterPocketContainer:onEdge:"
        )
        let destroySelector = NSSelectorFromString("_destroyPocketForEdge:")
        let pocketSelector = NSSelectorFromString(
            "_pocketForEdge:makeIfNeeded:"
        )
        guard scrollView.responds(to: unregisterSelector),
              scrollView.responds(to: destroySelector),
              scrollView.responds(to: pocketSelector)
        else { return false }

        typealias GetPocketMethod = @convention(c) (
            AnyObject,
            Selector,
            Int,
            Bool
        ) -> Unmanaged<AnyObject>?

        let pocketImplementation = scrollView.method(for: pocketSelector)
        let getPocket = unsafeBitCast(
            pocketImplementation,
            to: GetPocketMethod.self
        )
        guard let topScrollPocket = getPocket(
            scrollView,
            pocketSelector,
            topEdge,
            false
        )?.takeUnretainedValue() as? NSView
        else { return false }

        typealias UnregisterPocketMethod = @convention(c) (
            AnyObject,
            Selector,
            AnyObject,
            Int
        ) -> Void

        // PrintingUI observes the registered section to recompute the pocket
        // inset. Stop that exact observation before detaching the section.
        NotificationCenter.default.removeObserver(
            observer,
            name: NSView.frameDidChangeNotification,
            object: printerSection
        )

        let unregisterImplementation = scrollView.method(
            for: unregisterSelector
        )
        let unregister = unsafeBitCast(
            unregisterImplementation,
            to: UnregisterPocketMethod.self
        )
        unregister(
            scrollView,
            unregisterSelector,
            printerSection,
            topEdge
        )

        typealias DestroyPocketMethod = @convention(c) (
            AnyObject,
            Selector,
            Int
        ) -> Void

        let destroyImplementation = scrollView.method(for: destroySelector)
        let destroy = unsafeBitCast(
            destroyImplementation,
            to: DestroyPocketMethod.self
        )
        destroy(scrollView, destroySelector, topEdge)

        // `_destroyPocketForEdge:` clears AppKit's bookkeeping but currently
        // leaves the NSScrollPocket view (and its hard blur backdrop) attached
        // to the scroll view. Detach that exact retained edge-0 view too.
        topScrollPocket.removeFromSuperview()
        return true
    }

    private func privateObject(
        named getterName: String,
        on object: AnyObject
    ) -> AnyObject? {
        let getter = NSSelectorFromString(getterName)
        guard object.responds(to: getter),
              let result = object.perform(getter)
        else { return nil }
        return result.takeUnretainedValue()
    }
}

extension MarkdownWebView {
    /// Builds a print operation for the rendered document.
    ///
    /// `NSPrintOperation.run()` must never be used with a WKWebView: WebKit
    /// computes pagination asynchronously, so the synchronous path never learns
    /// the page count and can emit pages without bound. Only `runModal` is safe.
    private func makePrintOperation(jobTitle: String) -> NSPrintOperation {
        let printInfo = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo()
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = false

        let operation = webView.printOperation(with: printInfo)
        operation.jobTitle = jobTitle
        // WKWebView's print view needs an explicit frame, otherwise AppKit
        // asserts when the operation tries to lay out at zero size.
        operation.view?.frame = webView.bounds
        return operation
    }

    private func configuredPrintOperation(
        from window: NSWindow,
        panel: ExportPrintPanel? = nil
    ) -> NSPrintOperation {
        // The PDF save panel seeds its filename from the job title, so a window
        // titled "notes.md" would otherwise produce "notes.md.pdf".
        let operation = makePrintOperation(
            jobTitle: (window.title as NSString).deletingPathExtension)
        if let panel {
            operation.printPanel = panel
        }

        // Export renders the live preview, so there is no print size to pick.
        if panel == nil {
            let accessory = PrintSizeAccessoryController()
            accessory.applySize = { [weak self] size, done in
                self?.applyPrintPointSize(size, completion: done)
            }
            operation.printPanel.addAccessoryController(accessory)
        }
        operation.printPanel.options.insert(.showsPreview)
        return operation
    }

    /// Mermaid theme for paper printing. Diagrams bake their colors into the
    /// SVG at render time, so the forced-light print stylesheet needs figures
    /// re-rendered with mermaid's light theme.
    private static let paperPrintMermaidTheme = "default"

    private func runPrintOperation(
        _ operation: NSPrintOperation,
        from window: NSWindow,
        matchesPreview: Bool = false
    ) {
        // Export keeps the live read-only stylesheet intact. Regular Print
        // retains its paper-oriented size and pagination controls, forces the
        // light palette, and restores the on-screen theme when the panel ends.
        if matchesPreview {
            renderAllMermaidDiagrams {
                self.applyPreviewPrintMode {
                    operation.runModal(
                        for: window,
                        delegate: nil,
                        didRun: nil,
                        contextInfo: nil
                    )
                }
            }
        } else {
            renderAllMermaidDiagrams(forcedTheme: Self.paperPrintMermaidTheme) {
                self.applyPaperPrintMode {
                    self.applyPrintPointSize(PrintSizeOptions.pointSize) {
                        operation.runModal(
                            for: window,
                            delegate: self,
                            didRun: #selector(Self.paperPrintOperationDidRun(_:success:contextInfo:)),
                            contextInfo: nil
                        )
                    }
                }
            }
        }
    }

    @objc private func paperPrintOperationDidRun(
        _ operation: NSPrintOperation,
        success: Bool,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        renderAllMermaidDiagrams {}
    }

    /// Mermaid renders lazily as figures scroll into view, but pagination
    /// captures the whole document at once — a diagram that never got near
    /// the viewport would print as its raw source text. `forcedTheme` pins the
    /// mermaid theme (re-rendering mismatched figures); calling again without
    /// one restores the on-screen theme.
    private func renderAllMermaidDiagrams(
        forcedTheme: String? = nil,
        completion: @escaping () -> Void
    ) {
        let themeArgument = forcedTheme.map { "'\($0)'" } ?? ""
        let script = """
        if (window.MdPreview && typeof window.MdPreview.mermaidRenderAll === 'function') {
            await window.MdPreview.mermaidRenderAll(\(themeArgument));
        }
        """
        webView.callAsyncJavaScript(script, in: nil, in: .page) { result in
            if case .failure(let error) = result {
                Logger.perf.debug(
                    "mermaid print pre-render failed: \(error.localizedDescription, privacy: .public)"
                )
            }
            completion()
        }
    }

    /// Marks the live page so its paper-only CSS does not replace the
    /// read-only typography, width, spacing, wrapping, or active palette.
    /// WebKit still paginates it, but the pixels sent into that pagination are
    /// the same ones the preview renderer owns.
    private func applyPreviewPrintMode(completion: (() -> Void)? = nil) {
        let script = """
        (() => {
            document.documentElement.classList.add(
                '\(MarkdownHTML.previewPrintClass)'
            );
            document.getElementById('\(printSizeStyleElementID)')?.remove();
            let style = document.getElementById('\(previewPrintStyleElementID)');
            if (!style) {
                style = document.createElement('style');
                style.id = '\(previewPrintStyleElementID)';
                document.head.appendChild(style);
            }
            style.textContent = \(Self.javaScriptStringLiteral(
                MarkdownHTML.previewPrintOverrideCSS
            ));
            return true;
        })()
        """
        evaluatePrintSetupScript(script, label: "preview print mode", completion: completion)
    }

    private func applyPaperPrintMode(completion: (() -> Void)? = nil) {
        let script = """
        (() => {
            document.documentElement.classList.remove(
                '\(MarkdownHTML.previewPrintClass)'
            );
            document.getElementById('\(previewPrintStyleElementID)')?.remove();
            return true;
        })()
        """
        evaluatePrintSetupScript(script, label: "paper print mode", completion: completion)
    }

    private func evaluatePrintSetupScript(
        _ script: String,
        label: String,
        completion: (() -> Void)?
    ) {
        webView.evaluateJavaScript(script) { _, error in
            if let error {
                Logger.perf.debug(
                    "\(label, privacy: .public) setup failed: \(error.localizedDescription, privacy: .public)"
                )
            }
            completion?()
        }
    }

    private nonisolated static func javaScriptStringLiteral(_ value: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [value])
        let array = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        return String(array.dropFirst().dropLast())
    }

    /// Sets the printed body size by injecting a print-only rule into the
    /// already-rendered page. Updating one stable element keeps repeated
    /// changes idempotent and leaves the on-screen document untouched.
    private func applyPrintPointSize(
        _ requestedPoints: Int,
        completion: (() -> Void)? = nil
    ) {
        let points = PrintSizeOptions.clamped(requestedPoints)
        let script = """
        (() => {
            const id = '\(printSizeStyleElementID)';
            let style = document.getElementById(id);
            if (!style) {
                style = document.createElement('style');
                style.id = id;
                document.head.appendChild(style);
            }
            style.textContent =
                '@media print { body { font-size: \(points)pt !important; } }';
            return true;
        })()
        """
        webView.evaluateJavaScript(script) { _, error in
            if let error {
                Logger.perf.debug(
                    "print size injection failed: \(error.localizedDescription, privacy: .public)"
                )
            }
            completion?()
        }
    }

    /// File ▸ Export ▸ PDF… — the print panel's preview and page controls,
    /// with its button relabelled to save straight to a PDF.
    func exportPDF(from window: NSWindow) {
        let operation = configuredPrintOperation(
            from: window, panel: ExportPrintPanel())
        prepareForPanelDrivenExport(operation)
        runPrintOperation(operation, from: window, matchesPreview: true)
    }

    /// File ▸ Export ▸ HTML…
    func exportHTML(
        markdown: String,
        sourceURL: URL?,
        assetBaseURL: URL?,
        from window: NSWindow
    ) {
        presentExportSavePanel(
            title: NSLocalizedString(
                "Export as HTML", comment: "HTML export panel title"),
            contentType: .html, sourceURL: sourceURL,
            assetBaseURL: assetBaseURL, accessoryView: nil, from: window
        ) { url, done in
            do {
                let html = MarkdownHTML.makeHTML(
                    from: markdown,
                    allowsScroll: true,
                    assetBaseHref: assetBaseURL?.absoluteString,
                    vendorLoading: .inline
                )
                try html.write(to: url, atomically: true, encoding: .utf8)
                done(nil)
            } catch {
                done(error)
            }
        }
    }

    /// File ▸ Export ▸ PNG…
    func exportPNG(
        sourceURL: URL?,
        assetBaseURL: URL?,
        from window: NSWindow
    ) {
        presentExportSavePanel(
            title: NSLocalizedString(
                "Export as PNG", comment: "PNG export panel title"),
            contentType: .png, sourceURL: sourceURL,
            assetBaseURL: assetBaseURL, accessoryView: nil, from: window
        ) { [weak self] url, done in
            self?.writePNG(to: url, completion: done)
        }
    }

    /// File ▸ Export ▸ Word… — a save panel with a theme popup. The .docx is
    /// built from the Markdown, not the rendered page; Mermaid diagrams are
    /// drawn offscreen first and embedded as pictures.
    func exportWord(
        markdown: String,
        sourceURL: URL?,
        assetBaseURL: URL?,
        from window: NSWindow
    ) {
        DocxThemeStore.ensureUserDirectory()
        let themeRow = ExportThemeRowView(
            width: 320,
            themes: DocxThemeStore.themes(),
            selectedID: DocxThemeStore.selectedID
        )
        themeRow.onChange = { DocxThemeStore.selectedID = $0.id }

        presentExportSavePanel(
            title: NSLocalizedString(
                "Export as Word", comment: "Word export panel title"),
            contentType: .wordDocument, sourceURL: sourceURL,
            assetBaseURL: assetBaseURL, accessoryView: themeRow, from: window
        ) { url, done in
            let theme = themeRow.selectedTheme
            // Diagrams follow the Mermaid switch in Settings ▸ Extensions;
            // switched off, they export as code like any other fence.
            let mermaidEnabled = RenderExtensionPreferences.currentConfiguration
                .isEnabled("mermaid")
            Task { @MainActor in
                let diagrams = mermaidEnabled
                    ? await MermaidRasterizer.render(DocxExporter.mermaidSources(in: markdown))
                    : [:]
                do {
                    try DocxExporter.write(
                        markdown: markdown, assetBaseURL: assetBaseURL,
                        theme: theme, mermaidDiagrams: diagrams, to: url)
                    done(nil)
                } catch {
                    done(error)
                }
            }
        }
    }

    /// Shared save sheet for the formats we write ourselves. `write` reports
    /// `nil` on success; a failure is shown as an alert on the document window.
    private func presentExportSavePanel(
        title: String,
        contentType: UTType,
        sourceURL: URL?,
        assetBaseURL: URL?,
        accessoryView: NSView?,
        from window: NSWindow,
        write: @escaping (URL, @escaping (Error?) -> Void) -> Void
    ) {
        let panel = NSSavePanel()
        panel.title = title
        panel.prompt = NSLocalizedString(
            "Export", comment: "Export panel confirmation button")
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowsOtherFileTypes = false
        panel.allowedContentTypes = [contentType]
        panel.accessoryView = accessoryView
        panel.directoryURL =
            sourceURL?.deletingLastPathComponent() ?? assetBaseURL

        let sourceName = sourceURL?.lastPathComponent ?? window.title
        let baseName = (sourceName as NSString).deletingPathExtension
        let fileExtension = contentType.preferredFilenameExtension ?? "file"
        panel.nameFieldStringValue = "\(baseName).\(fileExtension)"

        panel.beginSheetModal(for: window) { response in
            // NSSavePanel may invoke its completion while it is still ordered
            // onscreen. Detach it before showing anything else.
            panel.orderOut(nil)
            guard response == .OK, let url = panel.url else { return }
            write(url) { error in
                if let error {
                    NSAlert(error: error).beginSheetModal(for: window)
                }
            }
        }
    }

    /// Rasterises the document to a single tall PNG. `createPDF` captures the
    /// whole scrollable page as one unpaginated sheet, so no page breaks cut
    /// through the content, and it renders screen media — the image keeps the
    /// on-screen palette rather than the print stylesheet's forced light one.
    private func writePNG(to url: URL, completion: @escaping (Error?) -> Void) {
        webView.createPDF(configuration: WKPDFConfiguration()) { result in
            switch result {
            case .failure(let error):
                completion(error)
            case .success(let data):
                do {
                    try Self.writePNG(fromPDF: data, to: url)
                    completion(nil)
                } catch {
                    completion(error)
                }
            }
        }
    }

    private static func writePNG(fromPDF data: Data, to url: URL) throws {
        guard let document = PDFDocument(data: data), document.pageCount > 0 else {
            throw exportError("The document could not be rendered as an image.")
        }

        // 2x so the result stays sharp on Retina displays and when zoomed.
        let scale: CGFloat = 2
        let pages = (0..<document.pageCount).compactMap { document.page(at: $0) }
        let bounds = pages.map { $0.bounds(for: .mediaBox) }
        let width = bounds.map(\.width).max() ?? 0
        let height = bounds.map(\.height).reduce(0, +)
        guard width > 0, height > 0 else {
            throw exportError("The document could not be rendered as an image.")
        }

        let pixelWidth = Int((width * scale).rounded())
        let pixelHeight = Int((height * scale).rounded())
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw exportError("The image could not be allocated.")
        }
        rep.size = NSSize(width: width, height: height)

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
            throw exportError("The image could not be allocated.")
        }
        NSGraphicsContext.current = context
        // No extra scale here: `rep.size` is in points while the rep holds
        // `scale`x the pixels, so AppKit already maps points to pixels.
        let cgContext = context.cgContext
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()

        // PDF origin is bottom-left, so stack downward from the top edge.
        var offsetY = height
        for (page, pageBounds) in zip(pages, bounds) {
            offsetY -= pageBounds.height
            cgContext.saveGState()
            cgContext.translateBy(x: 0, y: offsetY)
            page.draw(with: .mediaBox, to: cgContext)
            cgContext.restoreGState()
        }

        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw exportError("The image could not be encoded.")
        }
        try png.write(to: url)
    }

    private static func exportError(_ message: String) -> NSError {
        NSError(
            domain: "doc.daisy.export",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: NSLocalizedString(
                message, comment: "PNG export failure")]
        )
    }

    /// File ▸ Print… — the system print panel, with the font size in a
    /// "Daisy" accessory pane so the panel's own live page
    /// thumbnails preview the choice.
    func printDocument(from window: NSWindow) {
        let operation = configuredPrintOperation(from: window)
        runPrintOperation(operation, from: window)
    }

    private func prepareForPanelDrivenExport(_ operation: NSPrintOperation) {
        // The PDF-services action sets these after the user chooses a URL.
        // Pre-setting `.save` makes NSPrintOperation bypass NSPrintPanel.
        operation.printInfo.jobDisposition = .spool
        operation.printInfo.dictionary().removeObject(
            forKey: NSPrintInfo.AttributeKey.jobSavingURL.rawValue as NSString
        )
    }
}
