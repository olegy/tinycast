import Foundation
import Observation

/// One command's options screen: its list-run, the list it printed, and a refreshing action.
@MainActor
@Observable
final class CommandOptionsSession {
    /// A slow network volume must not hold the palette; the action itself has no deadline.
    static let listTimeout: Duration = .seconds(10)

    let command: CustomCommand
    private(set) var list: CommandOptionList?
    private(set) var failure: String?
    private(set) var isLoading = false
    /// True while a refreshing action runs, so a second ↵ cannot stack another.
    var isActing = false
    @ObservationIgnored private var loading: Task<Void, Never>?

    init(command: CustomCommand) {
        self.command = command
    }

    var isBusy: Bool { isLoading || isActing }

    /// The command's name until its own prompt arrives, so the field never reads as root search.
    var prompt: String? {
        guard let list else { return failure == nil ? command.name : nil }
        return list.prompt
    }

    var status: String? { failure == nil ? list?.status : nil }

    /// The script's order is the meaning of the list, so a query filters and never re-ranks.
    func rows(matching query: String) -> [CommandOption] {
        guard let list else { return [] }
        let query = ActionMenuSearchQuery(query)
        guard !query.isEmpty else { return list.options }
        return list.options.filter { query.score($0.title) != nil }
    }

    /// The row to highlight: the one acted on when it is still offered, else the list's default.
    func landing(in rows: [CommandOption], preferring argument: String?) -> Int {
        if let argument,
            let index = rows.firstIndex(where: { $0.argument == argument && !$0.isDisabled })
        {
            return index
        }
        if rows.count == list?.options.count, let list { return list.landingIndex }
        return rows.firstIndex { !$0.isDisabled } ?? 0
    }

    /// The previous list stays up while a refresh loads, so its rows never flash away.
    func load(onLoaded: @escaping @MainActor () -> Void) {
        loading?.cancel()
        isLoading = true
        let command = command
        loading = Task { [weak self] in
            let result = await ShellCommandRunner.listOptions(
                command.command, loadingShellEnvironment: command.loadsShellEnvironment,
                workingDirectory: command.workingDirectory,
                environment: [CustomCommand.phaseVariable: "list"], timeout: Self.listTimeout)
            guard !Task.isCancelled, let self else { return }
            self.apply(result)
            onLoaded()
        }
    }

    func cancel() {
        loading?.cancel()
        loading = nil
        isLoading = false
    }

    private func apply(_ result: ShellCommandResult) {
        isLoading = false
        loading = nil
        guard result.succeeded else {
            failure = Self.failureText(result)
            return
        }
        failure = nil
        list = CommandOptionList.parse(result.standardOutput ?? "")
    }

    private static func failureText(_ result: ShellCommandResult) -> String {
        let summary: String
        switch result.termination {
        case .launchFailed(let reason): summary = reason
        case .timedOut:
            summary = String(localized: "The command did not list its options within 10 seconds.")
        case .stopped: summary = String(localized: "Stopped")
        case .exited(let status): summary = String(localized: "The command exited with status \(status).")
        }
        return [summary, result.standardError].compactMap { $0 }.joined(separator: "\n\n")
    }
}
