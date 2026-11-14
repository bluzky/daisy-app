//
//  LinkHandler.swift
//  daisy
//
//  Opens a link activated in a document window, the same way wherever it was
//  activated: a click in Read mode, a click in the inspector, or Cmd+click in
//  the editor. Markdown files open in Daisy, other files in their default
//  app, web links through the external-link policy, sections scroll the
//  preview, and metadata tokens open their workspace page.
//

import Cocoa

@MainActor
enum LinkHandler {
    static func open(_ link: LinkTarget, in controller: DocumentWindowController) {
        switch link {
        case .external(let url):
            ExternalLinkOpener.open(url, window: controller.window)
        case .file(let url, let fragment):
            guard FileKind.classify(url) == .markdown else {
                NSWorkspace.shared.open(url)
                return
            }
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.fragment = fragment
            controller.openMarkdownLink(components?.url ?? url)
        case .section(let id):
            controller.mainSplit?.scrollToFragment(id)
        case .metadata(let token):
            guard let root = controller.indexedWorkspaceRootURL else {
                NSSound.beep()
                return
            }
            do {
                let page = try WorkspacePage.openOrCreate(token: token, root: root)
                controller.openMarkdownLink(page)
            } catch {
                guard let window = controller.window else { return }
                NSAlert(error: error).beginSheetModal(for: window)
            }
        }
    }
}
