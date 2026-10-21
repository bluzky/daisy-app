//
//  LinkTarget.swift
//  daisy
//
//  What activating a link opens, whichever view it was activated in: the
//  Read mode preview, the inspector's Links section or the editor.
//  `LinkHandler.open` takes it from there.
//

import Foundation

enum LinkTarget: Equatable {
    /// Has a scheme other than `file:`; opened through the external-link policy.
    case external(URL)
    /// A local file, with the `#section` to open it at, if any.
    case file(URL, fragment: String?)
    /// `#fragment`: a heading or anchor in this document.
    case section(String)
    /// A `#tag`, `@context` or `+project` token as written, marker included.
    /// Opens its page in the workspace (see `WorkspacePage`).
    case metadata(String)
}
