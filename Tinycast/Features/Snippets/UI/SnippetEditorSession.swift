import SwiftUI

@MainActor
@Observable
final class SnippetEditorSession {
    enum Field: Hashable {
        case folder, name, keywords, content
    }

    /// Nil while creating.
    let original: Snippet?
    /// The file as the editor read it, so a save can tell what changed on disk meanwhile.
    let originalText: String
    /// Where a new snippet goes; an edited one stays where it is.
    var root: String
    var name: String
    var keywords: String
    var content: String
    var selection: TextSelection?
    var focusedField: Field = .name

    private let initialKeywords: String
    private let initialContent: String

    init(editing snippet: Snippet, text: String) {
        let document = SnippetDocument(text: text)
        original = snippet
        originalText = text
        root = snippet.root
        name = snippet.name
        keywords = document.keywords ?? ""
        content = document.content
        initialKeywords = document.keywords ?? ""
        initialContent = document.content
    }

    init(creatingIn root: String, content: String) {
        original = nil
        originalText = ""
        self.root = root
        name = ""
        keywords = ""
        self.content = content
        initialKeywords = ""
        initialContent = content
    }

    var isCreating: Bool { original == nil }

    var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var nameProblem: SnippetFileName.Problem? { SnippetFileName.problem(in: name) }

    var canSave: Bool {
        nameProblem == nil && !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isDirty: Bool {
        name != (original?.name ?? "") || keywords != initialKeywords || content != initialContent
            || root != (original?.root ?? root)
    }

    var focusOrder: [Field] {
        isCreating ? [.folder, .name, .keywords, .content] : [.name, .keywords, .content]
    }

    func advanceFocus(backwards: Bool) {
        let fields = focusOrder
        let index = fields.firstIndex(of: focusedField) ?? 0
        focusedField = fields[(index + (backwards ? fields.count - 1 : 1)) % fields.count]
    }
}
