import SwiftUI

struct SnippetsScreen: PaletteScreen {
    let store: SnippetStore
    let coordinator: SnippetCoordinator
    let vm: PaletteState
    let metrics: InterfaceMetrics
    let openActions: () -> Void
    let scrollToFollow: () -> Void

    var rows: [Snippet] { SnippetSearch.filter(store.snippets, query: vm.query) }

    var primaryActionTitle: String { String(localized: "Copy to Clipboard") }

    private func snippet(at selection: Int) -> Snippet? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    func hasPrimaryAction(at selection: Int) -> Bool { snippet(at: selection) != nil }

    func actions(at selection: Int) -> PopoverMenuContent? {
        guard let snippet = snippet(at: selection) else { return nil }
        return SnippetActionsMenu.content(snippet: snippet, store: store, coordinator: coordinator)
    }

    func activate(at selection: Int) {
        guard let snippet = snippet(at: selection) else { return }
        coordinator.copy(snippet)
    }

    func secondary(at selection: Int) -> Bool {
        guard let snippet = snippet(at: selection) else { return false }
        coordinator.paste(snippet)
        return true
    }

    func perform(_ shortcut: PaletteShortcut, at selection: Int) -> Bool {
        switch shortcut {
        case .newItem:
            coordinator.editSnippet(nil)
            return true
        case .restart:
            coordinator.reload()
            return true
        default: break
        }
        guard let snippet = snippet(at: selection) else { return false }
        switch shortcut {
        case .edit: coordinator.editSnippet(snippet)
        case .copyName: coordinator.copyPath(snippet)
        case .openInEditor: coordinator.openInEditor(snippet)
        case .delete: coordinator.delete(snippet)
        default: return false
        }
        return true
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(
            content(selection: selection, scroll: scroll)
                .onChange(of: focusRequest, initial: true) { applyFocus() })
    }

    private struct FocusRequest: Equatable {
        let path: String?
        let rows: [Snippet.ID]
        let scanning: Bool
    }

    private var focusRequest: FocusRequest {
        FocusRequest(
            path: coordinator.focusPath, rows: coordinator.focusPath == nil ? [] : rows.map(\.id),
            scanning: store.isScanning)
    }

    /// Kept until the rescan a save started has run, since that moves the saved file to the top.
    private func applyFocus() {
        guard let path = coordinator.focusPath else { return }
        if let index = rows.firstIndex(where: { $0.path == path }) {
            vm.selection = index
            scrollToFollow()
        }
        if !store.isScanning { coordinator.focusHandled() }
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        let rows = rows
        if rows.isEmpty {
            emptyState
        } else {
            let selected = snippet(at: selection)
            HStack(spacing: 0) {
                SnippetList(
                    results: rows, store: store, selectedID: selected?.id, scroll: scroll,
                    onSelect: { snippet in
                        if let index = rows.firstIndex(of: snippet) { vm.selection = index }
                    },
                    onActivate: { activate(at: vm.selection) },
                    onActions: { snippet in
                        if let index = rows.firstIndex(of: snippet) { vm.selection = index }
                        openActions()
                    }
                )
                .frame(width: metrics.size.clipboardListWidth)
                Rectangle().fill(Theme.Colors.separator).frame(width: Theme.Size.hairline)
                SnippetPreview(snippet: selected, onClick: { if let selected { coordinator.noteUse(selected) } })
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if store.snippets.isEmpty, store.sources.isEmpty, store.hasLoaded || !store.isScanning {
            SnippetEmptyState(
                text: String(localized: "Add a snippets folder to get started"),
                action: String(localized: "Open Snippets Settings"), perform: coordinator.openSettings)
        } else if store.snippets.isEmpty, store.hasLoaded {
            SnippetEmptyState(
                text: String(localized: "No snippets yet"),
                action: String(localized: "Create Snippet"), perform: { coordinator.editSnippet(nil) })
        } else if store.snippets.isEmpty {
            EmptyResults(text: String(localized: "Loading snippets…"))
        } else {
            EmptyResults(text: String(localized: "No matching snippets"))
        }
    }
}

@MainActor
enum SnippetActionsMenu {
    static func content(
        snippet: Snippet, store: SnippetStore, coordinator: SnippetCoordinator
    ) -> PopoverMenuContent {
        var items: [PopoverMenuItem] = [
            PopoverMenuItem(
                title: String(localized: "Copy to Clipboard"), systemImage: "doc.on.clipboard", shortcut: "↵"
            ) { coordinator.copy(snippet) }
        ]
        if let content = try? SnippetScanner.readText(at: snippet.path),
            SnippetClipboardText.paste(SnippetDocument(text: content).content) != nil
        {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Paste to Active App"), systemImage: "doc.on.doc",
                    shortcut: "⌘↵"
                ) { coordinator.paste(snippet) })
        }
        items.append(
            PopoverMenuItem(
                title: String(localized: "Edit Snippet"), systemImage: "pencil", startsSection: true,
                shortcut: "⌘E"
            ) { coordinator.editSnippet(snippet) })
        items.append(
            PopoverMenuItem(title: String(localized: "Create Snippet"), systemImage: "plus", shortcut: "⌘N") {
                coordinator.editSnippet(nil)
            })
        let destinations = store.sources.filter { $0.root != snippet.root }
        for source in destinations {
            items.append(
                PopoverMenuItem(
                    title: String(localized: "Move to \(source.name)"),
                    systemImage: SnippetSourceIcon.symbol(for: source.icon),
                    startsSection: source == destinations.first
                ) { coordinator.move(snippet, to: source) })
        }
        items.append(
            PopoverMenuItem(
                title: String(localized: "Open in Editor"), systemImage: "square.and.pencil",
                startsSection: true, shortcut: "⇧⌘E"
            ) { coordinator.openInEditor(snippet) })
        items.append(
            PopoverMenuItem(title: String(localized: "Copy Path"), systemImage: "link", shortcut: "⌥⌘C") {
                coordinator.copyPath(snippet)
            })
        items.append(
            PopoverMenuItem(
                title: String(localized: "Reload Snippets"), systemImage: "arrow.clockwise", shortcut: "⌘R"
            ) { coordinator.reload() })
        items.append(
            PopoverMenuItem(
                title: String(localized: "Delete Snippet"), systemImage: "trash", startsSection: true,
                shortcut: "⌃X", isDestructive: true
            ) { coordinator.delete(snippet) })
        return PopoverMenuContent(header: snippet.name, items: items)
    }
}
