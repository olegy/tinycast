import SwiftUI
import UniformTypeIdentifiers

struct SnippetsSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        return Form {
            FeatureSwitchSection(
                anchor: .snippetsSnippets,
                enableTitle: "Enable Snippets",
                enableSubtitle: "Search Markdown files in your folders, then copy or paste them.",
                isEnabled: $settings.snippetsEnabled,
                showsInLauncher: $settings.snippetsShowInLauncher,
                showsIcon: true,
                showsHeader: false)

            Group {
                FeatureCommandsSection(owner: .snippets, anchor: .snippetsCommands)
                SnippetFoldersSection()
                SnippetExcludesSection()
                SnippetEditorSection()
            }
            .settingsEnabled(settings.snippetsEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.snippets)
    }
}

private let home = FileManager.default.homeDirectoryForCurrentUser

private struct SnippetFoldersSection: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppCore.self) private var core
    /// Recomputed only on change: a `fileExists` per row is too much per body render.
    @State private var missing: Set<String> = []

    var body: some View {
        Section {
            ForEach(settings.snippetFolders, id: \.self) { folder in
                SettingsScopeRow(
                    scope: name(of: folder),
                    path: FileSearchScope.expand(folder, homeDirectory: home).path,
                    isMissing: missing.contains(folder)
                ) {
                    settings.snippetFolders.removeAll { $0 == folder }
                }
            }
            Button("Add…", action: addFolders)
                .help("Add a folder of Markdown snippets.")
        } header: {
            SettingsSectionHeader(.snippetsFolders)
        } footer: {
            Text(
                """
                Every .md file in these folders and their subfolders is a snippet. Subfolder names \
                become tags. A .vault.json file at a folder's root can give it a name and an icon: \
                {"name": "Work", "icon": "hammer"}.
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onAppear(perform: refreshMissing)
        .onChange(of: settings.snippetFolders) { _, _ in refreshMissing() }
    }

    private func name(of folder: String) -> String {
        let root = FileSearchScope.expand(folder, homeDirectory: home).standardizedFileURL.path
        return core.snippetStore.sources.first { $0.root == root }?.name ?? folder
    }

    private func refreshMissing() {
        missing = Set(
            settings.snippetFolders.filter {
                !FileManager.default.fileExists(atPath: FileSearchScope.expand($0, homeDirectory: home).path)
            })
    }

    private func addFolders() {
        guard let urls = chooseFolders(message: String(localized: "Choose folders of Markdown snippets."))
        else { return }
        let added = urls.map { FileSearchScope.abbreviate($0.standardizedFileURL.path, homeDirectory: home) }
        settings.snippetFolders += added.filter { !settings.snippetFolders.contains($0) }
    }
}

private struct SnippetExcludesSection: View {
    @Environment(AppSettings.self) private var settings
    @State private var draft = ""

    var body: some View {
        Section {
            ForEach(settings.snippetExcludePatterns, id: \.self) { pattern in
                LabeledContent {
                    Button {
                        settings.snippetExcludePatterns.removeAll { $0 == pattern }
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(pattern)")
                } label: {
                    Text(pattern).lineLimit(1).truncationMode(.middle)
                }
            }
            // Titled, a grouped form squeezes the field into a sliver too narrow to click.
            HStack(spacing: Theme.Spacing.lg) {
                TextField("Pattern", text: $draft, prompt: Text("Templates, Archive* or ~/notes/old"))
                    .labelsHidden()
                    .onSubmit { add(draft) }
                Button("Add") { add(draft) }
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Add Folder…", action: addFolders)
                    .help("Skip a folder and everything in it.")
            }
        } header: {
            SettingsSectionHeader(.snippetsExcludedFolders)
        } footer: {
            Text(
                """
                Matching folders are skipped in every snippets folder. A name like Templates matches \
                anywhere; a path like ~/notes/old skips that folder. Folders starting with a dot are \
                always skipped.
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func addFolders() {
        guard let urls = chooseFolders(message: String(localized: "Choose folders to leave out."))
        else { return }
        for url in urls {
            add(FileSearchScope.abbreviate(url.standardizedFileURL.path, homeDirectory: home))
        }
    }

    private func add(_ text: String) {
        let pattern = text.trimmingCharacters(in: .whitespaces)
        draft = ""
        guard !pattern.isEmpty, !settings.snippetExcludePatterns.contains(pattern) else { return }
        settings.snippetExcludePatterns.append(pattern)
    }
}

private struct SnippetEditorSection: View {
    @Environment(AppSettings.self) private var settings
    @State private var apps: [(bundleID: String, name: String)] = []

    var body: some View {
        @Bindable var settings = settings
        return Section {
            Picker(selection: $settings.snippetEditorBundleID) {
                Text("Default App").tag(String?.none)
                ForEach(apps, id: \.bundleID) { app in
                    Text(app.name).tag(String?.some(app.bundleID))
                }
            } label: {
                SettingsRowTitle(.snippetsEditor, "Open Snippets With")
            }
        } header: {
            SettingsSectionHeader(.snippetsEditor)
        } footer: {
            Text("Used by Open in Editor (⇧⌘E). Default App is the one macOS opens Markdown files with.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear(perform: loadApps)
    }

    private func loadApps() {
        let type = UTType(filenameExtension: "md") ?? .plainText
        var seen = Set<String>()
        apps = NSWorkspace.shared.urlsForApplications(toOpen: type).compactMap { url in
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, seen.insert(id).inserted
            else { return nil }
            return (id, FileManager.default.displayName(atPath: url.path))
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if let current = settings.snippetEditorBundleID, !seen.contains(current) {
            apps.append((current, current))
        }
    }
}

@MainActor
private func chooseFolders(message: String) -> [URL]? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = true
    panel.prompt = String(localized: "Add")
    panel.message = message
    // Tinycast is an accessory app, so the panel opens behind the frontmost app without this.
    NSApp.activate()
    guard panel.runModal() == .OK else { return nil }
    return panel.urls
}
