//
//  InspectorViewController.swift
//  daisy
//

import Cocoa
import SwiftUI

final class InspectorViewController: NSViewController {

    private var host: NSHostingView<InspectorView>!
    private var metadata = DocumentMetadata()

    /// A link picked in the Links section, with the document it belongs to.
    var onOpenLink: ((DocumentLink, URL?) -> Void)?

    override func loadView() {
        host = NSHostingView(rootView: makeView())
        view = host
    }

    func display(metadata: DocumentMetadata) {
        self.metadata = metadata
        loadViewIfNeeded()
        host.rootView = makeView()
    }

    private func makeView() -> InspectorView {
        let documentURL = metadata.fileURL
        return InspectorView(metadata: metadata) { [weak self] link in
            self?.onOpenLink?(link, documentURL)
        }
    }
}
