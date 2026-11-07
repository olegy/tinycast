import Foundation

/// Walks the snippets folders and reads only each file's head; every call runs off-main.
nonisolated enum SnippetScanner {
    struct Outcome: Sendable {
        let snippets: [Snippet]
        let sources: [SnippetSource]
        let failures: [String]
    }

    private static let chunk = 4_096
    /// A frontmatter longer than this is not one a snippet file would carry.
    private static let headLimit = 65_536

    /// `known` entries whose date and size still match are reused without opening the file.
    @concurrent
    static func scan(
        roots: [String], excludes: [String], homeDirectory: URL, known: [String: Snippet]
    ) async -> Outcome {
        let ignore = FileSearchIgnoreList(patterns: excludes, homeDirectory: homeDirectory)
        var snippets: [Snippet] = []
        var seen = Set<String>()
        var sources: [SnippetSource] = []
        var failures: [String] = []
        for root in roots {
            guard !Task.isCancelled else { break }
            let decoration = try? Data(
                contentsOf: URL(filePath: root).appending(path: SnippetSource.decorationFile))
            sources.append(SnippetSource(root: root, decoration: decoration))
            for file in markdownFiles(under: root, ignore: ignore) where seen.insert(file.path).inserted {
                do {
                    snippets.append(try snippet(at: file, root: root, known: known[file.path]))
                } catch {
                    failures.append("\(file.path): \(error.localizedDescription)")
                }
            }
        }
        return Outcome(snippets: SnippetSearch.ordered(snippets), sources: sources, failures: failures)
    }

    /// The whole file, for the preview, a copy or the editor.
    @concurrent
    static func text(at path: String) async throws -> String {
        try readText(at: path)
    }

    static func readText(at path: String) throws -> String {
        try utf8(Data(contentsOf: URL(filePath: path)))
    }

    /// A file that is not UTF-8 is reported, never shown or rewritten as mojibake.
    private static func utf8(_ data: Data) throws -> String {
        guard let text = String(validating: data, as: UTF8.self) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return text
    }

    private struct File {
        let path: String
        let modified: Date
        let size: Int64
    }

    private static func markdownFiles(under root: String, ignore: FileSearchIgnoreList) -> [File] {
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .isRegularFileKey, .contentModificationDateKey, .fileSizeKey
        ]
        // Hidden entries are always skipped, as the Raycast extension did: .obsidian, .git, .trash.
        guard
            let enumerator = FileManager.default.enumerator(
                at: URL(filePath: root, directoryHint: .isDirectory), includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }
        var files: [File] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            let path = url.standardizedFileURL.path
            if values.isDirectory == true {
                if ignore.excludes(name: url.lastPathComponent, path: path) {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values.isRegularFile == true, url.pathExtension.lowercased() == "md" else { continue }
            files.append(
                File(
                    path: path, modified: values.contentModificationDate ?? .distantPast,
                    size: Int64(values.fileSize ?? 0)))
        }
        return files
    }

    private static func snippet(at file: File, root: String, known: Snippet?) throws -> Snippet {
        if let known, known.modified == file.modified, known.size == file.size, known.root == root {
            return known
        }
        let head = try readHead(at: file.path)
        return Snippet(
            path: file.path, root: root, keywords: SnippetDocument(text: head).keywords,
            modified: file.modified, size: file.size)
    }

    /// Only as much as the frontmatter needs; the body is read when the snippet is shown.
    private static func readHead(at path: String) throws -> String {
        let handle = try FileHandle(forReadingFrom: URL(filePath: path))
        defer { try? handle.close() }
        var data = Data()
        while data.count < headLimit {
            guard let next = try handle.read(upToCount: chunk), !next.isEmpty else { break }
            data.append(next)
            // A chunk may end inside a character; the next one completes it.
            if let text = String(validating: data, as: UTF8.self), !SnippetDocument.needsMoreText(text) {
                return text
            }
        }
        // Up to three bytes of a character cut off at the limit.
        for cut in 0...3 where cut < data.count || cut == 0 {
            if let text = String(validating: data.dropLast(cut), as: UTF8.self) { return text }
        }
        throw CocoaError(.fileReadInapplicableStringEncoding)
    }
}
