import Foundation

/// One choice a list-run printed; choosing it runs the same command with `argument` as `$1`.
struct CommandOption: Hashable, Identifiable, Sendable {
    /// The line's position, so two options sharing a title stay two rows.
    let id: Int
    let title: String
    let argument: String
    var subtitle: String?
    var icon: String?
    var isDisabled = false
    var isDefault = false
    /// After the action the palette stays and the list is asked for again.
    var refreshes = false
}

/// What a command printed when asked for its options, in xbar's line format.
struct CommandOptionList: Equatable, Sendable {
    static let separator = "---"
    private static let parameterMarker = " | "

    /// The search field's placeholder: what the user is choosing.
    var prompt: String?
    /// Free text at the left of the bottom bar.
    var status: String?
    var options: [CommandOption]

    /// The highlight on open: the first enabled default, else the first enabled option.
    var landingIndex: Int {
        options.firstIndex { $0.isDefault && !$0.isDisabled }
            ?? options.firstIndex { !$0.isDisabled } ?? 0
    }

    /// Never fails: an unreadable parameter is dropped, never the option it sits on.
    static func parse(_ text: String) -> CommandOptionList {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let header: ArraySlice<String>
        let body: ArraySlice<String>
        if let separator = lines.firstIndex(of: Self.separator) {
            header = lines[..<separator]
            body = lines[(separator + 1)...]
        } else {
            header = []
            body = lines[...]
        }
        let options = body.filter { !$0.isEmpty }.enumerated().compactMap { index, line in
            option(index: index, line: line)
        }
        return CommandOptionList(
            prompt: header.first.flatMap(\.nonEmpty),
            status: header.dropFirst().first.flatMap(\.nonEmpty),
            options: options)
    }

    private static func option(index: Int, line: String) -> CommandOption? {
        let title: String
        var parameters: [String: String] = [:]
        if let marker = line.range(of: parameterMarker) {
            title = line[..<marker.lowerBound].trimmingCharacters(in: .whitespaces)
            parameters = Self.parameters(line[marker.upperBound...])
        } else {
            title = line
        }
        guard !title.isEmpty else { return nil }
        var option = CommandOption(
            id: index, title: title, argument: parameters["arg"]?.nonEmpty ?? title)
        option.subtitle = parameters["subtitle"]?.nonEmpty
        option.icon = parameters["icon"]?.nonEmpty
        option.isDisabled = flag(parameters["disabled"])
        option.isDefault = flag(parameters["default"])
        option.refreshes = flag(parameters["refresh"])
        return option
    }

    private static func flag(_ value: String?) -> Bool {
        value?.lowercased() == "true"
    }

    /// `key=value` pairs split on whitespace; a quoted value keeps its spaces, as xbar's does.
    static func parameters(_ text: Substring) -> [String: String] {
        var result: [String: String] = [:]
        var index = text.startIndex
        while index < text.endIndex {
            while index < text.endIndex, text[index].isWhitespace { index = text.index(after: index) }
            let keyStart = index
            while index < text.endIndex, text[index] != "=", !text[index].isWhitespace {
                index = text.index(after: index)
            }
            let key = String(text[keyStart..<index]).lowercased()
            guard index < text.endIndex, text[index] == "=" else { continue }
            index = text.index(after: index)
            var value = ""
            if index < text.endIndex, text[index] == "\"" || text[index] == "'" {
                let quote = text[index]
                index = text.index(after: index)
                while index < text.endIndex, text[index] != quote {
                    value.append(text[index])
                    index = text.index(after: index)
                }
                if index < text.endIndex { index = text.index(after: index) }
            } else {
                while index < text.endIndex, !text[index].isWhitespace {
                    value.append(text[index])
                    index = text.index(after: index)
                }
            }
            if !key.isEmpty { result[key] = value }
        }
        return result
    }
}

extension String {
    fileprivate var nonEmpty: String? { isEmpty ? nil : self }
}
