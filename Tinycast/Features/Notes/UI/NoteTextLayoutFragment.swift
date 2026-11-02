import AppKit

/// Draws without AppKit's font smoothing, whose stem darkening reads as bold at the larger sizes.
class NoteTextLayoutFragment: NSTextLayoutFragment {
    override func draw(at point: CGPoint, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        context.setShouldSmoothFonts(false)
        super.draw(at: point, in: context)
    }
}
