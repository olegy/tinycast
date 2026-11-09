import SwiftUI

struct SnippetEditorScreen: PaletteScreen {
    let coordinator: SnippetCoordinator
    let openMenuCorner: MenuPanelCorner?
    let openInputMenu: (PopoverMenuContent, MenuPanelCorner, Int) -> Void

    var rows: [Snippet] { [] }
    var primaryActionTitle: String {
        coordinator.editor?.isCreating == false
            ? String(localized: "Save") : String(localized: "Create")
    }
    let hidesSearchField = true
    let actsWithoutRows = true

    func hasPrimaryAction(at selection: Int) -> Bool { coordinator.editor != nil }
    func isPrimaryActionEnabled(at selection: Int) -> Bool { coordinator.editor?.canSave == true }
    func hasActions(at selection: Int) -> Bool { false }
    func ownsVerticalKeys(at selection: Int) -> Bool { true }

    func tab(at selection: Int, backwards: Bool) -> Bool {
        coordinator.editor?.advanceFocus(backwards: backwards)
        return true
    }

    func activate(at selection: Int) { coordinator.saveSnippet() }
    func secondary(at selection: Int) -> Bool { false }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        guard let editor = coordinator.editor else { return AnyView(Color.clear) }
        return AnyView(
            SnippetEditorView(editor: editor, openMenuCorner: openMenuCorner, openInputMenu: openInputMenu)
                .id(ObjectIdentifier(editor))
                .environment(coordinator))
    }
}

struct SnippetEditorView: View {
    @Bindable var editor: SnippetEditorSession
    let openMenuCorner: MenuPanelCorner?
    let openInputMenu: (PopoverMenuContent, MenuPanelCorner, Int) -> Void

    @Environment(SnippetCoordinator.self) private var coordinator
    @Environment(AppCore.self) private var core
    @Environment(PaletteState.self) private var palette
    @Environment(\.metrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var focusedField: SnippetEditorSession.Field?
    @FocusState private var focusedControl: SnippetEditorSession.Field?
    @State private var folderMenuFrame: CGRect = .zero

    private struct FocusRequest: Hashable {
        let field: SnippetEditorSession.Field
        let token: UUID
    }

    private var sources: [SnippetSource] { core.snippetStore.sources }

    var body: some View {
        ScrollView {
            VStack(spacing: metrics.spacing.xxl) {
                if editor.isCreating {
                    FormRow("Folder", alignment: .top) { folderField }
                }
                FormRow("Name", alignment: .top) { nameField }
                FormRow("Keywords", alignment: .top) { keywordsField }
                FormRow("Content", alignment: .top) {
                    FormTextArea(
                        text: $editor.content, selection: $editor.selection,
                        focused: focusBinding(.content), minimumHeight: metrics.size.textAreaUnit * 8,
                        label: String(localized: "Snippet content"), isCode: true,
                        moveFocus: editor.advanceFocus
                    )
                    .formFieldChrome(focused: focusedField == .content)
                }
            }
            .font(metrics.typography.rowTitle)
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(.horizontal, metrics.spacing.xxxl * 2)
            .padding(.vertical, metrics.spacing.md)
        }
        .scrollClipDisabled()
        .focusEffectDisabled()
        .task(id: FocusRequest(field: editor.focusedField, token: palette.focusToken)) {
            palette.noteEditingField(true)
            let field = editor.focusedField
            focusedControl = field == .folder ? .folder : nil
            await Task.yield()
            guard !Task.isCancelled else { return }
            focusedField = field
        }
        .onChange(of: focusedField) { _, field in
            if let field, editor.focusedField != field { editor.focusedField = field }
            focusedControl = field == .folder ? .folder : nil
        }
        .onChange(of: focusedControl) { _, field in
            if let field { focusedField = field }
        }
        .onDisappear {
            coordinator.editorDidClose(editor)
            palette.noteEditingField(false)
        }
    }

    private func detail(_ text: String) -> some View {
        Text(text).font(metrics.typography.rowTrailing)
            .foregroundStyle(Theme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.md) {
            FormTextInput(
                text: $editor.name, focused: focusBinding(.name),
                placeholder: String(localized: "File name, without .md"),
                label: String(localized: "Snippet name"), moveFocus: editor.advanceFocus
            )
            .frame(height: metrics.size.dialogButtonHeight)
            .formFieldChrome(focused: focusedField == .name)
            if let problem = editor.nameProblem, problem != .empty {
                detail(message(for: problem)).foregroundStyle(.orange)
            }
        }
    }

    private var keywordsField: some View {
        VStack(alignment: .leading, spacing: metrics.spacing.md) {
            FormTextInput(
                text: $editor.keywords, focused: focusBinding(.keywords),
                placeholder: String(localized: "Words to find it by"),
                label: String(localized: "Keywords"), moveFocus: editor.advanceFocus
            )
            .frame(height: metrics.size.dialogButtonHeight)
            .formFieldChrome(focused: focusedField == .keywords)
            detail(String(localized: "Separated by spaces. Folder names are keywords too."))
        }
    }

    private func message(for problem: SnippetFileName.Problem) -> String {
        switch problem {
        case .empty: String(localized: "A name is required.")
        case .slash: String(localized: "A name can’t contain slashes.")
        case .invalidCharacter: String(localized: "A name can’t contain : * ? \" < > |")
        case .leadingDot: String(localized: "A name can’t start with a dot.")
        }
    }

    private var selectedSource: SnippetSource? {
        sources.first { $0.root == editor.root }
    }

    private var folderField: some View {
        let isOpen = openMenuCorner == .belowControl(folderMenuFrame)
        return VStack(alignment: .leading, spacing: metrics.spacing.md) {
            HStack(spacing: metrics.spacing.md) {
                SnippetSourceIcon(icon: selectedSource?.icon, size: metrics.size.menuIcon)
                Text(selectedSource?.name ?? (editor.root as NSString).lastPathComponent)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(metrics.typography.disclosure)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
                    .animation(reduceMotion ? nil : Theme.MenuMotion.chevronAnimation, value: isOpen)
            }
            .padding(.horizontal, metrics.spacing.xl)
            .frame(height: metrics.size.dialogButtonHeight)
            .contentShape(.rect)
            .onTapGesture(perform: showFolderMenu)
            .focusable()
            .focused($focusedControl, equals: .folder)
            .onKeyPress(keys: [.return, .space]) { _ in
                showFolderMenu()
                return .handled
            }
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .global)
            } action: {
                folderMenuFrame = $0
            }
            .formFieldChrome(focused: focusedField == .folder)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Folder")
            .accessibilityValue(selectedSource?.name ?? "")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { showFolderMenu() }
            detail(abbreviated(editor.root))
        }
    }

    private func abbreviated(_ path: String) -> String {
        FileSearchScope.abbreviate(path, homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
    }

    private func showFolderMenu() {
        let items = sources.map { source in
            PopoverMenuItem(title: source.name, systemImage: SnippetSourceIcon.symbol(for: source.icon)) {
                editor.root = source.root
            }
        }
        let selected = sources.firstIndex { $0.root == editor.root } ?? 0
        openInputMenu(PopoverMenuContent(items: items), .belowControl(folderMenuFrame), selected)
    }

    private func focusBinding(_ field: SnippetEditorSession.Field) -> Binding<Bool> {
        Binding(
            get: { focusedField == field },
            set: { value in
                if value { focusedField = field } else if focusedField == field { focusedField = nil }
            })
    }
}
