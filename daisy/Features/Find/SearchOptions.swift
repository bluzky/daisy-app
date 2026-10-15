//
//  SearchOptions.swift
//  daisy
//
//  What the find bar searches for and what a search reports back.
//

import Foundation
import CoreGraphics

enum SearchMode: String {
    case substring
    case word
    case regex
}

/// What the find bar is searching for besides the text itself.
struct SearchOptions: Equatable {
    var mode: SearchMode = .substring
    var caseSensitive = false

    /// The options object the editor and preview scripts take.
    var javaScriptLiteral: String {
        "{mode:\"\(mode.rawValue)\",caseSensitive:\(caseSensitive)}"
    }
}

struct FindResult {
    let top: CGFloat?
    let bottom: CGFloat?
    let index: Int
    let total: Int
    /// The pattern was an invalid regex.
    var error = false
    /// More matches exist than the highlight limit; `total` is a floor.
    var capped = false

    static let none = FindResult(top: nil, bottom: nil, index: 0, total: 0)

    /// Decodes the `{index, total, error, capped}` dictionary the editor and
    /// preview scripts return.
    init?(scriptResult: Any?) {
        guard let dict = scriptResult as? [String: Any],
              let index = (dict["index"] as? NSNumber)?.intValue,
              let total = (dict["total"] as? NSNumber)?.intValue else { return nil }
        self.init(top: nil, bottom: nil, index: index, total: total,
                  error: dict["error"] as? Bool ?? false,
                  capped: dict["capped"] as? Bool ?? false)
    }

    init(top: CGFloat?, bottom: CGFloat?, index: Int, total: Int,
         error: Bool = false, capped: Bool = false) {
        self.top = top
        self.bottom = bottom
        self.index = index
        self.total = total
        self.error = error
        self.capped = capped
    }
}
