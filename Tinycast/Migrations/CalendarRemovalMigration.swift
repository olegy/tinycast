import Foundation

/// Retires Calendar: its defaults and hotkeys, and the `calendar` section settings.json reports.
enum CalendarRemovalMigration {
    static func run(settingsFileEnabled: Bool, defaults: UserDefaults = .standard) {
        for key in retiredDefaults(in: defaults.dictionaryRepresentation().keys) {
            defaults.removeObject(forKey: key)
        }
        if let stored = defaults.stringArray(forKey: compactBarKey),
            let kept = keptCompactBar(stored)
        {
            defaults.set(kept, forKey: compactBarKey)
        }
        guard settingsFileEnabled else { return }
        let url = AppPaths.settingsFile()
        guard let data = try? Data(contentsOf: url), let migrated = migrated(data) else { return }
        try? migrated.write(to: url.resolvingSymlinksInPath(), options: .atomic)
    }

    static func retiredDefaults(in keys: some Sequence<String>) -> [String] {
        let fixed: Set = [
            "calendarEnabled", "calendarShowInLauncher", "calendarLauncherLimit", "calendarSpan",
            "joinWindowMinutes", "autoJoinMeetings", "autoJoinConfirms", "autoJoinNamedProvidersOnly",
            "cameraPreview", "meetingBrowser", "menuBarEvents", "calendarMenuBarDisplay",
            "menuBarLinkedEventsOnly", "calendarMenuBarHidesWhenEmpty", "hideCurrentEvent",
            "hiddenMeetingCalendars"
        ]
        let hotkeys = Set(retiredCommands.map { "hotkey." + $0 })
        return keys.filter { fixed.contains($0) || hotkeys.contains($0) }.sorted()
    }

    /// Nil when nothing changes, or the file has other problems, which the import must report.
    static func migrated(_ data: Data) -> Data? {
        guard var parsed = try? SettingsFileFormat.parse(data),
            parsed.issues.allSatisfy({ $0 == .unknownSetting("calendar") })
        else { return nil }
        var changed = !parsed.issues.isEmpty
        if case .array(let commands) = parsed.values[.compactBarCommands] {
            let kept = commands.filter { !retiredCommands.map(SettingsFileJSON.string).contains($0) }
            if kept != commands {
                parsed.values[.compactBarCommands] = .array(kept)
                changed = true
            }
        }
        return changed ? SettingsFileFormat.render(parsed.values) : nil
    }

    /// Nil when the stored list never named a retired command.
    static func keptCompactBar(_ stored: [String]) -> [String]? {
        let kept = stored.filter { !retiredCommands.contains($0) }
        return kept == stored ? nil : kept
    }

    private static let compactBarKey = "compactBarCommands"

    private static let retiredCommands = [
        "command:join-next-meeting", "command:my-schedule", "command:create-event",
        "command:copy-meeting-link", "command:open-in-calendar"
    ]
}
