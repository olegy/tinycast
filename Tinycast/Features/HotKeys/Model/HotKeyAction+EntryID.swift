import Foundation

extension HotKeyAction {
    /// A row's action from its ID alone; apps and panes are keyed by bundle ID instead.
    init?(entryID: String) {
        if let command = CommandID(rawValue: entryID) {
            guard let action = command.hotKeyAction else { return nil }
            self = action
        } else if let action = SystemActionCatalog.action(forEntryID: entryID) {
            self = .systemAction(id: action.id)
        } else if let id = CustomQuickAction.id(fromEntryID: entryID) {
            self = .quickAction(id: id)
        } else if let id = CustomCommand.id(fromEntryID: entryID) {
            self = .customCommand(id: id)
        } else if let id = Quicklink.id(fromEntryID: entryID) {
            self = .quicklink(id: id)
        } else if let id = AppleShortcut.id(fromEntryID: entryID) {
            self = .appleShortcut(id: id)
        } else {
            return nil
        }
    }

    /// The inverse of `init?(entryID:)`; nil for the actions no row ID names.
    var entryID: String? {
        switch self {
        case .command(let id): id.hotKeyAction == nil ? nil : id.rawValue
        case .systemAction(let id): SystemActionCatalog.action(id: id).entryID
        case .quickAction(let id): CustomQuickAction.entryIDPrefix + id.uuidString.lowercased()
        case .customCommand(let id): CustomCommand.entryIDPrefix + id.uuidString.lowercased()
        case .quicklink(let id): Quicklink.entryIDPrefix + id.uuidString.lowercased()
        case .appleShortcut(let id): AppleShortcut.entryID(for: id)
        case .togglePalette, .app, .settingsPane, .extensionCommand: nil
        }
    }
}
