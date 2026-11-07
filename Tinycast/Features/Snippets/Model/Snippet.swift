import Foundation

/// One Markdown file as the index knows it: its name, tags and date, never its body.
struct Snippet: Sendable, Equatable, Hashable, Identifiable, Codable {
    let path: String
    /// The snippets folder the file was found under, from settings.
    let root: String
    /// The `keywords` frontmatter string as written, which is what the editor shows.
    let keywords: String?
    let modified: Date
    let size: Int64

    var id: String { path }

    var name: String {
        let file = (path as NSString).lastPathComponent
        return (file as NSString).deletingPathExtension
    }

    /// The subfolders between the root and the file, each one a tag.
    var folders: [String] {
        let directory = (path as NSString).deletingLastPathComponent
        guard directory.count > root.count, directory.hasPrefix(root) else { return [] }
        return directory.dropFirst(root.count).split(separator: "/").map(String.init)
    }

    /// The `keywords` frontmatter's words, lowercased, without duplicates.
    var keywordTags: [String] {
        var seen = Set<String>()
        return SnippetSearch.words(in: keywords ?? "").filter { seen.insert($0).inserted }
    }

    /// Keyword words and folder names, lowercased, without duplicates, in that order.
    var tags: [String] {
        var seen = Set(keywordTags)
        return keywordTags + folders.map { $0.lowercased() }.filter { seen.insert($0).inserted }
    }

    /// What a query is matched against: the file name's words and the tags.
    var searchWords: [String] {
        var seen = Set<String>()
        return (SnippetSearch.words(in: name) + tags).filter { seen.insert($0).inserted }
    }
}

enum SnippetSearch {
    /// Runs of letters and digits, lowercased; anything else separates. `a12` stays one word.
    static func words(in text: String) -> [String] {
        text.lowercased().split { !($0.isLetter || $0.isNumber) }.map(String.init)
    }

    /// Every query word is part of some snippet word; strict on purpose, never fuzzy.
    static func matches(_ query: String, words: [String]) -> Bool {
        query.lowercased().split(whereSeparator: \.isWhitespace).allSatisfy { term in
            words.contains { $0.contains(term) }
        }
    }

    static func filter(_ snippets: [Snippet], query: String) -> [Snippet] {
        guard query.contains(where: { !$0.isWhitespace }) else { return snippets }
        return snippets.filter { matches(query, words: $0.searchWords) }
    }

    /// Newest change or use first; the name breaks a tie so the order never shuffles between scans.
    static func ordered(_ snippets: [Snippet], used: [String: Date] = [:]) -> [Snippet] {
        func recency(_ snippet: Snippet) -> Date { max(snippet.modified, used[snippet.path] ?? .distantPast) }
        return snippets.sorted {
            let (left, right) = (recency($0), recency($1))
            if left != right { return left > right }
            let byName = $0.name.localizedStandardCompare($1.name)
            return byName == .orderedSame ? $0.path < $1.path : byName == .orderedAscending
        }
    }
}

/// A snippet's file name as typed in the editor, before `.md` is added.
enum SnippetFileName {
    enum Problem: Equatable {
        case empty, slash, invalidCharacter, leadingDot
    }

    static func problem(in name: String) -> Problem? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .empty }
        if trimmed.contains("/") || trimmed.contains("\\") { return .slash }
        if trimmed.contains(where: { ":*?\"<>|".contains($0) }) { return .invalidCharacter }
        if trimmed.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) {
            return .invalidCharacter
        }
        // The scan skips hidden files, so a dot name would vanish the moment it was saved.
        if trimmed.hasPrefix(".") { return .leadingDot }
        return nil
    }

    static func fileName(for name: String) -> String {
        name.trimmingCharacters(in: .whitespaces) + ".md"
    }
}

/// A snippets folder's display name and icon, from the optional `.vault.json` at its root.
struct SnippetSource: Sendable, Equatable {
    let root: String
    let name: String
    /// An emoji or an SF Symbol name as written; the view decides which, or falls back.
    let icon: String?

    static let decorationFile = ".vault.json"

    init(root: String, decoration: Data?) {
        self.root = root
        struct Decoration: Decodable {
            let name: String?
            let icon: String?
        }
        let decoded = decoration.flatMap { try? JSONDecoder().decode(Decoration.self, from: $0) }
        let name = decoded?.name?.trimmingCharacters(in: .whitespaces) ?? ""
        self.name = name.isEmpty ? (root as NSString).lastPathComponent : name
        let icon = decoded?.icon?.trimmingCharacters(in: .whitespaces) ?? ""
        self.icon = icon.isEmpty ? nil : icon
    }
}
