import Foundation

/// Retires the Escape Key Behavior preference: its default and its key in settings.json.
enum EscapeKeyBehaviorRemovalMigration {
    static func run(settingsFileEnabled: Bool, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
        guard settingsFileEnabled else { return }
        let url = AppPaths.settingsFile()
        guard let data = try? Data(contentsOf: url), let migrated = migrated(data) else { return }
        try? migrated.write(to: url.resolvingSymlinksInPath(), options: .atomic)
    }

    /// Nil when the key is absent, or the file has other problems, which the import must report.
    static func migrated(_ data: Data) -> Data? {
        guard let parsed = try? SettingsFileFormat.parse(data), !parsed.issues.isEmpty,
            parsed.issues.allSatisfy({ $0 == .unknownSetting(fileKey) })
        else { return nil }
        return SettingsFileFormat.render(parsed.values)
    }

    static let defaultsKey = "escapeKeyBehavior"
    private static let fileKey = "general.escapeKeyBehavior"
}
