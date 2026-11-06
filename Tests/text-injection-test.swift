import AppKit
import Foundation

@main
@MainActor
struct TextInjectionTests {
    static var failures = 0
    static var passes = 0

    static func main() async throws {
        // The in-process delivery tier drives a real text view, which needs AppKit awake.
        _ = NSApplication.shared
        try await testDeliveryQueueAndPasteboard()
        await testCopySelectionFallback()
        testOwnEditorInjection()

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    private static func testCopySelectionFallback() async {
        let injector = TextInjector(clipboardManager: ClipboardManager())
        let backing = NSPasteboard(name: .init("tinycast-copy-tests-\(UUID().uuidString)"))
        defer { backing.releaseGlobally() }
        let pasteboard = StubPasteboard(backing: backing)

        func seed(_ text: String) {
            let item = NSPasteboardItem()
            item.setString(text, forType: .string)
            backing.clearContents()
            _ = backing.writeObjects([item])
        }

        seed("Something the reader copied earlier")
        let unchanged = await injector.copySelection(from: nil, pasteboard: pasteboard)
        check("a copy that never lands returns nothing, not the stale clipboard", unchanged == nil)
        check(
            "the reader's clipboard survives a failed copy",
            backing.string(forType: .string) == "Something the reader copied earlier")

        seed("Original")
        let writer = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            let item = NSPasteboardItem()
            item.setString("the selection", forType: .string)
            backing.clearContents()
            _ = backing.writeObjects([item])
        }
        let copied = await injector.copySelection(from: nil, pasteboard: pasteboard)
        _ = await writer.result
        check("a copy that lands is read back: \(copied ?? "nil")", copied == "the selection")
        check(
            "the reader's clipboard is restored afterwards",
            backing.string(forType: .string) == "Original")

        let manager = ClipboardManager()
        let paused = TextInjector(clipboardManager: manager)
        seed("Original")
        let probe = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            let pausesAtCopy = manager.pauses
            let item = NSPasteboardItem()
            item.setString("the selection", forType: .string)
            backing.clearContents()
            _ = backing.writeObjects([item])
            return pausesAtCopy
        }
        _ = await paused.copySelection(from: nil, pasteboard: pasteboard)
        let pausesAtCopy = await probe.value
        check("history is paused while the borrowed copy lands", pausesAtCopy == 1)
        check("the restore is baselined before history resumes", manager.syncedWhilePaused)
        check("a landed copy resumes history", manager.pauses == 0)
        _ = await paused.copySelection(from: nil, pasteboard: pasteboard)
        check("a copy that never lands resumes history", manager.pauses == 0)

        // Two borrows in flight: the later one must not read the earlier one's restore as a copy.
        seed("Secret")
        let first = Task { @MainActor in
            await injector.copySelection(from: nil, pasteboard: pasteboard)
        }
        try? await Task.sleep(for: .milliseconds(100))
        let second = await injector.copySelection(from: nil, pasteboard: pasteboard)
        let earlier = await first.value
        check(
            "overlapping borrows never return the clipboard as a selection: "
                + "\(earlier ?? "nil"), \(second ?? "nil")",
            earlier == nil && second == nil)
        check(
            "overlapping borrows leave the clipboard as it was",
            backing.string(forType: .string) == "Secret")
    }

    /// Our panels never activate, so the frontmost app is not where the typist's caret is.
    private static func testOwnEditorInjection() {
        let editor = HarnessEditor(frame: NSRect(x: 0, y: 0, width: 320, height: 120))

        editor.string = "Regards, "
        editor.setSelectedRange(NSRange(location: 9, length: 0))
        editor.inject(InjectedText("Ada Lovelace"), over: editor.selectedRange())
        check("text is inserted at the caret", editor.string == "Regards, Ada Lovelace")
        check(
            "the caret lands after the inserted text",
            editor.selectedRange() == NSRange(location: 21, length: 0))

        editor.string = "wrap me"
        editor.setSelectedRange(NSRange(location: 0, length: 7))
        editor.inject(InjectedText("<b></b>", cursorOffsetFromEnd: 4), over: editor.selectedRange())
        check(
            "the selection is replaced and the caret honours the template's cursor offset",
            editor.string == "<b></b>" && editor.selectedRange() == NSRange(location: 3, length: 0))

        check(
            "the caret offset counts UTF-16 units, not characters",
            InjectedText("\u{1F1F3}\u{1F1F1} done", cursorOffsetFromEnd: 5).caretPrefixLength == 4)
    }

    private static func testDeliveryQueueAndPasteboard() async throws {
        let queue = DeliveryQueue()
        var order: [String] = []
        queue.enqueue {
            order.append("first-start")
            try? await Task.sleep(for: .milliseconds(30))
            order.append("first-end")
        }
        queue.enqueue {
            order.append("second")
        }
        await queue.drain()
        check(
            "interactive deliveries are retained and serialized",
            order == ["first-start", "first-end", "second"] && queue.isIdle)

        var completionCount = 0
        var failureCount = 0
        let completion = DeliveryCompletion(
            onDelivered: { completionCount += 1 }, onFailed: { failureCount += 1 })
        completion.confirm()
        completion.confirm()
        completion.settle()
        check(
            "delivery completion invokes its callback exactly once after confirmation",
            completion.isConfirmed && completionCount == 1 && failureCount == 0)

        var unconfirmedFailures = 0
        let unconfirmed = DeliveryCompletion(onFailed: { unconfirmedFailures += 1 })
        unconfirmed.settle()
        unconfirmed.settle()
        unconfirmed.confirm()
        check(
            "a delivery that returned early reports failure exactly once and stays unconfirmed",
            !unconfirmed.isConfirmed && unconfirmedFailures == 1)

        check(
            "unavailable AX text attributes use the event delivery fallback",
            AccessibilityReplacement.unavailable.fallsBackToEvents)
        check(
            "a rejected AX replacement fails closed instead of falling back to events",
            !AccessibilityReplacement.rejected.fallsBackToEvents)

        check(
            "AX replacement confirmation requires the observable text to actually change",
            TextReplacementPolicy.confirmsReplacement(
                originalValue: "!tcprobe",
                replacementRange: NSRange(location: 0, length: 8),
                insertedText: "PROBE_OK",
                observedValue: "PROBE_OK"))
        check(
            "an AX setter success with unchanged text is not accepted as delivery",
            !TextReplacementPolicy.confirmsReplacement(
                originalValue: "!tcprobe",
                replacementRange: NSRange(location: 0, length: 8),
                insertedText: "PROBE_OK",
                observedValue: "!tcprobe"))
        check(
            "an AX write that lands somewhere unexpected is not accepted as delivery",
            !TextReplacementPolicy.confirmsReplacement(
                originalValue: "keep !tcprobe",
                replacementRange: NSRange(location: 5, length: 8),
                insertedText: "PROBE_OK",
                observedValue: "PROBE_OK !tcprobe"))
        check(
            "an unreadable value after the write is not accepted as delivery",
            !TextReplacementPolicy.confirmsReplacement(
                originalValue: "!tcprobe",
                replacementRange: NSRange(location: 0, length: 8),
                insertedText: "PROBE_OK",
                observedValue: nil))

        check(
            "a Unicode keystroke never carries more than Blink's four-unit cap",
            UnicodeTypingChunk.split(String(repeating: "a", count: 30))
                .allSatisfy { $0.count <= UnicodeTypingChunk.maxUTF16Units })
        check(
            "chunked Unicode keystrokes reassemble into the original text",
            UnicodeTypingChunk.split("Fix this sentence, 雪が降る 👨‍👩‍👧 — done.")
                .flatMap { $0 } == Array("Fix this sentence, 雪が降る 👨‍👩‍👧 — done.".utf16))
        check(
            "a surrogate pair is never split across two keystrokes",
            UnicodeTypingChunk.split("ab👩🏽‍🚀").allSatisfy { chunk in
                String(decoding: chunk, as: UTF16.self).unicodeScalars.allSatisfy { $0.value != 0xFFFD }
            })
        check("empty text produces no keystrokes", UnicodeTypingChunk.split("").isEmpty)
        check(
            "unreadable AX state accepts a posted paste after the conservative delay",
            PasteConfirmationPolicy.acceptsUnconfirmedDelivery(
                attempt: 15,
                hadPreviousState: true,
                readStateAfterPaste: false))
        check(
            "readable unchanged AX state is not treated as a confirmed paste",
            !PasteConfirmationPolicy.acceptsUnconfirmedDelivery(
                attempt: 79,
                hadPreviousState: true,
                readStateAfterPaste: true))

        let backingPasteboard = NSPasteboard(
            name: .init("tinycast-injection-tests-\(UUID().uuidString)"))
        let pasteboard = StubPasteboard(backing: backingPasteboard)
        defer { backingPasteboard.releaseGlobally() }
        let customType = NSPasteboard.PasteboardType("com.example.custom")
        let firstItem = NSPasteboardItem()
        firstItem.setString("Original", forType: .string)
        firstItem.setData(Data([0, 1, 2, 3]), forType: customType)
        let secondType = NSPasteboard.PasteboardType("com.example.second")
        let secondItem = NSPasteboardItem()
        secondItem.setData(Data([4, 5, 6]), forType: secondType)
        check(
            "pasteboard fixture writes multiple items and types",
            pasteboard.replaceObjects([firstItem, secondItem]))

        let lease = TemporaryPasteboardLease.begin(
            text: "Temporary",
            pasteboard: pasteboard)
        check(
            "the lent pasteboard carries the text and no representation of the original",
            lease?.isOwned == true
                && pasteboard.string(forType: .string) == "Temporary"
                && pasteboard.pasteboardItems?.count == 1
                && pasteboard.pasteboardItems?[0].data(forType: customType) == nil
                && pasteboard.pasteboardItems?[0].data(forType: secondType) == nil
        )
        let restoreResult = lease?.restoreIfOwned()
        let restoredItems = pasteboard.pasteboardItems
        check(
            "pasteboard restoration preserves every item, type, and payload",
            restoreResult != nil
                && restoredItems?.count == 2
                && restoredItems?[0].string(forType: .string) == "Original"
                && restoredItems?[0].data(forType: customType) == Data([0, 1, 2, 3])
                && restoredItems?[1].data(forType: secondType) == Data([4, 5, 6]))
        check(
            "pasteboard restoration leaves no Tinycast marker on the restored clipboard",
            restoredItems?.allSatisfy {
                !$0.types.contains(ClipboardManager.internalType)
            } == true)

        pasteboard.writeFailuresRemaining = 1
        var recoveredMutationCount: Int?
        let failedLease = TemporaryPasteboardLease.begin(
            text: "Temporary failure",
            pasteboard: pasteboard,
            onMutation: { recoveredMutationCount = $0 })
        check(
            "a failed temporary write restores the original clipboard before falling back",
            failedLease == nil
                && pasteboard.string(forType: .string) == "Original"
                && pasteboard.pasteboardItems?.count == 2
                && recoveredMutationCount == pasteboard.changeCount)

        let supersededLease = TemporaryPasteboardLease.begin(
            text: "Temporary again",
            pasteboard: pasteboard)
        let newerItem = NSPasteboardItem()
        newerItem.setString("Newer copy", forType: .string)
        _ = pasteboard.replaceObjects([newerItem])
        check(
            "pasteboard restoration never overwrites a newer copy",
            supersededLease?.restoreIfOwned() == .superseded
                && pasteboard.string(forType: .string) == "Newer copy")

        _ = pasteboard.replaceObjects([])
        let emptyLease = TemporaryPasteboardLease.begin(
            text: "Temporary from empty",
            pasteboard: pasteboard)
        check(
            "an empty clipboard still lends a temporary string to paste",
            emptyLease?.isOwned == true
                && pasteboard.string(forType: .string) == "Temporary from empty")
        check(
            "restoring a borrowed empty clipboard leaves it empty again",
            emptyLease?.restoreIfOwned() != nil
                && pasteboard.pasteboardItems?.isEmpty != false)

        let imageOnlyItem = NSPasteboardItem()
        imageOnlyItem.setData(Data([9, 8, 7]), forType: .png)
        _ = pasteboard.replaceObjects([imageOnlyItem])
        let imageLease = TemporaryPasteboardLease.begin(
            text: "Temporary over image",
            pasteboard: pasteboard)
        check(
            "a non-text clipboard still lends a temporary string to paste",
            imageLease?.isOwned == true
                && pasteboard.string(forType: .string) == "Temporary over image")
        check(
            "restoring a borrowed image clipboard returns the original payload",
            imageLease?.restoreIfOwned() != nil
                && pasteboard.pasteboardItems?.count == 1
                && pasteboard.data(forType: .png) == Data([9, 8, 7])
                && pasteboard.string(forType: .string) == nil)
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

@MainActor
private final class StubPasteboard: PasteboardAccess {
    let backing: NSPasteboard
    var writeFailuresRemaining = 0

    init(backing: NSPasteboard) {
        self.backing = backing
    }

    var changeCount: Int { backing.changeCount }
    var pasteboardItems: [NSPasteboardItem]? { backing.pasteboardItems }

    @discardableResult
    func clearContents() -> Int {
        backing.clearContents()
    }

    func writeObjects(_ objects: [any NSPasteboardWriting]) -> Bool {
        if writeFailuresRemaining > 0 {
            writeFailuresRemaining -= 1
            return false
        }
        return backing.writeObjects(objects)
    }

    func replaceObjects(_ objects: [any NSPasteboardWriting]) -> Bool {
        clearContents()
        return objects.isEmpty || writeObjects(objects)
    }

    func string(forType type: NSPasteboard.PasteboardType) -> String? {
        backing.string(forType: type)
    }

    func data(forType type: NSPasteboard.PasteboardType) -> Data? {
        backing.data(forType: type)
    }
}

@MainActor
final class ClipboardManager {
    static let internalType = NSPasteboard.PasteboardType("com.tinycast.internal")
    func prepareForTinycastPasteboardMutation() {}
    private(set) var pauses = 0
    private(set) var syncedWhilePaused = false
    func synchronizeAfterTinycastPasteboardMutation(changeCount: Int) {
        syncedWhilePaused = pauses > 0
    }
    func pauseCapture() { pauses += 1 }
    func resumeCapture() { pauses -= 1 }
}

enum Permissions {
    static func ensureAccessibility() -> Bool { false }
    static func isAccessibilityTrusted() -> Bool { false }
}

enum Paster {
    @MainActor static func postCommandV(toPid pid: pid_t? = nil) {}
    @MainActor static func postCommandC(toPid pid: pid_t? = nil) {}
}

private final class HarnessEditor: NSTextView, InjectableTextView {}
