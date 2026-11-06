import Foundation

@main
@MainActor
struct TemplateTests {
    static var failures = 0
    static var passes = 0

    static func main() {
        testTemplateExpansion()
        testDynamicPlaceholders()
        testTemplateEncodingAndSelectionAlias()

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    private static func testTemplateExpansion() {
        var calendar = Calendar(identifier: .gregorian)
        let timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.timeZone = timeZone
        let now = calendar.date(
            from: DateComponents(
                year: 2026, month: 7, day: 24, hour: 13, minute: 5))!
        let context = TemplateEngine.ExpansionContext(
            clipboard: "{date} 📋",
            selection: "{cursor} selected",
            now: now,
            calendar: calendar,
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: timeZone)

        let expandedDateValues = TemplateEngine.expand(text: "{date}|{time}", context: context)
        check(
            "default date and time tokens use the injected locale, calendar, and time zone",
            expandedDateValues.text == "Jul 24, 2026|1:05\u{202F}PM")

        let values =
            "C:{clipboard}|S:{selection}|D:{date format=\"yyyy-MM-dd HH:mm\"}|"
            + "{argument name=\"First\"}|{argument}|{argument name=\"First\"}"
        let missing = TemplateEngine.expand(text: values, context: context)
        check(
            "missing arguments are unique and ordered by appearance",
            missing.missingArguments.map(\.name) == ["First", "Argument"])
        check(
            "missing argument tokens stay visible until values are supplied",
            missing.text.hasSuffix("{argument name=\"First\"}|{argument}|{argument name=\"First\"}"))

        let expandedValues = TemplateEngine.expand(
            text: values,
            context: context,
            userArguments: ["First": "{clipboard}", "Argument": "{cursor}"])
        check(
            "clipboard, selection, and arguments insert token-shaped text literally",
            expandedValues.text
                == "C:{date} 📋|S:{cursor} selected|D:2026-07-24 13:05|{clipboard}|{cursor}|{clipboard}")
        check(
            "injected cursor-shaped text does not set cursor position",
            expandedValues.cursorOffsetFromEnd == nil)
        check("all supplied arguments clear the missing list", expandedValues.missingArguments.isEmpty)

        let literalBraceResult = TemplateEngine.expand(
            text: "{\"generated\":\"{date}\"}|struct { value: {time} }", context: context)
        check(
            "literal JSON and code braces do not mask nested valid tokens",
            literalBraceResult.text == "{\"generated\":\"Jul 24, 2026\"}|struct { value: 1:05\u{202F}PM }")

        let promptTemplate = "{clipboard}|{selection}|{date format=\"HH:mm\"}|{argument name=\"Value\"}"
        let beforePrompt = TemplateEngine.expand(text: promptTemplate, context: context)
        let afterPrompt = TemplateEngine.expand(
            text: promptTemplate,
            context: context,
            userArguments: ["Value": "Done"])
        check(
            "argument prompts reuse the captured expansion context",
            beforePrompt.text.replacingOccurrences(
                of: "{argument name=\"Value\"}",
                with: "Done") == afterPrompt.text)

        let cursorResult = TemplateEngine.expand(
            text: "🙂👨‍👩‍👧‍👦{cursor}é終{cursor}", context: context)
        check("all cursor tokens are removed from final text", cursorResult.text == "🙂👨‍👩‍👧‍👦é終")
        check(
            "the first cursor wins, counted in characters", cursorResult.cursorOffsetFromEnd == 2)
        check(
            "a snippet reference is not a token and stays literal",
            TemplateEngine.expand(text: "{snippet:Child}|{snippet name=\"Child\"}", context: context).text
                == "{snippet:Child}|{snippet name=\"Child\"}")
    }

    /// Every token, parameter and modifier, against injected clock, locale and UUIDs.
    private static func testDynamicPlaceholders() {
        var calendar = Calendar(identifier: .gregorian)
        let timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.timeZone = timeZone
        let now = calendar.date(
            from: DateComponents(
                year: 2026, month: 7, day: 24, hour: 13, minute: 5))!
        let uuids = UUIDSequence()
        let context = TemplateEngine.ExpansionContext(
            clipboardHistory: ["  newest  ", "older", "oldest"],
            selection: "picked",
            now: now,
            calendar: calendar,
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: timeZone,
            makeUUID: { uuids.next() })

        func expand(
            _ text: String, arguments: [String: String] = [:]
        )
            -> TemplateEngine
            .ExpansionResult
        {
            TemplateEngine.expand(text: text, context: context, userArguments: arguments)
        }

        check(
            "datetime combines the date and time styles",
            expand("{datetime}").text == "Jul 24, 2026 at 1:05\u{202F}PM")
        check("day renders the weekday name", expand("{day}").text == "Friday")

        check(
            "a single signed offset shifts the date",
            expand("{date offset=\"+1d\"}").text == "Jul 25, 2026")
        check("offsets accept a bare unquoted value", expand("{day offset=-3d}").text == "Tuesday")
        check(
            "multiple offsets apply in order",
            expand("{date offset=\"+2y +5M\"}").text == "Dec 24, 2028")
        check(
            "minute and hour offsets shift the time",
            expand("{time offset=\"+3h +30m\"}").text == "4:35\u{202F}PM")
        check(
            "an unknown offset unit leaves the token literal",
            expand("{date offset=\"+1w\"}").text == "{date offset=\"+1w\"}")
        check(
            "an offset without an amount leaves the token literal",
            expand("{date offset=\"d\"}").text == "{date offset=\"d\"}")

        check(
            "locale overrides the context locale",
            expand("{date locale=\"fr-FR\"}").text == "24 juil. 2026")
        check(
            "format and locale together are rejected as ambiguous",
            expand("{date format=\"yyyy\" locale=\"fr-FR\"}").text
                == "{date format=\"yyyy\" locale=\"fr-FR\"}")
        check(
            "format still applies with an offset",
            expand("{date offset=\"-1d\" format=\"yyyy-MM-dd\"}").text == "2026-07-23")
        check(
            "a bare format needs no quotes",
            expand("{date format=yyyy-MM-dd}").text == "2026-07-24")
        check(
            "a bare format keeps its spaces",
            expand("{date format=MMMM d, yyyy}").text == "July 24, 2026")
        check(
            "a bare value ends at the next parameter",
            expand("{date format=MMM d offset=+1d}").text == "Jul 25")
        check(
            "a bare value trailing another parameter keeps its spaces",
            expand("{date offset=+1d format=MMM d}").text == "Jul 25")
        check(
            "a bare format with no value leaves the token literal",
            expand("{date format=}").text == "{date format=}")

        // UUID comes from the injected source, once per token.
        check("each uuid token draws a fresh value", expand("{uuid}|{uuid}").text == "uuid-1|uuid-2")

        check(
            "clipboard offset zero is the current clipboard",
            expand("{clipboard}").text == "  newest  ")
        check(
            "clipboard offset reaches back through history",
            expand("{clipboard offset=1}|{clipboard offset=2}").text == "older|oldest")
        check(
            "a clipboard offset past the end expands to nothing",
            expand("{clipboard offset=9}").text.isEmpty)
        check(
            "a negative clipboard offset leaves the token literal",
            expand("{clipboard offset=-1}").text == "{clipboard offset=-1}")

        check(
            "uppercase and lowercase modifiers apply",
            expand("{selection | uppercase}|{selection | lowercase}").text == "PICKED|picked")
        check("trim strips surrounding whitespace", expand("{clipboard | trim}").text == "newest")
        check(
            "modifiers chain left to right",
            expand("{clipboard | trim | uppercase}").text == "NEWEST")
        check(
            "percent-encode escapes everything outside the unreserved set",
            expand("{argument name=\"U\" | percent-encode}", arguments: ["U": "a b/c?d&e=f~g-h"]).text
                == "a%20b%2Fc%3Fd%26e%3Df~g-h")
        check(
            "json-stringify escapes without adding quotes",
            expand("{argument name=\"J\" | json-stringify}", arguments: ["J": "a\"b\\c\nd"]).text
                == "a\\\"b\\\\c\\nd")
        check(
            "raw is accepted and changes nothing",
            expand("{clipboard | raw}").text == "  newest  ")
        check(
            "an unknown modifier leaves the token literal",
            expand("{clipboard | shout}").text == "{clipboard | shout}")
        check(
            "a modifier on a structural token leaves it literal",
            expand("{cursor | uppercase}").text == "{cursor | uppercase}")
        check(
            "a pipe inside a quoted value is not a modifier separator",
            expand("{date format=\"yyyy|MM\"}").text == "2026|07")

        let defaulted = expand("{argument name=\"Tone\" default=\"happy\"}")
        check(
            "an argument default expands without prompting",
            defaulted.text == "happy" && defaulted.missingArguments.isEmpty)
        check(
            "a supplied value beats the default",
            expand("{argument name=\"Tone\" default=\"happy\"}", arguments: ["Tone": "sad"]).text
                == "sad")
        let optioned = expand("{argument name=\"Tone\" options=\"happy, sad, professional\"}")
        check(
            "options travel with the missing argument",
            optioned.missingArguments == [
                .init(name: "Tone", options: ["happy", "sad", "professional"])
            ])
        check(
            "an empty options list leaves the token literal",
            expand("{argument name=\"Tone\" options=\", \"}").text
                == "{argument name=\"Tone\" options=\", \"}")

        // What the header's argument fields are built from, without expanding anything else.
        check(
            "declared arguments are listed in written order, once each",
            TemplateEngine.declaredArguments(
                in: "{argument name=\"Repo\"}/{argument name=\"Branch\"}?q={argument name=\"Repo\"}"
            ).map(\.name) == ["Repo", "Branch"])
        check(
            "an argument with a default is still offered, but optional",
            TemplateEngine.declaredArguments(
                in: "{argument name=\"Tone\" default=\"happy\"}")
                == [.init(name: "Tone", options: [], isOptional: true)])
        check(
            "an occurrence without a default leaves the argument owed",
            TemplateEngine.declaredArguments(
                in: "{argument name=\"Tone\" default=\"happy\"}/{argument name=\"Tone\"}")
                == [.init(name: "Tone", options: [], isOptional: false)])
        check(
            "options travel with a declared argument as they do with a missing one",
            TemplateEngine.declaredArguments(
                in: "{argument name=\"Tone\" options=\"happy, sad\"}")
                == [.init(name: "Tone", options: ["happy", "sad"], isOptional: false)])
        check(
            "a template that reads only the clipboard declares no arguments",
            TemplateEngine.declaredArguments(in: "https://x.dev/?q={clipboard}").isEmpty)

        // Malformed tokens stay literal rather than vanishing.
        check("an unknown placeholder stays literal", expand("{weather}").text == "{weather}")
        check(
            "an unknown parameter leaves the token literal",
            expand("{date style=\"long\"}").text == "{date style=\"long\"}")
        check(
            "a duplicated parameter leaves the token literal",
            expand("{date offset=\"+1d\" offset=\"+2d\"}").text
                == "{date offset=\"+1d\" offset=\"+2d\"}")
        check(
            "an unterminated quote leaves the token literal",
            expand("{date format=\"yyyy}").text == "{date format=\"yyyy}")
        check(
            "a parameter on a token that takes none leaves it literal",
            expand("{uuid offset=1}").text == "{uuid offset=1}")
        check(
            "an empty clipboard history expands the clipboard to nothing",
            TemplateEngine.expand(
                text: "[{clipboard}]",
                context: TemplateEngine.ExpansionContext(
                    clipboardHistory: [],
                    selection: "",
                    now: now,
                    calendar: calendar,
                    locale: Locale(identifier: "en_US_POSIX"),
                    timeZone: timeZone)
            ).text == "[]")
    }

    /// Shared with Quicklinks: bare strings, encoding, and Raycast's `{selectedText}`.
    private static func testTemplateEncodingAndSelectionAlias() {
        var calendar = Calendar(identifier: .gregorian)
        let timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.timeZone = timeZone
        let context = TemplateEngine.ExpansionContext(
            clipboardHistory: ["a b&c"],
            selection: "a b&c",
            now: calendar.date(from: DateComponents(year: 2026, month: 7, day: 24))!,
            calendar: calendar,
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: timeZone)

        func expand(
            _ text: String,
            encoding: TemplateEngine.ValueEncoding = .none,
            arguments: [String: String] = [:]
        ) -> TemplateEngine.ExpansionResult {
            TemplateEngine.expand(
                text: text, context: context, userArguments: arguments, encoding: encoding)
        }

        check(
            "a bare template expands without a snippet record",
            expand("q={clipboard}").text == "q=a b&c")
        check(
            "a snippet reference has nothing to resolve against and stays literal",
            expand("{snippet:Child}").text == "{snippet:Child}")
        check(
            "missing arguments are reported from the text entry point too",
            expand("{argument name=\"Repository\"}").missingArguments
                == [.init(name: "Repository", options: [])])

        check(
            "percent encoding escapes a value substituted into a URL",
            expand("https://x.com/?q={clipboard}", encoding: .percentEncoding).text
                == "https://x.com/?q=a%20b%26c")
        check(
            "the literal parts of the template are never encoded",
            expand("https://x.com/a b?q={selection}", encoding: .percentEncoding).text
                == "https://x.com/a b?q=a%20b%26c")
        check(
            "encoding runs after the pipeline, so uppercase cannot rewrite the hex",
            expand("{clipboard | uppercase}", encoding: .percentEncoding).text == "A%20B%26C")
        check(
            "raw opts a value out of automatic encoding",
            expand("{clipboard | raw}", encoding: .percentEncoding).text == "a b&c")
        check(
            "an explicit percent-encode is not applied twice",
            expand("{clipboard | percent-encode}", encoding: .percentEncoding).text
                == "a%20b%26c")
        check(
            "encoding reaches every value-producing token",
            expand("{argument name=\"A\"}", encoding: .percentEncoding, arguments: ["A": "x y"]).text
                == "x%20y")
        check(
            "snippets ask for no encoding, so their expansion is unchanged",
            expand("{clipboard}").text == "a b&c")

        check(
            "selectedText resolves to the selection",
            expand("{selectedText}").text == expand("{selection}").text)
        check(
            "the alias is case-insensitive like every other token name",
            expand("{SelectedText}").text == "a b&c")
        check(
            "the alias takes the same modifier pipeline",
            expand("{selectedText | trim | uppercase}").text == "A B&C")
        check(
            "the alias is encoded like the canonical spelling",
            expand("{selectedText}", encoding: .percentEncoding).text == "a%20b%26c")
        check(
            "the alias rejects parameters, exactly as selection does",
            expand("{selectedText offset=1}").text == "{selectedText offset=1}")
        check(
            "readsSelection sees both spellings",
            expand("a {selection} b").readsSelection && expand("a {selectedText} b").readsSelection)
        check(
            "readsSelection is false for a template that reads no selection",
            !expand("{clipboard} {date}").readsSelection)
        check(
            "readsSelection parses rather than searches, so a malformed token does not count",
            !expand("{selection offset=1}").readsSelection)
        // {query} is Raycast's spelling of {argument}.
        check(
            "query resolves as an argument named Argument",
            expand("{query}", arguments: ["Argument": "hi"]).text == "hi")
        check(
            "the query alias is case-insensitive like every other token name",
            expand("{Query}", arguments: ["Argument": "hi"]).text == "hi")
        check(
            "the query alias keeps named parameters",
            expand("{query name=\"Keyword\"}", arguments: ["Keyword": "x"]).text == "x")
        check(
            "a parameter named query is still an argument, not the alias",
            expand("{argument name=\"query\"}", arguments: ["query": "kept"]).text == "kept")
    }

    private static func check(_ description: String, _ condition: @autoclosure () -> Bool) {
        if condition() {
            print("PASS  \(description)")
            passes += 1
        } else {
            print("FAIL  \(description)")
            failures += 1
        }
    }
}

/// Deterministic `{uuid}` source; the lock is why it is `@unchecked Sendable`.
private final class UUIDSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return "uuid-\(count)"
    }
}
