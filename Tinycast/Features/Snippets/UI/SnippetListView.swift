import AppKit
import SwiftUI

struct SnippetList: View {
    @Environment(\.metrics) private var metrics
    let results: [Snippet]
    let store: SnippetStore
    let selectedID: Snippet.ID?
    /// Changes only when the list should scroll, so mouse selection never yanks the position.
    let scroll: ScrollIntent
    let onSelect: (Snippet) -> Void
    let onActivate: () -> Void
    let onActions: (Snippet) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(results) { snippet in
                        SnippetRow(
                            snippet: snippet, icon: store.source(of: snippet)?.icon,
                            selected: snippet.id == selectedID
                        )
                        .selectionFrame(snippet.id == selectedID)
                        .contentShape(Rectangle())
                        .onRightClick { onActions(snippet) }
                        // A click only selects; acting needs ↵ or a double click, as in Clipboard History.
                        .onRowClick(
                            select: { onSelect(snippet) },
                            activate: {
                                onSelect(snippet)
                                onActivate()
                            })
                        .id(snippet.id)
                    }
                }
                .padding(.horizontal, metrics.spacing.md)
                .padding(.top, metrics.spacing.xs)
                .padding(.bottom, metrics.spacing.md)
                .hideNativeScrollers()
                .scrollOriginAnchor()
            }
            .edgeDissolve()
            .thinScrollbar()
            .scrollFollowsSelection(
                scroll, row: selectedID, atOrigin: selectedID == results.first?.id, proxy: proxy)
        }
    }
}

private struct SnippetRow: View {
    @Environment(\.metrics) private var metrics
    let snippet: Snippet
    let icon: String?
    let selected: Bool
    @State private var hovered = false

    /// Matches Clipboard History's glyph, which sits small inside its row-icon tile.
    private static let iconScale: CGFloat = 0.6

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        HStack(spacing: metrics.spacing.lg) {
            SnippetSourceIcon(icon: icon, size: metrics.size.resultRowIcon * Self.iconScale)
                .frame(width: metrics.size.resultRowIcon, height: metrics.size.resultRowIcon)
            Text(snippet.name)
                .font(metrics.typography.rowTitle)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, metrics.spacing.md)
        .padding(.vertical, metrics.spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: metrics.radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
    }
}

/// A snippets folder's `.vault.json` icon: an emoji, an SF Symbol, or the plain folder.
struct SnippetSourceIcon: View {
    let icon: String?
    let size: CGFloat

    static let fallback = "folder"

    /// For menus, which take a symbol only; an emoji icon shows the folder there.
    static func symbol(for icon: String?) -> String {
        guard let icon else { return fallback }
        return resolvedSymbol(icon) ?? fallback
    }

    private static func resolvedSymbol(_ name: String) -> String? {
        [name, name.lowercased()].first { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }
    }

    private static func isEmoji(_ text: String) -> Bool {
        text.count == 1 && text.unicodeScalars.contains { $0.properties.isEmojiPresentation || $0.value > 0x2000 }
    }

    var body: some View {
        if let icon, Self.isEmoji(icon) {
            Text(icon).font(.system(size: size * 0.8))
        } else {
            SymbolImage(name: icon.flatMap(Self.resolvedSymbol) ?? Self.fallback, size: size * 0.8)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }
}

struct SnippetEmptyState: View {
    let text: String
    let action: String
    let perform: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: SnippetCoordinator.symbol).font(.largeTitle)
                .symbolRenderingMode(.hierarchical).foregroundStyle(.tertiary)
            Text(text).foregroundStyle(.secondary)
            Button(action, action: perform)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The selected snippet as it reads: name, tags, then the Markdown with highlighted code.
struct SnippetPreview: View {
    @Environment(\.metrics) private var metrics
    let snippet: Snippet?
    let onClick: () -> Void
    @State private var loaded: Loaded?

    private struct Loaded: Equatable {
        let snippet: Snippet
        let content: String
    }

    var body: some View {
        if let snippet {
            ScrollView {
                VStack(alignment: .leading, spacing: metrics.spacing.lg) {
                    Text(snippet.name)
                        .font(metrics.typography.sectionHeader)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    let tags = snippet.folders.map { "/" + $0.lowercased() } + snippet.keywordTags.map { "#" + $0 }
                    if !tags.isEmpty { tagLine(tags) }
                    Rectangle().fill(Theme.Colors.separator).frame(height: Theme.Size.hairline)
                    if let loaded, loaded.snippet == snippet {
                        ChatMarkdownText(blocks: MarkdownBlock.parse(loaded.content))
                    }
                }
                .padding(.horizontal, metrics.spacing.xl)
                .padding(.vertical, metrics.spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .edgeDissolve()
            .background(ClickWatcher(onClick: onClick))
            .task(id: snippet) {
                let text = try? await SnippetScanner.text(at: snippet.path)
                guard !Task.isCancelled else { return }
                loaded = Loaded(snippet: snippet, content: SnippetDocument(text: text ?? "").content)
            }
        } else {
            Color.clear
        }
    }

    private func tagLine(_ tags: [String]) -> some View {
        Text(tags.joined(separator: "  "))
            .font(metrics.typography.rowTrailing)
            .foregroundStyle(Theme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Hears a click anywhere over its frame without taking it, so text selection still works.
private struct ClickWatcher: NSViewRepresentable {
    let onClick: () -> Void

    func makeNSView(context: Context) -> ClickWatcherView { ClickWatcherView() }

    func updateNSView(_ view: ClickWatcherView, context: Context) {
        view.onClick = onClick
    }
}

private final class ClickWatcherView: NSView {
    var onClick: () -> Void = {}
    private var monitor: Any?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.noteClick(event)
            return event
        }
    }

    private func noteClick(_ event: NSEvent) {
        guard let window, event.window === window,
            visibleRect.contains(convert(event.locationInWindow, from: nil))
        else { return }
        onClick()
    }
}
