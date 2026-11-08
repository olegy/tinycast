import Foundation

@main
@MainActor
struct WindowManagementRemovalMigrationTest {
    static var failures = 0

    static func main() throws {
        let retired = file(extra: #", "windowManagement": { "enabled": true, "gap": 8 }"#)
        let rewrite = WindowManagementRemovalMigration.migrated(retired)
        check("a file with the windowManagement section is rewritten", rewrite != nil)
        if let rewrite {
            let parsed = try SettingsFileFormat.parse(rewrite)
            let original = try SettingsFileFormat.parse(retired)
            check("the rewrite reports nothing", parsed.issues.isEmpty)
            check("the rewrite keeps every other value", parsed.values == original.values)
        }
        let typo = file(appearance: #""compactMod": true"#, extra: #", "windowManagement": {}"#)
        check("another unknown key leaves the file to the import", migrated(typo) == nil)
        check("a file without the section is left alone", migrated(file()) == nil)
        check("invalid JSON is left alone", migrated(Data("{".utf8)) == nil)

        let keys = [
            "windowManagementEnabled", "windowManagementGap", "windowRooms", "customWindowSizes",
            "boundWindowLayoutIDs", "hotkey.windowCommand.left-half",
            "hotkey.customWindowSize.0a1b", "hotkey.command:switch-room",
            "hotkey.command:clipboard-history", "hotkey.command:switch-windows", "quicklinksEnabled"
        ]
        check(
            "only the window management defaults retire",
            WindowManagementRemovalMigration.retiredDefaults(in: keys) == [
                "boundWindowLayoutIDs", "customWindowSizes", "hotkey.command:switch-room",
                "hotkey.customWindowSize.0a1b", "hotkey.windowCommand.left-half",
                "windowManagementEnabled", "windowManagementGap", "windowRooms"
            ])
        check(
            "lists drop retired rows, kinds and links and keep the rest",
            WindowManagementRemovalMigration.kept([
                "window-command:left-half", "windowRoom", "window-size", "window-layout:ab",
                "command:create-room", "command:switch-windows", "systemAction", "quicklink:x"
            ]) == ["command:switch-windows", "systemAction", "quicklink:x"])
        check(
            "a list without them is left alone",
            WindowManagementRemovalMigration.kept(["command:search-emoji"]) == nil)
        check(
            "aliases of retired rows go",
            WindowManagementRemovalMigration.keptAliases([
                "window-room:ab": "work", "command:search-emoji": "em"
            ]) == ["command:search-emoji": "em"])
        check(
            "aliases without them are left alone",
            WindowManagementRemovalMigration.keptAliases(["command:search-emoji": "em"]) == nil)

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    private static func migrated(_ data: Data) -> Data? {
        WindowManagementRemovalMigration.migrated(data)
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
