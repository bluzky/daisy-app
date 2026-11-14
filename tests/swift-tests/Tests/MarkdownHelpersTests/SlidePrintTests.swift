import AppKit
import PDFKit
import WebKit
import XCTest

@testable import MarkdownHelpers

/// Prints a deck to PDF through WebKit's print operation, set up the way
/// `MarkdownWebView+PDFExport` sets it up, and checks the pages.
final class SlidePrintTests: XCTestCase {
  private final class Finished: NSObject {
    var done = false
    @objc func printOperationDidRun(_: NSPrintOperation, success _: Bool, contextInfo _: UnsafeMutableRawPointer?) {
      done = true
    }
  }

  @MainActor
  private func printedPages(_ markdown: String, aspect: SlideDeckSettings.Aspect) async throws -> PDFDocument {
    let output = FileManager.default.temporaryDirectory.appendingPathComponent("slides-\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: output) }
    // The app's Read Mode page: scrolling article, top clearance.
    let rendered = MarkdownHTML.render(markdown: markdown, allowsScroll: true, vendorLoading: .lazy,
                                       contentWidth: .centered,
                                       pageTopClearance: MarkdownHTML.appPageTopClearance)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 800),
                          styleMask: [.titled], backing: .buffered, defer: false)
    let webView = WKWebView(frame: window.contentView!.bounds)
    window.contentView!.addSubview(webView)
    webView.loadHTMLString(rendered.html, baseURL: nil)
    let deadline = Date().addingTimeInterval(10)
    while webView.isLoading && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
    try await Task.sleep(for: .milliseconds(300))
    _ = try await webView.evaluateJavaScript("""
    document.documentElement.setAttribute('\(MarkdownHTML.slidesPrintAttribute)', '');
    const style = document.createElement('style');
    style.textContent = '@media print { \(MarkdownHTML.slidesPrintPageCSS(aspect: aspect)) }';
    document.head.appendChild(style);
    true
    """)
    let info = NSPrintInfo.shared.copy() as! NSPrintInfo
    info.horizontalPagination = .fit
    info.verticalPagination = .automatic
    info.orientation = .landscape
    info.paperSize = NSSize(width: CGFloat(MarkdownHTML.slideCanvasWidth) * 0.75,
                            height: CGFloat(aspect.canvasHeight) * 0.75)
    info.topMargin = 0
    info.bottomMargin = 0
    info.leftMargin = 0
    info.rightMargin = 0
    info.jobDisposition = .save
    info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = output
    let operation = webView.printOperation(with: info)
    operation.showsPrintPanel = false
    operation.showsProgressPanel = false
    operation.view?.frame = webView.bounds
    let finished = Finished()
    operation.runModal(for: window, delegate: finished,
                       didRun: #selector(Finished.printOperationDidRun(_:success:contextInfo:)),
                       contextInfo: nil)
    let end = Date().addingTimeInterval(20)
    while !finished.done && Date() < end { try await Task.sleep(for: .milliseconds(100)) }
    return try XCTUnwrap(PDFDocument(url: output))
  }

  @MainActor
  func testEachSlidePrintsOnExactlyOnePage() async throws {
    let pdf = try await printedPages("""
    ---
    slides: true
    paginate: true
    ---

    # One

    ???

    notes

    ---

    ## Two

    - a
    - b

    ---

    ## Three
    """, aspect: .wide)
    XCTAssertEqual(pdf.pageCount, 3, "no blank page after a slide")
    for index in 0..<pdf.pageCount {
      let page = try XCTUnwrap(pdf.page(at: index))
      XCTAssertEqual(page.bounds(for: .mediaBox).size, CGSize(width: 960, height: 540))
      let text = page.string ?? ""
      XCTAssertTrue(text.contains(["One", "Two", "Three"][index]), text)
      XCTAssertTrue(text.contains(String(index + 1)), "the page number stays on its slide: \(text)")
      XCTAssertFalse(text.contains("notes"), "notes don't print")
    }
  }

  @MainActor
  func testPageSizeFollowsTheAspect() async throws {
    let pdf = try await printedPages("---\nslides: true\naspect: 4:3\n---\n\n# One\n\n---\n\n## Two",
                                     aspect: .standard)
    XCTAssertEqual(pdf.pageCount, 2)
    XCTAssertEqual(pdf.page(at: 0)?.bounds(for: .mediaBox).size, CGSize(width: 960, height: 720))
  }
}
