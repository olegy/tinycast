import Foundation

@main
@MainActor
struct EscapeKeyBehaviorRemovalMigrationTest {
    static var failures = 0

    static func main() throws {
        let retired = Data(
            #"{ "general": { "language": "en", "escapeKeyBehavior": "closeAndPopToRoot" } }"#.utf8)
        let rewrite = EscapeKeyBehaviorRemovalMigration.migrated(retired)
        check("a file with the key is rewritten", rewrite != nil)
        if let rewrite {
            let parsed = try SettingsFileFormat.parse(rewrite)
            check("the rewrite reports nothing", parsed.issues.isEmpty)
            check("the rewrite keeps every other value", parsed.values[.language] == .string("en"))
        }

        let typo = Data(#"{ "general": { "escapeKeyBehavior": "x", "langage": "en" } }"#.utf8)
        check("another unknown key leaves the file to the import", migrated(typo) == nil)
        check("a file without the key is left alone", migrated(Data(#"{ "general": {} }"#.utf8)) == nil)
        check("invalid JSON is left alone", migrated(Data("{".utf8)) == nil)

        let suite = "escape-key-behavior-removal-migration-test"
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("no defaults suite") }
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("closeAndPopToRoot", forKey: EscapeKeyBehaviorRemovalMigration.defaultsKey)
        defaults.set("dark", forKey: "appearance")
        EscapeKeyBehaviorRemovalMigration.run(settingsFileEnabled: false, defaults: defaults)
        check(
            "the default is removed",
            defaults.object(forKey: EscapeKeyBehaviorRemovalMigration.defaultsKey) == nil)
        check("other defaults stay", defaults.string(forKey: "appearance") == "dark")

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    private static func migrated(_ data: Data) -> Data? {
        EscapeKeyBehaviorRemovalMigration.migrated(data)
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
