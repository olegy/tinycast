import SwiftUI

struct RootPaletteView: View {
    @Environment(AppCore.self) private var core
    @Environment(PaletteState.self) private var vm
    @Environment(AppIndex.self) private var appIndex
    @Environment(ClipboardStore.self) private var store
    @Environment(FavoritesStore.self) private var favorites
    @Environment(VisibilityStore.self) private var visibility
    @Environment(CalculatorHistoryStore.self) private var calcHistory
    /// Observed so the card re-evaluates when a snapshot lands or consent changes.
    @Environment(CurrencyRateStore.self) private var currencyRates
    @Environment(EmojiIndex.self) private var emojiIndex
    @Environment(FrequentEmojiStore.self) private var frequentEmoji
    @Environment(FileSearchSession.self) private var fileSearch
    @Environment(DictionarySession.self) private var dictionary
    @Environment(MenuSearchSession.self) private var menuSearch
    @Environment(WindowSwitchSession.self) private var windowSwitch
    @Environment(UninstallSession.self) private var uninstall
    @Environment(QuicklinkStore.self) private var quicklinks
    @Environment(ExtensionManager.self) private var extensions
    @Environment(AppSettings.self) private var settings
    @Environment(\.metrics) private var metrics
    @FocusState private var searchFocused: Bool
    /// Kept apart from the search field's own focus. See docs/features/palette.md.
    @FocusState private var argumentFocused: String?
    /// Which in-window menu is open; at most one, so the state cannot disagree with itself.
    @State private var openMenu: OpenMenu?
    /// Sampled once by `openActions`, so the running-only rows can't appear while the menu is up.
    @State private var selectionIsRunning = false
    @State private var menuSelection = 0
    /// The argument field whose choices are up, so `menuContent` can rebuild the same menu.
    @State private var argumentOptionsField: String?
    @State private var inputOptions: PopoverMenuContent?
    @State private var menuPanel = MenuPanelController()
    /// The palette's own window, reported by `WindowReader`; the menu hangs off its frame.
    @State private var hostWindow: NSWindow?
    /// The pending scroll request; modes are exclusive, so one piece of state serves all.
    @State private var scroll = ScrollIntent(kind: .top)
    @State private var compactSelection = CompactBarSelection()

    /// Compact vs. full; the source of truth is on `AppCore`, so the two can't disagree.
    private var isCollapsed: Bool { core.paletteCoordinator.paletteIsCollapsed }

    private var renderingOutset: CGFloat { isCollapsed ? Theme.Size.paletteGlassOutset : 0 }

    private var screen: any PaletteScreen {
        switch vm.mode {
        case .launcher:
            return LauncherScreen(
                appIndex: appIndex, favorites: favorites, visibility: visibility,
                currencyRates: currencyRates, core: core, vm: vm, running: selectionIsRunning,
                openActions: openActions, openArgumentOptions: openArgumentOptions,
                scrollToFollow: { scroll = ScrollIntent(kind: .follow) })
        case .uninstall:
            return UninstallScreen(
                session: uninstall, core: core, vm: vm, openActions: openActions)
        case .snippets:
            return SnippetsScreen(
                store: core.snippetStore, coordinator: core.snippetCoordinator, vm: vm,
                metrics: metrics, openActions: openActions,
                scrollToFollow: { scroll = ScrollIntent(kind: .follow) })
        case .snippetEditor:
            return SnippetEditorScreen(
                coordinator: core.snippetCoordinator, openMenuCorner: menuCorner,
                openInputMenu: openInputOptions)
        case .quicklinks:
            return QuicklinkListScreen(
                store: quicklinks, core: core, vm: vm, openActions: openActions,
                openArgumentOptions: openArgumentOptions)
        case .quicklinkEditor:
            return QuicklinkEditorScreen(
                coordinator: core.quicklinkCoordinator, openMenuCorner: menuCorner,
                openInputMenu: openInputOptions)
        case .emoji:
            return EmojiScreen(
                index: emojiIndex, frequent: frequentEmoji, pinned: core.pinnedEmoji, core: core, vm: vm,
                tone: settings.emojiSkinTone, defaultColumns: settings.emojiGridColumns,
                openActions: openActions)
        case .fileSearch:
            return FileSearchScreen(
                session: fileSearch, core: core, vm: vm, openActions: openActions)
        case .menuSearch:
            return MenuSearchScreen(
                session: menuSearch, core: core, vm: vm, openActions: openActions)
        case .switchWindows:
            return WindowSwitchScreen(session: windowSwitch, core: core)
        case .customCommandEditor:
            return CustomCommandEditorScreen(
                coordinator: core.customCommandCoordinator, openMenuCorner: menuCorner,
                openInputMenu: openInputOptions)
        case .customCommands:
            return CustomCommandListScreen(
                store: core.customCommands, coordinator: core.customCommandCoordinator,
                vm: vm, metrics: metrics, openActions: openActions)
        case .clipboard:
            return ClipboardScreen(
                store: store, core: core, vm: vm, openActions: openActions,
                scrollToFollow: { scroll = ScrollIntent(kind: .follow) })
        case .ai:
            return AIScreen(
                vm: vm, metrics: metrics, chat: quickAI,
                coordinator: core.quickAICoordinator, chatCoordinator: core.aiChatCoordinator,
                openAttachments: toggleAIAttachments)
        case .aiHistory:
            return ChatHistoryScreen(
                history: core.chatHistory, chat: quickAI, coordinator: core.quickAICoordinator,
                vm: vm, openActions: openActions, metrics: metrics)
        case .dictionary:
            return DictionaryScreen(session: dictionary, core: core, vm: vm)
        case .calculatorHistory:
            return CalculatorHistoryScreen(
                history: calcHistory, currencyRates: currencyRates, core: core, vm: vm,
                openActions: openActions)
        case .extensionCommand:
            return ExtensionCommandScreen(
                screen: extensionScreen, extensions: extensions, vm: vm, openActions: openActions)
        case .quickAction:  // mod: quick-action-screen
            return QuickActionScreen(
                coordinator: core.quickActionScreen, palette: vm, metrics: metrics,
                openMenuCorner: menuCorner, openInputMenu: openInputOptions)
        }
    }

    private var extensionScreen: ExtensionScreen {
        guard vm.mode == .extensionCommand, case .rendered(let tree) = extensions.state else {
            return .empty
        }
        return ExtensionScreen(tree: tree, query: vm.query)
    }

    private func handleFormReturn(_ press: KeyPress) -> KeyPress.Result {
        guard !vm.isEditingField, !vm.isComposing else { return .ignored }
        let modifiers = press.modifiers.intersection([.command, .control, .option, .shift])
        guard modifiers == .command else { return .ignored }
        activateSelection()
        return .handled
    }

    private var isExtensionForm: Bool {
        vm.mode == .extensionCommand && extensionScreen.kind == .form
    }

    /// Selection clamped into the results: one source for highlight, preview and activation.
    private func selection(count: Int) -> Int {
        count == 0 ? 0 : min(max(vm.selection, 0), count - 1)
    }

    /// Takes a resolved screen — reaching `rows` costs a list build, so callers resolve it once.
    private func selection(in screen: any PaletteScreen) -> Int {
        selection(count: screen.rows.count)
    }

    private var menuOpen: Bool { openMenu != nil }

    // MARK: - Popover menu content

    /// The clipboard type filter's rows; activating one is the only way the filter changes.
    private var clipboardFilterContent: PopoverMenuContent {
        PopoverMenuContent(
            items: ClipboardFilter.allCases.enumerated().map { index, filter in
                PopoverMenuItem(
                    title: filter.title, systemImage: filter.systemImage,
                    startsSection: index == 1
                ) {
                    vm.clipboardFilter = filter
                }
            })
    }

    private var fileSearchFilterContent: PopoverMenuContent {
        PopoverMenuContent(
            items: FileSearchFilter.allCases.map { filter in
                PopoverMenuItem(title: filter.title, systemImage: filter.systemImage) {
                    vm.fileSearchFilter = filter
                }
            })
    }

    /// All Categories stays above the divider; the remaining rows match their section order.
    private var emojiCategoryContent: PopoverMenuContent {
        PopoverMenuContent(
            items: EmojiCategoryFilter.allCases.enumerated().map { index, filter in
                PopoverMenuItem(
                    title: filter.title, systemImage: filter.systemImage,
                    startsSection: index == 1
                ) {
                    vm.emojiCategoryFilter = filter
                }
            })
    }

    /// The one source every menu path addresses rows through, so none can disagree.
    private var menuContent: PaletteMenuContent? {
        switch openMenu {
        case .actions:
            let screen = screen
            return screen.menuContent(
                at: selection(in: screen), searchQuery: ActionMenuSearchQuery(vm.menuQuery),
                menuSelection: $menuSelection,
                onActivate: activateMenuItem)
        case .clipboardFilter:
            return headerMenu(
                clipboardFilterContent, width: metrics.size.clipboardFilterMenuWidth)
        case .fileSearchFilter:
            return headerMenu(fileSearchFilterContent, width: metrics.size.fileSearchFilterMenuWidth)
        case .emojiCategory:
            return headerMenu(emojiCategoryContent, width: metrics.size.emojiCategoryMenuWidth)
        case .aiModel:
            return headerMenu(
                AIModelMenu.models(coordinator: core.aiChatCoordinator, chat: quickAI),
                width: metrics.size.menuWidth)
        case .aiReasoning:
            return headerMenu(
                AIModelMenu.reasoning(
                    coordinator: core.aiChatCoordinator, chat: quickAI),
                width: metrics.size.menuWidth)
        case .aiAttachments:
            guard !quickAI.pendingAttachments.isEmpty else { return nil }
            return headerMenu(
                AIModelMenu.attachments(
                    coordinator: core.aiChatCoordinator, chat: quickAI),
                width: metrics.size.menuWidth)
        case .argumentOptions:
            guard let field = argumentOptionsField,
                let popover = headerAccessory?.optionsMenu(field)
            else { return nil }
            return headerMenu(popover, width: metrics.size.menuWidth)
        case .inputOptions(let corner):
            guard let inputOptions else { return nil }
            let width: CGFloat =
                switch corner {
                case .belowControl(let frame, _): max(metrics.size.formMenuMinimumWidth, frame.width)
                default: metrics.size.formMenuMinimumWidth
                }
            return headerMenu(
                inputOptions, width: width, extraRowsHeight: metrics.size.formMenuExtraRowsHeight)
        case .extensionAccessory:
            return extensionCommandScreen?.searchAccessoryMenu(
                searchQuery: ActionMenuSearchQuery(vm.menuQuery),
                menuSelection: $menuSelection, onActivate: activateMenuItem)
        case nil: return nil
        }
    }

    var body: some View {
        // Resolve the screen once per render, so the flat index can't drift from the rows.
        let screen = screen
        let count = screen.rows.count
        let sel = selection(count: count)
        // An extension's Form has no rows to count, but ↵ still acts.
        let showActionGroup =
            (count > 0 || screen.actsWithoutRows)
            && screen.hasPrimaryAction(at: sel)

        // One header position, so focus survives the swap. See docs/features/palette.md.
        return keyHandlers(
            stateObservers(
                Group {
                    if isCollapsed {
                        Color.clear
                    } else {
                        screen.body(selection: sel, scroll: scroll)
                    }
                }
                .mask {
                    BarClip(
                        top: metrics.size.headerHeight + metrics.size.headerPadding,
                        bottom: metrics.size.bottomBarHeight)
                }
                .safeAreaInset(edge: .top, spacing: 0) { header }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !isCollapsed {
                        bottomBar(
                            pillLabel: screen.primaryActionTitle, showActionGroup: showActionGroup,
                            formPrimaryShortcut: screen.hidesSearchField && screen.actsWithoutRows,
                            primaryActionEnabled: screen.isPrimaryActionEnabled(at: sel),
                            secondaryLabel: showActionGroup ? screen.secondaryActionTitle(at: sel) : nil,
                            showActions: screen.hasActions(at: sel))
                    }
                }
                // No title bar, so this thin top margin is the only place left to grab the panel.
                .overlay(alignment: .topLeading) { topDragStrip }
                // The menu lives in its own window; this only reports the one to hang it from.
                .background(
                    WindowReader {
                        hostWindow = $0
                        installHeaderArrowHandler(in: $0)
                    }
                )
                // The window's frame is the size source, so the glass and clip stay matched.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                // Compact, the bar's own glass shapes are the surface and the window is bare.
                // Hidden rather than unmounted, so expanding never shows a frame without glass.
                .background(GlassEffectView().opacity(isCollapsed ? 0 : 1))
                .overlay {
                    Theme.Colors.dialogDimming
                        .opacity(core.isDimmingPaletteForDialog && !isCollapsed ? 1 : 0)
                        .allowsHitTesting(false)
                }
                .animation(
                    .easeOut(
                        duration: core.isDimmingPaletteForDialog
                            ? Theme.Duration.dialogEnter : Theme.Duration.dialogExit),
                    value: core.isDimmingPaletteForDialog
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: isCollapsed ? 0 : metrics.radius.panel, style: .continuous
                    )
                    .inset(by: -renderingOutset))),
            selection: sel
        )
        .padding(renderingOutset)
    }

    /// The emoji grid's observers, split out so `stateObservers` stays within type-checker reach.
    @ViewBuilder
    private func emojiObservers(_ content: some View) -> some View {
        content
            .onChange(of: vm.emojiCategoryFilter) { land() }
            .onChange(of: core.pinnedEmoji.revision) { emojiGridChanged() }
            .onChange(of: (screen as? EmojiScreen)?.frequentlyUsed) { old, new in
                guard let old, let new else { return }
                (screen as? EmojiScreen)?.frequentlyUsedChanged(from: old, to: new)
                emojiGridChanged()
            }
            .onChange(of: vm.emojiGridColumnsOverride) { emojiGridChanged() }
            .onChange(of: settings.emojiGridColumns) { emojiGridChanged() }
            .onChange(of: vm.emojiGridZoomToken) {
                guard let zoom = vm.emojiGridZoom else { return }
                (screen as? EmojiScreen)?.zoom(zoom)
            }
    }

    /// Pins and density move cells under the selection, and can change an open Actions menu's rows.
    private func emojiGridChanged() {
        guard vm.mode == .emoji else { return }
        scroll = ScrollIntent(kind: .follow)
        refreshActionsMenu()
    }

    /// Split from `body` for the same reason `keyHandlers` is: one chain cannot carry them all.
    @ViewBuilder
    private func stateObservers(_ content: some View) -> some View {
        emojiObservers(content)
            // Every show bumps focusToken so the search field refocuses.
            .onChange(of: vm.focusToken) {
                resetCompactSelection()
                searchFocused = !screen.hidesSearchField
            }
            .onChange(of: vm.isVisible) { resetCompactSelection() }
            .onChange(of: vm.isComposing) {
                if vm.isComposing { resetCompactSelection() }
            }
            .onChange(of: compactCommands) {
                compactSelection.reconcile(commands: compactCommands)
            }
            // A preserved screen re-summons as it was left, so a menu must end with the palette.
            .modifier(PaletteHideObserver { if menuOpen { closeMenus() } })
            .onChange(of: vm.query) {
                resetCompactSelection()
                if vm.collapseQueryLineBreaks() { return }
                land(restoringSelection: true)
                if vm.mode == .fileSearch { fileSearch.search(vm.query, filter: vm.fileSearchFilter) }
                if vm.mode == .launcher { core.fileSearchCoordinator.searchFromLauncher(vm.query) }
                if vm.mode == .dictionary { dictionary.lookUp(vm.query) }
                if vm.mode == .menuSearch { menuSearch.filter(vm.query) }
                if vm.mode == .switchWindows { windowSwitch.filter(vm.query) }
                // A command that took over the search text filters its own list.
                if vm.mode == .extensionCommand, let handler = extensionScreen.searchTextHandler {
                    extensions.dispatch(handler: handler, arguments: [vm.query])
                }
            }
            // Anything typed while the command was still starting predates its handler.
            .onChange(of: extensionScreen.searchTextHandler) { previous, handler in
                guard previous == nil, let handler, !vm.query.isEmpty else { return }
                extensions.dispatch(handler: handler, arguments: [vm.query])
            }
            .modifier(ExtensionSelectionForwarder(screen: extensionScreen, selection: vm.selection))
            // A narrower list means the old index points at a different row, or at none.
            .onChange(of: vm.clipboardFilter) { land(restoringSelection: true) }
            // The filter is part of the query, so narrowing re-runs it rather than thinning rows.
            .onChange(of: vm.fileSearchFilter) {
                land()
                fileSearch.search(vm.query, filter: vm.fileSearchFilter)
            }
            .onChange(of: vm.mode) {
                vm.clipboardFilter = .all
                vm.fileSearchFilter = .all
                vm.emojiCategoryFilter = .all
                vm.emojiGridColumnsOverride = nil
                if menuOpen { closeMenus() }
                land(restoringSelection: true)
                searchFocused = !screen.hidesSearchField
                if vm.mode != .uninstall { uninstall.cancel() }
                // Entering with no query is the blank screen's own request for recents.
                if vm.mode == .fileSearch {
                    fileSearch.search(vm.query, filter: vm.fileSearchFilter)
                } else if vm.mode == .launcher {
                    core.fileSearchCoordinator.searchFromLauncher(vm.query)
                } else {
                    fileSearch.cancel()
                }
                if vm.mode == .dictionary {
                    dictionary.lookUp(vm.query)
                } else {
                    dictionary.reset()
                }
                if vm.mode != .menuSearch { menuSearch.reset() }
                if vm.mode != .switchWindows { windowSwitch.reset() }
                // Leaving the screen any other way than Escape still ends the command's session.
                if vm.mode != .extensionCommand, extensions.running != nil {
                    Task { await extensions.stop() }
                }
            }
            // `prepare` may change nothing else, so this still lands the list as freshly opened.
            .onChange(of: vm.resetToken) {
                if menuOpen { closeMenus() }
                land()
            }
            // ⌘. arrives as a token rather than a key press. See `PaletteState.pinChordToken`.
            .onChange(of: vm.pinChordToken) { performShortcut(.pin) }
            .onChange(of: vm.queryRewriteToken) {
                if menuOpen { closeMenus() }
                searchFocused = true
                // Next turn, past the refocus that selects all, so typing extends the answer.
                Task { @MainActor in (hostWindow as? PalettePanel)?.moveFieldEditorCaretToEnd() }
            }
            .onChange(of: vm.favoriteSlotToken) {
                if let index = vm.favoriteSlotIndex { performShortcut(.favoriteSlot(index)) }
            }
            // One optional makes "exactly one menu" structural; this only presents it.
            .onChange(of: openMenu) {
                guard menuOpen else { return }
                syncMenuPanel(presenting: true)
            }
            // The hosted tree is its own hierarchy, so the highlight has to be pushed into it.
            .onChange(of: menuSelection) { syncMenuPanel(presenting: false) }
            .onChange(of: vm.menuQuery) { menuQueryChanged() }
            .onDisappear {
                menuPanel.hide()
                (hostWindow as? PalettePanel)?.onHeaderFieldBoundaryArrow = nil
            }
            // The first show builds this view after `prepare`, so no handler saw that reset.
            .onAppear {
                searchFocused = !screen.hidesSearchField
                land()
                focusPendingArgument()
            }
            .modifier(SearchFieldHiding(hidden: hidesSearchField, apply: applySearchFieldHiding))
            // Several paths flip `paletteIsCollapsed`, so resize the window to match.
            .onChange(of: core.paletteCoordinator.paletteIsCollapsed) {
                resetCompactSelection()
                core.paletteCoordinator.syncPaletteSize()
            }
    }

    /// Split from `body`: one chain of this length is past what the type-checker will infer.
    @ViewBuilder
    private func keyHandlers(_ content: some View, selection sel: Int) -> some View {
        content
            // Repeat included: holding the key keeps stepping, as the bare-key form does.
            .onKeyPress(keys: [.downArrow], phases: [.down, .repeat]) { press in
                if let reorder = movePinnedOrFavorite(1, modifiers: press.modifiers) { return reorder }
                if vm.isControlListOpen { return .ignored }
                if menuOpen {
                    moveMenu(1)
                    return .handled
                }
                // Marked text owns these keys: an IME drives its candidate window with them.
                if vm.isComposing { return .ignored }
                if isCollapsed {
                    if compactSelection.command != nil {
                        activateCompactSelection()
                        return .handled
                    }
                    // The compact bar shows no selection, so Down reveals the list's first row.
                    vm.selection = 0
                    core.paletteCoordinator.expandFromCompact()
                    return .handled
                }
                return moveVertically(1)
            }
            .onKeyPress(keys: [.upArrow], phases: [.down, .repeat]) { press in
                if let reorder = movePinnedOrFavorite(-1, modifiers: press.modifiers) { return reorder }
                if vm.isControlListOpen { return .ignored }
                if isCollapsed { return .ignored }
                if menuOpen {
                    moveMenu(-1)
                    return .handled
                }
                if vm.isComposing { return .ignored }
                return moveVertically(-1)
            }
            .onKeyPress(keys: [.leftArrow], phases: [.down, .repeat]) { press in
                if vm.isControlListOpen { return .ignored }
                if menuOpen { return .handled }
                if vm.isComposing { return .ignored }
                if moveCompactSelection(-1, modifiers: press.modifiers) { return .handled }
                return moveHorizontally(-1) ? .handled : .ignored
            }
            .onKeyPress(keys: [.rightArrow], phases: [.down, .repeat]) { press in
                if vm.isControlListOpen { return .ignored }
                if menuOpen { return .handled }
                if vm.isComposing { return .ignored }
                if moveCompactSelection(1, modifiers: press.modifiers) { return .handled }
                return moveHorizontally(1) ? .handled : .ignored
            }
            // Plain ↵ runs an open menu's row or non-form selection; ⌘↵ submits forms.
            .onKeyPress(keys: [.return, KeyEquivalent("\u{3}")], phases: .down) { press in
                let command = press.modifiers.contains(.command)
                let option = press.modifiers.contains(.option)
                if menuOpen, !command, !option {
                    activateMenuItem(menuSelection)
                    return .handled
                }
                if isCollapsed, !command, !option {
                    guard !vm.isComposing, !vm.isControlListOpen else { return .ignored }
                    activateCompactSelection()
                    return .handled
                }
                if vm.mode.isNativeEditor { return .ignored }
                if isExtensionForm { return handleFormReturn(press) }
                let screen = screen
                guard command || option else {
                    guard !vm.isComposing else { return .ignored }
                    // The fallback for a hidden-field screen with no control focused to answer.
                    let answersWithoutFocus = screen.hidesSearchField && screen.rows.isEmpty
                    guard searchFocused || answersWithoutFocus else { return .ignored }
                    activateSelection()
                    return .handled
                }
                let selection = selection(in: screen)
                if command, press.modifiers.contains(.control), screen.tertiary(at: selection) {
                    return .handled
                }
                if command, press.modifiers.contains(.shift),
                    screen.perform(.copyCalculation, at: selection)
                {
                    return .handled
                }
                if command { return screen.secondary(at: selection) ? .handled : .ignored }
                return screen.pasteKeepingWindowOpen(at: selection) ? .handled : .ignored
            }
            .onKeyPress(.escape) {
                // An open control list owns Escape before the palette beneath it.
                if vm.isControlListOpen { return .ignored }
                if vm.isComposing, !menuOpen { return .ignored }
                switch PaletteEscapeAction.resolve(
                    menuOpen: menuOpen, menuQuery: vm.menuQuery,
                    argumentFocused: argumentFocused != nil, query: vm.query, mode: vm.mode,
                    canGoBack: vm.canGoBack,
                    compactRootExpanded: settings.compactMode && vm.mode == .launcher && !isCollapsed)
                {
                case .clearMenuQuery, .closeMenu:
                    escapeMenu()
                case .leaveArgumentField:
                    returnFocusToSearchField()
                case .clearQuery:
                    if settings.compactMode, vm.mode == .launcher { vm.forceExpanded = true }
                    vm.query = ""
                case .exitExtensionScreen:
                    core.extensionCoordinator.exitExtensionScreen()
                case .goBack:
                    goBack()
                case .collapsePalette:
                    vm.forceExpanded = false
                    resetCompactSelection()
                case .hidePalette:
                    core.paletteCoordinator.hidePalette()
                    // mod: escape-pop-to-root — a close by Escape is done with the screen, so reset.
                    core.paletteCoordinator.popToRootNow()
                }
                return .handled
            }
            // tinycast-space: typing a user alias exactly and pressing Space opens its entry, the
            // way Raycast does. A row with inline arguments gets its first field focused; anything
            // else runs, so further typing lands in the command's own search field. Apps and
            // settings panes keep searching, since "tg something" is more often a query.
            .onKeyPress(.space, phases: .down) { press in
                guard vm.mode == .launcher, searchFocused, argumentFocused == nil, !menuOpen,
                    !vm.isComposing, !vm.isControlListOpen, !isCollapsed,
                    press.modifiers.subtracting(.capsLock).isEmpty,
                    !vm.query.isEmpty
                else { return .ignored }
                // "\ " escapes the Space: the backslash becomes a plain space and the query searches on.
                if vm.query.hasSuffix("\\") {
                    vm.query.removeLast()
                    vm.query += " "
                    return .handled
                }
                return openAliasEntry() ? .handled : .ignored
            }
            .onKeyPress(keys: [.tab], phases: .down) { press in
                // ⇥ inside an open list belongs to the list, not to the form's field order.
                if vm.isControlListOpen || menuOpen { return .handled }
                if vm.isComposing { return .ignored }
                // tinycast-space: Tab on an exact alias does what Space does.
                if vm.mode == .launcher, searchFocused, argumentFocused == nil, !isCollapsed,
                    press.modifiers.subtracting(.capsLock).isEmpty, !vm.query.isEmpty, openAliasEntry()
                {
                    return .handled
                }
                advanceTabFocus(backwards: press.modifiers.contains(.shift))
                return .handled
            }
            .modifier(
                ExtensionShortcutKeys(
                    screen: { menuOpen ? nil : screen as? ExtensionCommandScreen }, selection: sel)
            )
            .onKeyPress(phases: .down) { press in
                guard press.modifiers.contains(.command),
                    ASCIIKeyboardLayout.matches(press.key, character: "k")
                else { return .ignored }
                // A control's open list owns the screen, so a second panel may never open over it.
                guard !vm.isControlListOpen else { return .handled }
                // The Actions menu has no anchor in the compact bar, so swallow ⌘K there.
                guard !isCollapsed else { return .handled }
                let screen = screen
                guard !screen.rows.isEmpty || screen.actsWithoutRows else { return .handled }
                // An error calc card has no actions, so don't open an empty panel.
                guard screen.hasPrimaryAction(at: selection(in: screen)) else { return .handled }
                // ⌘K opens exactly what the footer advertises, never a menu it doesn't offer.
                guard screen.hasActions(at: selection(in: screen)) else { return .handled }
                toggleActions()
                return .handled
            }
            // The screen answers row chords; a bare backspace is intercepted in `sendEvent`.
            .onKeyPress(phases: .down) { press in
                let isDeleteKey = press.key == .delete || press.key == .deleteForward
                if isDeleteKey, menuOpen { return .handled }
                guard
                    let shortcut = PaletteShortcut.resolve(
                        command: press.modifiers.contains(.command),
                        shift: press.modifiers.contains(.shift),
                        option: press.modifiers.contains(.option),
                        control: press.modifiers.contains(.control),
                        isDeleteKey: isDeleteKey,
                        matches: { ASCIIKeyboardLayout.matches(press.key, character: $0) })
                else { return .ignored }
                guard !shortcut.requiresExpanded || !isCollapsed else { return .ignored }
                let screen = screen
                guard screen.perform(shortcut, at: selection(in: screen)) else { return .ignored }
                if shortcut.closesMenu, menuOpen { closeMenus() }
                return .handled
            }
            // Never gated on the rows: an over-narrow filter empties them, and this is the way out.
            .onKeyPress(phases: .down) { press in
                guard press.modifiers.contains(.command),
                    ASCIIKeyboardLayout.matches(press.key, character: "p")
                else { return .ignored }
                return performFilterAction() ? .handled : .ignored
            }
    }

    private var topDragStrip: some View {
        Color.clear
            // Compact, it stops at the capsule, so a button keeps its whole press.
            .frame(width: compactCapsuleWidth, height: headerTopPadding)
            .windowDraggable(settings.paletteDraggable, onBegan: beginDrag, onEnded: endDrag)
    }

    /// A header sliver nothing occupies — safe to drag; the search field handles its own.
    private func headerGutter(width: CGFloat) -> some View {
        Color.clear
            .frame(width: width)
            .windowDraggable(settings.paletteDraggable, onBegan: beginDrag, onEnded: endDrag)
    }

    private func beginDrag() { core.paletteCoordinator.beginPaletteDrag() }
    private func endDrag() { core.paletteCoordinator.endPaletteDrag() }

    /// A command can push a Form over its own list, which takes the keyboard mid-session.
    private func applySearchFieldHiding(_ hidden: Bool) {
        searchFocused = !hidden
        if hidden { vm.query = "" }
    }

    private var header: some View {
        headerBar
            // The field stops where the capsule will, so it never runs under a button.
            .frame(width: compactCapsuleWidth)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) {
                if !isCollapsed { BarSeparator() }
            }
            // Behind the row, which a glass container would otherwise paint over.
            .background(alignment: .topLeading) {
                if isCollapsed {
                    CompactBar(
                        commands: compactCommands, selection: compactSelection.command,
                        onRun: runCompactCommand)
                }
            }
            // Next turn, once the show's `land()` and search refocus are done, so neither undoes it.
            .onChange(of: vm.pendingArgumentEntryID) {
                Task { @MainActor in focusPendingArgument() }
            }
            .onChange(of: argumentFocused) { _, field in vm.noteEditingField(field != nil) }
            .onChange(of: quickAI.pendingAttachments.map(\.id)) { refreshAttachmentsMenu() }
    }

    private var compactCommands: [CommandID] {
        settings.compactBarCommands.filter(appIndex.isCommandEnabled)
    }

    private func resetCompactSelection() {
        compactSelection.command = nil
    }

    private func moveCompactSelection(_ step: Int, modifiers: EventModifiers = []) -> Bool {
        guard isCollapsed, vm.query.isEmpty, !vm.isComposing, !menuOpen,
            !vm.isControlListOpen,
            modifiers.isDisjoint(with: [.command, .control, .option, .shift])
        else { return false }
        compactSelection.move(by: step, commands: compactCommands)
        return true
    }

    private func activateCompactSelection() {
        guard let command = compactSelection.command else { return }
        runCompactCommand(command)
    }

    private func runCompactCommand(_ command: CommandID) {
        guard isCollapsed, vm.isVisible, compactCommands.contains(command) else { return }
        withTransaction(\.disablesAnimations, true) {
            core.launcherCoordinator.runCommand(command)
        }
    }

    /// Where the compact capsule ends beside its buttons; nil while expanded.
    private var compactCapsuleWidth: CGFloat? {
        guard isCollapsed else { return nil }
        return CompactBarGeometry(metrics: metrics, count: compactCommands.count)
            .capsuleWidth(revealed: true)
    }

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 0) {
            // Matches the list rows and section headers' own indent below.
            headerGutter(width: metrics.spacing.md * 2)
            // A screen with nothing beneath it starts on the section headers' column, like the root.
            if hasBackStep {
                HeaderBackButton(action: goBack)
                headerGutter(width: metrics.spacing.xl)
            }
            // One structural position: a field inside a branch loses first responder when it flips.
            headerField
                .simultaneousGesture(TapGesture().onEnded { resetCompactSelection() })
            if let accessory = headerAccessory {
                accessory.view
                // Given room last: at the default priority it would split it with the field.
                Spacer(minLength: 0).layoutPriority(-1)
            }
            if !isCollapsed, vm.mode == .clipboard {
                headerGutter(width: metrics.spacing.md)
                ClipboardFilterButton(
                    filter: vm.clipboardFilter, isOpen: openMenu == .clipboardFilter,
                    action: toggleClipboardFilter)
            }
            if !isCollapsed, vm.mode == .fileSearch {
                headerGutter(width: metrics.spacing.md)
                HeaderMenuButton(
                    title: vm.fileSearchFilter.title, systemImage: vm.fileSearchFilter.systemImage,
                    isOpen: openMenu == .fileSearchFilter,
                    help: String(localized: "Filter by type  ⌘P"),
                    action: toggleFileSearchFilter)
            }
            if !isCollapsed, vm.mode == .emoji {
                headerGutter(width: metrics.spacing.md)
                HeaderMenuButton(
                    title: vm.emojiCategoryFilter.title,
                    systemImage: vm.emojiCategoryFilter.systemImage,
                    isOpen: openMenu == .emojiCategory,
                    help: String(localized: "Filter by category  ⌘P"),
                    action: toggleEmojiCategory)
            }
            if !isCollapsed, vm.mode == .ai {
                headerGutter(width: metrics.spacing.md)
                AIModelButton(
                    title: core.aiChatCoordinator.selectedModelTitle(for: quickAI),
                    icon: core.aiChatCoordinator.selectedModelIcon(for: quickAI),
                    isOpen: openMenu == .aiModel,
                    action: toggleAIModel)
                if !core.aiChatCoordinator.reasoningEfforts(for: quickAI).isEmpty {
                    headerGutter(width: metrics.spacing.md)
                    AIReasoningButton(
                        title: core.aiChatCoordinator.selectedReasoningTitle(for: quickAI),
                        isOpen: openMenu == .aiReasoning,
                        action: toggleAIReasoning)
                }
            }
            if !isCollapsed, let command = extensionCommandScreen,
                let accessory = command.searchAccessory
            {
                headerGutter(width: metrics.spacing.md)
                command.searchAccessoryButton(
                    accessory, isOpen: openMenu == .extensionAccessory,
                    action: toggleExtensionSearchAccessory)
            }
            if showsStatusIcons {
                headerGutter(width: metrics.spacing.md)
                StatusIconStrip()
            }
            headerGutter(width: metrics.spacing.md * 2)
        }
        // One row height in both states; only the padding around it differs.
        .frame(height: metrics.size.headerHeight)
        .padding(.top, headerTopPadding)
        .padding(.bottom, isCollapsed ? metrics.size.headerPadding : headerBottomPadding)
        .frame(maxWidth: .infinity)
    }

    /// Expanded, the padding splits around the row so it centres above the separator.
    private var headerTopPadding: CGFloat {
        isCollapsed ? metrics.size.headerPadding : (metrics.size.headerPadding / 2).rounded()
    }

    private var headerBottomPadding: CGFloat { metrics.size.headerPadding - headerTopPadding }

    /// An argument strip owns the row's width, so the icons step aside while one shows.
    private var showsStatusIcons: Bool {
        !isCollapsed && vm.mode == .launcher && headerAccessory == nil
            && !core.statusIconCoordinator.icons.isEmpty
    }

    /// Mode-gated ahead of the cast, which would otherwise cost every other mode a list build.
    private var extensionCommandScreen: ExtensionCommandScreen? {
        guard vm.mode == .extensionCommand else { return nil }
        return screen as? ExtensionCommandScreen
    }

    /// Whichever screen offers one; the compact bar has no room for it.
    private var headerAccessory: PaletteHeaderAccessory? {
        guard !isCollapsed else { return nil }
        let screen = screen
        return screen.headerAccessory(at: selection(in: screen), focus: $argumentFocused)
    }

    /// Resolved through `PaletteTabAction`, so the hint cannot promise the wrong destination.
    private var tabOpensChat: Bool {
        guard !isCollapsed, headerAccessory?.fieldNames.isEmpty ?? true else { return false }
        return PaletteTabAction.resolve(
            mode: vm.mode, aiEnabled: settings.aiEnabled,
            clipboardEnabled: settings.clipboardEnabled) == .ask
    }

    private var hidesSearchField: Bool { !isCollapsed && screen.hidesSearchField }

    /// The field, kept mounted and hidden rather than swapped: a branch would tear its editor down.
    private var headerField: some View {
        searchField
            // A ceiling, not a size, so the row squeezes a long query before the strip overruns.
            .frame(minWidth: searchFieldFloor, maxWidth: searchFieldWidth)
            .opacity(hidesSearchField ? 0 : 1)
            .allowsHitTesting(!hidesSearchField)
            .accessibilityHidden(hidesSearchField)
            // The frame it publishes is where the panel puts an I-beam; hidden, it owns nowhere.
            .onChange(of: hidesSearchField) { _, hidden in
                if hidden { vm.searchFieldFrame = .zero }
            }
    }

    /// Fixed only where something shares the row: the accessory strip, or a screen's own title.
    private var searchFieldWidth: CGFloat? {
        if hidesSearchField { return nil }
        return headerAccessory.map(searchFieldWidth)
    }

    private var searchFieldFloor: CGFloat? {
        searchFieldWidth.map { min($0, metrics.size.searchFieldMinWidth) }
    }

    /// Capped to keep the strip on screen; empty, it measures the prompt so the strip follows it.
    private func searchFieldWidth(for accessory: PaletteHeaderAccessory) -> CGFloat {
        let font = metrics.typography.searchFieldNSFont
        let text = vm.query.isEmpty ? searchPrompt : vm.query
        let typed = (text as NSString).size(withAttributes: [.font: font]).width
        let back = vm.mode == .launcher ? 0 : metrics.size.headerIconSlot + metrics.spacing.xl
        let chrome = back + metrics.spacing.md * 3
        let room = metrics.size.panelWidth - accessory.width - chrome
        // +3pt so the caret sits after the last glyph rather than on top of it.
        return min(
            max(typed + metrics.scaled(3), metrics.scaled(18)),
            max(room, metrics.size.searchFieldMinWidth))
    }

    private var searchPrompt: String {
        // Squeezed to the caret, the field has no room for a prompt; beside one it keeps it.
        if headerAccessory?.placement == .afterQuery, vm.mode != .ai { return "" }
        if vm.mode == .extensionCommand, let placeholder = extensionScreen.searchPlaceholder {
            return placeholder
        }
        return vm.mode.placeholder
    }

    /// The one search field — empty it's a drag handle, and any text hands every press to editing.
    private var searchField: some View {
        @Bindable var vm = vm
        return TextField("", text: $vm.query)
            .textFieldStyle(.plain)
            .font(metrics.typography.searchField)
            .tint(Theme.Colors.textPrimary)
            .focused($searchFocused)
            // Fills the row's height, so there's no gap above it for topDragStrip to meet.
            .frame(maxHeight: .infinity)
            .background(alignment: .leading) {
                // An IME's marked text leaves `query` empty, so the placeholder would overlap it.
                if vm.query.isEmpty, !vm.isComposing {
                    Text(searchPrompt)
                        .font(metrics.typography.searchField)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .lineLimit(1)
                        // Never a click target: tapping the placeholder must still land the caret.
                        .allowsHitTesting(false)
                }
            }
            // The prompt used to carry this; without it the field would be unlabelled.
            .accessibilityLabel(Text(searchPrompt))
            // Never branches on query — that tore down the field editor mid-keystroke once.
            .overlay {
                if settings.paletteDraggable {
                    EmptyFieldDragHandle(
                        // Marked text leaves `query` empty, and composing it is still editing.
                        isEmpty: vm.query.isEmpty && !vm.isComposing,
                        onBegan: beginDrag, onEnded: endDrag,
                        // A press that never moved was aimed at the field the handle covers.
                        onClick: { searchFocused = true })
                }
            }
            // The panel resolves the pointer against this rather than hit-testing for the field.
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .global)
            } action: {
                // A hidden field takes no caret, so it claims no I-beam region either.
                vm.searchFieldFrame = hidesSearchField ? .zero : $0
            }
    }

    /// The Uninstall screen's primary action is destructive, so its pill isn't white.
    private var pillTint: Color {
        vm.mode == .uninstall ? Theme.Colors.destructive : .primary
    }

    private func bottomBar(
        pillLabel: String, showActionGroup: Bool, formPrimaryShortcut: Bool,
        primaryActionEnabled: Bool, secondaryLabel: String?, showActions: Bool
    ) -> some View {
        let showsTabHint = tabOpensChat
        return HStack(spacing: 0) {
            Color.clear.frame(width: 0, height: 0)
                .modifier(ExtensionToastSlot(extensions: extensions, showing: vm.mode == .extensionCommand))
            if showActionGroup || showsTabHint {
                PaletteActionGroup(
                    primary: showActionGroup
                        ? PaletteActionGroup.Primary(
                            label: pillLabel, tint: pillTint, formShortcut: formPrimaryShortcut,
                            enabled: primaryActionEnabled)
                        : nil,
                    secondaryLabel: secondaryLabel, showsTabHint: showsTabHint,
                    showActions: showActionGroup && showActions,
                    onPrimary: activateSelection, onSecondary: activateSecondary,
                    onTabHint: cycleMode, onActions: toggleActions
                )
                .fixedSize()
            }
        }
        .padding(.horizontal, metrics.spacing.md)
        .frame(height: metrics.size.bottomBarHeight)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .top) { BarSeparator() }
    }

    private func activateSecondary() {
        guard !isCollapsed else { return }
        let screen = screen
        _ = screen.secondary(at: selection(in: screen))
    }

    /// The one path opening the Actions menu, sampling the state its rows depend on.
    private func openActions() {
        let launcher = screen as? LauncherScreen
        selectionIsRunning = launcher.map { $0.isRunning(at: selection(in: $0)) } ?? false
        open(.actions, highlighting: 0)
    }

    private func toggleActions() {
        if openMenu == .actions {
            closeMenus()
        } else {
            openActions()
        }
    }

    /// Opens on the active filter, so the current value is the highlighted row like a pop-up's.
    private func toggleClipboardFilter() {
        if openMenu == .clipboardFilter {
            closeMenus()
            return
        }
        let active = ClipboardFilter.allCases.firstIndex(of: vm.clipboardFilter) ?? 0
        open(.clipboardFilter, highlighting: active)
    }

    private func toggleFileSearchFilter() {
        if openMenu == .fileSearchFilter {
            closeMenus()
            return
        }
        let active = FileSearchFilter.allCases.firstIndex(of: vm.fileSearchFilter) ?? 0
        open(.fileSearchFilter, highlighting: active)
    }

    private func performFilterAction() -> Bool {
        switch PaletteFilterAction.resolve(
            collapsed: isCollapsed, mode: vm.mode,
            commandHasAccessory: extensionCommandScreen?.searchAccessory != nil)
        {
        case .extensionAccessory: toggleExtensionSearchAccessory()
        case .clipboardFilter: toggleClipboardFilter()
        case .fileSearchFilter: toggleFileSearchFilter()
        case .emojiCategory: toggleEmojiCategory()
        case .aiModel: toggleAIModel()
        case .ignored: return false
        }
        return true
    }

    private func toggleEmojiCategory() {
        if openMenu == .emojiCategory {
            closeMenus()
            return
        }
        let active = EmojiCategoryFilter.allCases.firstIndex(of: vm.emojiCategoryFilter) ?? 0
        open(.emojiCategory, highlighting: active)
    }

    private func toggleExtensionSearchAccessory() {
        if openMenu == .extensionAccessory {
            closeMenus()
            return
        }
        guard let accessory = extensionCommandScreen?.searchAccessory else { return }
        let value = extensions.accessorySelection(accessory)
        open(.extensionAccessory, highlighting: accessory.index(of: value))
    }

    private func toggleAIModel() {
        if openMenu == .aiModel {
            closeMenus()
            return
        }
        let refreshTask = core.aiChatCoordinator.prepareModelSwitcher()
        open(.aiModel, highlighting: aiModelHighlight)
        Task { @MainActor in
            await refreshTask.value
            guard openMenu == .aiModel else { return }
            menuSelection = aiModelHighlight
            syncMenuPanel(presenting: false)
        }
    }

    private var quickAI: AIChatState { core.aiChats.quickAI }

    private var aiModelHighlight: Int {
        AIModelMenu.modelHighlight(coordinator: core.aiChatCoordinator, chat: quickAI)
    }

    private func toggleAIAttachments() {
        if openMenu == .aiAttachments {
            closeMenus()
            return
        }
        open(.aiAttachments, highlighting: 0)
    }

    private func toggleAIReasoning() {
        if openMenu == .aiReasoning {
            closeMenus()
            return
        }
        open(
            .aiReasoning,
            highlighting: AIModelMenu.reasoningHighlight(
                coordinator: core.aiChatCoordinator, chat: quickAI))
    }

    /// Every header menu states its own width, so resizing one never moves another.
    private func headerMenu(
        _ popover: PopoverMenuContent, width: CGFloat, extraRowsHeight: CGFloat = 0
    ) -> PaletteMenuContent {
        let filtered = popover.matching(ActionMenuSearchQuery(vm.menuQuery))
        return PaletteMenuContent(
            popover: filtered.content, selection: $menuSelection, width: width,
            search: PopoverMenu.Search(placeholder: String(localized: "Search…"), placement: .top),
            onActivate: activateMenuItem, preferredSelection: filtered.bestMatch,
            extraRowsHeight: extraRowsHeight)
    }

    /// Every open path lands here, so the highlight is always stated rather than left behind.
    private func open(_ menu: OpenMenu, highlighting row: Int) {
        vm.menuQuery = ""
        menuSelection = row
        vm.noteMenuPresentation()
        openMenu = menu
        vm.menuOpen = true
    }

    private func closeMenus() {
        menuPanel.hide()
        if menuOpen { searchFocused = !screen.hidesSearchField }
        openMenu = nil
        argumentOptionsField = nil
        inputOptions = nil
        vm.menuQuery = ""
        // Stated here rather than mirrored later: the window delegate reads it during this turn.
        vm.menuOpen = false
        InlineEntryEditor.shared.end(stoppingRecordingIn: core)  // tinycast-space
    }

    private func openInputOptions(
        _ content: PopoverMenuContent, corner: MenuPanelCorner, selection: Int
    ) {
        inputOptions = content
        open(.inputOptions(corner), highlighting: selection)
    }

    private func menuQueryChanged() {
        guard menuOpen, let content = menuContent else { return }
        let next =
            content.preferredSelection
            ?? (0..<content.rowCount).first(where: content.isSelectable) ?? 0
        if next != menuSelection { menuSelection = next }
        syncMenuPanel(presenting: false)
    }

    private func syncMenuPanel(presenting: Bool) {
        guard let content = menuContent, let corner = menuCorner else {
            menuPanel.hide()
            return
        }
        let view = content.view(corner)
        if presenting, let hostWindow {
            menuPanel.show(
                view, corner: corner, parent: hostWindow, core: core,
                clipPath: content.clipPath,
                onKeyDown: handleMenuPanelKey, onDismiss: closeMenus)
        } else {
            menuPanel.update(
                view, corner: corner, core: core, clipPath: content.clipPath)
        }
    }

    private func handleMenuPanelKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags
        let navigationModifiers = modifiers.intersection([.command, .control, .option, .shift])
        if event.charactersIgnoringModifiers == "\u{1B}" {
            escapeMenu()
            return true
        }
        if vm.mode.isNativeEditor,
            (hostWindow as? PalettePanel)?.onCommandShortcut?(event) == true
        {
            return true
        }
        switch event.specialKey {
        case .some(.downArrow) where navigationModifiers.isEmpty:
            moveMenu(1)
            return true
        case .some(.upArrow) where navigationModifiers.isEmpty:
            moveMenu(-1)
            return true
        case .some(.carriageReturn), .some(.enter):
            let screen = screen
            let selection = selection(in: screen)
            if modifiers.contains([.command, .control]), screen.tertiary(at: selection) { return true }
            if modifiers.contains([.command, .shift]),
                screen.perform(.copyCalculation, at: selection)
            {
                return true
            }
            if modifiers.contains(.command) { return screen.secondary(at: selection) }
            if modifiers.contains(.option) {
                return screen.pasteKeepingWindowOpen(at: selection)
            }
            activateMenuItem(menuSelection)
            return true
        case .some(.tab), .some(.backTab):
            return true
        default:
            break
        }

        guard !modifiers.isDisjoint(with: [.command, .control]) else { return false }
        let character = ASCIIKeyboardLayout.chordKey(for: event)
        if modifiers.contains(.control) {
            if character == "n" {
                moveMenu(1)
                return true
            }
            if character == "p" {
                moveMenu(-1)
                return true
            }
        }
        if modifiers.contains(.command), character == "k" {
            toggleActions()
            return true
        }
        if modifiers.contains(.command), character == "p", performFilterAction() { return true }
        if let shortcut = PaletteShortcut.resolve(
            command: modifiers.contains(.command), shift: modifiers.contains(.shift),
            option: modifiers.contains(.option), control: modifiers.contains(.control),
            isDeleteKey: false, matches: { character == String($0).lowercased() })
        {
            let screen = screen
            guard screen.perform(shortcut, at: selection(in: screen)) else { return false }
            if shortcut.closesMenu { closeMenus() }
            return true
        }
        if modifiers.contains(.command),
            (hostWindow as? PalettePanel)?.onCommandShortcut?(event) == true
        {
            return true
        }
        return false
    }

    private func escapeMenu() {
        if vm.menuQuery.isEmpty {
            closeMenus()
        } else {
            vm.menuQuery = ""
        }
    }

    /// An action can remove the last visible pin; never leave an invisible menu owning input.
    private func refreshActionsMenu() {
        guard openMenu == .actions else { return }
        guard menuContent != nil else {
            closeMenus()
            return
        }
        syncMenuPanel(presenting: false)
    }

    /// A row is addressed by index, so a file staged or dropped under the open menu re-lays it.
    private func refreshAttachmentsMenu() {
        guard openMenu == .aiAttachments else { return }
        guard let content = menuContent else {
            closeMenus()
            return
        }
        menuSelection = min(menuSelection, max(content.rowCount - 1, 0))
        syncMenuPanel(presenting: false)
    }

    private var menuCorner: MenuPanelCorner? {
        switch openMenu {
        case .actions: .bottomTrailing
        case .argumentOptions: .belowHeaderTrailing
        case .inputOptions(let corner): corner
        case .clipboardFilter, .fileSearchFilter, .emojiCategory, .aiModel, .aiReasoning,
            .aiAttachments, .extensionAccessory:
            .belowHeaderTrailing
        case nil: nil
        }
    }

    // MARK: - Actions

    /// Every reset lands here, so handlers that fire together agree in whatever order they run.
    private func land(restoringSelection: Bool = false) {
        let restored = restoringSelection ? vm.restoredSelection : nil
        let landing = restored.map { min($0, max(screen.rows.count - 1, 0)) } ?? screen.landingSelection
        vm.selection = landing
        scroll = ScrollIntent(kind: restored != nil ? .follow : landing == 0 ? .top : .center)
    }

    private func move(_ delta: Int, in screen: any PaletteScreen) {
        let count = screen.rows.count
        guard count > 0 else { return }
        vm.selection = min(max(selection(count: count) + delta, 0), count - 1)
        scroll = ScrollIntent(kind: .follow)
    }

    private func moveVertically(_ delta: Int) -> KeyPress.Result {
        let screen = screen
        // A control editing with ↑/↓ keeps them; only ⇥ leaves it.
        guard !screen.ownsVerticalKeys(at: selection(in: screen)) else { return .ignored }
        // Moving off a command takes its argument fields with it, so hand focus back first.
        if argumentFocused != nil { returnFocusToSearchField() }
        guard let next = screen.move(delta, axis: .vertical, from: selection(in: screen)) else {
            move(delta, in: screen)
            return .handled
        }
        vm.selection = next
        scroll = ScrollIntent(kind: .follow)
        return .handled
    }

    /// ←/→: consumed only by a horizontally navigating screen, else the caret keeps them.
    private func moveHorizontally(_ delta: Int) -> Bool {
        let screen = screen
        guard let next = screen.move(delta, axis: .horizontal, from: selection(in: screen)) else {
            return false
        }
        vm.selection = next
        scroll = ScrollIntent(kind: .follow)
        return true
    }

    /// Claimed whole on the launcher and emoji grid, so a press at an end cannot reach the caret.
    private func movePinnedOrFavorite(
        _ delta: Int, modifiers: SwiftUI.EventModifiers
    ) -> KeyPress.Result? {
        guard modifiers.contains(.command), modifiers.contains(.option), !isCollapsed else {
            return nil
        }
        if let launcher = screen as? LauncherScreen {
            if launcher.moveFavorite(delta, at: selection(in: launcher)), menuOpen { closeMenus() }
            return .handled
        }
        guard let emoji = screen as? EmojiScreen else { return nil }
        emoji.movePin(delta, at: selection(in: emoji))
        return .handled
    }

    private func moveMenu(_ delta: Int) {
        guard let content = menuContent else { return }
        var row = menuSelection + delta
        while (0..<content.rowCount).contains(row) {
            if content.isSelectable(row) {
                menuSelection = row
                return
            }
            row += delta
        }
    }

    private func activateMenuItem(_ index: Int) {
        guard let content = menuContent, (0..<content.rowCount).contains(index) else { return }
        guard content.isSelectable(index) else { return }
        // tinycast-space: a row that edits in place keeps its menu up. See InlineEntryEditor.
        if content.keepsOpen(index) { return content.activate(index) }
        // Close first: an action opening a window must find the palette key, or nothing hides it.
        closeMenus()
        // A mouse click on a row takes the caret with it; menus close back into the field.
        if argumentFocused == nil, !vm.mode.isNativeEditor { searchFocused = true }
        content.activate(index)
    }

    /// For the chords the panel hands over as tokens, which work while a menu is open.
    private func performShortcut(_ shortcut: PaletteShortcut) {
        let screen = screen
        _ = screen.perform(shortcut, at: selection(in: screen))
    }

    /// A ring hop leaves a step back — except the hop closing the ring on the launcher, its root.
    private func cycleMode() {
        switch PaletteTabAction.resolve(
            mode: vm.mode, aiEnabled: settings.aiEnabled,
            clipboardEnabled: settings.clipboardEnabled)
        {
        case .carryQuery(.launcher):
            vm.mode = .launcher
            vm.resetNavigation()
        case .carryQuery(let mode): vm.pushCarryingQuery(mode: mode)
        case .freshScreen(let mode): vm.push(mode: mode)
        case .ask: core.quickAICoordinator.ask(vm.query)
        }
    }

    /// tinycast-space: the exact-alias jump shared by Space and Tab. False when the query is not
    /// exactly a user alias of an entry that opens.
    private func openAliasEntry() -> Bool {
        // Case-sensitive on purpose: "cc" opens its command, "CC" (Shift) just searches.
        guard let key = core.aliases.aliases.first(where: { $0.value == vm.query })?.key,
            let launcher = screen as? LauncherScreen,
            let index = launcher.rows.firstIndex(where: {
                if case .entry(let app) = $0 { return app.preferenceKey == key }
                return false
            }),
            case .entry(let app) = launcher.rows[index],
            app.kind != .application, app.kind != .systemSettings
        else { return false }
        vm.selection = index
        scroll = ScrollIntent(kind: .follow)
        // Asked of the row itself, not of the header: its fields are built a pass later, so
        // reading the accessory here would miss them and open the row instead.
        let wantsArguments: Bool
        // A view command whose arguments are all optional opens instead, so what follows lands
        // in its own search bar — Search Homebrew's query is just its first search.
        var opensInside = false
        switch app.kind {
        case .quicklink:
            wantsArguments = core.quicklinks.quicklink(entryID: app.id).map {
                !TemplateEngine.declaredArguments(in: $0.link).isEmpty
            } ?? false
        case .customCommand:
            wantsArguments = !(core.customCommands.command(entryID: app.id)?.arguments ?? []).isEmpty
        case .extensionCommand:
            let command = extensions.resolve(app)?.1
            let arguments = command?.arguments ?? []
            opensInside = command?.mode == .view && !arguments.contains(where: \.required)
            wantsArguments = !arguments.isEmpty && !opensInside
        default:
            wantsArguments = false
        }
        if wantsArguments {
            // The palette focuses the first unanswered field as soon as the fields exist.
            vm.pendingArgumentEntryID = app.id
        } else if !opensInside, let field = headerAccessory?.fieldNames.first {
            argumentFocused = field
            searchFocused = false
        } else {
            launcher.activate(at: index)
        }
        return true
    }

    private func advanceTabFocus(backwards: Bool) {
        let screen = screen
        if screen.tab(at: selection(in: screen), backwards: backwards) { return }
        if let next = screen.tabTarget(from: selection(in: screen), backwards: backwards) {
            vm.selection = next
            scroll = ScrollIntent(kind: .follow)
            return
        }
        guard let accessory = headerAccessory, !accessory.fieldNames.isEmpty else {
            return cycleMode()
        }
        // Read from the local value: a `@FocusState` set in this tick still reads back stale.
        let next = accessory.field(after: argumentFocused, backwards: backwards)
        argumentFocused = next
        searchFocused = next == nil
    }

    /// Right at an inline field's end and Left at its start continue the same ring as Tab.
    private func installHeaderArrowHandler(in window: NSWindow?) {
        guard let panel = window as? PalettePanel else { return }
        panel.onHeaderFieldBoundaryArrow = { boundary in
            if isCollapsed {
                return moveCompactSelection(boundary == .leading ? -1 : 1)
            }
            guard !menuOpen, !vm.isControlListOpen, !isCollapsed,
                let accessory = headerAccessory, !accessory.fieldNames.isEmpty
            else { return false }
            switch boundary {
            case .leading:
                // Query's left edge keeps its normal caret behavior; an argument moves back.
                guard argumentFocused != nil else { return false }
                advanceTabFocus(backwards: true)
            case .trailing:
                advanceTabFocus(backwards: false)
            }
            return true
        }
    }

    /// AppKit selects the whole query as the field editor comes back, which is the wanted reset.
    private func returnFocusToSearchField() {
        argumentFocused = nil
        searchFocused = true
    }

    /// The palette was opened to fill one row's fields, so the caret starts in the first empty one.
    private func focusPendingArgument() {
        guard vm.pendingArgumentEntryID != nil,
            // tinycast-space: alias + Space lands in an optional field too, as Raycast does.
            let field = headerAccessory?.firstIncompleteField ?? headerAccessory?.fieldNames.first
        else { return }
        argumentFocused = field
        searchFocused = false
        vm.pendingArgumentEntryID = nil
    }

    /// An `options=` field is chosen from the palette's own menu, never typed into.
    private func openArgumentOptions(_ field: String) {
        guard let accessory = headerAccessory, accessory.optionsMenu(field) != nil else { return }
        argumentFocused = field
        searchFocused = false
        argumentOptionsField = field
        open(.argumentOptions, highlighting: 0)
    }

    /// An extension keeps its own stack, so it can have a step back the palette cannot see.
    private var hasBackStep: Bool {
        vm.canGoBack || (vm.mode == .extensionCommand && extensions.navigationDepth > 1)
    }

    private func goBack() {
        if vm.mode == .customCommandEditor {
            core.customCommandCoordinator.cancelCustomCommandEditing()
            return
        }
        if vm.mode == .quicklinkEditor {
            core.quicklinkCoordinator.cancelQuicklinkEditing()
            return
        }
        if vm.mode == .snippetEditor {
            core.snippetCoordinator.cancelSnippetEditing()
            return
        }
        if vm.mode == .extensionCommand {
            core.extensionCoordinator.exitExtensionScreen()
            return
        }
        if !vm.pop() {
            core.paletteCoordinator.hidePalette()
            core.paletteCoordinator.popToRootNow()  // mod: escape-pop-to-root
        }
    }

    private func activateSelection() {
        guard !isCollapsed else { return }
        // An unfilled field blocks the launch; focus it instead of acting on a half-typed row.
        if let incomplete = headerAccessory?.firstIncompleteField {
            argumentFocused = incomplete
            searchFocused = false
            return
        }
        let screen = screen
        screen.activate(at: selection(in: screen))
    }

}

/// The palette's in-window menus. One optional of these is the whole "only one is open" invariant.
private enum OpenMenu: Equatable {
    case actions
    case extensionAccessory
    case argumentOptions
    case inputOptions(MenuPanelCorner)
    case clipboardFilter
    case fileSearchFilter
    case emojiCategory
    case aiModel
    case aiReasoning
    case aiAttachments
}

/// Reads visibility in its own body, so a summon never re-renders the palette's.
private struct PaletteHideObserver: ViewModifier {
    @Environment(PaletteState.self) private var vm
    let onHide: () -> Void

    func body(content: Content) -> some View {
        content.onChange(of: vm.isVisible) { _, visible in
            if !visible { onHide() }
        }
    }
}

/// Its own modifier: the palette's body is already at the type-checker's limit.
private struct SearchFieldHiding: ViewModifier {
    let hidden: Bool
    let apply: (Bool) -> Void

    func body(content: Content) -> some View {
        content.onChange(of: hidden) { _, hidden in apply(hidden) }
    }
}

/// Hover state lives here, so lighting the chevron never re-renders the header around it.
private struct HeaderBackButton: View {
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.metrics) private var metrics

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(metrics.typography.headerIcon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(hovered ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                .frame(width: metrics.size.headerIconSlot)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: Theme.Duration.hover), value: hovered)
        .help("Esc to go back or ⌘ Esc to go to root search")
    }
}

/// The footer's actions in priority order, split by ticks that hide beside a hovered button.
private struct PaletteActionGroup: View {
    struct Primary {
        let label: String
        let tint: Color
        let formShortcut: Bool
        let enabled: Bool
    }

    private enum Slot: Hashable {
        case primary, secondary, tabHint, actions
    }

    let primary: Primary?
    let secondaryLabel: String?
    let showsTabHint: Bool
    let showActions: Bool
    let onPrimary: () -> Void
    let onSecondary: () -> Void
    let onTabHint: () -> Void
    let onActions: () -> Void
    @State private var hovered: Slot?
    @Environment(\.metrics) private var metrics
    @Environment(\.displayScale) private var displayScale

    private var slots: [Slot] {
        var slots: [Slot] = []
        if primary != nil { slots.append(.primary) }
        if primary != nil, secondaryLabel != nil { slots.append(.secondary) }
        if showsTabHint { slots.append(.tabHint) }
        if showActions { slots.append(.actions) }
        return slots
    }

    var body: some View {
        let slots = slots
        HStack(spacing: metrics.spacing.xxs) {
            ForEach(Array(slots.enumerated()), id: \.element) { index, slot in
                if index > 0 {
                    Rectangle()
                        .fill(Theme.Colors.separator)
                        .frame(width: 1 / displayScale, height: metrics.size.barSeparatorTick)
                        .opacity(hovered == slot || hovered == slots[index - 1] ? 0 : 1)
                }
                button(for: slot)
            }
        }
    }

    @ViewBuilder
    private func button(for slot: Slot) -> some View {
        switch slot {
        case .primary:
            if let primary {
                BarButton(chrome: .rounded, action: onPrimary) {
                    label(
                        primary.label, tint: primary.tint, keys: primary.formShortcut ? ["⌘", "↵"] : ["↵"])
                }
                .disabled(!primary.enabled)
                .onHover { track(.primary, $0 && primary.enabled) }
            }
        case .secondary:
            BarButton(chrome: .rounded, action: onSecondary) {
                label(secondaryLabel ?? "", tint: Theme.Colors.textSecondary, keys: ["⌘", "↵"])
            }
            .onHover { track(.secondary, $0) }
        case .tabHint:
            BarButton(chrome: .rounded, action: onTabHint) {
                label(
                    String(localized: "Quick AI"), tint: Theme.Colors.textSecondary, keys: ["⇥"],
                    hidesKeys: true)
            }
            .help("Press Tab to ask Quick AI")
            .onHover { track(.tabHint, $0) }
        case .actions:
            BarButton(chrome: .rounded, action: onActions) {
                label(String(localized: "Actions"), tint: Theme.Colors.textSecondary, keys: ["⌘", "K"])
            }
            .onHover { track(.actions, $0) }
        }
    }

    private func label(
        _ text: String, tint: Color, keys: [String], hidesKeys: Bool = false
    ) -> some View {
        HStack(spacing: metrics.spacing.sm) {
            Text(text)
                .font(metrics.typography.bar)
                .foregroundStyle(tint)
            HStack(spacing: metrics.spacing.xxs) {
                ForEach(keys, id: \.self) { KeyCapChip(text: $0, style: .outline) }
            }
            .accessibilityHidden(hidesKeys)
        }
    }

    private func track(_ slot: Slot, _ isHovered: Bool) {
        if isHovered {
            hovered = slot
        } else if hovered == slot {
            hovered = nil
        }
    }
}

/// The hard edge between the list and a bar: a device-pixel line in the separator ink.
private struct BarSeparator: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(Theme.Colors.separator)
            .frame(height: 1 / displayScale)
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
    }
}

/// Clips the list to the space between the bars, so no row is ever drawn beneath one.
/// The bars' own heights, not the proxy's insets: a mask's geometry reports none.
private struct BarClip: View {
    let top: CGFloat
    let bottom: CGFloat

    var body: some View {
        GeometryReader { _ in
            Rectangle()
                .padding(.top, top)
                .padding(.bottom, bottom)
        }
        .ignoresSafeArea()
    }
}
