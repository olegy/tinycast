import Darwin
import Foundation

enum SnippetFileError: LocalizedError, Equatable {
    /// Another file already has the name; replacing it needs the reader's say-so.
    case exists(name: String)
    /// The file changed on disk after the editor read it.
    case changedOnDisk
    case missing

    var errorDescription: String? {
        switch self {
        case .exists(let name): String(localized: "“\(name)” already exists.")
        case .changedOnDisk: String(localized: "The file changed on disk.")
        case .missing: String(localized: "The snippet’s file is gone.")
        }
    }
}

/// Every write a snippet file gets. Never rewrites a file whole: see docs/features/snippets.md.
nonisolated enum SnippetFileWriter {
    /// A new file in `directory`; a file it replaces goes to the Trash.
    static func create(
        in directory: String, name: String, keywords: String, content: String, replacing: Bool
    ) throws -> String {
        let target = path(in: directory, name: name)
        try clear(target, replacing: replacing, keeping: nil)
        try write(SnippetDocument.newFile(keywords: keywords, content: content), to: target)
        return target
    }

    /// Changes only what was edited. `original` is the text the editor opened with.
    static func update(
        at path: String, original: String, name: String, keywords: String, content: String,
        replacing: Bool, overwritingDiskChanges: Bool
    ) throws -> String {
        guard FileManager.default.fileExists(atPath: path) else { throw SnippetFileError.missing }
        let current = try SnippetScanner.readText(at: path)
        if current != original, !overwritingDiskChanges { throw SnippetFileError.changedOnDisk }
        let edited = Self.edited(current, original: original, keywords: keywords, content: content)
        let target = Self.path(in: (path as NSString).deletingLastPathComponent, name: name)
        if target != path { try clear(target, replacing: replacing, keeping: path) }
        if edited != current { try write(edited, to: path) }
        if target != path { try rename(path, to: target) }
        return target
    }

    /// The same file, name and text under another snippets folder's root.
    static func move(_ path: String, to directory: String, replacing: Bool) throws -> String {
        let target = (directory as NSString).appendingPathComponent((path as NSString).lastPathComponent)
        guard target != path else { return path }
        try clear(target, replacing: replacing, keeping: path)
        try rename(path, to: target)
        return target
    }

    static func trash(_ path: String) throws {
        try FileManager.default.trashItem(at: URL(filePath: path), resultingItemURL: nil)
    }

    /// Only the fields the editor changed reach the text, so a disk edit elsewhere survives.
    static func edited(_ current: String, original: String, keywords: String, content: String) -> String {
        let before = SnippetDocument(text: original)
        var text = current
        if keywords.trimmingCharacters(in: .whitespaces) != (before.keywords ?? "") {
            text = SnippetDocument(text: text).replacingKeywords(with: keywords)
        }
        if content != before.content {
            text = SnippetDocument(text: text).replacingContent(with: content)
        }
        return text
    }

    static func path(in directory: String, name: String) -> String {
        (directory as NSString).appendingPathComponent(SnippetFileName.fileName(for: name))
    }

    /// `keeping` is the file being renamed, which a case-only rename finds at the target too.
    private static func clear(_ target: String, replacing: Bool, keeping: String?) throws {
        guard FileManager.default.fileExists(atPath: target) else { return }
        if let keeping, isSameFile(target, keeping) { return }
        guard replacing else {
            throw SnippetFileError.exists(name: ((target as NSString).lastPathComponent as NSString)
                .deletingPathExtension)
        }
        try trash(target)
    }

    private static func isSameFile(_ a: String, _ b: String) -> Bool {
        let keys: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        guard let first = try? URL(filePath: a).resourceValues(forKeys: keys).fileResourceIdentifier,
            let second = try? URL(filePath: b).resourceValues(forKeys: keys).fileResourceIdentifier
        else { return false }
        return first.isEqual(second)
    }

    /// `rename(2)`, which unlike `moveItem` takes a case-only rename on a case-insensitive volume.
    private static func rename(_ path: String, to target: String) throws {
        guard Darwin.rename(path, target) != 0 else { return }
        guard errno == EXDEV else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        try FileManager.default.moveItem(atPath: path, toPath: target)
    }

    /// Atomic, so Obsidian or a crash never sees half a file.
    private static func write(_ text: String, to path: String) throws {
        try Data(text.utf8).write(to: URL(filePath: path), options: .atomic)
    }
}
