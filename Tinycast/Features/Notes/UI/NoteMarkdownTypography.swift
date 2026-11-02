import AppKit

/// The editor's `NSFont`s: the system text styles one step up, scaled by the Text Size setting.
@MainActor
enum NoteMarkdownTypography {
    private(set) static var body = textCut(ofSize: size(.title3))
    private(set) static var heading1 = heading(.largeTitle, weight: .bold)
    private(set) static var heading2 = heading(.title1, weight: .bold)
    private(set) static var heading3 = heading(.title2, weight: .semibold)
    private(set) static var inlineCode = NSFont.monospacedSystemFont(ofSize: body.pointSize, weight: .regular)
    private(set) static var codeBlock = NSFont.monospacedSystemFont(ofSize: body.pointSize - 1, weight: .regular)
    /// Small enough that a hidden marker leaves no visible gap, while staying a real glyph run.
    static let hidden = NSFont.systemFont(ofSize: 0.01)

    /// False when the size is already in effect, so the caller can skip a full restyle.
    static func setBodySize(_ pointSize: CGFloat) -> Bool {
        guard pointSize != body.pointSize else { return false }
        body = textCut(ofSize: pointSize)
        heading1 = heading(.largeTitle, weight: .bold)
        heading2 = heading(.title1, weight: .bold)
        heading3 = heading(.title2, weight: .semibold)
        inlineCode = NSFont.monospacedSystemFont(ofSize: pointSize, weight: .regular)
        codeBlock = NSFont.monospacedSystemFont(ofSize: pointSize - 1, weight: .regular)
        return true
    }

    /// Levels 4 to 6 share the third heading's style.
    static func heading(_ level: Int) -> NSFont {
        switch level {
        case 1: heading1
        case 2: heading2
        default: heading3
        }
    }

    static func adding(_ traits: NSFontDescriptor.SymbolicTraits, to font: NSFont) -> NSFont {
        let current = font.fontDescriptor.symbolicTraits
        let descriptor = font.fontDescriptor.withSymbolicTraits(current.union(traits))
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    }

    /// Keeps each heading's ratio to the body that the unscaled text styles have.
    private static func heading(_ style: NSFont.TextStyle, weight: NSFont.Weight) -> NSFont {
        let scale = body.pointSize / size(.title3)
        return NSFont.systemFont(ofSize: (size(style) * scale).rounded(), weight: weight)
    }

    /// SF switches to its tighter Display cut at 20 points; the body keeps the Text cut at any size.
    private static func textCut(ofSize pointSize: CGFloat) -> NSFont {
        let font = NSFont.systemFont(ofSize: pointSize)
        let opticalSize = NSFontDescriptor.AttributeName(kCTFontOpticalSizeAttribute as String)
        let descriptor = font.fontDescriptor.addingAttributes([opticalSize: textOpticalSize])
        return NSFont(descriptor: descriptor, size: pointSize) ?? font
    }

    private static let textOpticalSize: CGFloat = 17

    private static func size(_ style: NSFont.TextStyle) -> CGFloat {
        NSFont.preferredFont(forTextStyle: style).pointSize
    }

    static func inlineCode(matching font: NSFont) -> NSFont {
        font.pointSize == body.pointSize
            ? inlineCode : NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
    }
}
