import Foundation

enum NoteEditAction: Sendable, Equatable {
    enum InlineStyle: Sendable, CaseIterable { case bold, italic, strikethrough, code }
    enum ListStyle: Sendable { case bullet, ordered, task }
    enum Direction: Sendable { case up, down }

    case newline
    case deleteBackward
    case indent
    case outdent
    case toggleInline(InlineStyle)
    case toggleLink
    /// Level 0 turns the line back into a plain paragraph.
    case setHeading(level: Int)
    case toggleList(ListStyle)
    case toggleCodeBlock
    case toggleQuote
    case toggleTask(lineIndex: Int)
    /// Swaps the touched items with their neighbouring sibling, nested items travelling along.
    case moveListItem(Direction)
    /// The `[] ` input rule.
    case typedSpace
    /// A URL over selected text links it; a list item into an empty item replaces its marker.
    case paste(String)
}
