//
//  RenderExtensionsSettingsView.swift
//  daisy
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

            journalSection
        }
        .formStyle(.grouped)
        .onAppear {
            model.refreshFromExternalSources()
        }
        .onReceive(NotificationCenter.default.publisher(for: TemplateStore.didChangeNotification)) { _ in
            model.refreshTemplates()
        }
    }

    /// The Journal extension: on or off, and the template new entries use.
    private var journalSection: some View {
        Section {
            Toggle(isOn: $model.journalEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Journal"))
                    Text(L("Workspace windows"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            LabeledContent {
                Picker("", selection: $model.journalTemplateName) {
                    Text(L("None")).tag(String?.none)
                    if let name = model.journalTemplateName, !model.templateNames.contains(name) {
                        Text(String(format: L("%@ (not found)"), name)).tag(String?.some(name))
                    }
                    ForEach(model.templateNames, id: \.self) { name in
                        Text(name).tag(String?.some(name))
                    }
                }
                .labelsHidden()
                .fixedSize()
            } label: {
                Text(L("New entry template"))
                Text(model.templateFilePath == nil
                     ? L("Choose a template file in General to use one.")
                     : L("Used when an entry is first created."))
            }
            .disabled(!model.journalEnabled)
            Toggle(isOn: $model.journalCarryOverEnabled) {
                Text(L("Carry over unfinished tasks"))
                Text(L("Today’s new entry takes the unchecked tasks from earlier entries, which lose them."))
            }
            .disabled(!model.journalEnabled)
            Stepper(value: $model.journalCarryOverDays, in: JournalSetting.carryOverDayRange) {
                LabeledContent(L("Days to look back"), value: "\(model.journalCarryOverDays)")
            }
            .disabled(!model.journalEnabled || !model.journalCarryOverEnabled)
        } header: {
            Text(L("Workspace"))
        } footer: {
            Text(L("The Journal button in the toolbar and the Go menu open one Markdown file per day in the workspace’s journals folder. In a template, {{date}} and {{weekday}} are the entry’s day and {{carryover}} places carried-over tasks. With no template, an entry starts with just its date."))
        }
    }
}
