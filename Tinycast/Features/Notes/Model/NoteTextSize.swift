import Foundation

/// The editor's body size; headings, code and list geometry all scale from it.
enum NoteTextSize: String, CaseIterable, Identifiable, Sendable {
    case standard
    case medium
    case large
    case largest

    var id: String { rawValue }

    var pointSize: Double {
        switch self {
        case .standard: 15
        case .medium: 18
        case .large: 20
        case .largest: 23
        }
    }
}
