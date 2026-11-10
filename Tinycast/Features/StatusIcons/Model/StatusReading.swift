import Foundation

/// What one status icon draws: an emoji, and its tooltip.
struct StatusReading: Equatable, Sendable {
    let emoji: String
    let summary: String
}
