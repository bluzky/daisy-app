//
//  DocumentWindowController+QueryBlocks.swift
//  daisy
//
//  Answers the preview's ```tasks and ```notes blocks from the window's
//  workspace index, and again each time the index's records change. A
//  result row opens its file at its line; a task's checkbox checks it off
//  the way the Tasks sidebar does. Outside a workspace nothing is answered,
//  so the blocks show their source.
//

import Cocoa

/// Where query blocks are shown: Read mode's page or the editor.
enum QueryBlockTarget: Hashable {
    case preview, editor
}

extension DocumentWindowController {
    /// The blocks `target` now shows. Called whenever they change, including
    /// to none.
    func runQueryBlocks(_ requests: [QueryBlockRequest], for target: QueryBlockTarget) {
        guard queryBlockRequests[target, default: []] != requests else { return }
        queryBlockRequests[target] = requests.isEmpty ? nil : requests
        restartQueryBlocks()
    }

    /// Re-answers every shown block from the current index: after a new
    /// request, and when the window's workspace changes.
    func restartQueryBlocks() {
        queryBlockTask?.cancel()
        queryBlockTask = nil
        queryBlockMatches = [:]
        let requests = queryBlockRequests
        guard let index = workspaceIndex, !requests.isEmpty else {
            mainSplit?.clearEditorQueryResults()
            return
        }
        queryBlockTask = Task { [weak self] in
            for await _ in await index.recordChanges() {
                // Changes in a burst (a scan, a save) collapse into one run:
                // the stream keeps only the newest revision while this waits.
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                var allMatches: [String: WorkspaceQueryMatch] = [:]
                var answers: [(QueryBlockTarget, [QueryBlockResult])] = []
                for (target, targetRequests) in requests {
                    let (results, matches) = await QueryBlocks.results(for: targetRequests, index: index)
                    allMatches.merge(matches) { first, _ in first }
                    answers.append((target, results))
                }
                guard let self, !Task.isCancelled else { return }
                self.queryBlockMatches = allMatches
                for (target, results) in answers { self.mainSplit?.showQueryResults(results, in: target) }
            }
        }
    }

    func stopQueryBlocks() {
        queryBlockTask?.cancel()
        queryBlockTask = nil
        queryBlockMatches = [:]
        mainSplit?.clearEditorQueryResults()
    }

    func openQueryResult(path: String, line: Int) {
        switch queryBlockMatches[QueryBlocks.key(path: path, line: line)] {
        case let .task(task)?:
            openTask(task, inNewTab: false)
        case .file?:
            guard let root = workspaceIndex?.root,
                  (try? WorkspaceFileWriter.components(of: path)) != nil else {
                NSSound.beep()
                return
            }
            mainSplit?.openLink(.file(root.appending(path: path, directoryHint: .notDirectory), fragment: nil))
        case nil:
            NSSound.beep()
        }
    }

    func setQueryTaskChecked(path: String, line: Int, checked: Bool) {
        guard case let .task(task)? = queryBlockMatches[QueryBlocks.key(path: path, line: line)] else {
            NSSound.beep()
            restartQueryBlocks()
            return
        }
        setTaskChecked(task, checked: checked) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    let alert = NSAlert()
                    alert.messageText = error
                    alert.beginSheetModal(for: self.documentWindow)
                }
                // Puts the checkbox back when the change failed; the index's
                // change stream refreshes it when it worked.
                self.restartQueryBlocks()
            }
        }
    }
}
