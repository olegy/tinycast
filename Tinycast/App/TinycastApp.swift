import SwiftUI

@main
enum TinycastLaunch {
    static func main() {
        AppSettings.pinLanguage()
        TinycastApp.main()
    }
}

struct TinycastApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    private let appName = Bundle.main.appDisplayName

    var body: some Scene {
        MenuBarExtra(isInserted: menuBarInsertion) {
            MenuBarMenu(appName: appName)
        } label: {
            MenuBarLabel(appName: appName)
        }
        .commands { menuBarCommands }
    }

    /// Read in `body` for Observation; SwiftUI echoes the binding back, so only a change writes.
    private var menuBarInsertion: Binding<Bool> {
        let settings = AppCore.shared.settings
        let isInserted = settings.showInMenuBar
        return Binding(
            get: { isInserted },
            set: { inserted in
                guard inserted != settings.showInMenuBar else { return }
                settings.showInMenuBar = inserted
            })
    }

    /// Declared, not assigned to `NSApp.mainMenu`: SwiftUI rebuilds the menu on any scene change.
    @CommandsBuilder
    private var menuBarCommands: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About \(appName)") { AppCore.shared.settingsCoordinator.showAbout() }
            Button("Check for Updates…") { AppCore.shared.updateCoordinator.checkForUpdates() }
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { AppCore.shared.settingsCoordinator.showSettings() }
                .keyboardShortcut(",")
        }
        CommandGroup(replacing: .appTermination) {
            Button("Close Window") {
                // The chat window closes itself when it is in front; otherwise ⌘Q is Settings'.
                guard !AppCore.shared.aiChatCoordinator.closeWindowIfKey() else { return }
                AppCore.shared.settingsCoordinator.closeSettings()
            }
            .keyboardShortcut("q")
        }
    }
}
