import Foundation

/// How the note window sits among other windows.
enum NoteWindowMode: String, CaseIterable, Identifiable, Sendable {
    /// Above every app and on every Space, without activating Tinycast.
    case floating
    /// An ordinary window on its own Space, which other apps can cover.
    case standard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .floating: String(localized: "Floating")
        case .standard: String(localized: "Standard")
        }
    }

    var detail: String {
        switch self {
        case .floating: String(localized: "Stays above other windows on every Space.")
        case .standard: String(localized: "Behaves like a normal window.")
        }
    }
}

/// The surface the note is written on.
enum NotePaper: String, CaseIterable, Identifiable, Sendable {
    case glass
    case frosted
    case solid
    case cream
    case white

    var id: String { rawValue }

    var title: String {
        switch self {
        case .glass: String(localized: "Glass")
        case .frosted: String(localized: "Frosted")
        case .solid: String(localized: "Solid")
        case .cream: String(localized: "Cream")
        case .white: String(localized: "White")
        }
    }

    var detail: String {
        switch self {
        case .glass: String(localized: "The desktop shows through clearly, with a lit edge.")
        case .frosted: String(localized: "Translucent, with the desktop softened behind it.")
        case .solid: String(localized: "Opaque. Easiest to read over a busy desktop.")
        case .cream: String(localized: "Warm off-white stock, easier on the eyes over a long session.")
        case .white: String(localized: "Plain white paper with dark ink.")
        }
    }

    /// Only the system surfaces take a tint; an opaque paper is its own colour.
    var takesTint: Bool {
        switch self {
        case .glass, .frosted, .solid: true
        case .cream, .white: false
        }
    }

    /// An opaque paper is light whatever the system appearance, so its ink must be too.
    var forcesLightAppearance: Bool { !takesTint }
}

/// A faint colour wash over a translucent paper.
enum NoteTint: String, CaseIterable, Identifiable, Sendable {
    case none
    case graphite
    case amber
    case rose
    case moss
    case indigo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: String(localized: "No Tint")
        case .graphite: String(localized: "Graphite")
        case .amber: String(localized: "Amber")
        case .rose: String(localized: "Rose")
        case .moss: String(localized: "Moss")
        case .indigo: String(localized: "Indigo")
        }
    }
}
