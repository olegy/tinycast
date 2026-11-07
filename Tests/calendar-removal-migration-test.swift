import Foundation

@main
@MainActor
struct CalendarRemovalMigrationTest {
    static var failures = 0

    static func main() throws {
        let retired = file(extra: #", "calendar": { "showInLauncher": true, "commands": {} }"#)
        let rewrite = CalendarRemovalMigration.migrated(retired)
        check("a file with the calendar section is rewritten", rewrite != nil)
        if let rewrite {
            let parsed = try SettingsFileFormat.parse(rewrite)
            let original = try SettingsFileFormat.parse(retired)
            check("the rewrite reports nothing", parsed.issues.isEmpty)
            check("the rewrite keeps every other value", parsed.values == original.values)
        }

        let bar = file(
            appearance: #""compactBarCommands": ["command:my-schedule", "command:search-files"]"#)
        let barRewrite = CalendarRemovalMigration.migrated(bar).flatMap {
            try? SettingsFileFormat.parse($0)
        }
        check(
            "My Schedule leaves the compact bar and the rest stays",
            barRewrite?.values[.compactBarCommands] == .array([.string("command:search-files")]))

        let typo = file(appearance: #""compactMod": true"#, extra: #", "calendar": {}"#)
        check("another unknown key leaves the file to the import", migrated(typo) == nil)
        check("a file without the section is left alone", migrated(file()) == nil)
        check("invalid JSON is left alone", migrated(Data("{".utf8)) == nil)

        let keys = [
            "calendarEnabled", "autoJoinMeetings", "cameraPreview", "hiddenMeetingCalendars",
            "hotkey.command:join-next-meeting", "hotkey.command:clipboard-history", "quicklinksEnabled"
        ]
        check(
            "only the calendar defaults retire",
            CalendarRemovalMigration.retiredDefaults(in: keys) == [
                "autoJoinMeetings", "calendarEnabled", "cameraPreview", "hiddenMeetingCalendars",
                "hotkey.command:join-next-meeting"
            ])
        check(
            "the stored compact bar drops only the retired command",
            CalendarRemovalMigration.keptCompactBar(["command:my-schedule", "command:search-emoji"])
                == ["command:search-emoji"])
        check(
            "a compact bar without it is left alone",
            CalendarRemovalMigration.keptCompactBar(["command:search-emoji"]) == nil)

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    private static func migrated(_ data: Data) -> Data? {
        CalendarRemovalMigration.migrated(data)
    }

    private static func file(appearance: String = #""compactMode": true"#, extra: String = "") -> Data {
        Data(
            #"{ "general": { "language": "en" }, "appearance": { \#(appearance) }\#(extra) }"#.utf8)
    }

    private static func check(_ description: String, _ condition: @autoclosure () -> Bool) {
        if condition() {
            print("PASS  \(description)")
        } else {
            print("FAIL  \(description)")
            failures += 1
        }
    }
}
