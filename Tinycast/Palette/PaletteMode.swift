import AppKit

enum PaletteMode: String, CaseIterable, Identifiable {
    case launcher
    case clipboard
    case ai
    case aiHistory
    case calculatorHistory
    case emoji
    case fileSearch
    case menuSearch
    case switchWindows
    case customCommandEditor
    case customCommands
    case uninstall
    case snippets
    case snippetEditor
    case quicklinks
    case quicklinkEditor
    case dictionary
    case extensionCommand
    case quickAction  // mod: quick-action-screen

    var id: String { rawValue }

    var isNativeEditor: Bool {
        self == .snippetEditor || self == .quicklinkEditor
            || self == .customCommandEditor
    }

    var systemImage: String {
        switch self {
        case .launcher: return "magnifyingglass"
        case .clipboard: return "doc.on.doc"
        case .ai: return "sparkles"
        case .aiHistory: return "clock.arrow.circlepath"
        case .calculatorHistory: return "plus.forwardslash.minus"
        case .emoji: return "face.smiling"
        case .fileSearch: return "doc.text.magnifyingglass"
        case .menuSearch: return "menubar.rectangle"
        case .switchWindows: return "macwindow.on.rectangle"
        case .customCommandEditor, .customCommands: return CustomCommand.sfSymbol
        case .uninstall: return "trash"
        case .snippets, .snippetEditor: return "curlybraces"
        case .quicklinks, .quicklinkEditor: return Quicklink.sfSymbol
        case .dictionary: return "book.closed"
        case .extensionCommand: return "puzzlepiece.extension"
        case .quickAction: return "wand.and.sparkles"  // mod: quick-action-screen
        }
    }
    var placeholder: String {
        switch self {
        case .launcher: return String(localized: "Search for apps and commands…")
        case .clipboard: return String(localized: "Type to filter entries…")
        case .ai: return String(localized: "Ask anything…")
        case .aiHistory: return String(localized: "Search chats…")
        case .calculatorHistory:
            return String(localized: "Do math, convert units, or search your past calculations…")
        case .emoji: return String(localized: "Search emoji and symbols…")
        case .fileSearch: return String(localized: "Search files and folders…")
        case .menuSearch: return String(localized: "Search menu bar items…")
        case .switchWindows: return String(localized: "Search open windows…")
        case .customCommandEditor: return String(localized: "Command editor")
        case .customCommands: return String(localized: "Search custom commands…")
        case .uninstall: return String(localized: "Filter files and folders by name…")
        case .snippets: return String(localized: "Search snippets…")
        case .snippetEditor: return String(localized: "Snippet editor")
        case .quicklinks: return String(localized: "Search quicklinks…")
        case .quicklinkEditor: return String(localized: "Quicklink editor")
        case .dictionary: return String(localized: "Look up a word…")
        // Replaced by the command's own `searchBarPlaceholder` whenever it declares one.
        case .extensionCommand: return String(localized: "Search…")
        case .quickAction: return String(localized: "Quick Actions")  // mod: quick-action-screen
        }
    }
}

/// The app a paste lands in, resolved once per show so nothing re-reads it per render.
struct PasteTarget: Equatable {
    let name: String
    /// Bundle path for `IconCache` — nil for a target with no on-disk bundle.
    let iconPath: String?

    init?(app: NSRunningApplication?) {
        guard let app, let name = app.localizedName else { return nil }
        self.name = name
        iconPath = app.bundleURL?.path
    }

    var pasteTitle: String { String(localized: "Paste to \(name)") }
}
