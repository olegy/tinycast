import AppKit

extension NSAppearance {
    /// `bestMatch`, not a name comparison, so vibrant and accessibility variants resolve.
    var isDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}

extension NSColor {
    /// A theme colour is a fresh dynamic object on every read, so only its resolved value compares.
    func resolves(like other: NSColor?, in appearance: NSAppearance) -> Bool {
        guard let other else { return false }
        var same = false
        appearance.performAsCurrentDrawingAppearance {
            same = usingColorSpace(.sRGB) == other.usingColorSpace(.sRGB)
        }
        return same
    }

    /// Built in sRGB, where `Color.white` resolves, so a dark branch is the same pixel.
    static func srgbInk(_ white: CGFloat, alpha: Double) -> NSColor {
        NSColor(srgbRed: white, green: white, blue: white, alpha: alpha)
    }
}
