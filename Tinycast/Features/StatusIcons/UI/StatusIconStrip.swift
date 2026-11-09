import SwiftUI

/// The status icons at the left of the palette's bottom bar, one small tile each.
struct StatusIconStrip: View {
    @Environment(AppCore.self) private var core
    @Environment(\.metrics) private var metrics

    var body: some View {
        let coordinator = core.statusIconCoordinator
        // All or nothing: when the bar runs short, the icons give way to the action hints.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: metrics.spacing.sm) {
                ForEach(coordinator.icons) { icon in
                    StatusIconTile(icon: icon) { coordinator.run(icon) }
                }
            }
            // Lines the first tile up with the list rows and the search field above it.
            .padding(.leading, metrics.spacing.md)
            Color.clear.frame(width: 0, height: 0)
        }
    }
}

private struct StatusIconTile: View {
    /// About as tall as the bar's key-cap hints, and well under a list row's icon.
    private static let side: CGFloat = 20
    private static let cornerFraction: CGFloat = 0.23
    private static let glyphFraction: CGFloat = 0.5
    private static let attentionOpacity: Double = 0.3

    let icon: StatusIconCoordinator.Icon
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.metrics) private var metrics

    var body: some View {
        let side = metrics.scaled(Self.side)
        let tile = RoundedRectangle(cornerRadius: side * Self.cornerFraction, style: .continuous)
            .fill(fill)
            .frame(width: side, height: side)
            .overlay {
                Image(systemName: icon.reading.symbol)
                    .font(.system(size: side * Self.glyphFraction, weight: .medium))
                    .foregroundStyle(
                        hovered && isClickable ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: icon.reading.summary))
        Group {
            if isClickable {
                Button(action: action) { tile.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .onHover { hovered = $0 }
                    .animation(.easeOut(duration: Theme.Duration.hover), value: hovered)
            } else {
                tile
            }
        }
        .tooltip(icon.reading.summary, alignment: .leading)
    }

    private var isClickable: Bool { icon.command != nil }

    private var fill: Color {
        switch icon.reading.tone {
        case .normal: Theme.Colors.controlSurface
        case .attention: Theme.Colors.warning.opacity(Self.attentionOpacity)
        }
    }
}
