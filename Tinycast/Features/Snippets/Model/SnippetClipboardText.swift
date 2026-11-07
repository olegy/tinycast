import Foundation

/// What ↵ copies and ⌘↵ pastes from a snippet's content. See docs/features/snippets.md.
enum SnippetClipboardText {
    /// A fenced block's lines, fences excluded; an unclosed block runs to the end, as in CommonMark.
    struct CodeBlock: Equatable {
        let lines: [Substring]
        let isClosed: Bool
    }

    /// The content whole, unless it is nothing but one code block, which copies without its fences.
    static func copy(_ content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = scan(trimmed)
        guard parsed.blocks.count == 1, let block = parsed.blocks.first, block.isClosed, !parsed.hasProse
        else { return trimmed }
        return block.lines.joined(separator: "\n")
    }

    /// One line of text, or the one line of a sole code block; nil when there is no single line.
    static func paste(_ content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = scan(trimmed)
        switch parsed.blocks.count {
        case 0:
            guard !trimmed.isEmpty, !trimmed.contains(where: \.isNewline) else { return nil }
            return trimmed
        case 1:
            guard let block = parsed.blocks.first, block.isClosed else { return nil }
            let lines = block.lines.filter { !$0.allSatisfy(\.isWhitespace) }
            guard lines.count == 1, let line = lines.first else { return nil }
            return line.trimmingCharacters(in: .whitespaces)
        default:
            return nil
        }
    }

    /// Fenced blocks and whether any text stands outside them.
    static func scan(_ text: String) -> (blocks: [CodeBlock], hasProse: Bool) {
        var blocks: [CodeBlock] = []
        var hasProse = false
        var open: (fence: Character, length: Int)?
        var lines: [Substring] = []
        for line in TextLine.split(text).map({ text[$0.content] }) {
            if let fence = open {
                if isClosingFence(line, fence: fence.fence, length: fence.length) {
                    blocks.append(CodeBlock(lines: lines, isClosed: true))
                    open = nil
                    lines = []
                } else {
                    lines.append(line)
                }
            } else if let fence = openingFence(line) {
                open = fence
            } else if !line.allSatisfy(\.isWhitespace) {
                hasProse = true
            }
        }
        if open != nil { blocks.append(CodeBlock(lines: lines, isClosed: false)) }
        return (blocks, hasProse)
    }

    private static func openingFence(_ line: Substring) -> (fence: Character, length: Int)? {
        let indent = line.prefix { $0 == " " }
        guard indent.count <= 3 else { return nil }
        let rest = line.dropFirst(indent.count)
        guard let fence = rest.first, fence == "`" || fence == "~" else { return nil }
        let run = rest.prefix { $0 == fence }
        guard run.count >= 3 else { return nil }
        // A backtick fence's info string may not hold a backtick, or it is inline code.
        if fence == "`", rest.dropFirst(run.count).contains("`") { return nil }
        return (fence, run.count)
    }

    private static func isClosingFence(_ line: Substring, fence: Character, length: Int) -> Bool {
        let indent = line.prefix { $0 == " " }
        guard indent.count <= 3 else { return false }
        let rest = line.dropFirst(indent.count)
        let run = rest.prefix { $0 == fence }
        return run.count >= length && rest.dropFirst(run.count).allSatisfy(\.isWhitespace)
    }
}
