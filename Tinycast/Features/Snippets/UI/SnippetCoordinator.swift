import AppKit

/// Snippets' actions: copy, paste, the editor and the file operations. See docs/features/snippets.md.
@MainActor
@Observable
final class SnippetCoordinator {
    nonisolated static let symbol = "curlybraces"
    /// A larger clipboard is a log or a dump, not something to prefill a new snippet with.
    static let prefillLimit = 10_000

    private(set) var editor: SnippetEditorSession?
    /// The snippet the list selects once it shows it, wherever a save or rescan has moved it.
    private(set) var focusPath: String?
    /// The selected snippet's body, shown by the preview and read by the footer to offer Paste.
    private(set) var preview: SnippetPreviewText?
    private let store: SnippetStore
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let windowController: PaletteWindowController
    private let paletteCoordinator: PaletteCoordinator
    private unowned let core: AppCore
    @ObservationIgnored private var isSaving = false

    init(
        store: SnippetStore, settings: AppSettings, appIndex: AppIndex,
        windowController: PaletteWindowController, paletteCoordinator: PaletteCoordinator, core: AppCore
    ) {
        self.store = store
        self.settings = settings
        self.appIndex = appIndex
        self.windowController = windowController
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    // MARK: - Feature presence

    /// Starts or stops the index and shows or hides the commands; safe to call on any change.
    func applyEnabled() {
        let commands: Set<CommandID> = [.searchSnippets, .createSnippet]
        appIndex.setCommandsVisible(commands, settings.snippetsEnabled)
        appIndex.setCommandsListed(commands, settings.snippetsShowInLauncher)
        if settings.snippetsEnabled {
            store.start(folders: settings.snippetFolders, excludes: settings.snippetExcludePatterns)
            return
        }
        store.stop()
        if core.palette.mode == .snippetEditor { closeEditor() }
        if core.palette.mode == .snippets, !core.palette.pop() {
            paletteCoordinator.hidePalette()
            core.palette.prepare(mode: .launcher)
        }
    }

    func reportFailures(_ failures: [String]) {
        let shown = failures.prefix(5).joined(separator: "\n")
        let more = failures.count > 5 ? "\n" + String(localized: "and \(failures.count - 5) more") : ""
        Task {
            await core.showNotice(
                title: String(localized: "Some Snippets Couldn’t Be Read"), message: shown + more,
                symbol: Self.symbol, tone: .neutral)
        }
    }

    // MARK: - Showing

    func showSnippets(query: String? = nil) {
        guard settings.snippetsEnabled else { return }
        paletteCoordinator.togglePalette(mode: .snippets, seeding: query)
    }

    func reload() {
        store.rescan(reportingAllFailures: true)
        core.showMessage(String(localized: "Reloading snippets"))
    }

    func openSettings() {
        paletteCoordinator.hidePalette()
        core.settingsCoordinator.showSettings(tab: .snippets)
    }

    // MARK: - Copy and paste

    /// The text a row stands for, read fresh so a disk edit made a moment ago is what goes out.
    func content(of snippet: Snippet) -> String? {
        guard let text = try? SnippetScanner.readText(at: snippet.path) else {
            core.showMessage(String(localized: "The snippet’s file is gone"), tone: .danger)
            store.rescan()
            return nil
        }
        return SnippetDocument(text: text).content
    }

    /// Owned by the preview's task, so a newer selection cancels a read still in flight.
    func loadPreview(of snippet: Snippet) async {
        let text = try? await SnippetScanner.text(at: snippet.path)
        guard !Task.isCancelled else { return }
        preview = SnippetPreviewText(snippet: snippet, content: SnippetDocument(text: text ?? "").content)
    }

    func noteUse(_ snippet: Snippet) {
        store.noteUse(of: snippet.path)
    }

    /// Lifts used snippets while nothing is on screen; a restored list stays on the same snippet.
    func paletteDidHide() {
        let palette = core.palette
        guard palette.mode == .snippets else { return store.applyUse() }
        let rows = SnippetSearch.filter(store.snippets, query: palette.query)
        let selected = rows.indices.contains(palette.selection) ? rows[palette.selection] : nil
        store.applyUse()
        guard let selected else { return }
        let reordered = SnippetSearch.filter(store.snippets, query: palette.query)
        if let index = reordered.firstIndex(of: selected) { palette.selection = index }
    }

    func copy(_ snippet: Snippet) {
        guard let content = content(of: snippet) else { return }
        noteUse(snippet)
        paletteCoordinator.hidePalette(restoreFocus: false)
        guard Paster.copyPlainText(SnippetClipboardText.copy(content)) else {
            core.showMessage(String(localized: "Couldn’t copy snippet"), tone: .danger)
            return
        }
        core.showMessage(String(localized: "Copied to Clipboard"))
    }

    /// Only a single line pastes: a block of text dropped into a terminal would run line by line.
    func paste(_ snippet: Snippet) {
        guard let content = content(of: snippet) else { return }
        guard let line = SnippetClipboardText.paste(content) else {
            core.showMessage(String(localized: "Only one-line snippets can be pasted"), tone: .neutral)
            return
        }
        noteUse(snippet)
        let previous = windowController.previousApp
        paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.pasteString(line, previousApp: previous)
    }

    func copyPath(_ snippet: Snippet) {
        noteUse(snippet)
        paletteCoordinator.hidePalette(restoreFocus: false)
        Paster.copyPlainText(snippet.path)
        core.showMessage(String(localized: "Copied path"))
    }

    func openInEditor(_ snippet: Snippet) {
        noteUse(snippet)
        paletteCoordinator.hidePalette(restoreFocus: false)
        let file = URL(filePath: snippet.path)
        guard let bundleID = settings.snippetEditorBundleID,
            let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else {
            NSWorkspace.shared.open(file)
            return
        }
        NSWorkspace.shared.open([file], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: - Files

    func move(_ snippet: Snippet, to source: SnippetSource) {
        Task { await perform(name: snippet.name) { replacing, _ in
            store.noteUse(of: try SnippetFileWriter.move(snippet.path, to: source.root, replacing: replacing))
        } }
    }

    func delete(_ snippet: Snippet) {
        Task {
            guard
                await core.confirm(
                    title: String(localized: "Move “\(snippet.name)” to the Trash?"), message: nil,
                    symbol: "trash", confirmTitle: String(localized: "Move to Trash"))
            else { return }
            do {
                try SnippetFileWriter.trash(snippet.path)
            } catch {
                await reportError(error, name: snippet.name)
            }
            store.rescan()
        }
    }

    // MARK: - Editor

    /// Nil starts a new snippet, prefilled with short text from the clipboard.
    func editSnippet(_ snippet: Snippet?) {
        guard settings.snippetsEnabled else { return }
        if let snippet {
            guard let text = try? SnippetScanner.readText(at: snippet.path) else {
                core.showMessage(String(localized: "The snippet’s file is gone"), tone: .danger)
                store.rescan()
                return
            }
            editor = SnippetEditorSession(editing: snippet, text: text)
            focusPath = snippet.path
        } else {
            guard let root = store.sources.first?.root ?? store.snippets.first?.root else {
                openSettings()
                return
            }
            let clipboard = NSPasteboard.general.string(forType: .string) ?? ""
            focusPath = nil
            editor = SnippetEditorSession(
                creatingIn: root, content: clipboard.count <= Self.prefillLimit ? clipboard : "")
        }
        paletteCoordinator.showPalette(mode: .snippetEditor)
    }

    func saveSnippet() {
        guard let editor, editor.canSave, !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            var savedPath: String?
            let saved = await perform(name: editor.trimmedName) { replacing, overwriting in
                if let original = editor.original {
                    savedPath = try SnippetFileWriter.update(
                        at: original.path, original: editor.originalText, name: editor.trimmedName,
                        keywords: editor.keywords, content: editor.content, replacing: replacing,
                        overwritingDiskChanges: overwriting)
                } else {
                    savedPath = try SnippetFileWriter.create(
                        in: editor.root, name: editor.trimmedName, keywords: editor.keywords,
                        content: editor.content, replacing: replacing)
                }
            }
            guard saved, self.editor === editor else { return }
            focusPath = savedPath
            closeEditor()
        }
    }

    /// Unsaved edits ask before they go.
    func cancelSnippetEditing() {
        guard core.palette.mode == .snippetEditor else { return }
        guard let editor, editor.isDirty else {
            closeEditor()
            return
        }
        Task {
            guard
                await core.confirm(
                    title: String(localized: "Discard changes?"), message: nil, symbol: Self.symbol,
                    confirmTitle: String(localized: "Discard"))
            else { return }
            if self.editor === editor { closeEditor() }
        }
    }

    func focusHandled() {
        focusPath = nil
    }

    func editorDidClose(_ editor: SnippetEditorSession) {
        if self.editor === editor { self.editor = nil }
    }

    private func closeEditor() {
        if core.palette.mode == .snippetEditor, !core.palette.pop(preservingSelection: true) {
            paletteCoordinator.hidePalette()
            core.palette.prepare(mode: .launcher)
        }
        editor = nil
    }

    /// Runs a write, asking before it replaces another file or overwrites a change made on disk.
    @discardableResult
    private func perform(
        name: String, _ write: (_ replacing: Bool, _ overwriting: Bool) throws -> Void
    ) async -> Bool {
        var replacing = false
        var overwriting = false
        while true {
            do {
                try write(replacing, overwriting)
                store.rescan()
                return true
            } catch SnippetFileError.exists(let existing) where !replacing {
                guard
                    await core.confirm(
                        title: String(localized: "Replace “\(existing)”?"),
                        message: String(localized: "A snippet with this name is already there. It moves to the Trash."),
                        symbol: Self.symbol, confirmTitle: String(localized: "Replace"))
                else { return false }
                replacing = true
            } catch SnippetFileError.changedOnDisk where !overwriting {
                guard
                    await core.confirm(
                        title: String(localized: "The file changed on disk"),
                        message: String(localized: "Save anyway? Only the fields you edited are written."),
                        symbol: Self.symbol, confirmTitle: String(localized: "Save"))
                else { return false }
                overwriting = true
            } catch {
                await reportError(error, name: name)
                store.rescan()
                return false
            }
        }
    }

    private func reportError(_ error: Error, name: String) async {
        await core.showNotice(
            title: String(localized: "Couldn’t Save “\(name)”"), message: error.localizedDescription,
            symbol: Self.symbol, tone: .danger)
    }
}

struct SnippetPreviewText: Equatable {
    let snippet: Snippet
    let content: String
}
