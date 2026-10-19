//
//  InspectorView.swift
//  daisy
//

import AppKit
import SwiftUI

struct DocumentMetadata: Equatable {
    var fileURL: URL?
    var wordCount: Int = 0
    var links: [DocumentLink] = []
    var modifiedDate: Date?
    var frontmatter: [FrontmatterEntry] = []
}

extension DocumentMetadata {
    static func make(url: URL?, markdown: String) -> DocumentMetadata {
        var meta = DocumentMetadata()
        meta.fileURL = url

        let split = MarkdownFrontmatter.split(markdown)
        if let raw = split.raw {
            meta.frontmatter = MarkdownFrontmatter.parse(raw, format: split.format ?? .yaml)
        }
        let body = split.body
        meta.wordCount = body.split { $0.isWhitespace }.count
        meta.links = DocumentLink.collect(from: body)

        if let url,
           let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
            meta.modifiedDate = attrs[.modificationDate] as? Date
        }
        return meta
    }
}

struct InspectorView: View {
    let metadata: DocumentMetadata
    /// Called when a row in the Links section is clicked or opened from its
    /// context menu.
    var onOpenLink: (DocumentLink) -> Void = { _ in }
    @State private var tab: Tab = .document

    enum Tab: String, CaseIterable, Identifiable {
        case document = "Document"
        case properties = "Properties"
        var id: String { rawValue }

        var localizedTitle: String {
            NSLocalizedString(rawValue, comment: "Inspector tab title")
        }

        var systemImage: String {
            switch self {
            case .document: return "doc"
            case .properties: return "info"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabPicker
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            switch tab {
            case .document: documentTab
            case .properties: propertiesTab
            }
        }
    }

    private var tabPicker: some View {
        Picker(NSLocalizedString("Inspector tab", comment: "Inspector tab picker accessibility label"), selection: $tab) {
            ForEach(Tab.allCases) { tab in
                Image(systemName: tab.systemImage)
                    .accessibilityLabel(tab.localizedTitle)
                    .tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.large)
        .modifier(TabPickerSizing())
    }

    private var documentTab: some View {
        Form {
            Section {
                LabeledContent(
                    NSLocalizedString("Words", comment: "Inspector field label"),
                    value: metadata.wordCount.formatted()
                )
                if let modified = metadata.modifiedDate {
                    LabeledContent(NSLocalizedString("Modified", comment: "Inspector field label")) {
                        Text(modified, format: .dateTime.year().month().day().hour().minute())
                    }
                }
            }

            Section(NSLocalizedString("Links", comment: "Inspector section title")) {
                if metadata.links.isEmpty {
                    Text(NSLocalizedString("No links", comment: "Inspector empty links message"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(metadata.links) { link in
                        linkRow(link)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func linkRow(_ link: DocumentLink) -> some View {
        Button {
            onOpenLink(link)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: Self.symbol(for: link.kind))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    // A link with no text, such as an autolink, shows only
                    // its destination.
                    if !link.text.isEmpty, link.text != link.destination {
                        Text(link.text)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Text(link.destination)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(link.destination)
        .contextMenu {
            Button(NSLocalizedString("Open Link", comment: "Link context menu")) {
                onOpenLink(link)
            }
            Button(NSLocalizedString("Copy Link", comment: "Link context menu")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(link.destination, forType: .string)
            }
        }
    }

    private static func symbol(for kind: DocumentLink.Kind) -> String {
        switch kind {
        case .web: "globe"
        case .file: "doc"
        case .section: "number"
        }
    }

    @ViewBuilder
    private var propertiesTab: some View {
        if metadata.frontmatter.isEmpty {
            Text(NSLocalizedString("No frontmatter", comment: "Inspector empty frontmatter message"))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Form {
                Section {
                    ForEach(metadata.frontmatter) { entry in
                        LabeledContent(entry.key, value: entry.value)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}

private struct TabPickerSizing: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.buttonSizing(.flexible)
        } else {
            content.fixedSize()
        }
    }
}
