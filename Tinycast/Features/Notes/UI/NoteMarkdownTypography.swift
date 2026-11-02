import AppKit

/// The editor's `NSFont`s, every heading a fixed ratio of the body the Text Size setting picks.
@MainActor
enum NoteMarkdownTypography {
    private(set) static var body = textCut(ofSize: NoteTextSize.standard.pointSize)
    private(set) static var heading1 = heading(scale: 1.3)
    private(set) static var heading2 = heading(scale: 1.15)
    private(set) static var heading3 = heading(scale: 1.05)
    private(set) static var inlineCode = codeFont(matching: body.pointSize)
    private(set) static var codeBlock = NSFont.monospacedSystemFont(ofSize: body.pointSize - 1, weight: .regular)
    /// Small enough that a hidden marker leaves no visible gap, while staying a real glyph run.
    static let hidden = NSFont.systemFont(ofSize: 0.01)

    /// False when the size is already in effect, so the caller can skip a full restyle.
    static func setBodySize(_ pointSize: CGFloat) -> Bool {
        guard pointSize != body.pointSize else { return false }
        body = textCut(ofSize: pointSize)
        heading1 = heading(scale: 1.3)
        heading2 = heading(scale: 1.15)
        heading3 = heading(scale: 1.05)
        inlineCode = codeFont(matching: pointSize)
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

    /// Semibold throughout: size alone ranks the levels, so no heading reads heavier than the next.
    private static func heading(scale: CGFloat) -> NSFont {
        NSFont.systemFont(ofSize: (body.pointSize * scale).rounded(), weight: .semibold)
    }

    /// SF switches to its tighter Display cut at 20 points; the body keeps the Text cut at any size.
    private static func textCut(ofSize pointSize: CGFloat) -> NSFont {
        let font = NSFont.systemFont(ofSize: pointSize)
        let opticalSize = NSFontDescriptor.AttributeName(kCTFontOpticalSizeAttribute as String)
        let descriptor = font.fontDescriptor.addingAttributes([opticalSize: textOpticalSize])
        return NSFont(descriptor: descriptor, size: pointSize) ?? font
    }

    private static let textOpticalSize: CGFloat = 17

    static func inlineCode(matching font: NSFont) -> NSFont {
        font.pointSize == body.pointSize ? inlineCode : codeFont(matching: font.pointSize)
    }

    /// SF Mono's wide cells read a size larger than SF Pro, so a code span sits a step smaller.
    private static func codeFont(matching pointSize: CGFloat) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: (pointSize * 0.87).rounded(), weight: .regular)
    }
}
