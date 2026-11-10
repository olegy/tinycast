import SwiftUI

struct StatusIconsSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        return Form {
            FeatureSwitchSection(
                anchor: .statusIconsStatusIcons,
                enableTitle: "Enable Status Icons",
                enableSubtitle: "Show status icons at the right of the search field.",
                isEnabled: $settings.statusIconsEnabled,
                showsIcon: true,
                showsHeader: false)

            StatusDNSSection()
                .settingsEnabled(settings.statusIconsEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.statusIcons)
    }
}

private struct StatusDNSSection: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppCore.self) private var core

    var body: some View {
        @Bindable var settings = settings
        return Section {
            Toggle(isOn: $settings.statusDNSEnabled) {
                SettingsRowTitle(.statusIconsDNS, "Show DNS icon")
                Text("🔒 local (encrypted), 🌐 provider, 🤷 unknown status")
            }
            TextField(
                text: $settings.statusDNSLocalResolvers,
                prompt: Text(verbatim: DNSStatus.defaultLocalResolvers)
            ) {
                SettingsRowTitle(.statusIconsDNS, "Local resolvers")
            }
            Picker(selection: command) {
                Text("Nothing").tag(UUID?.none)
                ForEach(commands) { command in
                    Text(verbatim: command.name).tag(UUID?.some(command.id))
                }
            } label: {
                SettingsRowTitle(.statusIconsDNS, "On click, run")
            }
            .settingsEnabled(settings.customCommandsEnabled)
        } header: {
            SettingsSectionHeader(.statusIconsDNS)
        } footer: {
            if !settings.customCommandsEnabled {
                Text("Turn on Custom Commands in Settings › Commands to run one on click.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var commands: [CustomCommand] {
        core.customCommands.commands.filter(\.isEnabled)
    }

    /// A deleted or disabled command has no row, so it reads as Nothing rather than a blank.
    private var command: Binding<UUID?> {
        Binding(
            get: {
                guard let id = settings.statusDNSCommand, commands.contains(where: { $0.id == id })
                else { return nil }
                return id
            },
            set: { settings.statusDNSCommand = $0 })
    }
}
