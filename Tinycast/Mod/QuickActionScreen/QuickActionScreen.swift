import SwiftUI

/// The palette's Quick Action screen: the text to send on top, the reply beneath it.
struct QuickActionScreen: PaletteScreen {
    let coordinator: QuickActionScreenCoordinator
    let palette: PaletteState
    let metrics: InterfaceMetrics
    let openMenuCorner: MenuPanelCorner?
    let openInputMenu: (PopoverMenuContent, MenuPanelCorner, Int) -> Void

    struct Row: Identifiable {
        let id = "quick-action"
    }

    /// One row, so the footer keeps its plain ↵ chip and ⌘K, as on Quick AI.
    let rows = [Row()]
    let hidesSearchField = true

    var primaryActionTitle: String { coordinator.primaryTitle }

    func hasPrimaryAction(at selection: Int) -> Bool { coordinator.session != nil }
    func isPrimaryActionEnabled(at selection: Int) -> Bool { coordinator.isPrimaryEnabled }
    func ownsVerticalKeys(at selection: Int) -> Bool { true }
    func tab(at selection: Int, backwards: Bool) -> Bool { true }

    func activate(at selection: Int) { coordinator.primary() }

    /// ⌘↵ copies a finished result, wherever the paste would have gone.
    func secondary(at selection: Int) -> Bool {
        guard coordinator.session?.hasResult == true else { return false }
        coordinator.copy()
        return true
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        switch shortcut {
        case .edit: return coordinator.edit()
        case .pin where coordinator.session?.isRunning == true: coordinator.stop()
        default: return false
        }
        return true
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let session = coordinator.session else { return nil }
        var items: [PopoverMenuItem] = []
        switch session.phase {
        case .editing, .failed:
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Run"), systemImage: session.action.symbol,
                    isEnabled: session.canRun, shortcut: "↵"
                ) { refocusing { coordinator.run() } })
        case .running:
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Stop"), systemImage: "stop.fill", shortcut: "esc"
                ) { refocusing { coordinator.stop() } })
        case .finished:
            if coordinator.canPaste {
                items.append(
                    PopoverMenuItem(
                        title: coordinator.pasteTitle, systemImage: "doc.on.clipboard", shortcut: "↵"
                    ) { refocusing { coordinator.paste() } })
            }
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Copy"), systemImage: "doc.on.doc",
                    shortcut: coordinator.canPaste ? "⌘↵" : "↵"
                ) { refocusing { coordinator.copy() } })
        case .needsLanguageDownload:
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Open Language & Region"), systemImage: "globe",
                    shortcut: "↵"
                ) { refocusing { coordinator.openLanguageSettings() } })
        }
        if session.phase == .finished || session.phase.isFailure {
            items.append(
                PopoverMenuItem(title: String(localized: "Edit"), systemImage: "pencil", shortcut: "⌘E") {
                    _ = coordinator.edit()
                })
        }
        if !session.isRunning {
            items.append(
                PopoverMenuItem(
                    title: session.action.usesTranslationFramework
                        ? String(localized: "Change Language") : String(localized: "Change Model"),
                    systemImage: session.action.usesTranslationFramework ? "globe" : "cpu",
                    startsSection: true, shortcut: "⌘P"
                ) { refocusing { coordinator.requestMenu() } })
        }
        if session.refusal == .needsAccessibility || !Permissions.isAccessibilityTrusted() {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Open Accessibility settings"),
                    systemImage: "hand.raised", startsSection: true
                ) { refocusing { coordinator.openAccessibilitySettings() } })
        }
        return PopoverMenuContent(header: session.action.title, items: items)
    }

    /// Every row hands the caret back to the editor, which the closing menu took it from.
    private func refocusing(_ action: () -> Void) {
        coordinator.refocus()
        action()
    }

    /// The whole header row: the field is hidden, so the strip takes the room it leaves.
    func headerAccessory(
        at selection: Int, focus: FocusState<String?>.Binding
    ) -> PaletteHeaderAccessory? {
        guard let session = coordinator.session else { return nil }
        let width =
            metrics.size.panelWidth - metrics.spacing.md * 4 - metrics.size.headerIconSlot
            - metrics.spacing.xl
        return PaletteHeaderAccessory(
            width: width, fieldNames: [], firstIncompleteField: nil,
            placement: .besideSearchField,
            view: AnyView(
                QuickActionScreenHeader(
                    coordinator: coordinator, session: session, openMenuCorner: openMenuCorner,
                    openInputMenu: openInputMenu
                )
                .frame(width: width)))
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        guard let session = coordinator.session else { return AnyView(Color.clear) }
        return AnyView(
            QuickActionScreenView(coordinator: coordinator, session: session, palette: palette)
                .id(ObjectIdentifier(session)))
    }
}

extension QuickActionSession.Phase {
    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}
