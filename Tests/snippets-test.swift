import Foundation

@main
struct SnippetsTests {
    nonisolated(unsafe) static var failures = 0

    static func main() async {
        testFrontmatter()
        testKeywordEdits()
        testContentEdits()
        testNewFile()
        testClipboardText()
        testSearch()
        testFileNames()
        testSources()
        testWriter()
        await testScanner()

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    static func check(_ name: String, _ condition: Bool) {
        if condition {
            print("  ok  \(name)")
        } else {
            failures += 1
            print("FAIL  \(name)")
        }
    }

    static func expect<T: Equatable>(_ name: String, _ actual: T, _ expected: T) {
        check(name, actual == expected)
        if actual != expected { print("      got \(actual), expected \(expected)") }
    }

    static func testFrontmatter() {
        var doc = SnippetDocument(text: "---\nkeywords: docker run\n---\n\nbody\n")
        expect("keywords read", doc.keywords, "docker run")
        expect("content skips frontmatter and blank line", doc.content, "body")

        doc = SnippetDocument(text: "---\nKeywords: Express  JWT\ntags: [a]\n---\nx")
        expect("key is case-insensitive", doc.keywords, "Express  JWT")

        doc = SnippetDocument(text: "---\nkeywords: [a, b]\n---\nx")
        expect("a list is not a keywords string", doc.keywords, nil)
        check("a list still makes frontmatter", doc.hasFrontmatter)

        doc = SnippetDocument(text: "---\nkeywords: \"a: b\"\n---\nx")
        expect("quotes are taken off", doc.keywords, "a: b")

        doc = SnippetDocument(text: "---\nkeywords: a b # note\n---\nx")
        expect("a comment is not part of the value", doc.keywords, "a b")

        doc = SnippetDocument(text: "text\n---\nkeywords: a\n---\n")
        check("--- mid-text is no frontmatter", !doc.hasFrontmatter && doc.keywords == nil)

        doc = SnippetDocument(text: "---\n# Header\nplain words here\n---\nx")
        check("a block that is not a mapping is body", !doc.hasFrontmatter)
        expect("…and the whole file is content", doc.content, "---\n# Header\nplain words here\n---\nx")

        doc = SnippetDocument(text: "---\nkeywords: a\n")
        check("an unclosed block is body", !doc.hasFrontmatter)

        doc = SnippetDocument(text: "---\r\nkeywords: crlf\r\n---\r\n\r\nbody\r\n")
        expect("CRLF keywords", doc.keywords, "crlf")
        expect("CRLF content", doc.content, "body")

        doc = SnippetDocument(text: "\n\n  indented\nnext\n\n")
        expect("leading blank lines go, indentation stays", doc.content, "  indented\nnext")

        check("an open frontmatter needs more text", SnippetDocument.needsMoreText("---\nkeywords: a\n"))
        check("a closed one does not", !SnippetDocument.needsMoreText("---\nkeywords: a\n---\nbo"))
        check("no frontmatter needs nothing", !SnippetDocument.needsMoreText("hello"))
    }

    static func testKeywordEdits() {
        let obsidian = "---\ntags: [x, y]\nkeywords: old words\ncreated: 2024-01-01\n---\n\nBody\n"
        expect(
            "only the keywords line changes",
            SnippetDocument(text: obsidian).replacingKeywords(with: "new words"),
            "---\ntags: [x, y]\nkeywords: new words\ncreated: 2024-01-01\n---\n\nBody\n")
        expect(
            "clearing removes only that line",
            SnippetDocument(text: obsidian).replacingKeywords(with: "  "),
            "---\ntags: [x, y]\ncreated: 2024-01-01\n---\n\nBody\n")

        let noKey = "---\naliases: a\n---\nBody"
        expect(
            "a missing key is added before the closing fence",
            SnippetDocument(text: noKey).replacingKeywords(with: "k"),
            "---\naliases: a\nkeywords: k\n---\nBody")

        expect(
            "no frontmatter gets one",
            SnippetDocument(text: "Body\n").replacingKeywords(with: "k1 k2"),
            "---\nkeywords: k1 k2\n---\n\nBody\n")
        expect(
            "a frontmatter that held only keywords goes entirely",
            SnippetDocument(text: "---\nkeywords: a\n---\n\nBody\n").replacingKeywords(with: ""),
            "Body\n")
        expect(
            "an unchanged value leaves the text alone",
            SnippetDocument(text: obsidian).replacingKeywords(with: "old words"), obsidian)

        let list = "---\nkeywords:\n  - a\n  - b\nother: 1\n---\nx"
        expect(
            "a list value is replaced with its continuation lines",
            SnippetDocument(text: list).replacingKeywords(with: "c"),
            "---\nkeywords: c\nother: 1\n---\nx")

        expect(
            "CRLF files keep CRLF",
            SnippetDocument(text: "---\r\nkeywords: a\r\nx: 1\r\n---\r\nB").replacingKeywords(with: "b"),
            "---\r\nkeywords: b\r\nx: 1\r\n---\r\nB")
        expect(
            "a value YAML would misread is quoted",
            SnippetDocument(text: "B").replacingKeywords(with: "#tag"),
            "---\nkeywords: \"#tag\"\n---\n\nB")
    }

    static func testContentEdits() {
        let file = "---\ntags: x\n---\n\nold body\n"
        expect(
            "frontmatter and spacing stay, body changes",
            SnippetDocument(text: file).replacingContent(with: "new\nbody\n\n"),
            "---\ntags: x\n---\n\nnew\nbody\n")
        expect(
            "no trailing newline stays none",
            SnippetDocument(text: "old").replacingContent(with: "new"), "new")
        expect(
            "CRLF is kept for new lines",
            SnippetDocument(text: "a\r\nb\r\n").replacingContent(with: "c\nd"), "c\r\nd\r\n")
        expect(
            "an empty body after frontmatter",
            SnippetDocument(text: "---\nk: v\n---\n").replacingContent(with: "x"),
            "---\nk: v\n---\nx\n")
        expect(
            "a fence without a line break is not glued to the body",
            SnippetDocument(text: "---\nk: v\n---").replacingContent(with: "x"),
            "---\nk: v\n---\n\nx\n")
        expect(
            "unchanged content returns the text as is",
            SnippetDocument(text: file).replacingContent(with: "old body"), file)
    }

    static func testNewFile() {
        expect("plain body", SnippetDocument.newFile(keywords: " ", content: "x  \n\n"), "x\n")
        expect(
            "with keywords", SnippetDocument.newFile(keywords: "a b", content: "x"),
            "---\nkeywords: a b\n---\n\nx\n")
        let doc = SnippetDocument(text: SnippetDocument.newFile(keywords: "a", content: "body"))
        check("round-trips", doc.keywords == "a" && doc.content == "body")
    }

    static func testClipboardText() {
        typealias Clip = SnippetClipboardText
        expect("one line copies and pastes", Clip.copy("  git status \n"), "git status")
        expect("one line pastes", Clip.paste("git status"), "git status")

        let sole = "```bash\ndocker ps -a\n```"
        expect("a sole block copies without fences", Clip.copy(sole), "docker ps -a")
        expect("a sole one-line block pastes its line", Clip.paste(sole), "docker ps -a")

        let explained = "List all containers:\n\n```bash\n  docker ps -a  \n```\n\nThen prune."
        expect("prose around a block copies everything", Clip.copy(explained), explained)
        expect("…but pastes only the code line", Clip.paste(explained), "docker ps -a")

        let multi = "```\nline 1\nline 2\n```"
        expect("a sole multi-line block copies its code", Clip.copy(multi), "line 1\nline 2")
        expect("…and cannot paste", Clip.paste(multi), nil)

        let two = "```\na\n```\n```\nb\n```"
        expect("two blocks copy whole", Clip.copy(two), two)
        expect("two blocks cannot paste", Clip.paste(two), nil)

        expect("multi-line prose cannot paste", Clip.paste("one\ntwo"), nil)
        expect("empty cannot paste", Clip.paste(" \n "), nil)

        let tilde = "~~~~\ncode ``` here\n~~~\n~~~~"
        expect("tilde fences and a shorter inner fence", Clip.copy(tilde), "code ``` here\n~~~")
        expect("an unclosed fence copies whole", Clip.copy("```\nx"), "```\nx")
        expect("an unclosed fence cannot paste", Clip.paste("```\nx"), nil)
        expect("inline ``` with a backtick info string is prose", Clip.paste("```a`b```"), "```a`b```")
        expect("four-space fences are not fences", Clip.paste("a\n    ```\n    b\n    ```"), nil)
        expect("a blank line inside a one-line block", Clip.paste("```\n\nx\n\n```"), "x")
    }

    static func testSearch() {
        expect("words", SnippetSearch.words(in: "JWT validation for Express-a12_b"), [
            "jwt", "validation", "for", "express", "a12", "b"
        ])
        expect("cyrillic words", SnippetSearch.words(in: "Привет, мир"), ["привет", "мир"])

        let date = Date(timeIntervalSince1970: 1_000)
        let snippet = Snippet(
            path: "/v/ruby/Rails App/auth token.md", root: "/v", keywords: "JWT Express", modified: date,
            size: 1)
        expect("name", snippet.name, "auth token")
        expect("folders", snippet.folders, ["ruby", "Rails App"])
        expect("tags", snippet.tags, ["jwt", "express", "ruby", "rails app"])
        check("all terms must match", SnippetSearch.matches("auth exp", words: snippet.searchWords))
        check("a folder tag with a space matches inside", SnippetSearch.matches("app", words: snippet.searchWords))
        check("not fuzzy", !SnippetSearch.matches("autth", words: snippet.searchWords))
        check("and, not or", !SnippetSearch.matches("auth docker", words: snippet.searchWords))
        check("case-insensitive", SnippetSearch.matches("RUBY", words: snippet.searchWords))

        let root = Snippet(path: "/v/top.md", root: "/v", keywords: nil, modified: date, size: 1)
        expect("a root file has no folder tags", root.tags, [])

        let a = Snippet(path: "/v/a.md", root: "/v", keywords: nil, modified: date, size: 1)
        let b = Snippet(path: "/v/b.md", root: "/v", keywords: nil, modified: date, size: 1)
        let newest = Snippet(
            path: "/v/z.md", root: "/v", keywords: nil, modified: date.addingTimeInterval(5), size: 1)
        expect("newest first, then by name", SnippetSearch.ordered([b, newest, a]).map(\.name), ["z", "a", "b"])
        expect(
            "a recent use outranks an older change",
            SnippetSearch.ordered([newest, a, b], used: [b.path: date.addingTimeInterval(9)]).map(\.name),
            ["b", "z", "a"])
        expect(
            "an older use changes nothing",
            SnippetSearch.ordered([b, newest, a], used: [b.path: date.addingTimeInterval(-9)]).map(\.name),
            ["z", "a", "b"])
        expect("blank query keeps all", SnippetSearch.filter([a, b], query: "  ").count, 2)
    }

    static func testFileNames() {
        expect("empty", SnippetFileName.problem(in: "  "), .empty)
        expect("slash", SnippetFileName.problem(in: "a/b"), .slash)
        expect("colon", SnippetFileName.problem(in: "a:b"), .invalidCharacter)
        expect("dot", SnippetFileName.problem(in: ".hidden"), .leadingDot)
        expect("spaces and dashes are fine", SnippetFileName.problem(in: "my - snippet v2"), nil)
        expect("file name", SnippetFileName.fileName(for: " x "), "x.md")
    }

    static func testSources() {
        let decorated = SnippetSource(root: "/v/1-MEMO", decoration: Data(#"{"name":"Personal","icon":"🧠"}"#.utf8))
        check("name and icon from .vault.json", decorated.name == "Personal" && decorated.icon == "🧠")
        let plain = SnippetSource(root: "/v/1-MEMO", decoration: Data("{oops".utf8))
        check("broken JSON falls back to the folder name", plain.name == "1-MEMO" && plain.icon == nil)
    }

    static func temporaryFolder() -> String {
        let url = FileManager.default.temporaryDirectory.appending(path: "snippets-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.standardizedFileURL.path
    }

    static func read(_ path: String) -> String {
        (try? String(contentsOfFile: path, encoding: .utf8)) ?? "<missing>"
    }

    static func testWriter() {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(atPath: folder) }
        let fm = FileManager.default

        let created = try? SnippetFileWriter.create(
            in: folder, name: "first", keywords: "k", content: "hello", replacing: false)
        expect("create writes the new-file shape", read(created ?? ""), "---\nkeywords: k\n---\n\nhello\n")
        do {
            _ = try SnippetFileWriter.create(in: folder, name: "first", keywords: "", content: "x", replacing: false)
            check("create refuses to replace silently", false)
        } catch {
            expect("…and names the file", error as? SnippetFileError, .exists(name: "first"))
        }

        let path = (folder as NSString).appendingPathComponent("note.md")
        let original = "---\ntags: [a]\ncreated: today\n---\n\nold\n"
        try? original.write(toFile: path, atomically: true, encoding: .utf8)
        let renamed = try? SnippetFileWriter.update(
            at: path, original: original, name: "note renamed", keywords: "kw", content: "new",
            replacing: false, overwritingDiskChanges: false)
        expect("rename keeps the folder", renamed, (folder as NSString).appendingPathComponent("note renamed.md"))
        check("the old name is gone", !fm.fileExists(atPath: path))
        expect(
            "edit keeps every other frontmatter line", read(renamed ?? ""),
            "---\ntags: [a]\ncreated: today\nkeywords: kw\n---\n\nnew\n")

        let current = read(renamed ?? "")
        try? (current + "edited elsewhere\n").write(toFile: renamed ?? "", atomically: true, encoding: .utf8)
        do {
            _ = try SnippetFileWriter.update(
                at: renamed ?? "", original: current, name: "note renamed", keywords: "kw2", content: "new",
                replacing: false, overwritingDiskChanges: false)
            check("a disk change is caught", false)
        } catch {
            expect("…as changedOnDisk", error as? SnippetFileError, .changedOnDisk)
        }
        let merged = try? SnippetFileWriter.update(
            at: renamed ?? "", original: current, name: "note renamed", keywords: "kw2", content: "new",
            replacing: false, overwritingDiskChanges: true)
        check("overwriting still changes only keywords", read(merged ?? "").contains("keywords: kw2"))
        check("…so the disk edit to the body survives", read(merged ?? "").contains("edited elsewhere"))

        let caseOnly = try? SnippetFileWriter.update(
            at: merged ?? "", original: read(merged ?? ""), name: "Note Renamed", keywords: "kw2",
            content: SnippetDocument(text: read(merged ?? "")).content, replacing: false,
            overwritingDiskChanges: false)
        check(
            "a case-only rename works",
            caseOnly != nil
                && (try? fm.contentsOfDirectory(atPath: folder))?.contains("Note Renamed.md") == true)

        let other = temporaryFolder()
        defer { try? fm.removeItem(atPath: other) }
        let moved = try? SnippetFileWriter.move(caseOnly ?? "", to: other, replacing: false)
        expect("move keeps the name", moved, (other as NSString).appendingPathComponent("Note Renamed.md"))
    }

    static func testScanner() async {
        let root = temporaryFolder()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let fm = FileManager.default
        func write(_ relative: String, _ text: String) {
            let path = (root as NSString).appendingPathComponent(relative)
            try? fm.createDirectory(
                atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try? text.write(toFile: path, atomically: true, encoding: .utf8)
        }
        let longFrontmatter = "---\n" + String(repeating: "pad: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\n", count: 300)
            + "keywords: deep\n---\nbody"
        write("top.md", "---\nkeywords: alpha\n---\nx")
        write("ruby/rails/auth.MD", "y")
        write("long.md", longFrontmatter)
        write(".obsidian/hidden.md", "z")
        write("skip/me.md", "z")
        write("notes.txt", "z")
        write(".vault.json", #"{"name":"Work"}"#)

        let home = URL(filePath: root)
        let outcome = await SnippetScanner.scan(roots: [root], excludes: ["skip"], homeDirectory: home, known: [:])
        expect("only visible, unexcluded .md files", Set(outcome.snippets.map(\.name)), ["top", "auth", "long"])
        expect(
            "keywords from the head", outcome.snippets.first { $0.name == "top" }?.keywords, "alpha")
        expect(
            "a frontmatter past the first chunk is still read",
            outcome.snippets.first { $0.name == "long" }?.keywords, "deep")
        expect("folder tags", outcome.snippets.first { $0.name == "auth" }?.tags, ["ruby", "rails"])
        expect("source decoration", outcome.sources.first?.name, "Work")

        let known = outcome.snippets.first { $0.name == "top" }!
        let stale = Snippet(
            path: known.path, root: root, keywords: "cached", modified: known.modified, size: known.size)
        let again = await SnippetScanner.scan(
            roots: [root], excludes: ["skip"], homeDirectory: home, known: [known.path: stale])
        expect(
            "an unchanged file is not reopened", again.snippets.first { $0.name == "top" }?.keywords, "cached")
    }
}
