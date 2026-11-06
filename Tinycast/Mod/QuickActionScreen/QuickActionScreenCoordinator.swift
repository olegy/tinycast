import AppKit
import Observation

/// Every Quick Action opens on one palette screen, where its text is read and edited first.
@MainActor
@Observable
final class QuickActionScreenCoordinator {
    private unowned let core: AppCore

    private(set) var session: QuickActionSession?
    /// Bumped by ⌘P, which the header answers by opening its menu.
    private(set) var menuRequest = UUID()
    /// An action whose editor Settings should open, taken by the Quick Actions pane once.
    private(set) var pendingEdit: QuickAction?

    @ObservationIgnored private var opening: Task<Void, Never>?

    private static let languageSettingsPane = "com.apple.Localization-Settings.extension"

    init(core: AppCore) {
        self.core = core
        core.palette.onQuickActionScreenLeft = { [weak self] in self?.discard() }
    }

    private var palette: PaletteState { core.palette }
    private var paletteCoordinator: PaletteCoordinator { core.paletteCoordinator }

    // MARK: - Opening

    /// The text is read before the screen shows, so the palette never covers what it reads.
    @discardableResult
    func open(_ action: QuickAction) -> Bool {
        if paletteCoordinator.isShowing(.quickAction), session?.action == action {
            paletteCoordinator.hidePalette()
            return true
        }
        opening?.cancel()
        let overPalette = paletteCoordinator.isVisible
        let target =
            overPalette
            ? InjectionTarget.behindPalette(
                ownWindow: paletteCoordinator.previousOwnWindow, app: paletteCoordinator.targetApp)
            : InjectionTarget.current()
        opening = Task { [weak self] in
            guard let self else { return }
            let capture = await capture(from: target, overPalette: overPalette)
            guard !Task.isCancelled else { return }
            present(makeSession(action, capture: capture), overPalette: overPalette)
        }
        return true
    }

    private struct Capture {
        var text: String
        var source: QuickActionSession.Source
        var refusal: QuickActionFailure?
    }

    private func capture(from target: InjectionTarget?, overPalette: Bool) async -> Capture {
        var refusal: QuickActionFailure?
        switch target {
        case .ownEditor(let editor)?:
            let selected = editor.injectableSelection
            if !selected.isEmpty { return Capture(text: selected, source: .selection) }
        case .external(let app)?:
            if !Permissions.isAccessibilityTrusted() {
                refusal = .needsAccessibility
            } else if app.bundleIdentifier == Bundle.main.bundleIdentifier {
                refusal = .noTarget
            } else if let selected = await selection(in: app, overPalette: overPalette) {
                return Capture(text: selected, source: .selection)
            }
        case nil:
            refusal = .noTarget
        }
        // Safe now that the text is shown and edited before anything is sent.
        guard let clipboard = NSPasteboard.general.string(forType: .string), !clipboard.isEmpty else {
            return Capture(text: "", source: .none, refusal: refusal)
        }
        return Capture(text: clipboard, source: .clipboard, refusal: refusal)
    }

    /// The borrowed ⌘C has to reach the app, so a palette in front steps aside for it.
    private func selection(in app: NSRunningApplication, overPalette: Bool) async -> String? {
        if case .text(let text) = AccessibilityText.read(in: app), !text.isEmpty { return text }
        if overPalette { paletteCoordinator.hidePalette(restoreFocus: false) }
        let copied = await core.textInjector.copySelection(from: app)
        return copied?.isEmpty == false ? copied : nil
    }

    private func makeSession(_ action: QuickAction, capture: Capture) -> QuickActionSession {
        let store = core.quickActionSettings
        store.repairModel(against: core.aiSettings.connections, fallback: core.aiSettings.defaultModel)
        let stored = store.settings.targetLanguage
        return QuickActionSession(
            action: action, text: capture.text, source: capture.source, refusal: capture.refusal,
            model: store.model(for: action) ?? core.aiSettings.defaultModel,
            language: stored.isEmpty ? Locale.current.language : Locale.Language(identifier: stored))
    }

    private func present(_ next: QuickActionSession, overPalette: Bool) {
        discard()
        if paletteCoordinator.isVisible {
            session = next
            if palette.mode == .quickAction {
                palette.focusToken = UUID()
            } else {
                palette.push(mode: .quickAction)
            }
        } else if overPalette {
            // Hidden only to borrow ⌘C: the screen it covered comes back as the step behind.
            paletteCoordinator.showPalette(mode: .launcher, restoreAnyMode: true)
            session = next
            if palette.mode != .quickAction { palette.push(mode: .quickAction) }
        } else {
            paletteCoordinator.popToRootNow()
            session = next
            paletteCoordinator.showPalette(mode: .quickAction)
        }
        if next.action == .translate { core.quickActionCoordinator.loadLanguages() }
    }

    /// Leaving the screen is the end of the session; hiding the palette only minimises it.
    func discard() {
        opening?.cancel()
        opening = nil
        session?.cancel()
        session = nil
    }

    // MARK: - The screen's verbs

    /// ↵: run while editing, then deliver what came back.
    func primary() {
        guard let session else { return }
        switch session.phase {
        case .editing, .failed: run()
        case .running: break
        case .finished where canPaste: paste()
        case .finished: copy()
        case .needsLanguageDownload: openLanguageSettings()
        }
    }

    var primaryTitle: String {
        guard let session else { return String(localized: "Run") }
        switch session.phase {
        case .editing, .running, .failed: return String(localized: "Run")
        case .finished: return canPaste ? pasteTitle : String(localized: "Copy")
        case .needsLanguageDownload: return String(localized: "Open Language & Region")
        }
    }

    var isPrimaryEnabled: Bool {
        guard let session else { return false }
        switch session.phase {
        case .editing, .failed: return session.canRun
        case .running: return false
        case .finished: return session.hasResult
        case .needsLanguageDownload: return true
        }
    }

    func run() {
        guard let session, session.canRun else { return }
        let action = session.action
        let text = session.text
        let model = session.model
        let language = session.language
        let instructionOverride = core.quickActionSettings.settings.instructionOverride(for: action)
        session.start { [weak self, weak session] runID in
            do {
                let result: String
                if action.usesTranslationFramework {
                    result = try await TextTranslator.translate(text, to: language)
                } else {
                    guard let provider = try self?.provider(for: model) else { return }
                    result = try await QuickActionRunner.run(
                        action, selection: text, using: provider,
                        instructionOverride: instructionOverride,
                        onDelta: { session?.append($0, runID: runID) })
                }
                guard !Task.isCancelled else { return }
                session?.finish(result, runID: runID)
            } catch is CancellationError {
                return
            } catch let error as TextTranslator.Failure where error.needsDownload {
                session?.requireLanguageDownload(runID: runID)
            } catch {
                guard !Task.isCancelled else { return }
                session?.fail(error.localizedDescription, runID: runID)
            }
        }
    }

    private func provider(for model: AIModelSelection?) throws -> any AIProvider {
        guard let model else {
            throw AIProviderError.unavailable(
                String(localized: "Choose a model in Settings \u{2192} Quick Actions."))
        }
        return try AIProviderFactory.make(
            selection: model, settings: core.aiSettings, subscription: core.chatGPTSubscription,
            installedAI: core.installedAI, guardrails: .permissiveContentTransformations)
    }

    /// Escape while a reply streams stops it; otherwise it leaves the screen like any other.
    func escape() -> Bool {
        guard !palette.menuOpen, !palette.isComposing else { return false }
        if let session, session.isRunning {
            session.stop()
            return true
        }
        if core.settings.escapeKeyBehavior == .navigateBackOrClose, palette.pop() { return true }
        close()
        return true
    }

    func stop() {
        session?.stop()
    }

    func edit() -> Bool {
        guard let session, !session.isRunning, session.phase != .editing else { return false }
        session.edit()
        palette.focusToken = UUID()
        return true
    }

    // MARK: - Delivery

    /// Read when it lands, so the paste follows whatever the palette covers now.
    private var pasteTarget: InjectionTarget? {
        InjectionTarget.behindPalette(
            ownWindow: paletteCoordinator.previousOwnWindow, app: paletteCoordinator.targetApp)
    }

    var canPaste: Bool {
        guard let target = pasteTarget else { return false }
        return target.ownEditor != nil || Permissions.isAccessibilityTrusted()
    }

    var pasteTitle: String {
        palette.pasteTarget?.pasteTitle ?? String(localized: "Paste")
    }

    /// Why Paste is missing, in the words of where to go about it.
    var pasteUnavailableReason: String? {
        guard !canPaste else { return nil }
        guard pasteTarget != nil else {
            return String(localized: "Nothing to paste into — the result can only be copied.")
        }
        return String(
            localized: "Allow Tinycast to use Accessibility in System Settings to paste the result.")
    }

    func paste() {
        guard let session, session.hasResult else { return }
        guard canPaste else {
            copy()
            return
        }
        let text = session.output
        let target = pasteTarget
        let title = session.action.title
        finish(restoreFocus: target?.ownEditor != nil)
        core.textInjector.deliver(
            InjectedText(text), target: target,
            onFailed: { [weak self] in
                _ = Paster.copyPlainText(text)
                self?.core.showMessage(
                    String(localized: "\(title) couldn't replace the selection — copied instead"),
                    tone: .danger)
            })
    }

    func copy() {
        guard let session, session.hasResult else { return }
        _ = Paster.copyPlainText(session.output)
        finish(restoreFocus: true)
        core.showMessage(String(localized: "Copied text"))
    }

    /// Done with the action: nothing is left to come back to.
    private func finish(restoreFocus: Bool) {
        paletteCoordinator.hidePalette(restoreFocus: restoreFocus)
        paletteCoordinator.popToRootNow()
    }

    private func close() {
        paletteCoordinator.hidePalette()
        paletteCoordinator.popToRootNow()
    }

    func openLanguageSettings() {
        close()
        AppLauncher.openSettingsPane(bundleID: Self.languageSettingsPane)
    }

    func openAccessibilitySettings() {
        close()
        Permissions.openAccessibilitySettings()
    }

    // MARK: - Model and language

    func requestMenu() {
        menuRequest = UUID()
    }

    /// A palette menu closes into the hidden search field, so its rows hand the caret back here.
    func refocus() {
        palette.focusToken = UUID()
    }

    var modelTitle: String {
        core.aiChatCoordinator.modelTitle(
            of: session?.model, among: core.aiChatCoordinator.modelOptions)
    }

    var modelIcon: PopoverMenuIcon {
        core.aiChatCoordinator.modelIcon(of: session?.model)
    }

    var efforts: [ChatGPTSubscription.Effort] {
        AIModelOption.efforts(
            for: session?.model, settings: core.aiSettings, subscription: core.chatGPTSubscription,
            installedAI: core.installedAI)
    }

    var effortTitle: String {
        guard let selected = session?.model?.effort,
            let effort = efforts.first(where: { $0.id == selected })
        else { return String(localized: "Reasoning") }
        return effort.title
    }

    var languages: [Locale.Language] { core.quickActionCoordinator.offeredLanguages }

    /// The first open finds the installed providers' catalogs cold, so it wakes them.
    func prepareModelMenu() {
        core.aiChatCoordinator.prepareModelSwitcher()
    }

    func select(_ option: AIModelOption) {
        session?.model = AIModelOption.withDefaultEffort(
            option.selection, settings: core.aiSettings, subscription: core.chatGPTSubscription,
            installedAI: core.installedAI)
        refocus()
    }

    func select(_ effort: ChatGPTSubscription.Effort) {
        guard let model = session?.model else { return }
        session?.model = model.withEffort(effort.id)
        refocus()
    }

    func select(_ language: Locale.Language) {
        session?.language = language
        refocus()
    }

    var modelGroups: [AIModelOptionGroup] { core.aiChatCoordinator.modelGroups }

    var isModelCatalogLoading: Bool { core.aiChatCoordinator.isModelCatalogLoading }

    // MARK: - Editing an action from the launcher

    /// Translate has no editor, as in Settings: there is no prompt and no model to change.
    func editableAction(for entry: AppEntry) -> QuickAction? {
        guard entry.kind == .quickAction else { return nil }
        if let builtIn = CommandCatalog.command(for: entry)?.builtInQuickAction {
            return builtIn.usesTranslationFramework ? nil : .builtIn(builtIn)
        }
        return CustomQuickAction.id(fromEntryID: entry.id)
            .flatMap(core.customQuickActions.action(id:))
            .map(QuickAction.custom)
    }

    @discardableResult
    func editAction(for entry: AppEntry) -> Bool {
        guard let action = editableAction(for: entry) else { return false }
        paletteCoordinator.hidePalette(restoreFocus: false)
        pendingEdit = action
        core.settingsCoordinator.showSettings(
            tab: .quickActions, revealing: .row(.quickActionsActions, action.title))
        return true
    }

    func takePendingEdit() -> QuickAction? {
        defer { pendingEdit = nil }
        return pendingEdit
    }
}
