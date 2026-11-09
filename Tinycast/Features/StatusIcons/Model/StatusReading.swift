import Foundation

/// What one status icon draws: its glyph, whether it asks for attention, and its tooltip.
struct StatusReading: Equatable, Sendable {
    enum Tone: Equatable, Sendable {
        case normal
        case attention
    }

    let symbol: String
    let tone: Tone
    let summary: String
}
