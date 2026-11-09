import SwiftUI

/// Delay before a closed palette pops to root; an unset key reads as `.immediately`.
enum PopToRootTimeout: Int, CaseIterable, Identifiable, Sendable {
    case immediately = 0
    case afterFive = 5
    case afterFifteen = 15
    case afterThirty = 30
    case afterSixty = 60
    case afterNinety = 90

    var id: Int { rawValue }

    var title: String {
        self == .immediately
            ? String(localized: "Immediately") : String(localized: "After \(rawValue) seconds")
    }

    var interval: TimeInterval { TimeInterval(rawValue) }
}

@MainActor
@Observable
final class AppSettings {
    @ObservationIgnored private let defaults = UserDefaults.standard
    private typealias Key = AppSettingsKey

    /// What `AppIndex` scans, in scan order; editing it re-indexes, being observed.
    var searchScopes: [String] {
        didSet { defaults.set(searchScopes, forKey: Key.searchScopes.rawValue) }
    }

    var launcherShowsSuggestions: Bool {
        didSet {
            defaults.set(launcherShowsSuggestions, forKey: Key.launcherShowsSuggestions.rawValue)
        }
    }

    /// How loose a fuzzy root-search hit may be and still show.
    var rootSearchSensitivity: SearchSensitivity {
        didSet {
            defaults.set(rootSearchSensitivity.rawValue, forKey: Key.rootSearchSensitivity.rawValue)
        }
    }

    /// Ships on, unlike every other feature switch: a launcher is expected to keep history.
    var clipboardEnabled: Bool {
        didSet { defaults.set(clipboardEnabled, forKey: Key.clipboardEnabled.rawValue) }
    }

    var clipboardTextSearchEnabled: Bool {
        didSet { defaults.set(clipboardTextSearchEnabled, forKey: Key.clipboardTextSearchEnabled.rawValue) }
    }

    var clipboardRetention: ClipboardRetention {
        didSet {
            defaults.set(clipboardRetention.rawValue, forKey: Key.clipboardRetention.rawValue)
        }
    }

    /// Bundle IDs never recorded from; ordered, so the Settings list stays stable.
    var clipboardDisabledApps: [String] {
        didSet { defaults.set(clipboardDisabledApps, forKey: Key.clipboardDisabledApps.rawValue) }
    }

    /// What ↵ does on a clipboard entry; Paste takes the chord the chosen action leaves free.
    var clipboardDefaultAction: ClipboardDefaultAction {
        didSet {
            defaults.set(
                clipboardDefaultAction.rawValue, forKey: Key.clipboardDefaultAction.rawValue)
        }
    }

    var launchAtLogin: Bool {
        didSet { LaunchAtLogin.set(launchAtLogin) }
    }

    /// The launcher icon's visibility; dragging the icon out of the menu bar turns it off.
    var showInMenuBar: Bool {
        didSet { defaults.set(showInMenuBar, forKey: Key.showInMenuBar.rawValue) }
    }

    var automaticallyCheckForUpdates: Bool {
        didSet {
            defaults.set(
                automaticallyCheckForUpdates, forKey: Key.automaticallyCheckForUpdates.rawValue)
        }
    }

    /// Preferred skin tone applied to modifier-capable emoji at render and copy time.
    var emojiSkinTone: EmojiSkinTone {
        didSet { defaults.set(emojiSkinTone.rawValue, forKey: Key.emojiSkinTone.rawValue) }
    }

    /// Grid density used when the emoji picker opens; in-session zoom remains temporary.
    var emojiGridColumns: EmojiGridColumns {
        didSet { defaults.set(emojiGridColumns.rawValue, forKey: Key.emojiGridColumns.rawValue) }
    }

    /// How long a closed palette keeps its state before popping back to the root launcher.
    var popToRootTimeout: PopToRootTimeout {
        didSet { defaults.set(popToRootTimeout.rawValue, forKey: Key.popToRootTimeout.rawValue) }
    }


    /// Follow macOS, or pin Tinycast to one appearance. Applied by `AppCore.applyAppearance()`.
    var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance.rawValue) }
    }

    /// The per-app key System Settings writes too, so the two never disagree.
    var language: AppLanguage {
        didSet { defaults.set([language.rawValue], forKey: Key.language.rawValue) }
    }

    /// Which separators the calculator reads and writes; `.system` follows Language & Region.
    var calcNumberStyle: CalcNumberStyle {
        didSet { defaults.set(calcNumberStyle.rawValue, forKey: Key.calcNumberStyle.rawValue) }
    }

    /// Scales the palette and its floating siblings only. Read through `InterfaceSize.metrics`.
    var interfaceSize: InterfaceSize {
        didSet {
            defaults.set(interfaceSize.rawValue, forKey: Key.interfaceSize.rawValue)
            let shift = Double(
                (oldValue.metrics.size.panelWidth - interfaceSize.metrics.size.panelWidth) / 2)
            if shift != 0 {
                palettePositions = palettePositions.mapValues { offset in
                    offset.count == 2 ? [offset[0] + shift, offset[1]] : offset
                }
            }
        }
    }

    /// Summon the launcher as a slim search bar that expands into the full list on typing.
    var compactMode: Bool {
        didSet { defaults.set(compactMode, forKey: Key.compactMode.rawValue) }
    }

    var compactBarCommands: [CommandID] {
        didSet { defaults.set(compactBarCommands.map(\.rawValue), forKey: Key.compactBarCommands.rawValue) }
    }

    /// Summon the palette on the display under the pointer instead of the one holding the menu bar.
    var openOnCursorScreen: Bool {
        didSet { defaults.set(openOnCursorScreen, forKey: Key.openOnCursorScreen.rawValue) }
    }

    var autoSwitchInputSourceID: String? {
        didSet {
            guard let autoSwitchInputSourceID else {
                defaults.removeObject(forKey: Key.autoSwitchInputSource.rawValue)
                return
            }
            defaults.set(autoSwitchInputSourceID, forKey: Key.autoSwitchInputSource.rawValue)
        }
    }

    /// Lets the panel be dragged by its top edge; off by default, so most launches never grab it.
    var paletteDraggable: Bool {
        didSet { defaults.set(paletteDraggable, forKey: Key.paletteDraggable.rawValue) }
    }

    /// Off, every surface changes at once; on, Reduce Motion still trims movement where it did.
    var animationsEnabled: Bool {
        didSet { defaults.set(animationsEnabled, forKey: Key.animationsEnabled.rawValue) }
    }

    /// Where a drag left the panel's top-left, per display and relative to it.
    var palettePositions: [String: [Double]] {
        didSet { defaults.set(palettePositions, forKey: Key.palettePosition.rawValue) }
    }

    var paletteExpandedCenterDisplays: Set<String> {
        didSet {
            defaults.set(
                Array(paletteExpandedCenterDisplays),
                forKey: Key.paletteExpandedCenterDisplays.rawValue)
        }
    }

    func palettePosition(on display: String) -> CGPoint? {
        palettePositions[display].flatMap { $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil }
    }

    func setPalettePosition(_ offset: CGPoint?, on display: String, expandedCenter: Bool) {
        if offset != nil && expandedCenter {
            paletteExpandedCenterDisplays.insert(display)
        } else {
            paletteExpandedCenterDisplays.remove(display)
        }
        guard let offset else {
            palettePositions.removeValue(forKey: display)
            return
        }
        palettePositions[display] = [offset.x, offset.y]
    }

    // Feature switches, off out of the box, and off means fully off.
    var fileSearchEnabled: Bool {
        didSet { defaults.set(fileSearchEnabled, forKey: Key.fileSearchEnabled.rawValue) }
    }

    /// Tilde-abbreviated, so a backup taken on one machine still points somewhere on another.
    var fileSearchScopes: [String] {
        didSet { defaults.set(fileSearchScopes, forKey: Key.fileSearchScopes.rawValue) }
    }

    /// Only what the user added; the shipped rules are compiled into `FileSearchIgnoreList`.
    var fileSearchIgnorePatterns: [String] {
        didSet {
            defaults.set(fileSearchIgnorePatterns, forKey: Key.fileSearchIgnorePatterns.rawValue)
        }
    }

    var fileSearchRemovedDefaultPatterns: [String] {
        didSet {
            defaults.set(
                fileSearchRemovedDefaultPatterns,
                forKey: Key.fileSearchRemovedDefaultPatterns.rawValue)
        }
    }

    var fileSearchEffectiveIgnorePatterns: [String] {
        FileSearchIgnoreList.patterns(
            added: fileSearchIgnorePatterns, removedDefaults: fileSearchRemovedDefaultPatterns)
    }

    var fileSearchShowInLauncher: Bool {
        didSet {
            defaults.set(fileSearchShowInLauncher, forKey: Key.fileSearchShowInLauncher.rawValue)
        }
    }

    /// Off by default: connecting a server is consent to run code Tinycast did not write.
    var mcpEnabled: Bool {
        didSet { defaults.set(mcpEnabled, forKey: Key.mcpEnabled.rawValue) }
    }
    var aiEnabled: Bool {
        didSet { defaults.set(aiEnabled, forKey: Key.aiEnabled.rawValue) }
    }

    var customCommandsEnabled: Bool {
        didSet { defaults.set(customCommandsEnabled, forKey: Key.customCommandsEnabled.rawValue) }
    }

    /// With the feature on, controls only whether its launcher section appears.
    var customCommandsShowInLauncher: Bool {
        didSet {
            defaults.set(
                customCommandsShowInLauncher, forKey: Key.customCommandsShowInLauncher.rawValue)
        }
    }

    /// Off out of the box: on means Tinycast may read a selection anywhere and type over it.
    var quickActionsEnabled: Bool {
        didSet { defaults.set(quickActionsEnabled, forKey: Key.quickActionsEnabled.rawValue) }
    }

    var navigationEnabled: Bool {
        didSet { defaults.set(navigationEnabled, forKey: Key.navigationEnabled.rawValue) }
    }

    var menuSearchDisabledApps: [String] {
        didSet { defaults.set(menuSearchDisabledApps, forKey: Key.menuSearchDisabledApps.rawValue) }
    }

    /// Off: the Apple menu is the same on every app, so it would only pad every snapshot.
    var menuSearchShowsAppleMenu: Bool {
        didSet {
            defaults.set(menuSearchShowsAppleMenu, forKey: Key.menuSearchShowsAppleMenu.rawValue)
        }
    }

    /// Consent to run third-party JavaScript: it confirms, defaults off, rides no backup.
    var extensionsEnabled: Bool {
        didSet { defaults.set(extensionsEnabled, forKey: Key.extensionsEnabled.rawValue) }
    }

    var extensionsShowInLauncher: Bool {
        didSet {
            defaults.set(extensionsShowInLauncher, forKey: Key.extensionsShowInLauncher.rawValue)
        }
    }

    /// Only an install from GitHub needs one — the store serves extensions already built.
    var extensionPackageManager: ExtensionPackageManager {
        didSet {
            defaults.set(
                extensionPackageManager.rawValue, forKey: Key.extensionPackageManager.rawValue)
        }
    }

    /// For a toolchain Tinycast doesn't know — mise or Nix shims are the common case.
    var extensionCustomSearchPaths: [String] {
        didSet {
            defaults.set(
                extensionCustomSearchPaths, forKey: Key.extensionCustomSearchPaths.rawValue)
        }
    }

    /// Off means fully off, down to a still-registered shortcut opening nothing.
    var quicklinksEnabled: Bool {
        didSet { defaults.set(quicklinksEnabled, forKey: Key.quicklinksEnabled.rawValue) }
    }

    var quicklinksShowInLauncher: Bool {
        didSet {
            defaults.set(quicklinksShowInLauncher, forKey: Key.quicklinksShowInLauncher.rawValue)
        }
    }

    /// Off means no scan, no watcher and no commands; the files themselves are never touched.
    var snippetsEnabled: Bool {
        didSet { defaults.set(snippetsEnabled, forKey: Key.snippetsEnabled.rawValue) }
    }

    var snippetsShowInLauncher: Bool {
        didSet { defaults.set(snippetsShowInLauncher, forKey: Key.snippetsShowInLauncher.rawValue) }
    }

    /// The snippets folders as the user added them, `~` allowed, all of equal standing.
    var snippetFolders: [String] {
        didSet { defaults.set(snippetFolders, forKey: Key.snippetFolders.rawValue) }
    }

    /// Folder patterns skipped in every snippets folder, in File Search's ignore syntax.
    var snippetExcludePatterns: [String] {
        didSet { defaults.set(snippetExcludePatterns, forKey: Key.snippetExcludePatterns.rawValue) }
    }

    /// The app Open in Editor uses; nil hands the file to whatever macOS opens Markdown with.
    var snippetEditorBundleID: String? {
        didSet { defaults.set(snippetEditorBundleID, forKey: Key.snippetEditorBundleID.rawValue) }
    }

    /// Off means no DNS subscription and nothing at the left of the bottom bar.
    var statusIconsEnabled: Bool {
        didSet { defaults.set(statusIconsEnabled, forKey: Key.statusIconsEnabled.rawValue) }
    }

    var statusDNSEnabled: Bool {
        didSet { defaults.set(statusDNSEnabled, forKey: Key.statusDNSEnabled.rawValue) }
    }

    /// Comma-separated; `DNSStatus.localResolvers(from:)` is the one parser.
    var statusDNSLocalResolvers: String {
        didSet {
            defaults.set(statusDNSLocalResolvers, forKey: Key.statusDNSLocalResolvers.rawValue)
        }
    }

    /// The custom command a click on the DNS icon runs; a deleted one reads as none.
    var statusDNSCommand: UUID? {
        didSet {
            defaults.set(statusDNSCommand?.uuidString, forKey: Key.statusDNSCommand.rawValue)
        }
    }

    /// Off means the Shortcuts tool is never run, down to a bound shortcut running nothing.
    var appleShortcutsEnabled: Bool {
        didSet { defaults.set(appleShortcutsEnabled, forKey: Key.appleShortcutsEnabled.rawValue) }
    }

    /// Ask for a new window rather than a tab; off is the macOS default.
    var quicklinkOpensNewWindow: Bool {
        didSet {
            defaults.set(quicklinkOpensNewWindow, forKey: Key.quicklinkOpensNewWindow.rawValue)
        }
    }

    var quicklinkPassesSelectedText: Bool {
        didSet {
            defaults.set(
                quicklinkPassesSelectedText, forKey: Key.quicklinkPassesSelectedText.rawValue)
        }
    }

    var quicklinkConfirmsBeforeDelete: Bool {
        didSet {
            defaults.set(
                quicklinkConfirmsBeforeDelete, forKey: Key.quicklinkConfirmsBeforeDelete.rawValue)
        }
    }

    /// Whether settings.json mirrors these settings; `AppCore` starts and stops the mirror.
    var settingsFileEnabled: Bool {
        didSet { defaults.set(settingsFileEnabled, forKey: Key.settingsFileEnabled.rawValue) }
    }

    /// Rows a link from outside may run without asking; only `DeepLinkCoordinator` adds to it.
    var allowedDeepLinks: [String] {
        didSet { defaults.set(allowedDeepLinks, forKey: Key.allowedDeepLinks.rawValue) }
    }

    /// With no per-app list the bundle follows macOS's languages, so this runs before any lookup.
    static func pinLanguage() {
        UserDefaults.standard.set([storedLanguage.rawValue], forKey: Key.language.rawValue)
    }

    /// The app's own domain only: a plain read falls through to the global list.
    private static var storedLanguage: AppLanguage {
        AppLanguage(
            storedPreferences: Bundle.main.bundleIdentifier
                .flatMap(UserDefaults.standard.persistentDomain(forName:))?[Key.language.rawValue]
                as? [String], systemPreferences: SystemLanguages.preferred)
    }

    init() {
        // The only feature switch that defaults on, so absence has to outrank a stored `false`.
        clipboardEnabled =
            defaults.object(forKey: Key.clipboardEnabled.rawValue) == nil
            || defaults.bool(forKey: Key.clipboardEnabled.rawValue)
        // `integer(forKey:)` returns 0 when unset, which no case matches.
        clipboardTextSearchEnabled = defaults.bool(forKey: Key.clipboardTextSearchEnabled.rawValue)
        clipboardRetention =
            ClipboardRetention(rawValue: defaults.integer(forKey: Key.clipboardRetention.rawValue))
            ?? .threeMonths
        // Password managers ship excluded, until the user first edits the list.
        clipboardDisabledApps =
            defaults.stringArray(forKey: Key.clipboardDisabledApps.rawValue)
            ?? ["com.apple.keychainaccess", "com.apple.Passwords"]
        clipboardDefaultAction =
            defaults.string(forKey: Key.clipboardDefaultAction.rawValue)
            .flatMap(ClipboardDefaultAction.init) ?? .paste
        launchAtLogin = LaunchAtLogin.isEnabled
        showInMenuBar =
            defaults.object(forKey: Key.showInMenuBar.rawValue) == nil
            || defaults.bool(forKey: Key.showInMenuBar.rawValue)
        automaticallyCheckForUpdates =
            defaults.object(forKey: Key.automaticallyCheckForUpdates.rawValue) == nil
            || defaults.bool(forKey: Key.automaticallyCheckForUpdates.rawValue)
        emojiSkinTone =
            defaults.string(forKey: Key.emojiSkinTone.rawValue).flatMap(EmojiSkinTone.init) ?? .none
        emojiGridColumns =
            EmojiGridColumns(rawValue: defaults.integer(forKey: Key.emojiGridColumns.rawValue))
            ?? .default
        popToRootTimeout =
            PopToRootTimeout(rawValue: defaults.integer(forKey: Key.popToRootTimeout.rawValue))
            ?? .immediately
        appearance =
            defaults.string(forKey: Key.appearance.rawValue).flatMap(AppAppearance.init) ?? .system
        language = Self.storedLanguage
        calcNumberStyle =
            defaults.string(forKey: Key.calcNumberStyle.rawValue).flatMap(CalcNumberStyle.init)
            ?? .system
        interfaceSize =
            defaults.string(forKey: Key.interfaceSize.rawValue).flatMap(InterfaceSize.init)
            ?? .standard
        compactMode =
            defaults.object(forKey: Key.compactMode.rawValue) == nil
            || defaults.bool(forKey: Key.compactMode.rawValue)
        compactBarCommands =
            defaults.stringArray(forKey: Key.compactBarCommands.rawValue)
            .flatMap(CommandID.compactBarCommands(from:)) ?? CommandID.defaultCompactBarCommands
        // Unset seeds the defaults; a stored empty array is a deliberately cleared list.
        searchScopes =
            defaults.stringArray(forKey: Key.searchScopes.rawValue) ?? SearchScopes.defaults
        launcherShowsSuggestions =
            defaults.object(forKey: Key.launcherShowsSuggestions.rawValue) == nil
            || defaults.bool(forKey: Key.launcherShowsSuggestions.rawValue)
        rootSearchSensitivity =
            defaults.string(forKey: Key.rootSearchSensitivity.rawValue)
            .flatMap(SearchSensitivity.init) ?? .default
        openOnCursorScreen =
            defaults.object(forKey: Key.openOnCursorScreen.rawValue) == nil
            || defaults.bool(forKey: Key.openOnCursorScreen.rawValue)
        autoSwitchInputSourceID = defaults.string(forKey: Key.autoSwitchInputSource.rawValue)
        paletteDraggable = defaults.bool(forKey: Key.paletteDraggable.rawValue)
        animationsEnabled =
            defaults.object(forKey: Key.animationsEnabled.rawValue) == nil
            || defaults.bool(forKey: Key.animationsEnabled.rawValue)
        palettePositions =
            defaults.dictionary(forKey: Key.palettePosition.rawValue)
            as? [String: [Double]] ?? [:]
        paletteExpandedCenterDisplays =
            Set(defaults.stringArray(forKey: Key.paletteExpandedCenterDisplays.rawValue) ?? [])
        fileSearchEnabled = defaults.bool(forKey: Key.fileSearchEnabled.rawValue)
        // Unset seeds home; a stored empty array is a cleared list that searches nothing.
        fileSearchScopes =
            defaults.stringArray(forKey: Key.fileSearchScopes.rawValue)
            ?? FileSearchScope.defaultScopes
        fileSearchIgnorePatterns =
            defaults.stringArray(forKey: Key.fileSearchIgnorePatterns.rawValue) ?? []
        fileSearchRemovedDefaultPatterns =
            defaults.stringArray(forKey: Key.fileSearchRemovedDefaultPatterns.rawValue) ?? []
        fileSearchShowInLauncher = defaults.bool(forKey: Key.fileSearchShowInLauncher.rawValue)
        aiEnabled = defaults.bool(forKey: Key.aiEnabled.rawValue)
        mcpEnabled = defaults.bool(forKey: Key.mcpEnabled.rawValue)
        customCommandsEnabled = defaults.bool(forKey: Key.customCommandsEnabled.rawValue)
        // These default on, so absence must be distinguished from a stored `false`.
        customCommandsShowInLauncher =
            defaults.object(forKey: Key.customCommandsShowInLauncher.rawValue) == nil
            || defaults.bool(forKey: Key.customCommandsShowInLauncher.rawValue)
        quickActionsEnabled = defaults.bool(forKey: Key.quickActionsEnabled.rawValue)
        // Opt-in, unlike its siblings: until it is asked for, nothing about extensions is loaded.
        extensionsEnabled = defaults.bool(forKey: Key.extensionsEnabled.rawValue)
        extensionsShowInLauncher =
            defaults.object(forKey: Key.extensionsShowInLauncher.rawValue) == nil
            || defaults.bool(forKey: Key.extensionsShowInLauncher.rawValue)
        extensionPackageManager =
            defaults.string(forKey: Key.extensionPackageManager.rawValue)
            .flatMap(ExtensionPackageManager.init(rawValue:)) ?? .automatic
        extensionCustomSearchPaths =
            defaults.stringArray(forKey: Key.extensionCustomSearchPaths.rawValue) ?? []
        navigationEnabled = defaults.bool(forKey: Key.navigationEnabled.rawValue)
        menuSearchDisabledApps =
            defaults.stringArray(forKey: Key.menuSearchDisabledApps.rawValue) ?? []
        menuSearchShowsAppleMenu = defaults.bool(forKey: Key.menuSearchShowsAppleMenu.rawValue)
        quicklinksEnabled = defaults.bool(forKey: Key.quicklinksEnabled.rawValue)
        quicklinksShowInLauncher =
            defaults.object(forKey: Key.quicklinksShowInLauncher.rawValue) == nil
            || defaults.bool(forKey: Key.quicklinksShowInLauncher.rawValue)
        snippetsEnabled = defaults.bool(forKey: Key.snippetsEnabled.rawValue)
        snippetsShowInLauncher =
            defaults.object(forKey: Key.snippetsShowInLauncher.rawValue) == nil
            || defaults.bool(forKey: Key.snippetsShowInLauncher.rawValue)
        snippetFolders = defaults.stringArray(forKey: Key.snippetFolders.rawValue) ?? []
        snippetExcludePatterns = defaults.stringArray(forKey: Key.snippetExcludePatterns.rawValue) ?? []
        snippetEditorBundleID = defaults.string(forKey: Key.snippetEditorBundleID.rawValue)
        statusIconsEnabled = defaults.bool(forKey: Key.statusIconsEnabled.rawValue)
        statusDNSEnabled = defaults.bool(forKey: Key.statusDNSEnabled.rawValue)
        statusDNSLocalResolvers =
            defaults.string(forKey: Key.statusDNSLocalResolvers.rawValue)
            ?? DNSStatus.defaultLocalResolvers
        statusDNSCommand =
            defaults.string(forKey: Key.statusDNSCommand.rawValue).flatMap(UUID.init(uuidString:))
        appleShortcutsEnabled = defaults.bool(forKey: Key.appleShortcutsEnabled.rawValue)
        quicklinkOpensNewWindow = defaults.bool(forKey: Key.quicklinkOpensNewWindow.rawValue)
        quicklinkPassesSelectedText = defaults.bool(
            forKey: Key.quicklinkPassesSelectedText.rawValue)
        quicklinkConfirmsBeforeDelete =
            defaults.object(forKey: Key.quicklinkConfirmsBeforeDelete.rawValue) == nil
            || defaults.bool(forKey: Key.quicklinkConfirmsBeforeDelete.rawValue)
        settingsFileEnabled = defaults.bool(forKey: Key.settingsFileEnabled.rawValue)
        allowedDeepLinks = defaults.stringArray(forKey: Key.allowedDeepLinks.rawValue) ?? []
    }
}
