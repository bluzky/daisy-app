//
//  GeneralSettingsView.swift
//  daisy
//

import SwiftUI

// MARK: - General

struct GeneralSettingsView: View {
    @Bindable private var model = SettingsModel.shared

    var body: some View {
        Form {
            Section {
                Picker(L("Language"), selection: $model.appLanguage) {
                    Text(L("System Default")).tag(AppLanguageSetting.systemDefault)
                    ForEach(AppLanguageSetting.availableLanguages(), id: \.self) { language in
                        Text(verbatim: AppLanguageSetting.displayName(for: language)).tag(language)
                    }
                }
            } header: {
                Text(L("Language"))
            } footer: {
                Text(L("Quit and reopen Daisy to apply language changes. This setting only affects the app, not Quick Look previews."))
            }

            Section {
                Picker(selection: $model.launchBehavior) {
                    Text(L("Show the Open dialog")).tag(LaunchBehaviorSetting.showOpenPanel)
                    Text(L("Create a new document")).tag(LaunchBehaviorSetting.newDocument)
                    Text(L("Reopen last folder and file")).tag(LaunchBehaviorSetting.reopenLastSession)
                    Text(L("Open a specific file or folder")).tag(LaunchBehaviorSetting.openChosenItem)
                } label: {
                    Text(L("On launch"))
                    Text(L("What Daisy opens when it starts or you click its Dock icon with no window open. Opening a file from Finder always opens that file."))
                }
                .pickerStyle(.menu)

                if model.launchBehavior == .openChosenItem {
                    LabeledContent {
                        Button(L("Choose…")) { model.chooseLaunchItem() }
                    } label: {
                        Text(L("File or folder"))
                        Text(model.launchItemPath ?? L("Not found. Choose it again."))
                    }
                }
            } header: {
                Text(L("Startup"))
            }

            Section {
                Toggle(isOn: $model.isAlwaysOnTop) {
                    Text(L("Always on Top"))
                    Text(L("Keeps every Daisy window in front of other apps, including windows you open later. A window in full screen is left alone until it comes back out."))
                }

                Toggle(isOn: $model.opensMarkdownLinksInNewWindows) {
                    Text(L("Open Markdown links in new windows"))
                    Text(L("Clicking a link to another Markdown file opens it in a separate window. Turn this off to open it in the current window."))
                }
            } header: {
                Text(L("Windows"))
            }

            Section {
                Toggle(isOn: $model.quickCaptureEnabled) {
                    Text(L("Quick Capture shortcut"))
                    Text(L("Press the shortcut in any app to open Inbox.md in Daisy with a new dated heading, ready to type."))
                }

                LabeledContent {
                    HStack {
                        ShortcutRecorderView(shortcut: model.quickCaptureShortcut) {
                            model.setQuickCaptureShortcut($0)
                        }
                        Button(L("Reset")) {
                            model.setQuickCaptureShortcut(.default)
                        }
                        .disabled(model.quickCaptureShortcut == .default)
                    }
                } label: {
                    Text(L("Shortcut"))
                    if let error = model.quickCaptureShortcutError {
                        Text(error).foregroundStyle(.red)
                    }
                }
                .disabled(!model.quickCaptureEnabled)

                LabeledContent {
                    Button(L("Choose…")) { model.chooseQuickCaptureFolder() }
                } label: {
                    Text(L("Capture folder"))
                    Text(model.quickCaptureFolderPath ?? L("Not chosen yet"))
                }
            } header: {
                Text(L("Quick Capture"))
            } footer: {
                Text(L("Daisy has to keep running to listen for the shortcut."))
            }

            Section {
                LabeledContent {
                    HStack {
                        Button(L("Choose…")) { model.chooseTemplateFile() }
                        Button(L("Clear")) { model.clearTemplateFile() }
                            .disabled(model.templateFilePath == nil)
                    }
                } label: {
                    Text(L("Template file"))
                    Text(model.templateFilePath ?? L("Not chosen yet"))
                    if model.templateFilePath != nil {
                        Text(model.templateCount == 0
                             ? L("No templates found. Add a <!-- template: Name --> line or a ## heading for each one.")
                             : String(format: L("%d templates found"), model.templateCount))
                            .foregroundStyle(model.templateCount == 0 ? .red : .secondary)
                    }
                }
            } header: {
                Text(L("Templates"))
            } footer: {
                Text(L("A template starts at a <!-- template: Name --> line, or at each ## heading if the file has no such line. Insert one from the Templates entry in the slash menu while editing."))
            }

            Section {
                LabeledContent {
                    TextField("", text: $model.textFileEntries, prompt: Text("lua, php, Justfile"))
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        .onSubmit { model.applyTextFileEntries() }
                } label: {
                    Text(L("Also edit as code"))
                    Text(L("Extensions or file names, separated by commas."))
                }
            } header: {
                Text(L("Code and text files"))
            } footer: {
                Text(L("Daisy edits common source and text files without a preview, and opens other files in their default app. Files over 5 MB, or not UTF-8, always open in the default app."))
            }
            .onDisappear { model.applyTextFileEntries() }

            Section {
                LabeledContent {
                    Picker("", selection: $model.autoSaveIntervalMinutes) {
                        Text(L("Never")).tag(AutoSaveSetting.disabledMinutes)
                        Text(L("30 seconds")).tag(AutoSaveSetting.thirtySeconds)
                        Text(L("1 minute")).tag(1)
                        ForEach([5, 10, 15, 30, 60], id: \.self) { minutes in
                            Text(String(format: L("%d minutes"), minutes))
                                .tag(minutes)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                } label: {
                    Text(L("Automatic saving"))
                    Text(L("Save edited documents periodically."))
                }
            } header: {
                Text(L("Saving"))
            } footer: {
                Text(L("Automatic saving runs while a document has unsaved edits."))
            }

            Section {
                if model.openTargets.isEmpty {
                    LabeledContent(L("Open documents in")) {
                        Text(L("No apps available")).foregroundStyle(.secondary)
                    }
                } else {
                    Picker(L("Open documents in"), selection: $model.openTargetID) {
                        aiAppItems
                        editorItems
                    }
                }

                LabeledContent(L("Command line tools")) {
                    Button(L("Install…")) {
                        appDelegate?.installCommandLineToolsFromSettings()
                    }
                }
            } header: {
                Text(L("External apps & tools"))
            } footer: {
                Text(L("The app the Open button in the document toolbar uses first. Its menu still offers every other installed app."))
                Text(L("Adds the daisy command to your PATH. Run it again after updating the app to refresh it."))
            }

            Section {
                Button(L("Reset App Link Approvals")) {
                    ExternalLinkPolicy.reset(defaults: AppearanceMode.sharedDefaults())
                }
            } header: {
                Text(L("App links"))
            } footer: {
                Text(L("Ask again before opening custom app links. Approvals are saved per URL scheme and shared with Quick Look."))
            }
        }
        .formStyle(.grouped)
        .onAppear {
            model.refreshFromExternalSources()
            model.reloadOpenTargets()
        }
        .onReceive(NotificationCenter.default.publisher(for: TemplateStore.didChangeNotification)) { _ in
            model.refreshTemplates()
        }
    }

    @ViewBuilder
    private var aiAppItems: some View {
        let apps = model.openTargets.filter(\.isAIApp)
        if !apps.isEmpty {
            Section(L("AI apps")) {
                ForEach(apps) { choice in
                    openTargetRow(choice)
                }
            }
        }
    }

    @ViewBuilder
    private var editorItems: some View {
        let editors = model.openTargets.filter { !$0.isAIApp }
        if !editors.isEmpty {
            Section(L("Editors")) {
                ForEach(editors) { choice in
                    openTargetRow(choice)
                }
            }
        }
    }

    private func openTargetRow(_ choice: OpenTargetChoice) -> some View {
        HStack {
            Image(nsImage: choice.icon)
            Text(choice.title)
        }
        .tag(choice.id)
    }
}
