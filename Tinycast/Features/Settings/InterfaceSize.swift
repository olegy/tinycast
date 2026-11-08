import CoreGraphics

/// How large the palette and its floating siblings render; an unset key reads as `.standard`.
enum InterfaceSize: String, CaseIterable, Identifiable, Sendable {
    // Raw values name the retired sizes whose fonts these keep, so a stored choice carries over.
    case standard = "large"
    case large = "larger"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: String(localized: "Default")
        case .large: String(localized: "Large")
        }
    }

    /// Frames, spacing and icons: the original proportions, only nudged up at `.large`.
    var scale: CGFloat {
        switch self {
        case .standard: 1
        case .large: 1.04
        }
    }

    var textScale: CGFloat {
        switch self {
        case .standard: 1.1
        case .large: 1.2
        }
    }

    var metrics: InterfaceMetrics { InterfaceMetrics(scale: scale, textScale: textScale) }
}
