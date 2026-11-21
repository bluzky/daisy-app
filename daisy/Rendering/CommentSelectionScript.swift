//
//  CommentSelectionScript.swift
//  daisy
//
//  The page script behind Add Comment in Read mode: what is selected, which
//  block of the source it sits in, and where its last line ends. It lives
//  apart from the page's other scripts so the WebKit tests can run the exact
//  code the app ships.
//

import Foundation

nonisolated enum CommentSelectionScript {
    /// A JavaScript function expression. It returns null for no selection,
    /// `{unsupported: true}` for one that spans blocks or sits in code, a
    /// table or a diagram, and otherwise the text, the source lines of its
    /// block, the earlier copies of the text in that block, and the bounds of
    /// the selection and of its last line in viewport pixels.
    static let function = """
    () => {
        const selection = window.getSelection();
        if (!selection || selection.rangeCount === 0 || selection.isCollapsed) return null;
        const range = selection.getRangeAt(0);
        const text = selection.toString();
        if (!text.trim()) return null;
        const owner = (node) => {
            const element = node.nodeType === 1 ? node : node.parentElement;
            return element ? element.closest('[data-source-start]') : null;
        };
        // Judged by the text the selection covers, not by where its ends sit:
        // a selection that begins at the first character of a list item or a
        // task line has its start on the item itself, not in its text.
        let first = null, last = null, firstOffset = 0;
        const root = range.commonAncestorContainer;
        const texts = [];
        if (root.nodeType === 3) {
            texts.push(root);
        } else {
            const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
            for (let node = walker.nextNode(); node; node = walker.nextNode()) texts.push(node);
        }
        for (const node of texts) {
            if (!range.intersectsNode(node)) continue;
            let from = 0, to = node.nodeValue.length;
            if (node === range.startContainer) from = range.startOffset;
            if (node === range.endContainer) to = range.endOffset;
            if (!node.nodeValue.slice(from, to).trim()) continue;
            if (!first) { first = node; firstOffset = from; }
            last = node;
        }
        if (!first) return null;
        const block = owner(first);
        if (!block || block !== owner(last) || block.closest('pre, figure, .mermaid, .katex')) {
            return { unsupported: true };
        }
        // A table is commented on one row at a time: the selection must sit in
        // a single cell, and the row's own source line stands in for the block.
        let start = Number(block.getAttribute('data-source-start'));
        let end = Number(block.getAttribute('data-source-end'));
        let scope = block;
        const table = block.closest('table');
        if (table) {
            const cellOf = (node) => node.parentElement ? node.parentElement.closest('td, th') : null;
            const cell = cellOf(first);
            const row = cell ? cell.parentElement : null;
            if (!cell || !row || cell !== cellOf(last)) return { unsupported: true };
            // Header on the first line, the delimiter row on the second, then
            // one line per body row.
            const line = start + (row.rowIndex === 0 ? 0 : row.rowIndex + 1);
            if (line > end) return { unsupported: true };
            start = end = line;
            scope = row;
        }
        const before = document.createRange();
        before.selectNodeContents(scope);
        before.setEnd(first, firstOffset);
        const earlier = before.toString();
        let occurrence = 0;
        for (let index = earlier.indexOf(text); index !== -1; index = earlier.indexOf(text, index + text.length)) {
            occurrence += 1;
        }
        const box = range.getBoundingClientRect();
        const lines = range.getClientRects();
        const lineEnd = lines.length ? lines[lines.length - 1] : box;
        return {
            text,
            start,
            end,
            occurrence,
            rect: { x: box.x, y: box.y, width: box.width, height: box.height },
            endRect: { x: lineEnd.x, y: lineEnd.y, width: lineEnd.width, height: lineEnd.height }
        };
    }
    """

    /// The function, called: what the tests evaluate.
    static var source: String { "(\(function))()" }
}
