import CoreServices
import Foundation

/// The in-memory index of every snippet file, kept current by FSEvents and cached across launches.
@MainActor
@Observable
final class SnippetStore {
    /// Newest change first, which is the order the screen lists them in.
    private(set) var snippets: [Snippet] = []
    private(set) var sources: [SnippetSource] = []
    /// False until the first scan, or the cache, has said what is there.
    private(set) var hasLoaded = false
    private(set) var isScanning = false
    /// Called when a scan finds unreadable files it had not already reported.
    @ObservationIgnored var onFailures: (([String]) -> Void)?

    @ObservationIgnored private var roots: [String] = []
    @ObservationIgnored private var excludes: [String] = []
    @ObservationIgnored private var watcher: FileSystemWatcher?
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var rescanPending = false
    @ObservationIgnored private var reportedFailures: Set<String> = []
    /// When each snippet was last used this session; never saved, so a relaunch forgets it.
    @ObservationIgnored private var used: [String: Date] = [:]
    @ObservationIgnored private let cacheURL: URL
    @ObservationIgnored private let homeDirectory: URL
    @ObservationIgnored private let events = DispatchQueue(label: "com.olegy.tinycast.snippets.events")

    init(
        cacheURL: URL = AppPaths.caches().appending(path: "snippets-index.json"),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.cacheURL = cacheURL
        self.homeDirectory = homeDirectory
    }

    var isRunning: Bool { watcher != nil || scanTask != nil || hasLoaded }

    /// Settings as written, `~` allowed; a call with nothing changed is free.
    func start(folders: [String], excludes: [String]) {
        let roots = folders.map {
            FileSearchScope.expand($0, homeDirectory: homeDirectory).standardizedFileURL.path
        }
        guard roots != self.roots || excludes != self.excludes || !isRunning else { return }
        self.roots = roots
        self.excludes = excludes
        if !hasLoaded { loadCache() }
        watch()
        rescan()
    }

    func stop() {
        watcher = nil
        scanTask?.cancel()
        scanTask = nil
        rescanPending = false
        roots = []
        snippets = []
        sources = []
        hasLoaded = false
        reportedFailures = []
        used = [:]
    }

    /// Lifts a snippet to the top on the next `applyUse`, without touching its file.
    func noteUse(of path: String, at date: Date = .now) {
        used[path] = date
    }

    /// Separate from `noteUse` so the list never reorders under the pointer.
    func applyUse() {
        let ordered = SnippetSearch.ordered(snippets, used: used)
        if ordered != snippets { snippets = ordered }
    }

    /// A fresh look at the folders; files whose date and size are unchanged are not reopened.
    func rescan(reportingAllFailures: Bool = false) {
        guard !roots.isEmpty else {
            finish(SnippetScanner.Outcome(snippets: [], sources: [], failures: []), cache: false)
            return
        }
        if reportingAllFailures { reportedFailures = [] }
        guard scanTask == nil else {
            rescanPending = true
            return
        }
        isScanning = true
        let roots = roots
        let excludes = excludes
        let home = homeDirectory
        let known = Dictionary(snippets.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        scanTask = Task {
            let outcome = await SnippetScanner.scan(
                roots: roots, excludes: excludes, homeDirectory: home, known: known)
            guard !Task.isCancelled else { return }
            scanTask = nil
            isScanning = false
            // Settings may have moved on while the scan ran; its result describes the old folders.
            let current = roots == self.roots && excludes == self.excludes
            if current { finish(outcome, cache: true) }
            if rescanPending || !current {
                rescanPending = false
                rescan()
            }
        }
    }

    func snippet(at path: String) -> Snippet? {
        snippets.first { $0.path == path }
    }

    func source(of snippet: Snippet) -> SnippetSource? {
        sources.first { $0.root == snippet.root }
    }

    private func finish(_ outcome: SnippetScanner.Outcome, cache: Bool) {
        let paths = Set(outcome.snippets.map(\.path))
        used = used.filter { paths.contains($0.key) }
        let ordered = used.isEmpty ? outcome.snippets : SnippetSearch.ordered(outcome.snippets, used: used)
        if ordered != snippets { snippets = ordered }
        if outcome.sources != sources { sources = outcome.sources }
        hasLoaded = true
        let fresh = outcome.failures.filter { !reportedFailures.contains($0) }
        reportedFailures = Set(outcome.failures)
        if !fresh.isEmpty { onFailures?(fresh) }
        if cache { saveCache() }
    }

    private func watch() {
        watcher = nil
        guard !roots.isEmpty else { return }
        watcher = FileSystemWatcher(
            paths: roots, since: FSEventStreamEventId(kFSEventStreamEventIdSinceNow), queue: events
        ) { [weak self] _ in
            Task { @MainActor in self?.rescan() }
        }
    }

    // MARK: - Cache

    private struct Cache: Codable {
        static let version = 1
        let version: Int
        let roots: [String]
        let excludes: [String]
        let snippets: [Snippet]
    }

    /// Shows the last scan at once; the rescan right after replaces whatever changed meanwhile.
    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
            let cache = try? JSONDecoder().decode(Cache.self, from: data),
            cache.version == Cache.version, cache.roots == roots, cache.excludes == excludes
        else { return }
        snippets = SnippetSearch.ordered(cache.snippets)
        sources = roots.map { root in
            let decoration = try? Data(
                contentsOf: URL(filePath: root).appending(path: SnippetSource.decorationFile))
            return SnippetSource(root: root, decoration: decoration)
        }
        hasLoaded = true
    }

    private func saveCache() {
        let cache = Cache(version: Cache.version, roots: roots, excludes: excludes, snippets: snippets)
        guard let data = try? JSONEncoder().encode(cache) else { return }
        let url = cacheURL
        Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }
}
