import Foundation

@main
@MainActor
struct SnippetsRemovalMigrationTest {
    static var failures = 0

    static func main() throws {
        let retired = file(extra: #", "snippets": { "showInLauncher": true, "commands": {} }"#)
        let rewrite = SnippetsRemovalMigration.migrated(retired)
        check("a file with the snippets section is rewritten", rewrite != nil)
        if let rewrite {
            let parsed = try SettingsFileFormat.parse(rewrite)
            let original = try SettingsFileFormat.parse(retired)
            check("the rewrite reports nothing", parsed.issues.isEmpty)
            check("the rewrite keeps every other value", parsed.values == original.values)
        }

        let both = file(
            appearance: #""showFavoritesInCompactMode": true, "compactMode": true"#,
            extra: #", "snippets": {}, "notes": { "enabled": true }"#)
        check(
            "the Notes section and compact favorites key retiring alongside it do not block it",
            migrated(both).map { (try? SettingsFileFormat.parse($0))?.issues.isEmpty } == true)

        let typo = file(appearance: #""compactMod": true"#, extra: #", "snippets": {}"#)
        check("another unknown key leaves the file to the import", migrated(typo) == nil)
        check("a file without the section is left alone", migrated(file()) == nil)
        check("invalid JSON is left alone", migrated(Data("{".utf8)) == nil)

        let keys = [
            "snippetsEnabled", "snippetsFolder", "boundSnippetIDs", "hotkey.snippet./tmp/a.md",
            "hotkey.command:search-snippets", "hotkey.command:clipboard-history", "quicklinksEnabled"
        ]
        check(
            "only the snippet defaults retire",
            SnippetsRemovalMigration.retiredDefaults(in: keys) == [
                "boundSnippetIDs", "hotkey.command:search-snippets", "hotkey.snippet./tmp/a.md",
                "snippetsEnabled", "snippetsFolder"
            ])

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    private static func migrated(_ data: Data) -> Data? {
        SnippetsRemovalMigration.migrated(data)
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
