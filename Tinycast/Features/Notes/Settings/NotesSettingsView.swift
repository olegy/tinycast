import SwiftUI

struct NotesSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                Toggle(isOn: $settings.notesEnabled) {
                    SettingsFeatureToggleLabel(
                        anchor: .notesNotes, title: "Enable Notes",
                        subtitle: "Plain Markdown in a floating editor.")
                }
            }
            .settingsAnchor(.notesNotes)

            Section {
                Picker(selection: $settings.notesWindowMode) {
                    ForEach(NoteWindowMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                } label: {
                    SettingsRowTitle(.notesOptions, "Window")
                    Text(settings.notesWindowMode.detail)
                }
                .settingsEnabled(settings.notesEnabled)
                LabeledContent {
                    HStack(spacing: Theme.Spacing.md) {
                        if settings.notesPaper.takesTint { NoteTintSwatches(tint: $settings.notesTint) }
                        Picker(selection: $settings.notesPaper) {
                            ForEach(NotePaper.allCases) { paper in
                                Text(paper.title).tag(paper)
                            }
                        } label: {
                            Text("Paper")
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                } label: {
                    SettingsRowTitle(.notesOptions, "Paper")
                    Text(settings.notesPaper.detail)
                }
                .settingsEnabled(settings.notesEnabled)
                Toggle(isOn: $settings.notesRendersMarkdown) {
                    SettingsRowTitle(.notesOptions, "Render Markdown")
                    Text("Formats as you type.")
                }
                .settingsEnabled(settings.notesEnabled)
                Toggle(isOn: $settings.notesFitsWindowToText) {
                    SettingsRowTitle(.notesOptions, "Fit Window to Text")
                    Text("Off keeps the size you set.")
                }
                .settingsEnabled(settings.notesEnabled)
                Toggle(isOn: $settings.notesShowsTitleBarButtons) {
                    SettingsRowTitle(.notesOptions, "Show Title Bar Buttons")
                }
                .settingsEnabled(settings.notesEnabled)
                Toggle(isOn: $settings.notesShowsFormattingBar) {
                    SettingsRowTitle(.notesOptions, "Show Formatting Bar")
                }
                .settingsEnabled(settings.notesEnabled && settings.notesRendersMarkdown)
                Toggle(isOn: $settings.notesShowsCharacterCount) {
                    SettingsRowTitle(.notesOptions, "Show Character Count")
                }
                .settingsEnabled(settings.notesEnabled)
                LabeledContent {
                    Slider(value: textSizeStep, in: 0...Double(NoteTextSize.allCases.count - 1), step: 1)
                        .frame(width: Self.textSizeSliderWidth)
                        .accessibilityValue(Text(verbatim: "\(Int(settings.notesTextSize.pointSize)) pt"))
                } label: {
                    SettingsRowTitle(.notesOptions, "Text Size")
                }
                .settingsEnabled(settings.notesEnabled)
                LabeledContent {
                    if settings.notesFolder != nil {
                        Button(
                            String(localized: "notes-use-default-folder", defaultValue: "Use Default"),
                            action: core.notesCoordinator.resetNotesFolder)
                    }
                    Button("Choose…", action: core.notesCoordinator.chooseNotesFolder)
                } label: {
                    SettingsRowTitle(.notesOptions, "Notes Folder")
                    Text((core.notesStore.notesDirectory.path as NSString).abbreviatingWithTildeInPath)
                }
            } header: {
                SettingsSectionHeader(.notesOptions)
            }

            FeatureCommandsSection(owner: .notes, anchor: .notesCommands)
                .settingsEnabled(settings.notesEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.notes)
    }

    private static let textSizeSliderWidth: CGFloat = 200

    /// The slider moves by whole steps, one per `NoteTextSize` case.
    private var textSizeStep: Binding<Double> {
        let sizes = NoteTextSize.allCases
        return Binding(
            get: { Double(sizes.firstIndex(of: settings.notesTextSize) ?? 0) },
            set: { settings.notesTextSize = sizes[min(max(Int($0.rounded()), 0), sizes.count - 1)] })
    }
}

/// One swatch per tint, the plain paper first; the chosen one wears a ring.
private struct NoteTintSwatches: View {
    @Binding var tint: NoteTint

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(NoteTint.allCases) { option in
                Button { tint = option } label: { swatch(option) }
                    .buttonStyle(.plain)
                    .help(option.title)
                    .accessibilityLabel(option.title)
                    .accessibilityAddTraits(option == tint ? .isSelected : [])
            }
        }
    }

    private func swatch(_ option: NoteTint) -> some View {
        Circle()
            .fill(option.color ?? Theme.Colors.controlSurface)
            .overlay { Circle().strokeBorder(Theme.Colors.border, lineWidth: 1) }
            .frame(width: Self.diameter, height: Self.diameter)
            .padding(Self.ringGap)
            .overlay {
                if option == tint { Circle().strokeBorder(Color.accentColor, lineWidth: 2) }
            }
            .contentShape(Circle())
    }

    private static let diameter: CGFloat = 14
    private static let ringGap: CGFloat = 3
}
