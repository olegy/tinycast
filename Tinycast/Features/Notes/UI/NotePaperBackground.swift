import SwiftUI

/// The note window's surface: one paper, with the tint's wash over it when the paper takes one.
struct NotePaperBackground: View {
    let paper: NotePaper
    let tint: NoteTint

    var body: some View {
        surface.overlay { tint.color?.opacity(Theme.Colors.NoteTint.opacity) }
    }

    @ViewBuilder
    private var surface: some View {
        switch paper {
        case .glass: Theme.Colors.panelScrim.background(GlassEffectView())
        case .frosted: NoteFrostedMaterial()
        case .solid: Theme.Colors.NotePaper.solid
        case .cream: Theme.Colors.NotePaper.cream
        case .white: Theme.Colors.NotePaper.white
        }
    }
}

extension NotePaper {
    var chrome: Color {
        switch self {
        case .glass, .frosted, .solid: Theme.Colors.NotePaper.systemChrome
        case .cream: Theme.Colors.NotePaper.creamChrome
        case .white: Theme.Colors.NotePaper.whiteChrome
        }
    }
}

extension NoteTint {
    var color: Color? {
        switch self {
        case .none: nil
        case .graphite: Theme.Colors.NoteTint.graphite
        case .amber: Theme.Colors.NoteTint.amber
        case .rose: Theme.Colors.NoteTint.rose
        case .moss: Theme.Colors.NoteTint.moss
        case .indigo: Theme.Colors.NoteTint.indigo
        }
    }
}

private struct NoteFrostedMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
