import AppKit
import Combine
import SwiftUI

/// The first-launch wizard, built from the app's own controls; re-runnable from Settings.
struct OnboardingView: View {
    @State private var step = 0
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings
    @Environment(HotKeyManager.self) private var hotKeys

    @State private var accessibilityTrusted = Permissions.isAccessibilityTrusted()
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private static let lastStep = 2
    static let width: CGFloat = 520
    /// Only until the first layout measures the real one, which is what the window then takes.
    static let initialSize = CGSize(width: width, height: 352)

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            hero
            stepContent
            footer
        }
        // Less on top: the title bar adds 32pt, and the lights must be cleared.
        .padding(.top, Theme.Spacing.xs)
        .padding([.horizontal, .bottom], Theme.Spacing.xxl)
        .frame(maxWidth: .infinity)
        // The ideal height, not the window's, so sizing to it converges instead of feeding back.
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) {
            $0.size.height
        } action: {
            core.onboardingCoordinator.fit(height: $0)
        }
        // Only the gradient reaches under the titlebar; the content stays in the safe area.
        .background(
            LinearGradient(
                colors: [Theme.Colors.sheen, Color.clear],
                startPoint: .top, endPoint: .center
            )
            .ignoresSafeArea()
        )
        // Onboarding's shortcut step has a recorder too, and it isn't inside a `SettingsPane`.
        .shortcutRecorderPopoverHost()
        .animation(.easeInOut(duration: 0.2), value: step)
        .onAppear { accessibilityTrusted = Permissions.isAccessibilityTrusted() }
        .onReceive(refreshTimer) { _ in
            let trusted = Permissions.isAccessibilityTrusted()
            if trusted != accessibilityTrusted { accessibilityTrusted = trusted }
        }
    }

    // MARK: - Hero (icon/glyph + title + subtitle)

    private var hero: some View {
        VStack(spacing: Theme.Spacing.md) {
            heroMark
            VStack(spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(.title2.weight(.bold))
                subtitle
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var heroMark: some View {
        if step == 0 {
            Image(nsImage: Self.appIcon)
                .resizable()
                .frame(width: 60, height: 60)
        } else {
            Image(systemName: heroSymbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(heroTint)
                .frame(width: 60, height: 60)
                .background(Circle().fill(heroTint.opacity(0.14)))
        }
    }

    private var title: String {
        switch step {
        case 0: String(localized: "Welcome to Tinycast")
        case 1: String(localized: "Enable Pasting")
        default: String(localized: "You're all set")
        }
    }

    private var subtitle: Text {
        switch step {
        case 0: Text("Set a shortcut to summon the launcher from anywhere.")
        case 1: Text("Let Tinycast paste items back into the app you were using.")
        default: readyMessage
        }
    }

    private var heroSymbol: String {
        switch step {
        case 1: "accessibility"
        default: "checkmark"
        }
    }

    private var heroTint: Color {
        switch step {
        case 1: .blue
        default: .green
        }
    }

    private var readyMessage: Text {
        if let caps = hotKeys.binding(for: .togglePalette)?.keycaps {
            return Text("Press \(KeyCapChip.inlineText(caps)) anytime to start using Tinycast.")
        }
        return Text("Tinycast is ready. Set a shortcut in Settings to summon it.")
    }

    // MARK: - Step content

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0: shortcutStep
        case 1: accessibilityStep
        default: doneStep
        }
    }

    private var shortcutStep: some View {
        @Bindable var settings = settings
        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            OnboardingCard {
                OnboardingRow(
                    title: String(localized: "onboarding-open-launcher", defaultValue: "App Launcher"),
                    subtitle: String(localized: "Press this shortcut to open Tinycast."),
                    systemImage: "magnifyingglass", tint: .blue
                ) {
                    ShortcutRecorder(action: .togglePalette)
                }
                OnboardingDivider()
                OnboardingRow(
                    title: String(localized: "Launch at login"),
                    subtitle: String(localized: "Start Tinycast automatically when you log in."),
                    systemImage: "power", tint: .green
                ) {
                    Toggle("", isOn: $settings.launchAtLogin)
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }
            caption(String(localized: "You can change these anytime in Settings."))
        }
    }

    private var accessibilityStep: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            OnboardingCard {
                OnboardingRow(
                    title: String(localized: "Accessibility"),
                    subtitle: String(
                        localized: "Allows pasting clipboard items and quicklinks into active apps."),
                    systemImage: "accessibility", tint: .blue
                ) {
                    statusBadge
                }
            }
            caption(String(localized: "Optional — you can enable this later in Settings › Permissions."))
        }
    }

    private var doneStep: some View {
        caption(String(localized: "Everything's ready. Hit Get Started to open the launcher."))
            .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Footer (step dots + navigation)

    private var footer: some View {
        VStack(spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(0...Self.lastStep, id: \.self) { index in
                    Circle()
                        .fill(index == step ? Color.primary : Color.primary.opacity(0.2))
                        .frame(width: 7, height: 7)
                }
            }
            HStack {
                if step > 0 {
                    Button {
                        step -= 1
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if showsSkip {
                    Button("Skip") { advance() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                Button(primaryTitle, action: primaryAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var showsSkip: Bool {
        step == 1 && !accessibilityTrusted
    }

    private var primaryTitle: String {
        switch step {
        case 0: String(localized: "Continue")
        case 1: accessibilityTrusted ? String(localized: "Continue") : String(localized: "Grant Access")
        default: String(localized: "Get Started")
        }
    }

    private func primaryAction() {
        switch step {
        case 1 where !accessibilityTrusted:
            Permissions.openAccessibilitySettings()
        case Self.lastStep:
            core.onboardingCoordinator.finishOnboarding()
        default:
            advance()
        }
    }

    private func advance() {
        step = min(step + 1, Self.lastStep)
    }

    // MARK: - Shared bits

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, Theme.Spacing.xs)
    }

    private var statusBadge: some View {
        HStack(spacing: Theme.Spacing.xs + 1) {
            Image(
                systemName: accessibilityTrusted
                    ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            Text(accessibilityTrusted ? "Granted" : "Not granted")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(accessibilityTrusted ? Color.green : Color.orange)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .background(
            Capsule().fill((accessibilityTrusted ? Color.green : Color.orange).opacity(0.14)))
    }

    // Read the bundle directly: the app icon is generic until LaunchServices registers.
    private static let appIcon: NSImage = {
        if let name = Bundle.main.infoDictionary?["CFBundleIconFile"] as? String,
            let url = Bundle.main.url(forResource: name, withExtension: "icns"),
            let image = NSImage(contentsOf: url)
        {
            return image
        }
        return NSApp.applicationIconImage
    }()
}
