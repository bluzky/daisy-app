//
//  ReferencesView.swift
//  daisy
//
//  The References panel's content: Linked (files with a Markdown link to
//  the open file) and Mentions (files using the tag, context or project
//  whose page it is), one row per source file: its name, then its folder.
//  Clicking a row opens that file at its first reference. Sections and rows
//  are drawn as the Agenda draws its own.
//

import SwiftUI

struct ReferencesView: View {
    @ObservedObject var store: ReferencesStore
    @FocusState private var listFocused: Bool
    @State private var focusedRowID: String?
    @State private var hoveredRowID: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.isWorkspace {
                content
            } else {
                NoWorkspaceView(symbol: "link",
                                message: NSLocalizedString("References are available in a workspace.",
                                                           comment: "References sidebar outside a workspace"),
                                canInitializeWorkspace: store.canInitializeWorkspace,
                                onInitializeWorkspace: store.onInitializeWorkspace)
            }
        }
        .frame(minWidth: 270, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text(NSLocalizedString("References", comment: "References sidebar title"))
                // As the Agenda's header.
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .accessibilityAddTraits(.isHeader)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch store.content {
        case .noFile:
            message(symbol: "doc",
                    NSLocalizedString("No saved file", comment: "References sidebar empty state"),
                    hint: NSLocalizedString("Open a file in the workspace to see what refers to it.",
                                            comment: "References sidebar empty state hint"))
        case .notIndexed:
            message(symbol: "doc.questionmark",
                    NSLocalizedString("Not in the workspace index", comment: "References sidebar empty state"),
                    hint: NSLocalizedString("Only Markdown files inside the workspace folder are indexed.",
                                            comment: "References sidebar empty state hint"))
        case .loading:
            if store.isIndexing { indexing } else { Spacer() }
        case .references(let references):
            list(references)
        }
    }

    private func rows(_ references: WorkspaceReferences) -> [Row] {
        ReferencesSection.allCases
            .filter { !store.collapsedSections.contains($0) }
            .flatMap { section in
                sources(references, section).map { Row(section: section, source: $0) }
            }
    }

    private func sources(_ references: WorkspaceReferences,
                         _ section: ReferencesSection) -> [WorkspaceReferences.Source] {
        switch section {
        case .linked: references.linked
        case .mentions: references.mentions
        }
    }

    private func list(_ references: WorkspaceReferences) -> some View {
        let rows = rows(references)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if references.isEmpty {
                        message(symbol: "link",
                                NSLocalizedString("No references", comment: "References sidebar empty state"),
                                hint: NSLocalizedString("Files that link to this one, or use the tag, context or project whose page it is, appear here.",
                                                        comment: "References sidebar empty state hint"))
                    }
                    ForEach(ReferencesSection.allCases, id: \.self) { section in
                        let sources = self.sources(references, section)
                        if !sources.isEmpty { self.section(section, sources) }
                    }
                    if store.isIndexing { indexing }
                    if store.isTruncated {
                        Label(NSLocalizedString("Some files are not indexed: the workspace is over the file limit.",
                                                comment: "References sidebar status"),
                              systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                }
                .padding(.bottom, 8)
            }
            .focusable()
            .focusEffectDisabled()
            .focused($listFocused)
            .onKeyPress(keys: [.upArrow, .downArrow, .return]) { press in
                handleKey(press.key, rows: rows, proxy: proxy)
            }
        }
    }

    private func handleKey(_ key: KeyEquivalent, rows: [Row], proxy: ScrollViewProxy) -> KeyPress.Result {
        guard !rows.isEmpty else { return .ignored }
        let current = rows.firstIndex { $0.id == focusedRowID }
        switch key {
        case .upArrow, .downArrow:
            let next = key == .upArrow ? max((current ?? rows.count) - 1, 0) : min((current ?? -1) + 1, rows.count - 1)
            focusedRowID = rows[next].id
            proxy.scrollTo(rows[next].id)
        case .return:
            guard let current else { return .ignored }
            store.onOpen?(rows[current].path, rows[current].line, false)
        default:
            return .ignored
        }
        return .handled
    }

    private func title(_ section: ReferencesSection) -> String {
        switch section {
        case .linked: NSLocalizedString("Linked", comment: "References sidebar section")
        case .mentions: NSLocalizedString("Mentions", comment: "References sidebar section")
        }
    }

    private func section(_ section: ReferencesSection, _ sources: [WorkspaceReferences.Source]) -> some View {
        let collapsed = store.collapsedSections.contains(section)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                if collapsed { store.collapsedSections.remove(section) } else { store.collapsedSections.insert(section) }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .frame(width: 10)
                    Text(title(section).uppercased())
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(sources.count)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        // Localizable.stringsdict holds its plural forms.
                        .accessibilityLabel(Text(String.localizedStringWithFormat(
                            NSLocalizedString("%d files", comment: "References sidebar count"), sources.count)))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(Text(collapsed
                ? NSLocalizedString("Collapsed", comment: "Tasks sidebar section state")
                : NSLocalizedString("Expanded", comment: "Tasks sidebar section state")))
            if !collapsed {
                ForEach(sources, id: \.path) { source in
                    rowView(Row(section: section, source: source))
                }
            }
        }
    }

    /// The source file's name, with its folder below it when it has one.
    private func rowView(_ row: Row) -> some View {
        let isHighlighted = hoveredRowID == row.id || (listFocused && focusedRowID == row.id)
        let name = (row.path as NSString).lastPathComponent
        let folder = (row.path as NSString).deletingLastPathComponent
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !folder.isEmpty {
                    Text(folder)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "arrow.up.right")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .opacity(isHighlighted ? 1 : 0)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHighlighted ? Color.primary.opacity(0.07) : Color.clear)
        )
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            focusedRowID = row.id
            store.onOpen?(row.path, row.line, false)
        }
        .onHover { hovering in
            if hovering { hoveredRowID = row.id } else if hoveredRowID == row.id { hoveredRowID = nil }
        }
        .help(row.path)
        .id(row.id)
        .contextMenu {
            Button(NSLocalizedString("Open", comment: "Tasks row context menu")) {
                store.onOpen?(row.path, row.line, false)
            }
            Button(NSLocalizedString("Open in New Tab", comment: "Tasks row context menu")) {
                store.onOpen?(row.path, row.line, true)
            }
            Button(NSLocalizedString("Reveal in Files", comment: "Tasks row context menu")) {
                store.onReveal?(row.path)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - States

    private var indexing: some View {
        Label(NSLocalizedString("Indexing workspace…", comment: "Tasks sidebar status"),
              systemImage: "arrow.triangle.2.circlepath")
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }

    private func message(symbol: String, _ title: String, hint: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.body)
            Text(hint)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
    }

    private struct Row {
        let section: ReferencesSection
        let source: WorkspaceReferences.Source

        var path: String { source.path }
        /// Where a click opens the file: its first reference.
        var line: Int { source.occurrences.first?.line ?? 1 }
        /// A file can be both linked and mentioned.
        var id: String { "\(section.rawValue):\(path)" }
    }
}
