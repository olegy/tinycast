import Foundation
import Observation

/// One Quick Action opened on the palette's screen: the text it works on and what came back.
@MainActor
@Observable
final class QuickActionSession {
    enum Source: Equatable {
        case selection
        case clipboard
        case none
    }

    enum Phase: Equatable {
        case editing
        case running
        case finished
        case failed(String)
        /// The pair is supported but not downloaded; the reader fetches it in System Settings.
        case needsLanguageDownload
    }

    let action: QuickAction
    let source: Source
    /// Why the text came from the clipboard instead, when the selection could not be asked for.
    let refusal: QuickActionFailure?
    var text: String
    /// This window's own choice; Settings never hears of it.
    var model: AIModelSelection?
    var language: Locale.Language
    private(set) var phase: Phase = .editing
    private(set) var output = ""
    /// The text the last run was given, so the diff stays true while the reader edits again.
    private(set) var ranText = ""

    @ObservationIgnored private var task: Task<Void, Never>?
    /// Bumped by every run and stop, so a superseded stream cannot write into the next one.
    @ObservationIgnored private(set) var runID = 0
    @ObservationIgnored private var cachedDiff: [TextDiffEngine.Chunk]?

    init(
        action: QuickAction, text: String, source: Source, refusal: QuickActionFailure?,
        model: AIModelSelection?, language: Locale.Language
    ) {
        self.action = action
        self.text = text
        self.source = source
        self.refusal = refusal
        self.model = model
        self.language = language
    }

    var isRunning: Bool { phase == .running }

    var isTooLong: Bool { text.utf8.count > QuickActionRunner.maxSelectionBytes }

    var canRun: Bool {
        !isRunning && !isTooLong && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasResult: Bool { phase == .finished && !output.isEmpty }

    var diff: [TextDiffEngine.Chunk] {
        guard action.showsDiff, phase == .finished else { return [] }
        if let cachedDiff { return cachedDiff }
        let chunks = TextDiffEngine.diff(original: ranText, modified: output)
        cachedDiff = chunks
        return chunks
    }

    func start(_ work: @escaping @MainActor (_ runID: Int) async -> Void) {
        task?.cancel()
        runID += 1
        ranText = text
        output = ""
        cachedDiff = nil
        phase = .running
        let mine = runID
        task = Task { await work(mine) }
    }

    func append(_ delta: String, runID: Int) {
        guard runID == self.runID else { return }
        output += delta
    }

    func finish(_ text: String, runID: Int) {
        guard runID == self.runID else { return }
        output = text
        cachedDiff = nil
        phase = .finished
    }

    func fail(_ message: String, runID: Int) {
        guard runID == self.runID else { return }
        phase = .failed(message)
    }

    func requireLanguageDownload(runID: Int) {
        guard runID == self.runID else { return }
        phase = .needsLanguageDownload
    }

    /// A stopped run is gone: its partial answer is not something to paste.
    func stop() {
        cancel()
        output = ""
        phase = .editing
    }

    func edit() {
        guard !isRunning else { return }
        phase = .editing
    }

    func cancel() {
        runID += 1
        task?.cancel()
        task = nil
    }
}
