//
//  SlidePreviewViewController.swift
//  daisy
//
//  View ▸ Slide Preview: the right pane's slide strip for a deck. In Edit
//  Mode it follows the editor's text and caret, so the slides being written
//  stay in view; in Read Mode it shows the rendered document.
//

import Cocoa
import WebKit

final class SlidePreviewViewController: NSViewController {
    /// The reader clicked a slide: its zero-based index.
    var slideSelected: ((Int) -> Void)?

    private let markdownView = MarkdownWebView(frame: .zero)
    private var markdown: String?
    private var assetBaseURL: URL?
    private var currentSlide: Int?
    private var isVisible = false
    private var pendingMarkdown: (String, URL?)?

    override func loadView() {
        markdownView.forcesSlides = true
        markdownView.extensionHostState = [MarkdownHTML.slidesPaneStateID: true]
        markdownView.contentDidReplace = { [weak self] in self?.markCurrentSlide(scroll: true) }
        markdownView.slideClicked = { [weak self] index in self?.slideSelected?(index) }
        view = markdownView
    }

    /// Only the panel on screen renders; one hidden keeps the latest text
    /// and shows it when it appears.
    func setPaneVisible(_ visible: Bool) {
        isVisible = visible
        if visible, let (markdown, base) = pendingMarkdown {
            pendingMarkdown = nil
            render(markdown, assetBaseURL: base)
        }
    }

    /// Shows `markdown` as slides. The page updates in place, so slides
    /// that didn't change, and their diagrams, are left alone.
    func display(markdown: String, assetBaseURL: URL?) {
        guard markdown != self.markdown || assetBaseURL != self.assetBaseURL else { return }
        guard isVisible else {
            pendingMarkdown = (markdown, assetBaseURL)
            return
        }
        render(markdown, assetBaseURL: assetBaseURL)
    }

    /// The editor's caret moved to `line` of the file: outline its slide,
    /// and scroll to it when it is another slide than before, so typing
    /// within a slide never moves the pane.
    func followCaret(toLine line: Int) {
        guard let markdown else { return }
        let index = MarkdownHTML.slideIndex(
            atSourceLine: line, markdown: markdown,
            configuration: RenderExtensionPreferences.currentConfiguration
        )
        guard index != currentSlide else { return }
        currentSlide = index
        markCurrentSlide(scroll: true)
    }

    private func render(_ markdown: String, assetBaseURL: URL?) {
        self.markdown = markdown
        self.assetBaseURL = assetBaseURL
        markdownView.display(markdown: markdown, assetBaseURL: assetBaseURL, documentID: "slide-preview")
    }

    private func markCurrentSlide(scroll: Bool) {
        guard let currentSlide else { return }
        markdownView.webView.evaluateJavaScript("""
        (() => {
            const frames = document.querySelectorAll('.mdp-slide-frame');
            frames.forEach((frame, index) => frame.toggleAttribute('data-mdp-pane-current', index === \(currentSlide)));
            const frame = frames[Math.min(\(currentSlide), frames.length - 1)];
            if (frame && \(scroll)) frame.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
        })();
        """) { _, _ in }
    }
}
