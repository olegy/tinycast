import AppKit

extension NSAttributedString.Key {
    /// An inline code span's chip fill; the span's kerning makes room for its padding.
    static let noteInlineCode = NSAttributedString.Key("tinycast.note.inlineCode")
}

/// Draws without AppKit's font smoothing, whose stem darkening reads as bold at the larger sizes.
class NoteTextLayoutFragment: NSTextLayoutFragment {
    static func chipPadding(for font: NSFont) -> CGFloat { (font.pointSize * 0.3).rounded() }

    private static let chipRadius: CGFloat = 4
    private static let chipVerticalPadding: CGFloat = 1.5

    override var renderingSurfaceBounds: CGRect {
        super.renderingSurfaceBounds.insetBy(dx: 0, dy: -Self.chipVerticalPadding)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        context.setShouldSmoothFonts(false)
        drawCodeChips(at: point, in: context)
        super.draw(at: point, in: context)
    }

    private func drawCodeChips(at point: CGPoint, in context: CGContext) {
        for line in textLineFragments {
            let text = line.attributedString
            text.enumerateAttribute(.noteInlineCode, in: line.characterRange) { value, range, _ in
                guard let fill = value as? NSColor,
                    let font = text.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
                else { return }
                let padding = Self.chipPadding(for: font)
                let string = text.string as NSString
                let last = string.rangeOfComposedCharacterSequence(at: NSMaxRange(range) - 1).location
                let firstX = Self.glyphX(at: range.location, in: line)
                let lastX = last == range.location ? firstX : line.locationForCharacter(at: last).x
                let first = Self.glyph(at: range.location, in: string, font: font)
                let final = Self.glyph(at: last, in: string, font: font)
                let start = firstX + (first.map(font.boundingRect(forCGGlyph:))?.minX ?? 0) - padding
                let end = lastX + (final.map(font.boundingRect(forCGGlyph:))?.maxX ?? 0) + padding
                let baseline = point.y + line.typographicBounds.minY + line.glyphOrigin.y
                let rect = CGRect(
                    x: point.x + line.typographicBounds.minX + start,
                    y: baseline - font.ascender - Self.chipVerticalPadding,
                    width: end - start,
                    height: font.ascender - font.descender + Self.chipVerticalPadding * 2)
                context.addPath(
                    CGPath(
                        roundedRect: rect, cornerWidth: Self.chipRadius, cornerHeight: Self.chipRadius,
                        transform: nil))
                context.setFillColor(fill.cgColor)
                context.fillPath()
            }
        }
    }

    /// A caret after kerning sits mid-gap, so the edge is measured from the glyph before.
    private static func glyphX(at index: Int, in line: NSTextLineFragment) -> CGFloat {
        let text = line.attributedString
        let string = text.string as NSString
        guard index > 0 else { return line.locationForCharacter(at: index).x }
        let previous = string.rangeOfComposedCharacterSequence(at: index - 1).location
        guard let kern = text.attribute(.kern, at: previous, effectiveRange: nil) as? CGFloat,
            let font = text.attribute(.font, at: previous, effectiveRange: nil) as? NSFont,
            let glyph = glyph(at: previous, in: string, font: font)
        else { return line.locationForCharacter(at: index).x }
        return line.locationForCharacter(at: previous).x + font.advancement(forCGGlyph: glyph).width + kern
    }

    /// Padding is measured from the ink, since a monospaced cell centres a narrow glyph in it.
    private static func glyph(at index: Int, in string: NSString, font: NSFont) -> CGGlyph? {
        let range = string.rangeOfComposedCharacterSequence(at: index)
        var characters = [unichar](repeating: 0, count: range.length)
        string.getCharacters(&characters, range: range)
        var glyphs = [CGGlyph](repeating: 0, count: range.length)
        guard CTFontGetGlyphsForCharacters(font, characters, &glyphs, range.length) else { return nil }
        return glyphs[0]
    }
}
