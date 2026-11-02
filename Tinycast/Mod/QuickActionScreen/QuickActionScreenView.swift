import AppKit
import SwiftUI

/// Icon and name on the left, the route on the right, where Quick AI keeps its own.
struct QuickActionScreenHeader: View {
    let coordinator: QuickActionScreenCoordinator
    let session: QuickActionSession
    let openMenuCorner: MenuPanelCorner?
    let openInputMenu: (PopoverMenuContent, MenuPanelCorner, Int) -> Void

    @Environment(\.metrics) private var metrics
    @State private var modelFrame: CGRect = .zero
    @State private var effortFrame: CGRect = .zero

    var body: some View {
        HStack(spacing: metrics.spacing.md) {
            SymbolImage(name: session.action.symbol, size: metrics.size.quickActionHeaderIcon)
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(session.action.title)
                .font(metrics.typography.searchField)
                .lineLimit(1)
            Spacer(minLength: metrics.spacing.md)
            if session.action.usesTranslationFramework {
                HeaderMenuButton(
                    title: TextTranslator.displayName(of: session.language), systemImage: "globe",
                    isOpen: openMenuCorner == .belowControl(modelFrame),
                    help: String(localized: "Translate to  ⌘P"), action: openLanguageMenu
                )
                .fixedSize()
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { modelFrame = $0 }
            } else {
                AIModelButton(
                    title: coordinator.modelTitle, icon: coordinator.modelIcon,
                    isOpen: openMenuCorner == .belowControl(modelFrame), action: openModelMenu
                )
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { modelFrame = $0 }
                if !coordinator.efforts.isEmpty {
                    AIReasoningButton(
                        title: coordinator.effortTitle,
                        isOpen: openMenuCorner == .belowControl(effortFrame), action: openEffortMenu
                    )
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                        effortFrame = $0
                    }
                }
            }
        }
        .disabled(session.isRunning)
        .onChange(of: coordinator.menuRequest) {
            guard !session.isRunning else { return }
            if session.action.usesTranslationFramework {
                openLanguageMenu()
            } else {
                openModelMenu()
            }
        }
    }

    private func openModelMenu() {
        coordinator.prepareModelMenu()
        let menu = QuickActionModelMenu.models(coordinator: coordinator, session: session)
        openInputMenu(menu.content, .belowControl(modelFrame), menu.highlight)
    }

    private func openEffortMenu() {
        let menu = QuickActionModelMenu.efforts(coordinator: coordinator, session: session)
        openInputMenu(menu.content, .belowControl(effortFrame), menu.highlight)
    }

    private func openLanguageMenu() {
        let menu = QuickActionModelMenu.languages(coordinator: coordinator, session: session)
        openInputMenu(menu.content, .belowControl(modelFrame), menu.highlight)
    }
}

/// The text to send above, about a quarter of the height; the reply takes the rest.
struct QuickActionScreenView: View {
    let coordinator: QuickActionScreenCoordinator
    @Bindable var session: QuickActionSession
    let palette: PaletteState

    @Environment(\.metrics) private var metrics

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                input
                    .frame(height: max(proxy.size.height * 0.28, metrics.size.headerHeight * 2))
                Divider()
                    .padding(.horizontal, metrics.spacing.xl)
                reply
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .task(id: palette.focusToken) { palette.noteEditingField(true) }
        .onDisappear { palette.noteEditingField(false) }
    }

    // MARK: - Input

    private var input: some View {
        QuickActionTextEditor(
            text: $session.text, isEditable: session.phase == .editing,
            focusToken: palette.focusToken, onKey: handle
        )
        .overlay(alignment: .topLeading) {
            if session.text.isEmpty {
                Text("Type or paste the text to work on…")
                    .font(metrics.typography.rowTitle)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .padding(.horizontal, metrics.spacing.xl * 2)
                    .padding(.vertical, metrics.spacing.md)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottomTrailing) { inputStatus }
        .opacity(session.phase == .editing ? 1 : 0.7)
    }

    @ViewBuilder
    private var inputStatus: some View {
        let label: String? =
            if session.isTooLong {
                String(localized: "That selection is too long to work on.")
            } else {
                switch session.source {
                case .selection: String(localized: "Selection")
                case .clipboard: String(localized: "Clipboard")
                case .none: nil
                }
            }
        if let label {
            Text(label)
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(session.isTooLong ? Theme.Colors.destructive : Theme.Colors.textTertiary)
                .padding(.horizontal, metrics.spacing.sm)
                .padding(.vertical, metrics.spacing.xxs)
                .frosted(in: Capsule())
                .padding(.horizontal, metrics.spacing.xl)
                .padding(.bottom, metrics.spacing.sm)
                .allowsHitTesting(false)
        }
    }

    private func handle(_ key: QuickActionTextEditor.Key) -> Bool {
        switch key {
        case .return:
            coordinator.primary()
            return true
        case .shiftReturn:
            return session.phase != .editing
        case .commandReturn:
            guard session.hasResult else { return true }
            coordinator.copy()
            return true
        case .commandE:
            return coordinator.edit()
        case .commandP:
            coordinator.requestMenu()
            return true
        }
    }

    // MARK: - Reply

    private var reply: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: metrics.spacing.md) {
                replyContent
                if let reason = coordinator.pasteUnavailableReason, session.hasResult {
                    Label(reason, systemImage: "info.circle")
                        .font(metrics.typography.rowTrailing)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, metrics.spacing.xl * 2)
            .padding(.vertical, metrics.spacing.xl)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    @ViewBuilder
    private var replyContent: some View {
        switch session.phase {
        case .editing where session.output.isEmpty:
            hint
        case .editing:
            VStack(alignment: .leading, spacing: metrics.spacing.md) {
                hint
                output.opacity(0.5)
            }
        case .running where session.output.isEmpty:
            HStack(spacing: metrics.spacing.md) {
                ProgressView().controlSize(.small)
                Text("Thinking…").foregroundStyle(Theme.Colors.textSecondary)
                Text("esc to stop").foregroundStyle(Theme.Colors.textTertiary)
            }
            .font(metrics.typography.rowTitle)
        case .running, .finished:
            output
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(metrics.typography.rowTitle)
                .foregroundStyle(Theme.Colors.textSecondary)
                .textSelection(.enabled)
        case .needsLanguageDownload:
            downloadPrompt
        }
    }

    private var hint: some View {
        Text("↵ to run \(session.action.title)  ·  ⇧↵ for a new line")
            .font(metrics.typography.rowTitle)
            .foregroundStyle(Theme.Colors.textTertiary)
    }

    @ViewBuilder
    private var output: some View {
        let chunks = session.diff
        if !chunks.isEmpty {
            // One `Text` per chunk would break the wrap, so the runs are styled inside one string.
            prose(Text(attributed(chunks)))
        } else if session.action.rendersMarkdown {
            ChatMarkdownText(
                blocks: MarkdownBlock.parse(session.output, midStream: session.isRunning))
        } else {
            prose(Text(session.output))
        }
    }

    private func prose(_ text: Text) -> some View {
        text
            .font(metrics.typography.rowTitle)
            .lineSpacing(metrics.spacing.xs)
            .textSelection(.enabled)
    }

    private func attributed(_ chunks: [TextDiffEngine.Chunk]) -> AttributedString {
        chunks.reduce(into: AttributedString()) { result, chunk in
            switch chunk {
            case .equal(let text):
                result.append(AttributedString(text))
            case .inserted(let text):
                var run = AttributedString(text)
                run.foregroundColor = Theme.Colors.success
                result.append(run)
            case .deleted(let text):
                var run = AttributedString(text)
                run.foregroundColor = Theme.Colors.destructive
                run.strikethroughStyle = .single
                result.append(run)
            }
        }
    }

    private var downloadPrompt: some View {
        let language = TextTranslator.displayName(of: session.language)
        return VStack(alignment: .leading, spacing: metrics.spacing.xs) {
            Text("\(language) hasn't been downloaded yet.")
                .font(metrics.typography.rowTitle)
                .foregroundStyle(Theme.Colors.textSecondary)
            Text("Click **Translation Languages…** in Language & Region, then download it.")
                .font(metrics.typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
    }
}

/// A plain-text editor that hands ↵ and the screen's chords to the screen before typing them.
struct QuickActionTextEditor: NSViewRepresentable {
    enum Key {
        case `return`
        case shiftReturn
        case commandReturn
        case commandE
        case commandP
    }

    @Binding var text: String
    let isEditable: Bool
    let focusToken: UUID
    let onKey: (Key) -> Bool

    @Environment(\.metrics) private var metrics

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay

        let view = InputView(usingTextLayoutManager: true)
        view.delegate = context.coordinator
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.lineFragmentPadding = 0
        view.string = text
        view.onKey = { [weak coordinator = context.coordinator] key in
            coordinator?.input.onKey(key) ?? false
        }
        scroll.documentView = view
        context.coordinator.view = view
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.input = self
        guard let view = context.coordinator.view else { return }
        let font = metrics.typography.textNSFont(.body)
        if view.font != font { view.font = font }
        let color = NSColor(Theme.Colors.textPrimary)
        if view.textColor != color { view.textColor = color }
        if view.insertionPointColor != color { view.insertionPointColor = color }
        let inset = NSSize(width: metrics.spacing.xl * 2, height: metrics.spacing.md)
        if view.textContainerInset != inset { view.textContainerInset = inset }
        if view.isEditable != isEditable { view.isEditable = isEditable }
        view.isSelectable = true
        if view.string != text {
            view.string = text
            view.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
        if context.coordinator.focusToken != focusToken {
            context.coordinator.focusToken = focusToken
            // Next turn: the show that bumped the token is still settling the window's focus.
            Task { @MainActor [weak view] in
                guard let view, let window = view.window else { return }
                window.makeFirstResponder(view)
            }
        }
    }

    final class InputView: NSTextView {
        var onKey: ((Key) -> Bool)?
        private let editingUndoManager = UndoManager()

        override var undoManager: UndoManager? { editingUndoManager }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.makeFirstResponder(self)
        }

        override func keyDown(with event: NSEvent) {
            if !hasMarkedText(), let key = Self.key(for: event), onKey?(key) == true { return }
            super.keyDown(with: event)
        }

        // The panel has no Edit menu of its own, so the chords are answered here.
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard window?.firstResponder === self, !hasMarkedText() else {
                return super.performKeyEquivalent(with: event)
            }
            let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
            if let key = Self.key(for: event), key != .return, key != .shiftReturn {
                return onKey?(key) == true || super.performKeyEquivalent(with: event)
            }
            guard isEditable, event.charactersIgnoringModifiers?.lowercased() == "z",
                modifiers == .command || modifiers == [.command, .shift]
            else { return super.performKeyEquivalent(with: event) }
            guard !event.isARepeat else { return true }
            breakUndoCoalescing()
            if modifiers == .command {
                editingUndoManager.undo()
            } else {
                editingUndoManager.redo()
            }
            return true
        }

        private static func key(for event: NSEvent) -> Key? {
            let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
            let isReturn =
                Int(event.keyCode) == 36 || Int(event.keyCode) == 76
            if isReturn {
                switch modifiers {
                case []: return .return
                case .shift: return .shiftReturn
                case .command: return .commandReturn
                default: return nil
                }
            }
            guard modifiers == .command, !event.isARepeat else { return nil }
            switch ASCIIKeyboardLayout.character(for: event)?.lowercased() {
            case "e": return .commandE
            case "p": return .commandP
            default: return nil
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var input: QuickActionTextEditor
        weak var view: InputView?
        var focusToken: UUID?

        init(_ input: QuickActionTextEditor) { self.input = input }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView, view.string != input.text else {
                return
            }
            input.text = view.string
        }

        /// ⇥ would leave for the palette's own focus ring, which this screen has no use for.
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            commandSelector == #selector(NSResponder.insertBacktab(_:))
        }
    }
}
