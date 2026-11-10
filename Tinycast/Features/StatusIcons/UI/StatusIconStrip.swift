import SwiftUI

/// The status icons at the right of the launcher's search field, one emoji each.
struct StatusIconStrip: View {
    @Environment(AppCore.self) private var core

    var body: some View {
        let coordinator = core.statusIconCoordinator
        HStack(spacing: 0) {
            ForEach(coordinator.icons) { icon in
                StatusIcon(icon: icon) { coordinator.run(icon) }
            }
        }
        .fixedSize()
    }
}

private struct StatusIcon: View {
    private static let emojiSize: CGFloat = 15

    let icon: StatusIconCoordinator.Icon
    let action: () -> Void
    @Environment(\.metrics) private var metrics

    var body: some View {
        let glyph = Text(verbatim: icon.reading.emoji)
            .font(.system(size: metrics.scaled(Self.emojiSize)))
            .accessibilityLabel(Text(verbatim: icon.reading.summary))
        Group {
            // The bar's own hover and press chrome, so it reads like the footer's hints.
            if icon.command != nil {
                BarButton(chrome: .rounded, isCompact: true, action: action) { glyph }
            } else {
                glyph
                    .padding(.horizontal, metrics.spacing.sm)
                    .frame(height: metrics.size.barButtonHeight)
            }
        }
        .help(icon.reading.summary)
    }
}
