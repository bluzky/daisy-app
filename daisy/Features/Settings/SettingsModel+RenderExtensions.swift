//
//  SettingsModel+RenderExtensions.swift
//  daisy
//
//  Toggle helpers for the Extensions settings pane.
//

extension SettingsModel {
    func isRenderExtensionEnabled(_ id: String) -> Bool {
        enabledRenderExtensionIDs.contains(id)
    }

    func setRenderExtensionEnabled(_ enabled: Bool, id: String) {
        guard enabled != isRenderExtensionEnabled(id) else { return }
        if enabled {
            enabledRenderExtensionIDs.insert(id)
        } else {
            enabledRenderExtensionIDs.remove(id)
        }
        appDelegate?.applyRenderExtensionPreferences(enabledRenderExtensionIDs)
    }
}
