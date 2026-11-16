//
//  MarkdownHTML+Comments.swift
//  daisy
//
//  Styles `{==text==}{>>comment<<}` (see `MarkdownComments`). The comment is
//  shown by CSS alone, so Quick Look, which never loads the page script,
//  shows it too.
//

import Foundation

nonisolated extension MarkdownHTML {

    /// The popover under a commented span: the note, read from `data-comment`,
    /// on hover or keyboard focus. Shared by Read mode and the editor so the
    /// two look alike. `selector` must match an element that is positioned.
    static func commentPopoverCSS(_ selector: String, appearance border: String, text: String) -> String {
        """
        \(selector)[data-comment]::after {
            content: attr(data-comment);
            display: none;
            position: absolute;
            z-index: 30;
            top: calc(100% + 6px);
            left: 0;
            width: max-content;
            max-width: min(22em, 80vw);
            padding: 0.45em 0.7em;
            border: 1px solid \(border);
            border-radius: 8px;
            background: Canvas;
            color: \(text);
            box-shadow: 0 6px 20px rgba(0, 0, 0, 0.18);
            font: 400 0.82rem/1.45 -apple-system, BlinkMacSystemFont, sans-serif;
            font-style: normal;
            text-align: start;
            text-decoration: none;
            white-space: pre-line;
            pointer-events: none;
        }
        \(selector)[data-comment]:hover::after, \(selector)[data-comment]:focus-visible::after {
            display: block;
        }
        /* Replies are listed behind bullets (`data-list`): every line after the
           first of each note is indented under its text. Where the keywords are
           not understood the declaration is dropped and the bullets still read. */
        \(selector)[data-list]::after {
            text-indent: 1em hanging each-line;
        }
        """
    }

    /// The bubble of a comment on a spot, drawn on `::before` so a mask on it
    /// cannot clip the popover on `::after`.
    static func commentPointCSS(_ selector: String) -> String {
        """
        \(selector) {
            position: relative;
            display: inline-block;
            width: 1.05em;
            height: 0.95em;
            margin: 0 0.2em;
            vertical-align: -0.1em;
        }
        \(selector)::before {
            content: "";
            position: absolute;
            inset: 0;
            background: color-mix(in srgb, var(--accent, rgb(88, 140, 255)) 80%, transparent);
            -webkit-mask: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 20 18'%3E%3Cpath d='M4 1h12a3 3 0 0 1 3 3v6a3 3 0 0 1-3 3H9l-4.5 4v-4H4a3 3 0 0 1-3-3V4a3 3 0 0 1 3-3z'/%3E%3C/svg%3E") center / contain no-repeat;
            mask: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 20 18'%3E%3Cpath d='M4 1h12a3 3 0 0 1 3 3v6a3 3 0 0 1-3 3H9l-4.5 4v-4H4a3 3 0 0 1-3-3V4a3 3 0 0 1 3-3z'/%3E%3C/svg%3E") center / contain no-repeat;
        }
        \(selector):hover::before { background: var(--accent, rgb(88, 140, 255)); }
        """
    }

    /// Highlights the commented text, and shows the note under it on hover or
    /// keyboard focus. A comment on a spot is a small bubble.
    static let commentsStylesheet = """
    :root { --mdp-comments: 1; }
    .mdp-comment {
        position: relative;
        cursor: default;
        outline: none;
    }
    mark.mdp-comment {
        background: color-mix(in srgb, var(--accent, rgb(88, 140, 255)) 22%, transparent);
        color: inherit;
        border-bottom: 2px solid color-mix(in srgb, var(--accent, rgb(88, 140, 255)) 60%, transparent);
        border-radius: 2px;
        -webkit-box-decoration-break: clone;
        box-decoration-break: clone;
    }
    mark.mdp-comment:hover, mark.mdp-comment:focus-visible {
        background: color-mix(in srgb, var(--accent, rgb(88, 140, 255)) 34%, transparent);
    }
    \(commentPointCSS(".mdp-comment-point"))
    \(commentPopoverCSS(".mdp-comment", appearance: "var(--grid)", text: "var(--text)"))
    @media print {
        .mdp-comment::after, .mdp-comment-point { display: none !important; }
        mark.mdp-comment { background: none; border-bottom: 0; }
    }
    """

    /// Read mode's Add Comment: a small bubble at the end of the selected
    /// text, which opens a one-line field in place. The host writes the
    /// comment into the file. Needs the host bridge, so Quick Look and HTML
    /// export, which have none, never show it.
    static let commentsComposerStylesheet = """
    .mdp-comment-add, .mdp-comment-composer {
        position: absolute;
        z-index: 40;
        font: 400 0.82rem/1.3 -apple-system, BlinkMacSystemFont, sans-serif;
    }
    .mdp-comment-add {
        width: 28px;
        height: 28px;
        padding: 0;
        display: grid;
        place-items: center;
        border: 1px solid var(--grid);
        border-radius: 50%;
        background: Canvas;
        color: var(--accent, rgb(88, 140, 255));
        box-shadow: 0 2px 8px rgba(0, 0, 0, 0.18);
        cursor: pointer;
    }
    .mdp-comment-add:hover { background: var(--accent, rgb(88, 140, 255)); color: white; }
    .mdp-comment-add svg { width: 16px; height: 16px; }
    .mdp-comment-composer {
        display: flex;
        gap: 6px;
        align-items: center;
        width: min(320px, calc(100vw - 24px));
        padding: 6px;
        border: 1px solid var(--grid);
        border-radius: 10px;
        background: Canvas;
        color: var(--text);
        box-shadow: 0 6px 20px rgba(0, 0, 0, 0.22);
    }
    .mdp-comment-composer input {
        flex: 1;
        min-width: 0;
        padding: 5px 8px;
        border: 1px solid var(--grid);
        border-radius: 6px;
        background: transparent;
        color: inherit;
        font: inherit;
        font-size: 0.9rem;
        outline: none;
    }
    .mdp-comment-composer input:focus { border-color: var(--accent, rgb(88, 140, 255)); box-shadow: 0 0 0 2px color-mix(in srgb, var(--accent, rgb(88, 140, 255)) 30%, transparent); }
    .mdp-comment-composer button {
        padding: 4px 9px;
        border: 0;
        border-radius: 6px;
        background: var(--accent, rgb(88, 140, 255));
        color: white;
        font: inherit;
        cursor: pointer;
    }
    ::highlight(mdp-comment-pending) { background: color-mix(in srgb, var(--accent, rgb(88, 140, 255)) 30%, transparent); }
    @media print { .mdp-comment-add, .mdp-comment-composer { display: none !important; } }
    """

    /// The bubble's code, for the page bridge (`hostBridgeScript`), which
    /// provides `post` and `window.MdPreview`. It rides in the bridge, not in
    /// an extension script, so a page that is only a plain document still
    /// loads no extension script. It stays idle unless the Comments extension
    /// is on, which `commentsStylesheet` shows by setting `--mdp-comments`.
    static func commentsComposerBody() -> String {
        let labels = [
            "add": NSLocalizedString("Add comment", comment: "Read mode comment bubble"),
            "placeholder": NSLocalizedString("Add a comment…", comment: "Add Comment field placeholder"),
            "submit": NSLocalizedString("Add", comment: "Add Comment field button")
        ]
        let data = (try? JSONSerialization.data(withJSONObject: labels, options: [.sortedKeys])) ?? Data("{}".utf8)
        let json = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "</", with: "<\\/")
        return """
        const commentLabels = \(json);
        const commentSelectionInfo = \(CommentSelectionScript.function);
        const COMMENT_ICON = '<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M4 3.5h12a1.5 1.5 0 0 1 1.5 1.5v8A1.5 1.5 0 0 1 16 14.5H9l-4 3v-3H4A1.5 1.5 0 0 1 2.5 13V5A1.5 1.5 0 0 1 4 3.5z"/><path d="M6.5 7.5h7M6.5 10.5h4"/></svg>';
        let commentBubble = null, commentComposer = null, commentPicked = null;

        function commentsEnabled() {
            return !!getComputedStyle(document.documentElement).getPropertyValue('--mdp-comments').trim();
        }
        function clearComment() {
            if (commentBubble) commentBubble.remove();
            if (commentComposer) commentComposer.remove();
            commentBubble = commentComposer = commentPicked = null;
            if (window.CSS && CSS.highlights) CSS.highlights.delete('mdp-comment-pending');
        }
        // Sits at the end of the selection's last line, kept inside the window.
        function placeComment(element, info, width) {
            const end = info.endRect;
            const left = Math.min(end.x + end.width + 6, window.innerWidth - width - 8);
            element.style.left = Math.max(8, left) + window.scrollX + 'px';
            element.style.top = end.y + window.scrollY + (end.height - element.offsetHeight) / 2 + 'px';
        }
        function showCommentBubble(info) {
            if (!commentBubble) {
                commentBubble = document.createElement('button');
                commentBubble.type = 'button';
                commentBubble.className = 'mdp-comment-add';
                commentBubble.setAttribute('aria-label', commentLabels.add);
                commentBubble.title = commentLabels.add;
                commentBubble.innerHTML = COMMENT_ICON;
                // Keep the selection while the bubble is pressed.
                commentBubble.addEventListener('mousedown', (event) => event.preventDefault());
                commentBubble.addEventListener('click', () => openCommentComposer());
                document.body.appendChild(commentBubble);
            }
            commentPicked = info;
            placeComment(commentBubble, info, 28);
        }
        function openCommentComposer() {
            if (!commentPicked) return;
            const info = commentPicked;
            if (window.CSS && CSS.highlights && window.Highlight) {
                CSS.highlights.set('mdp-comment-pending', new Highlight(window.getSelection().getRangeAt(0).cloneRange()));
            }
            if (commentBubble) { commentBubble.remove(); commentBubble = null; }
            const form = document.createElement('form');
            commentComposer = form;
            form.className = 'mdp-comment-composer';
            form.innerHTML = '<input type="text" autocomplete="off" spellcheck="true"><button type="submit"></button>';
            const input = form.querySelector('input');
            input.placeholder = commentLabels.placeholder;
            form.querySelector('button').textContent = commentLabels.submit;
            form.addEventListener('submit', (event) => {
                event.preventDefault();
                const note = input.value.trim();
                if (!note) return;
                post({ kind: 'addComment', note, text: info.text, start: info.start,
                       end: info.end, occurrence: info.occurrence });
                window.getSelection().removeAllRanges();
                clearComment();
            });
            form.addEventListener('keydown', (event) => {
                if (event.key === 'Escape') { event.preventDefault(); clearComment(); }
            });
            form.addEventListener('focusout', (event) => {
                if (commentComposer !== form || form.contains(event.relatedTarget)) return;
                clearComment();
            });
            document.body.appendChild(form);
            placeComment(form, info, form.offsetWidth);
            input.focus();
        }
        function refreshCommentBubble() {
            if (commentComposer) return;
            if (!hasHostBridge || !commentsEnabled()) { clearComment(); return; }
            const info = commentSelectionInfo();
            if (info && !info.unsupported) showCommentBubble(info);
            else clearComment();
        }
        document.addEventListener('mouseup', () => setTimeout(refreshCommentBubble, 0));
        document.addEventListener('keyup', (event) => {
            if (event.shiftKey || (event.key || '').startsWith('Arrow')) setTimeout(refreshCommentBubble, 0);
        });
        document.addEventListener('selectionchange', () => {
            if (commentComposer || !commentBubble) return;
            const selection = window.getSelection();
            if (!selection || selection.isCollapsed) clearComment();
        });
        window.MdPreview.registerExtension({ id: 'comments', render() { clearComment(); } });
        """
    }

    /// The editor keeps the source visible, because that is what an AI reads:
    /// the syntax goes quiet, the commented text is highlighted, and each
    /// note is a chip. The classes are added by `comments.js`.
    static let commentsEditorStylesheet = """
    .cm-comment-anchor {
        background: color-mix(in srgb, var(--accent, rgb(88, 140, 255)) 22%, transparent);
        border-radius: 2px;
        -webkit-box-decoration-break: clone;
        box-decoration-break: clone;
    }
    .cm-comment-syntax {
        color: var(--secondary, rgba(128, 128, 128, 0.8));
        opacity: 0.55;
    }
    .cm-comment-note {
        background: color-mix(in srgb, var(--accent, rgb(88, 140, 255)) 14%, transparent);
        border-radius: 4px;
        font-style: italic;
    }
    /* With the caret off its line the markup is hidden and the comment looks as
       it does in Read mode: the text highlighted with the note in a popover, or
       a bubble for a comment on a spot. */
    .cm-comment-anchor[data-comment] {
        position: relative;
        border-bottom: 2px solid color-mix(in srgb, var(--accent, rgb(88, 140, 255)) 60%, transparent);
        cursor: default;
    }
    .cm-comment-anchor[data-comment]:hover { background: color-mix(in srgb, var(--accent, rgb(88, 140, 255)) 34%, transparent); }
    \(commentPointCSS(".cm-comment-point"))
    .cm-comment-point { cursor: pointer; }
    \(commentPopoverCSS(".cm-comment-anchor", appearance: "var(--grid, rgba(128, 128, 128, 0.35))", text: "var(--text, CanvasText)"))
    \(commentPopoverCSS(".cm-comment-point", appearance: "var(--grid, rgba(128, 128, 128, 0.35))", text: "var(--text, CanvasText)"))
    """

    struct CommentsExtension: MarkdownRenderExtension {
        let id = "comments"
        let descriptor = RenderExtensionDescriptor(
            titleKey: "Comments",
            descriptionKey: nil,
            defaultEnabled: true,
            userToggleable: true
        )
        let order = 25
        let editor: (any EditorCapability)? = EditorModule(
            moduleID: "comments",
            css: MarkdownHTML.commentsEditorStylesheet
        )

        /// Always: Read mode can add a comment to any document, not only one
        /// that has comments.
        func isActive(in context: RenderContext) -> Bool { true }

        func assets(mode: VendorLoading) -> RenderAssets {
            // Styles only. The bubble's code is in the page bridge.
            RenderAssets(css: MarkdownHTML.commentsStylesheet + MarkdownHTML.commentsComposerStylesheet)
        }
    }
}
