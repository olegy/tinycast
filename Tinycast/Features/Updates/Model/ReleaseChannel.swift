import Foundation

/// Only the Release bundle has a release stream; Debug and any other id never update.
enum ReleaseChannel: Sendable {
    case stable
    /// A local build. It has no release stream, and never updates itself.
    case development

    init(bundleID: String?) {
        self = bundleID == "com.olegy.tinycast" ? .stable : .development
    }

    var updatesItself: Bool { self != .development }

    /// Lite publishes no prereleases, so a prerelease on the feed is never an update.
    func accepts(prerelease: Bool) -> Bool {
        self == .stable && !prerelease
    }
}
