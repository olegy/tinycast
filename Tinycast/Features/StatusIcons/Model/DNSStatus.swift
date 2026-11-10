import Foundation

/// Whether the system's DNS resolvers are all local ones. See docs/features/status-icons.md.
enum DNSStatus: Equatable, Sendable {
    case local
    case external
    /// No resolver at all: offline, or the monitor could not read the system's state.
    case noServers

    static let defaultLocalResolvers = "127.0.0.1, ::1"

    static func classify(resolvers: [String], local: Set<String>) -> DNSStatus {
        guard !resolvers.isEmpty else { return .noServers }
        return resolvers.allSatisfy { local.contains(normalized($0)) } ? .local : .external
    }

    /// The Local resolvers field: comma-separated, blanks dropped, IPv6 compared case-insensitively.
    static func localResolvers(from text: String) -> Set<String> {
        Set(text.split(separator: ",").map { normalized(String($0)) }.filter { !$0.isEmpty })
    }

    static func reading(resolvers: [String], local: Set<String>) -> StatusReading {
        let addresses = resolvers.joined(separator: ", ")
        switch classify(resolvers: resolvers, local: local) {
        case .local:
            return StatusReading(emoji: "🔒", summary: String(localized: "DNS: \(addresses) — local"))
        case .external:
            return StatusReading(
                emoji: "🌐", summary: String(localized: "DNS: \(addresses) — not local"))
        case .noServers:
            return StatusReading(emoji: "🤷", summary: String(localized: "DNS: no servers"))
        }
    }

    private static func normalized(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
