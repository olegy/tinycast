import Foundation

/// One snippet file's text, split into frontmatter and content without ever reshaping either.
struct SnippetDocument: Sendable, Equatable {
    let text: String
    /// The `keywords` value when it is a plain string; a list, a block or a number reads as nil.
    let keywords: String?
    /// Where the opening frontmatter ends, after the closing fence's line break; nil without one.
    private let frontmatterEnd: String.Index?
    private let closingFence: Range<String.Index>?
    /// The `keywords:` line and any continuation lines under it.
    private let keywordsLines: Range<String.Index>?
    private let contentStart: String.Index
    private let contentEnd: String.Index

    init(text: String) {
        self.text = text
        let lines = TextLine.split(text)
        let frontmatter = Self.frontmatter(in: lines, of: text)
        frontmatterEnd = frontmatter?.end
        closingFence = frontmatter?.closingFence
        keywords = frontmatter?.keywords
        keywordsLines = frontmatter?.keywordsLines
        var start = frontmatter?.end ?? text.startIndex
        for line in lines where line.full.lowerBound >= start {
            guard text[line.content].allSatisfy(\.isWhitespace) else { break }
            start = line.full.upperBound
        }
        contentStart = start
        var end = text.endIndex
        while end > start, text[text.index(before: end)].isWhitespace {
            end = text.index(before: end)
        }
        contentEnd = end
    }

    var hasFrontmatter: Bool { frontmatterEnd != nil }

    /// Everything after the frontmatter, less the blank lines and whitespace around it.
    var content: String { String(text[contentStart..<contentEnd]) }

    /// True while the head read so far opens a frontmatter whose closing fence is still unread.
    static func needsMoreText(_ head: String) -> Bool {
        let lines = TextLine.split(head)
        guard let first = lines.first, Self.isFence(head[first.content]) else { return false }
        return !lines.dropFirst().contains { Self.isFence(head[$0.content]) }
    }

    /// The whole file a new snippet is written as.
    static func newFile(keywords: String, content: String) -> String {
        let keywords = singleLine(keywords)
        let body = trimmingTrailingWhitespace(content)
        let tail = body.isEmpty ? "" : body + "\n"
        guard !keywords.isEmpty else { return tail }
        return "---\nkeywords: \(yamlScalar(keywords))\n---\n" + (tail.isEmpty ? "" : "\n" + tail)
    }

    /// The text with only the `keywords` line changed; every other byte stays as it was.
    func replacingKeywords(with value: String) -> String {
        let value = Self.singleLine(value)
        guard value != (keywords ?? "") else { return text }
        let newline = Self.newline(in: text)
        let line = "keywords: \(Self.yamlScalar(value))" + newline
        if let keywordsLines {
            var result = text
            if value.isEmpty, let frontmatterEnd, onlyKeywordsInFrontmatter {
                return Self.removingFrontmatter(from: text, end: frontmatterEnd)
            }
            result.replaceSubrange(keywordsLines, with: value.isEmpty ? "" : line)
            return result
        }
        guard !value.isEmpty else { return text }
        if let closingFence {
            var result = text
            result.insert(contentsOf: line, at: closingFence.lowerBound)
            return result
        }
        let head = "---" + newline + line + "---" + newline
        return text.isEmpty ? head : head + newline + text
    }

    /// The text with only the content changed; frontmatter and surrounding whitespace are kept.
    func replacingContent(with value: String) -> String {
        let newline = Self.newline(in: text)
        var body = Self.trimmingTrailingWhitespace(value)
        if newline != "\n" { body = body.replacingOccurrences(of: "\n", with: newline) }
        guard body != content else { return text }
        var prefix = String(text[..<contentStart])
        if !prefix.isEmpty, !prefix.hasSuffix("\n"), !prefix.hasSuffix("\r") {
            prefix += newline + newline
        }
        var tail = String(text[contentEnd...])
        if tail.isEmpty, contentStart == contentEnd, !body.isEmpty { tail = newline }
        return prefix + body + tail
    }

    private var onlyKeywordsInFrontmatter: Bool {
        guard let keywordsLines, let closingFence else { return false }
        let opening = TextLine.split(text).first?.full.upperBound ?? text.startIndex
        let before = text[opening..<keywordsLines.lowerBound]
        let after = text[keywordsLines.upperBound..<closingFence.lowerBound]
        return before.allSatisfy(\.isWhitespace) && after.allSatisfy(\.isWhitespace)
    }

    // MARK: - Parsing

    private struct Frontmatter {
        let end: String.Index
        let closingFence: Range<String.Index>
        let keywords: String?
        let keywordsLines: Range<String.Index>?
    }

    /// Recognised only when the file opens with `---` and a closing `---` holds a mapping.
    private static func frontmatter(in lines: [TextLine], of text: String) -> Frontmatter? {
        guard let first = lines.first, isFence(text[first.content]) else { return nil }
        guard let closingIndex = lines.indices.dropFirst().first(where: { isFence(text[lines[$0].content]) })
        else { return nil }
        let inner = Array(lines[1..<closingIndex])
        guard looksLikeMapping(inner.map { text[$0.content] }) else { return nil }
        var keywords: String?
        var keywordsLines: Range<String.Index>?
        if let keyIndex = inner.firstIndex(where: { key(of: text[$0.content])?.lowercased() == "keywords" }) {
            var last = keyIndex
            while last + 1 < inner.count, isContinuation(text[inner[last + 1].content]) { last += 1 }
            keywordsLines = inner[keyIndex].full.lowerBound..<inner[last].full.upperBound
            if last == keyIndex { keywords = scalarValue(of: text[inner[keyIndex].content]) }
        }
        let closing = lines[closingIndex]
        return Frontmatter(
            end: closing.full.upperBound, closingFence: closing.full, keywords: keywords,
            keywordsLines: keywordsLines)
    }

    private static func isFence(_ line: Substring) -> Bool {
        line.trimmingCharacters(in: .whitespaces) == "---"
    }

    /// A stand-in for a YAML parse: every line is a top-level key, a nested line or a comment.
    private static func looksLikeMapping(_ lines: [Substring]) -> Bool {
        var hasKey = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if isContinuation(line) {
                guard hasKey else { return false }
                continue
            }
            guard key(of: line) != nil else { return false }
            hasKey = true
        }
        return hasKey
    }

    private static func isContinuation(_ line: Substring) -> Bool {
        guard let first = line.first else { return false }
        return first == " " || first == "\t" || line == "-" || line.hasPrefix("- ")
    }

    private static func key(of line: Substring) -> String? {
        guard let first = line.first, first != " ", first != "\t", first != "#", first != "-"
        else { return nil }
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let after = line.index(after: colon)
        guard after == line.endIndex || line[after] == " " || line[after] == "\t" else { return nil }
        var key = line[..<colon].trimmingCharacters(in: .whitespaces)
        if key.count >= 2, let quote = key.first, quote == "\"" || quote == "'", key.last == quote {
            key = String(key.dropFirst().dropLast())
        }
        return key.isEmpty ? nil : key
    }

    private static func scalarValue(of line: Substring) -> String? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        var value = line[line.index(after: colon)...].replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard let first = value.first else { return nil }
        if first == "\"" || first == "'" {
            guard value.count >= 2, value.last == first else { return nil }
            value = String(value.dropFirst().dropLast())
            return first == "'"
                ? value.replacingOccurrences(of: "''", with: "'")
                : value.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
        }
        guard !"[{|>&*!%@`".contains(first) else { return nil }
        if let comment = value.range(of: " #") { value = String(value[..<comment.lowerBound]) }
        return value.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Writing

    /// Drops the block and the one blank line that separated it from the content.
    private static func removingFrontmatter(from text: String, end: String.Index) -> String {
        let rest = String(text[end...])
        guard let first = TextLine.split(rest).first, rest[first.content].allSatisfy(\.isWhitespace)
        else { return rest }
        return String(rest[first.full.upperBound...])
    }

    private static func newline(in text: String) -> String {
        text.contains("\r\n") ? "\r\n" : "\n"
    }

    private static func singleLine(_ value: String) -> String {
        value.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func trimmingTrailingWhitespace(_ value: String) -> String {
        var end = value.endIndex
        while end > value.startIndex, value[value.index(before: end)].isWhitespace {
            end = value.index(before: end)
        }
        return String(value[..<end])
    }

    /// Quoted only when YAML would read the bare words as something other than a string.
    private static func yamlScalar(_ value: String) -> String {
        let needsQuotes =
            value.contains(": ") || value.contains(" #") || value.hasSuffix(":")
            || value.first.map { "[]{}#&*!|>'\"%@`,?:-".contains($0) } == true
        guard needsQuotes else { return value }
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

/// A line of text by range, with and without its line break; `\r\n` counts as one break.
struct TextLine: Sendable, Equatable {
    let content: Range<String.Index>
    let full: Range<String.Index>

    static func split(_ text: String) -> [TextLine] {
        var lines: [TextLine] = []
        var start = text.startIndex
        var index = start
        while index < text.endIndex {
            if text[index].isNewline {
                let next = text.index(after: index)
                lines.append(TextLine(content: start..<index, full: start..<next))
                start = next
                index = next
            } else {
                index = text.index(after: index)
            }
        }
        if start < text.endIndex {
            lines.append(TextLine(content: start..<text.endIndex, full: start..<text.endIndex))
        }
        return lines
    }
}
