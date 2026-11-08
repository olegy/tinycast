import Foundation

/// Retires Window Management: its defaults, shortcuts, launcher references, the room-parking
/// ledger, and the `windowManagement` section settings.json would report.
enum WindowManagementRemovalMigration {
    static func run(
        settingsFileEnabled: Bool, applicationSupport: URL, defaults: UserDefaults = .standard
    ) {
        for key in retiredDefaults(in: defaults.dictionaryRepresentation().keys) {
            defaults.removeObject(forKey: key)
        }
        for key in listKeys {
            guard let stored = defaults.stringArray(forKey: key), let kept = kept(stored)
            else { continue }
            defaults.set(kept, forKey: key)
        }
        if let aliases = defaults.dictionary(forKey: aliasesKey) as? [String: String],
            let kept = keptAliases(aliases)
        {
            defaults.set(kept, forKey: aliasesKey)
        }
        try? FileManager.default.removeItem(
            at: applicationSupport.appendingPathComponent("room-parking.json"))
        guard settingsFileEnabled else { return }
        let url = AppPaths.settingsFile()
        guard let data = try? Data(contentsOf: url), let migrated = migrated(data) else { return }
        try? migrated.write(to: url.resolvingSymlinksInPath(), options: .atomic)
    }

    static func retiredDefaults(in keys: some Sequence<String>) -> [String] {
        let fixed: Set = [
            "windowManagementEnabled", "windowManagementShowInLauncher", "windowManagementGap",
            "windowManagementCycleMode", "windowManagementWrapDisplays",
            "windowManagementKeepProportions", "windowLayoutsShowInLauncher",
            "windowRoomsShowInLauncher", "windowLayouts", "windowRooms", "customWindowSizes",
            "roomMinimumWindowSizes", "boundWindowLayoutIDs", "boundWindowRoomIDs",
            "boundCustomWindowSizeIDs"
        ]
        let hotkeyPrefixes = [
            "hotkey.windowCommand.", "hotkey.windowLayout.", "hotkey.windowRoom.",
            "hotkey.customWindowSize."
        ]
        let commandHotkeys = Set(retiredCommands.map { "hotkey." + $0 })
        return keys.filter { key in
            fixed.contains(key) || commandHotkeys.contains(key)
                || hotkeyPrefixes.contains { key.hasPrefix($0) }
        }.sorted()
    }

    /// Nil when nothing in the list named a retired row, kind or link.
    static func kept(_ stored: [String]) -> [String]? {
        let kept = stored.filter { !isRetired($0) }
        return kept == stored ? nil : kept
    }

    static func keptAliases(_ aliases: [String: String]) -> [String: String]? {
        let kept = aliases.filter { !isRetired($0.key) }
        return kept.count == aliases.count ? nil : kept
    }

    /// Nil when nothing changes, or the file has other problems, which the import must report.
    static func migrated(_ data: Data) -> Data? {
        guard let parsed = try? SettingsFileFormat.parse(data), !parsed.issues.isEmpty,
            parsed.issues.allSatisfy({ $0 == .unknownSetting("windowManagement") })
        else { return nil }
        return SettingsFileFormat.render(parsed.values)
    }

    private static func isRetired(_ value: String) -> Bool {
        retiredKinds.contains(value) || retiredCommands.contains(value)
            || entryPrefixes.contains { value.hasPrefix($0) }
    }

    private static let listKeys = [
        "hiddenLauncherItems", "hiddenLauncherKinds", "favoriteApps", "allowedDeepLinks"
    ]
    private static let aliasesKey = "launcherAliases"
    private static let retiredKinds: Set = ["windowCommand", "windowLayout", "windowRoom"]
    /// `window-size` alone is the consent key the custom-size link was remembered under.
    private static let entryPrefixes = [
        "window-command:", "window-layout:", "window-room:", "window-size"
    ]
    private static let retiredCommands: Set = [
        "command:create-window-layout", "command:capture-window-layout", "command:switch-room",
        "command:create-room"
    ]
}
