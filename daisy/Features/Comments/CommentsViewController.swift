//
//  CommentsViewController.swift
//  daisy
//
//  The Comments panel of the right-hand pane: every `{==text==}{>>note<<}`
//  in the open document (`MarkdownComments`), with its line, the commented
//  text and the notes. Unlike the Agenda it needs no workspace: it reads the
//  window's own text, which the split view pushes in whenever Read mode shows
//  a document or the editor changes. Edits go back through `onResolve` and
//  `onReply`, along with the text the list was built from, so a list that has
//  fallen behind the document never changes the wrong comment.
//

import Cocoa
import Combine
import SwiftUI

@MainActor
final class CommentsStore: ObservableObject {
    @Published var comments: [MarkdownComments.Comment] = []
    @Published var hasDocument = false
    /// The comment whose reply field is open.
    @Published var replyingTo: Int?

    /// The text `comments` was read from.
    var snapshot = ""

    var onJump: ((Int) -> Void)?
    var onCopy: (() -> Void)?
    /// Comment index and the text it was read from.
    var onResolve: ((Int, String) -> Void)?
    /// Comment index, the reply, and the text the index was read from.
    var onReply: ((Int, String, String) -> Void)?
}

final class CommentsViewController: NSViewController {
    let store = CommentsStore()

    override func loadView() {
        let host = NSHostingView(rootView: CommentsView(store: store))
        host.translatesAutoresizingMaskIntoConstraints = false
        view = host
    }

    /// The pane reads the theme accent while drawing; redraw it on a theme change.
    func themeColorsDidChange() {
        store.objectWillChange.send()
    }

    /// Reads the comments out of `markdown`; nil when the window has no document.
    func setMarkdown(_ markdown: String?) {
        guard markdown != store.snapshot || store.hasDocument != (markdown != nil) else { return }
        store.hasDocument = markdown != nil
        store.snapshot = markdown ?? ""
        store.comments = markdown.map(MarkdownComments.comments(in:)) ?? []
        if let replying = store.replyingTo, !store.comments.indices.contains(replying) {
            store.replyingTo = nil
        }
    }
}
