import Foundation
import SystemConfiguration

/// Reports the primary service's DNS resolvers whenever configd changes them; nothing is polled.
@MainActor
final class DNSResolverMonitor {
    private static let key = "State:/Network/Global/DNS" as CFString
    private let onChange: ([String]) -> Void
    private var store: SCDynamicStore?

    init(onChange: @escaping ([String]) -> Void) {
        self.onChange = onChange
    }

    isolated deinit {
        stop()
    }

    /// Reports the current resolvers at once, then on every change until `stop()`.
    func start() {
        guard store == nil else { return }
        // Unretained: `stop()` detaches the callback before this monitor can go away.
        var context = SCDynamicStoreContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil,
            copyDescription: nil)
        guard
            let store = SCDynamicStoreCreate(
                nil, "Tinycast.StatusIcons" as CFString,
                { @MainActor _, _, info in
                    guard let info else { return }
                    Unmanaged<DNSResolverMonitor>.fromOpaque(info).takeUnretainedValue().report()
                }, &context)
        else { return }
        SCDynamicStoreSetNotificationKeys(store, [Self.key] as CFArray, nil)
        SCDynamicStoreSetDispatchQueue(store, .main)
        self.store = store
        report()
    }

    func stop() {
        guard let store else { return }
        SCDynamicStoreSetDispatchQueue(store, nil)
        self.store = nil
    }

    private func report() {
        guard let store else { return }
        let value = SCDynamicStoreCopyValue(store, Self.key) as? [String: Any]
        onChange(value?[kSCPropNetDNSServerAddresses as String] as? [String] ?? [])
    }
}
