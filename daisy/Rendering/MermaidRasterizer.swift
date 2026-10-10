//
//  MermaidRasterizer.swift
//  daisy
//
//  Renders Mermaid sources to PNG for the Word export. App-only: the Quick
//  Look extension does not compile this file.
//
//  Uses its own offscreen web view instead of the document's, so export works
//  the same in Read and Edit mode and doesn't disturb the on-screen page. The
//  diagram is drawn by WebKit and snapshotted, rather than handed to
//  `NSImage` as SVG, because mermaid lays labels out in `<foreignObject>`
//  HTML, which only a browser engine draws.
//

import AppKit
import WebKit

@MainActor
final class MermaidRasterizer: NSObject, WKNavigationDelegate {
    /// Pixels per CSS pixel in the PNG, so diagrams stay sharp when zoomed.
    private static let scale: CGFloat = 2
    /// Largest CSS width or height drawn; bigger diagrams are scaled down.
    private static let maxDimension: CGFloat = 4000

    private let webView: WKWebView
    private var loaded: CheckedContinuation<Bool, Never>?

    private override init() {
        webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            configuration: WKWebViewConfiguration())
        super.init()
        webView.navigationDelegate = self
    }

    /// Renders each distinct source with mermaid's light theme — a Word page
    /// is paper — keyed by the source text. Sources that fail to parse or
    /// draw are left out, so the exporter falls back to their text.
    static func render(_ sources: [String]) async -> [String: DocxImage] {
        let unique = Array(Set(sources))
        guard !unique.isEmpty,
              let vendor = MarkdownHTML.bundledVendorResource(
                "mermaid.min", ext: "js", subdir: "Vendor/Mermaid")
        else { return [:] }
        let rasterizer = MermaidRasterizer()
        guard await rasterizer.load(vendor: vendor) else { return [:] }
        var images: [String: DocxImage] = [:]
        for (index, source) in unique.enumerated() {
            if let image = await rasterizer.rasterize(source, id: "mmdocx\(index)") {
                images[source] = image
            }
        }
        return images
    }

    private func load(vendor: String) async -> Bool {
        let safeVendor = vendor.replacingOccurrences(of: "</script", with: "<\\/script")
        let html = """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8">
        <style>
        html, body { margin: 0; padding: 0; background: #fff; overflow: hidden; }
        #stage svg { display: block; }
        </style>
        <script>\(safeVendor)</script>
        <script>
        mermaid.initialize({
            startOnLoad: false,
            theme: 'default',
            securityLevel: 'strict',
            fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif'
        });
        </script>
        </head><body><div id="stage"></div></body></html>
        """
        return await withCheckedContinuation { continuation in
            loaded = continuation
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    /// Draws one diagram at its natural size and snapshots it. Returns nil
    /// when mermaid rejects the source.
    private func rasterize(_ source: String, id: String) async -> DocxImage? {
        let result = try? await webView.callAsyncJavaScript("""
            const stage = document.getElementById('stage');
            stage.innerHTML = '';
            let svgText;
            try {
                svgText = (await mermaid.render(id, source)).svg;
            } catch (err) {
                // Strict mode leaves its error graphic in the body.
                document.querySelectorAll('[id^="d' + id + '"], #' + id).forEach((n) => n.remove());
                return null;
            }
            stage.innerHTML = svgText;
            const svg = stage.querySelector('svg');
            if (!svg) return null;
            let width, height;
            const vb = svg.viewBox && svg.viewBox.baseVal;
            if (vb && vb.width && vb.height) {
                width = vb.width; height = vb.height;
            } else {
                const box = svg.getBBox();
                width = box.width; height = box.height;
            }
            if (!(width > 0 && height > 0)) return null;
            const fit = Math.min(1, maxDimension / Math.max(width, height));
            width = Math.ceil(width * fit);
            height = Math.ceil(height * fit);
            // Mermaid sizes the SVG to its container (width 100%, max-width);
            // pin it to the diagram's own size instead.
            svg.removeAttribute('style');
            svg.setAttribute('width', width);
            svg.setAttribute('height', height);
            await document.fonts.ready;
            return { width, height };
            """,
            arguments: ["source": source, "id": id, "maxDimension": Self.maxDimension],
            in: nil, contentWorld: .page)
        guard let size = result as? [String: Any],
              let width = (size["width"] as? NSNumber)?.doubleValue,
              let height = (size["height"] as? NSNumber)?.doubleValue
        else { return nil }

        webView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let configuration = WKSnapshotConfiguration()
        configuration.rect = NSRect(x: 0, y: 0, width: width, height: height)
        // `snapshotWidth` is in points and WebKit multiplies it by the
        // screen's backing scale, so ask for at least `scale` and resample to
        // exactly that: the PNG is then the same on every display.
        configuration.snapshotWidth = NSNumber(value: Double(width * Self.scale))
        configuration.afterScreenUpdates = true
        guard let image = try? await webView.takeSnapshot(configuration: configuration),
              let png = Self.png(image, pixelsWide: Int(width * Self.scale), pixelsHigh: Int(height * Self.scale))
        else { return nil }
        return DocxImage(data: png, ext: "png", width: width, height: height)
    }

    private static func png(_ image: NSImage, pixelsWide: Int, pixelsHigh: Int) -> Data? {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded?.resume(returning: true)
        loaded = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loaded?.resume(returning: false)
        loaded = nil
    }

    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        loaded?.resume(returning: false)
        loaded = nil
    }
}
