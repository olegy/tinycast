import Foundation

/// Retires Raycast themes: their defaults and the Theme command Tinycast wrote into extensions.
enum ThemesRemovalMigration {
    static func run(extensionsDirectory: URL, defaults: UserDefaults = .standard) {
        for key in retiredDefaults(in: defaults.dictionaryRepresentation().keys) {
            defaults.removeObject(forKey: key)
        }
        let command = extensionsDirectory.appendingPathComponent(commandFolder, isDirectory: true)
        try? FileManager.default.removeItem(at: command)
    }

    static func retiredDefaults(in keys: some Sequence<String>) -> [String] {
        let fixed: Set = [
            "spaceRaycastThemeLight", "spaceRaycastThemeDark", "spaceRaycastThemesImported",
            "spaceRaycastThemeBackgroundOpacity"
        ]
        return keys.filter { fixed.contains($0) }.sorted()
    }

    static let commandFolder = "tinycast-space-themes"
}
