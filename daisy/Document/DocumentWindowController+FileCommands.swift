import AppKit

extension DocumentWindowController {

    @objc func newProjectFile(_ sender: Any?) { perform(.newFile) }
    @objc func newProjectFolder(_ sender: Any?) { perform(.newFolder) }
    @objc func renameProjectItem(_ sender: Any?) { perform(.rename) }
    @objc func trashProjectItem(_ sender: Any?) { perform(.moveToTrash) }

    func projectFileCommand(for action: Selector?) -> ProjectFileCommand? {
        switch action {
        case #selector(newProjectFile(_:)): .newFile
        case #selector(newProjectFolder(_:)): .newFolder
        case #selector(renameProjectItem(_:)): .rename
        case #selector(trashProjectItem(_:)): .moveToTrash
        default: nil
        }
    }

    private var splitController: MainSplitViewController? {
        documentWindow.contentViewController as? MainSplitViewController
    }

    private func perform(_ command: ProjectFileCommand) {
        guard documentWindow.attachedSheet == nil else {
            NSSound.beep()
            return
        }
        splitController?.perform(command)
    }

    func canPerform(_ command: ProjectFileCommand) -> Bool {
        splitController?.canPerform(command) ?? false
    }
}
