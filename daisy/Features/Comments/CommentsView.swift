//
//  CommentsView.swift
//  daisy
//
//  The Comments panel's content: a header with Copy for AI, then one card per
//  comment. Clicking a card jumps to its line; the card's buttons reply to
//  the comment or resolve it. Drawn like the Agenda and References panels.
//

import SwiftUI

struct CommentsView: View {
    @ObservedObject var store: CommentsStore
    @State private var replyText = ""
    @FocusState private var replyFocused: Bool

    /// The theme's accent, as the sidebars' selection uses.
    private var accent: Color { Color(nsColor: DocumentWindowController.makeThemeAccent()) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if !store.hasDocument {
                message(symbol: "doc", NSLocalizedString("No document", comment: "Comments sidebar empty state"),
                        hint: NSLocalizedString("Open a Markdown file to see its comments.",
                                                comment: "Comments sidebar empty state hint"))
            } else if store.comments.isEmpty {
                message(symbol: "text.bubble", NSLocalizedString("No comments", comment: "Comments sidebar empty state"),
                        hint: NSLocalizedString("Select text in the editor and choose Insert ▸ Comment.",
                                                comment: "Comments sidebar empty state hint"))
            } else {
                list
            }
        }
        .frame(minWidth: 270, maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text(NSLocalizedString("Comments", comment: "Comments sidebar title"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .accessibilityAddTraits(.isHeader)
            if !store.comments.isEmpty {
                Text("\(store.comments.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(Color(nsColor: .quaternaryLabelColor).opacity(0.6)))
            }
            Spacer()
            Button {
                store.onCopy?()
            } label: {
                Label(NSLocalizedString("Copy for AI", comment: "Comments sidebar button"),
                      systemImage: "sparkles")
                    .font(.system(size: 11))
            }
            .buttonStyle(HoverHighlightButtonStyle())
            .disabled(store.comments.isEmpty)
            .help(NSLocalizedString("Copy every comment, with its line and text, as a brief to paste into an AI prompt",
                                    comment: "Comments sidebar button tooltip"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - List

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(store.comments.enumerated()), id: \.offset) { index, comment in
                        card(index, comment).id(index)
                    }
                }
                .padding(10)
            }
            .onChange(of: store.revealCount) {
                guard let index = store.highlighted else { return }
                withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(index, anchor: .center) }
            }
        }
    }

    private func card(_ index: Int, _ comment: MarkdownComments.Comment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                store.onJump?(comment.line)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(format: NSLocalizedString("Line %d", comment: "Comments sidebar row"), comment.line))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    if let anchor = comment.anchor {
                        Text(flattened(anchor))
                            .font(.system(size: 12).italic())
                            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                            .lineLimit(3)
                            .padding(.leading, 8)
                            .overlay(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 1.5).fill(accent.opacity(0.7)).frame(width: 3)
                            }
                    }
                    ForEach(Array(comment.notes.enumerated()), id: \.offset) { offset, note in
                        Text(note)
                            .font(.system(size: 13))
                            .foregroundStyle(Color(nsColor: .labelColor))
                            .padding(.leading, offset == 0 ? 0 : 12)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if store.replyingTo == index {
                replyField(index)
            } else {
                HStack(spacing: 12) {
                    Button {
                        replyText = ""
                        store.replyingTo = index
                    } label: {
                        Label(NSLocalizedString("Reply", comment: "Comments sidebar button"),
                              systemImage: "arrowshape.turn.up.left")
                    }
                    Button {
                        store.onResolve?(index, store.snapshot)
                    } label: {
                        Label(NSLocalizedString("Resolve", comment: "Comments sidebar button"),
                              systemImage: "checkmark.circle")
                    }
                    .help(NSLocalizedString("Remove the comment markup and keep the text",
                                            comment: "Comments sidebar button tooltip"))
                }
                .font(.system(size: 11))
                .buttonStyle(.borderless)
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(accent, lineWidth: 1.5)
            .opacity(store.highlighted == index ? 1 : 0))
        .animation(.easeOut(duration: 0.3), value: store.highlighted)
    }

    private func replyField(_ index: Int) -> some View {
        TextField(NSLocalizedString("Reply…", comment: "Comments sidebar reply field"), text: $replyText)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12))
            .focused($replyFocused)
            // The field is created by the same update that opens it, so focus
            // is asked for once it is on screen, not in that update.
            .onAppear { DispatchQueue.main.async { replyFocused = true } }
            .onSubmit {
                let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
                store.replyingTo = nil
                replyText = ""
                if !text.isEmpty { store.onReply?(index, text, store.snapshot) }
            }
            .onExitCommand {
                store.replyingTo = nil
                replyText = ""
            }
    }

    private func flattened(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
    }

    private func message(symbol: String, _ title: String, hint: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(.secondary)
            Text(title).foregroundStyle(.secondary)
            Text(hint).font(.callout).foregroundStyle(.tertiary).multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A borderless button that lights up under the pointer: its text goes to the
/// primary colour and a soft pill appears behind it.
private struct HoverHighlightButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        let lit = isEnabled && (isHovered || configuration.isPressed)
        configuration.label
            .foregroundStyle(Color(nsColor: lit ? .labelColor : .secondaryLabelColor))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .labelColor).opacity(configuration.isPressed ? 0.12 : lit ? 0.07 : 0))
            )
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: lit)
    }
}
