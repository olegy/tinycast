import SwiftUI

/// The choices a command printed; ↵ runs the command again with the chosen one as `$1`.
struct CommandOptionsScreen: PaletteScreen {
    let session: CommandOptionsSession?
    let coordinator: CustomCommandCoordinator
    let vm: PaletteState

    let rows: [CommandOption]

    init(session: CommandOptionsSession?, coordinator: CustomCommandCoordinator, vm: PaletteState) {
        self.session = session
        self.coordinator = coordinator
        self.vm = vm
        rows = session?.rows(matching: vm.query) ?? []
    }

    var primaryActionTitle: String { String(localized: "Run") }

    var landingSelection: Int { session?.landing(in: rows, preferring: nil) ?? 0 }

    private func option(at selection: Int) -> CommandOption? {
        rows.indices.contains(selection) ? rows[selection] : nil
    }

    func isPrimaryActionEnabled(at selection: Int) -> Bool {
        guard let option = option(at: selection), let session else { return false }
        return !option.isDisabled && !session.isBusy
    }

    func hasActions(at selection: Int) -> Bool { false }

    func activate(at selection: Int) {
        guard let option = option(at: selection) else { return }
        coordinator.chooseOption(option)
    }

    func secondary(at selection: Int) -> Bool { false }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        if let session {
            if let failure = session.failure {
                EmptyResults(
                    text: String(localized: "“\(session.command.name)” Failed"), detail: failure,
                    systemImage: "exclamationmark.triangle")
            } else if session.list == nil {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if rows.isEmpty {
                EmptyResults(
                    text: vm.query.isEmpty
                        ? String(localized: "No options") : String(localized: "No matching options"))
            } else {
                CommandOptionRows(
                    options: rows, fallbackSymbol: session.command.symbol,
                    selectedID: option(at: selection)?.id, scroll: scroll,
                    onSelect: { option in
                        if let index = rows.firstIndex(of: option) { vm.selection = index }
                    },
                    onActivate: { activate(at: vm.selection) })
            }
        } else {
            Color.clear
        }
    }
}

private struct CommandOptionRows: View {
    @Environment(\.metrics) private var metrics
    let options: [CommandOption]
    let fallbackSymbol: String
    let selectedID: CommandOption.ID?
    let scroll: ScrollIntent
    let onSelect: (CommandOption) -> Void
    let onActivate: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(options, id: \.rowKey) { option in
                        CommandOptionRow(
                            option: option, symbol: option.icon ?? fallbackSymbol,
                            selected: option.id == selectedID
                        )
                        .selectionFrame(option.id == selectedID)
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(option) }
                        .simultaneousGesture(
                            TapGesture(count: 2).onEnded {
                                onSelect(option)
                                onActivate()
                            })
                    }
                }
                .padding(.horizontal, metrics.spacing.md)
                .padding(.top, metrics.spacing.xs)
                .padding(.bottom, metrics.spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .thinScrollbar()
            .scrollFollowsSelection(
                scroll, row: selectedID.map(String.init),
                atOrigin: selectedID != nil && selectedID == options.first?.id, proxy: proxy)
        }
    }
}

private struct CommandOptionRow: View {
    @Environment(\.metrics) private var metrics
    let option: CommandOption
    let symbol: String
    let selected: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        return hovered ? Theme.Colors.rowHover : .clear
    }

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            SymbolImage(name: symbol, size: metrics.size.menuIcon)
                .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
            Text(option.title).font(metrics.typography.rowTitle).lineLimit(1)
            Spacer(minLength: metrics.spacing.sm)
            if let subtitle = option.subtitle {
                Text(subtitle)
                    .font(metrics.typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(option.isDisabled ? Theme.Colors.textTertiary : Theme.Colors.textPrimary)
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous).fill(fill))
        .armedHover($hovered)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension CommandOption {
    /// The scroll follower keys rows by string.
    fileprivate var rowKey: String { String(id) }
}
