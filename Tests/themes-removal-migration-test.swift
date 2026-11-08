import Foundation

@main
@MainActor
struct ThemesRemovalMigrationTest {
    static var failures = 0

    static func main() throws {
        let keys = [
            "spaceRaycastThemeLight", "spaceRaycastThemeDark", "spaceRaycastThemesImported",
            "spaceRaycastThemeBackgroundOpacity", "appearance", "animationsEnabled"
        ]
        check(
            "only the theme defaults retire",
            ThemesRemovalMigration.retiredDefaults(in: keys) == [
                "spaceRaycastThemeBackgroundOpacity", "spaceRaycastThemeDark",
                "spaceRaycastThemeLight", "spaceRaycastThemesImported"
            ])

        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let command = root.appendingPathComponent(ThemesRemovalMigration.commandFolder)
        let other = root.appendingPathComponent("someone-else")
        try fm.createDirectory(at: command, withIntermediateDirectories: true)
        try fm.createDirectory(at: other, withIntermediateDirectories: true)
        let suite = "themes-removal-migration-test"
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("no defaults suite") }
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data(), forKey: "spaceRaycastThemeDark")
        defaults.set("dark", forKey: "appearance")

        ThemesRemovalMigration.run(extensionsDirectory: root, defaults: defaults)
        check("the Theme command folder is removed", !fm.fileExists(atPath: command.path))
        check("other extensions stay", fm.fileExists(atPath: other.path))
        check("a theme default is removed", defaults.object(forKey: "spaceRaycastThemeDark") == nil)
        check("other defaults stay", defaults.string(forKey: "appearance") == "dark")
        ThemesRemovalMigration.run(extensionsDirectory: root, defaults: defaults)
        check("a second run is harmless", fm.fileExists(atPath: other.path))

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
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
