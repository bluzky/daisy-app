//
//  RenderExtensionsSettingsView.swift
//  md-preview
//

import SwiftUI

extension SettingsPaneIcon {
    var extensionTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4.4, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .frame(width: 20, height: 20)
            Image(systemName: "puzzlepiece.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
        }
    }
}

struct RenderExtensionsSettingsView: View {
    @Bindable private var model = SettingsModel.shared

    /// Which surfaces an extension changes, derived from its capabilities.
    private static func surfaceCaption(for renderExtension: any MarkdownRenderExtension) -> String {
        switch (renderExtension.affectsPreview, renderExtension.editor != nil) {
        case (true, true): "Preview & Editor"
        case (true, false): "Preview"
        default: "Editor"
        }
    }

    var body: some View {
        Form {
            Section {
                ForEach(
                    MarkdownHTML.renderExtensions.filter(\.descriptor.userToggleable),
                    id: \.id
                ) { renderExtension in
                    Toggle(
                        isOn: Binding(
                            get: { model.isRenderExtensionEnabled(renderExtension.id) },
                            set: { model.setRenderExtensionEnabled($0, id: renderExtension.id) }
                        )
                    ) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(MarkdownHTML.renderExtensionTitle(for: renderExtension.id))
                            Text(L(Self.surfaceCaption(for: renderExtension)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text(L("Markdown rendering"))
            } footer: {
                Text(L("These settings apply to document windows and Quick Look previews. Extensions marked Preview & Editor also apply in editor mode."))
            }
        }
        .formStyle(.grouped)
        .onAppear {
            model.refreshFromExternalSources()
        }
    }
}
