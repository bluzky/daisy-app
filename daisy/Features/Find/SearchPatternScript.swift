//
//  SearchPatternScript.swift
//  daisy
//
//  The preview's copy of the search pattern builder. The source editor builds
//  the same pattern in scripts/editor-bundle/src/find.js; keep the two in
//  step — tests/fixtures/find-parity.json pins both.
//

import Foundation

enum SearchPatternScript {
    /// Defines `window.__mdSearchPattern(query, mode, caseSensitive)`, which
    /// returns a global RegExp or throws for an invalid regex. `mode` is
    /// "substring", "word" or "regex".
    static let javaScript = """
    window.__mdSearchPattern = function (query, mode, caseSensitive) {
        var flags = 'gmu' + (caseSensitive ? '' : 'i');
        if (mode === 'regex') return new RegExp(query, flags);
        var literal = query.replace(/[.*+?^${}()|[\\]\\\\]/g, '\\\\$&');
        var word = '[\\\\p{L}\\\\p{N}_]';
        return new RegExp(mode === 'word' ? '(?<!' + word + ')' + literal + '(?!' + word + ')' : literal, flags);
    };
    """
}
