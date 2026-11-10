import Foundation

/// The status icons beside the launcher's search field. See docs/features/status-icons.md.
@MainActor
@Observable
final class StatusIconCoordinator {
    struct Icon: Identifiable, Equatable {
        let id: String
        let reading: StatusReading
        /// What a click runs; nil leaves the icon a tooltip and nothing more.
        let command: UUID?
    }

    private var dnsReading: StatusReading?
    @ObservationIgnored private var dnsResolvers: [String] = []
    @ObservationIgnored private var dnsMonitor: DNSResolverMonitor?
    private let settings: AppSettings
    private let customCommands: CustomCommandStore
    private let customCommandCoordinator: CustomCommandCoordinator

    init(
        settings: AppSettings, customCommands: CustomCommandStore,
        customCommandCoordinator: CustomCommandCoordinator
    ) {
        self.settings = settings
        self.customCommands = customCommands
        self.customCommandCoordinator = customCommandCoordinator
    }

    var icons: [Icon] {
        guard let dnsReading else { return [] }
        return [Icon(id: "dns", reading: dnsReading, command: runnable(settings.statusDNSCommand))]
    }

    /// Subscribes only while the feature and its DNS icon are both on; safe to call on any change.
    func applyEnabled() {
        guard settings.statusIconsEnabled, settings.statusDNSEnabled else {
            dnsMonitor?.stop()
            dnsMonitor = nil
            dnsReading = nil
            return
        }
        guard dnsMonitor == nil else { return updateDNSReading() }
        let monitor = DNSResolverMonitor { [weak self] resolvers in
            self?.dnsResolvers = resolvers
            self?.updateDNSReading()
        }
        dnsMonitor = monitor
        monitor.start()
    }

    func run(_ icon: Icon) {
        guard let command = icon.command else { return }
        customCommandCoordinator.runCustomCommand(id: command)
    }

    private func updateDNSReading() {
        let reading = DNSStatus.reading(
            resolvers: dnsResolvers,
            local: DNSStatus.localResolvers(from: settings.statusDNSLocalResolvers))
        if reading != dnsReading { dnsReading = reading }
    }

    private func runnable(_ id: UUID?) -> UUID? {
        guard settings.customCommandsEnabled, let id, customCommands.command(id: id)?.isEnabled == true
        else { return nil }
        return id
    }
}
