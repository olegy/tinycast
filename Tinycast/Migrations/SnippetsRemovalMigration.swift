import Foundation

/// Retires Snippets: its defaults and hotkeys, and the `snippets` section settings.json reports.
enum SnippetsRemovalMigration {
    static func run(settingsFileEnabled: Bool, defaults: UserDefaults = .standard) {
        for key in retiredDefaults(in: defaults.dictionaryRepresentation().keys) {
            defaults.removeObject(forKey: key)
        }
        guard settingsFileEnabled else { return }
        let url = AppPaths.settingsFile()
        guard let data = try? Data(contentsOf: url), let migrated = migrated(data) else { return }
        try? migrated.write(to: url.resolvingSymlinksInPath(), options: .atomic)
    }

    static func retiredDefaults(in keys: some Sequence<String>) -> [String] {
        let fixed: Set = [
            "snippetsEnabled", "snippetsShowInLauncher", "snippetsFolder", "boundSnippetIDs",
            "hotkey.command:search-snippets", "hotkey.command:create-snippet"
        ]
        return keys.filter { fixed.contains($0) || $0.hasPrefix("hotkey.snippet.") }.sorted()
    }

    /// Nil when the section is absent or the file has other problems, which the import must report.
    static func migrated(_ data: Data) -> Data? {
        guard let parsed = try? SettingsFileFormat.parse(data),
            parsed.issues.contains(.unknownSetting("snippets")),
            parsed.issues.allSatisfy({ retiredIssues.contains($0) })
        else { return nil }
        return SettingsFileFormat.render(parsed.values)
    }

    // Notes and compact favorites retire in the same release, so they must not block the rewrite.
    private static let retiredIssues: [SettingsFileIssue] = [
        .unknownSetting("snippets"), .unknownSetting("notes"),
        .unknownSetting("appearance.showFavoritesInCompactMode")
    ]
}
