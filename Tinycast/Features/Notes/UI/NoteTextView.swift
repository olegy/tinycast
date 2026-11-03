import AppKit

@MainActor
final class NoteTextView: NSTextView, InjectableTextView {
    var editorUndoManager: UndoManager?
    weak var editing: NoteTextViewEditing?
    /// True during `mouseDown`'s drag loop; revealing mid-drag would shift text under the pointer.
    private(set) var isDragSelecting = false

    /// Tracked here because the window still names this view first responder while it resigns.
    private var isFirstResponder = false
    private var keyObservers: [NotificationToken] = []

    private static let checkboxSlop: CGFloat = 3

    override var undoManager: UndoManager? { editorUndoManager }

    var isFocused: Bool { isFirstResponder && window?.isKeyWindow == true }

    private var rendersMarkdown: Bool { editing?.rendersMarkdown == true }

    /// One undoable replacement that reaches `textDidChange`, so autosave and restyling see it.
    @discardableResult
    func performEdit(_ plan: NoteEditPlan) -> Bool {
        breakUndoCoalescing()
        guard let textStorage, shouldChangeText(in: plan.range, replacementString: plan.replacement)
        else { return false }
        textStorage.replaceCharacters(in: plan.range, with: plan.replacement)
        didChangeText()
        setSelectedRange(plan.selection)
        breakUndoCoalescing()
        return true
    }

    func replaceUnchangedSelection(
        with text: String, source: String, range: NSRange
    ) -> Bool {
        guard isEditable, range.length > 0, string == source, selectedRange() == range else {
            return false
        }
        return performEdit(
            NoteEditPlan(
                range: range, replacement: text,
                selection: NSRange(location: range.location + (text as NSString).length, length: 0)))
    }

    func format(_ action: NoteEditAction) {
        perform(action)
    }

    func find(_ action: NSTextFinder.Action) {
        let item = NSMenuItem()
        item.tag = action.rawValue
        performTextFinderAction(item)
    }

    /// The frame never gets shorter than the clip view, so only the layout knows the text's height.
    func textHeight(upTo limit: CGFloat) -> CGFloat {
        guard let textLayoutManager else { return frame.height }
        var height: CGFloat = 0
        // Summed: until the next draw, the lines below an edit keep their old origins.
        textLayoutManager.enumerateTextLayoutFragments(
            from: textLayoutManager.documentRange.location, options: [.ensuresLayout]
        ) { fragment in
            height += fragment.layoutFragmentFrame.height
            return height < limit
        }
        return height + textContainerInset.height * 2
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard textStorage?.length == 0 else { return }
        NSGraphicsContext.current?.cgContext.setShouldSmoothFonts(false)
        NSAttributedString(
            string: String(localized: "Start writing…"),
            attributes: [
                .font: NoteMarkdownTypography.body,
                .foregroundColor: NSColor(Theme.Colors.textTertiary)
            ]
        ).draw(at: textContainerOrigin)
    }

    // MARK: - Keys

    override func insertNewline(_ sender: Any?) {
        guard !perform(.newline) else { return }
        super.insertNewline(sender)
    }

    override func deleteBackward(_ sender: Any?) {
        guard !perform(.deleteBackward) else { return }
        super.deleteBackward(sender)
    }

    /// The `[] ` input rule; the plan writes the space itself, so the typed one is dropped.
    override func insertText(_ string: Any, replacementRange: NSRange) {
        let caret = selectedRange()
        if string as? String == " ", caret.length == 0,
            replacementRange.location == NSNotFound || replacementRange == caret,
            perform(.typedSpace)
        {
            return
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    override func doCommand(by selector: Selector) {
        super.doCommand(by: selector)
        let name = NSStringFromSelector(selector)
        guard rendersMarkdown, let editing, name.hasPrefix("move"), !name.contains("AndModifySelection"),
            !hasMarkedText(), case let caret = selectedRange(), caret.length == 0
        else { return }
        let backward = selector == #selector(moveLeft(_:)) || selector == #selector(moveBackward(_:))
        let target = NoteMarkdownEditing.caret(
            afterMoving: caret.location, backward: backward, markdown: editing.markdown)
        if target != caret.location { setSelectedRange(NSRange(location: target, length: 0)) }
    }

    override func insertTab(_ sender: Any?) {
        guard !perform(.indent) else { return }
        super.insertTab(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        guard !perform(.outdent) else { return }
        super.insertBacktab(sender)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = ASCIIKeyboardLayout.chordKey(for: event)
        if key == "d", modifiers == .command {
            if !event.isARepeat { selectWordAtCaret() }
            return true
        }
        if key == "z", modifiers == .command || modifiers == [.command, .shift] {
            guard !event.isARepeat else { return true }
            breakUndoCoalescing()
            if modifiers == .command {
                editorUndoManager?.undo()
            } else {
                editorUndoManager?.redo()
            }
            return true
        }
        guard rendersMarkdown, let action = Self.chord(for: event, key: key) else {
            return super.performKeyEquivalent(with: event)
        }
        let repeatsWhileHeld = if case .moveListItem = action { true } else { false }
        if repeatsWhileHeld || !event.isARepeat { perform(action) }
        return true
    }

    override func paste(_ sender: Any?) {
        guard !pasteLink(from: .general) else { return }
        super.paste(sender)
    }

    /// A lone URL over selected text makes a link, and a list item fills an empty one in place.
    func pasteLink(from pasteboard: NSPasteboard) -> Bool {
        guard let string = pasteboard.string(forType: .string) else { return false }
        return perform(.paste(string))
    }

    /// ⌘D: the word under the caret, or the one the caret ends.
    func selectWordAtCaret() {
        let caret = selectedRange()
        guard caret.length == 0 else { return }
        let text = string as NSString
        let isWordCharacter = { (index: Int) in
            0 <= index && index < text.length
                && text.rangeOfCharacter(
                    from: Self.wordCharacters, range: NSRange(location: index, length: 1)
                ).location != NSNotFound
        }
        let anchor =
            isWordCharacter(caret.location)
            ? caret.location : isWordCharacter(caret.location - 1) ? caret.location - 1 : nil
        guard let anchor else { return }
        setSelectedRange(
            selectionRange(forProposedRange: NSRange(location: anchor, length: 0), granularity: .selectByWord))
    }

    private static let wordCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))

    @discardableResult
    private func perform(_ action: NoteEditAction) -> Bool {
        guard let editing, editing.rendersMarkdown, !hasMarkedText() else { return false }
        let plan = NoteMarkdownEditing.plan(
            action, source: string, selection: selectedRange(), markdown: editing.markdown)
        guard let plan else { return false }
        performEdit(plan)
        return true
    }

    /// The digit key codes, stated here so a local chord needs no Carbon.
    private enum DigitKey {
        static let zero: UInt16 = 0x1D
        static let one: UInt16 = 0x12
        static let two: UInt16 = 0x13
        static let three: UInt16 = 0x14
        static let seven: UInt16 = 0x1A
        static let eight: UInt16 = 0x1C
        static let nine: UInt16 = 0x19
    }

    private enum ArrowKey {
        static let down: UInt16 = 0x7D
        static let up: UInt16 = 0x7E
    }

    /// Digits match by key code, since shifted and optioned digits vary by keyboard layout.
    private static func chord(for event: NSEvent, key: String?) -> NoteEditAction? {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        switch modifiers {
        case [.command, .control]:
            switch event.keyCode {
            case ArrowKey.up: return .moveListItem(.up)
            case ArrowKey.down: return .moveListItem(.down)
            default: return nil
            }
        case [.command]:
            switch key {
            case "b": return .toggleInline(.bold)
            case "i": return .toggleInline(.italic)
            case "e": return .toggleInline(.code)
            case "k": return .toggleLink
            default: return nil
            }
        case [.command, .shift]:
            if key == "x" { return .toggleInline(.strikethrough) }
            if key == "b" { return .toggleQuote }
            switch event.keyCode {
            case DigitKey.seven: return .toggleList(.ordered)
            case DigitKey.eight: return .toggleList(.bullet)
            case DigitKey.nine: return .toggleList(.task)
            default: return nil
            }
        case [.command, .option]:
            if key == "c" { return .toggleCodeBlock }
            switch event.keyCode {
            case DigitKey.one: return .setHeading(level: 1)
            case DigitKey.two: return .setHeading(level: 2)
            case DigitKey.three: return .setHeading(level: 3)
            case DigitKey.zero: return .setHeading(level: 0)
            default: return nil
            }
        default:
            return nil
        }
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        guard rendersMarkdown else { return super.mouseDown(with: event) }
        guard !toggleTask(atContainerPoint: containerPoint(for: event)) else { return }
        isDragSelecting = true
        super.mouseDown(with: event)
        isDragSelecting = false
        editing?.dragSelectionEnded()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        guard rendersMarkdown, checkboxLine(atContainerPoint: containerPoint(for: event)) != nil else {
            return
        }
        NSCursor.arrow.set()
    }

    /// Toggles the task whose drawn box is under the point, leaving the caret where it was.
    func toggleTask(atContainerPoint point: CGPoint) -> Bool {
        guard let lineIndex = checkboxLine(atContainerPoint: point) else { return false }
        return perform(.toggleTask(lineIndex: lineIndex))
    }

    /// The source offset of the link edge a click landed on, when it is within a glyph's outer 30%.
    func linkEdge(ofLinkAt characterIndex: Int, clickedAt point: CGPoint) -> Int? {
        guard let storage = textStorage, characterIndex < storage.length else { return nil }
        var link = NSRange()
        let whole = NSRange(location: 0, length: storage.length)
        guard storage.attribute(.link, at: characterIndex, longestEffectiveRange: &link, in: whole) != nil,
            link.length > 0
        else { return nil }
        let edgeFraction: CGFloat = 0.3
        if let first = glyphFrame(at: link.location), first.minY <= point.y, point.y <= first.maxY,
            point.x <= first.minX + first.width * edgeFraction
        {
            return link.location
        }
        if let last = glyphFrame(at: NSMaxRange(link) - 1), last.minY <= point.y, point.y <= last.maxY,
            point.x >= last.maxX - last.width * edgeFraction
        {
            return NSMaxRange(link)
        }
        return nil
    }

    func containerPoint(for event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
    }

    private func checkboxLine(atContainerPoint point: CGPoint) -> Int? {
        guard let editing, let content = textContentStorage,
            let fragment = textLayoutManager?.textLayoutFragment(for: point) as? NoteBlockLayoutFragment,
            case .task(let level, _) = fragment.decoration.shape
        else { return nil }
        let firstLine = fragment.firstLine
        let box = NoteCheckboxGeometry.rect(
            level: level, firstLineHeight: firstLine.height,
            bodyPointSize: fragment.decoration.bodyPointSize
        ).offsetBy(dx: 0, dy: fragment.layoutFragmentFrame.minY + firstLine.minY)
        guard box.insetBy(dx: -Self.checkboxSlop, dy: -Self.checkboxSlop).contains(point) else { return nil }
        let start = content.offset(from: content.documentRange.location, to: fragment.rangeInElement.location)
        return editing.markdown.lineIndex(at: start)
    }

    private func glyphFrame(at characterIndex: Int) -> CGRect? {
        guard let layout = textLayoutManager, let content = textContentStorage,
            let start = content.location(content.documentRange.location, offsetBy: characterIndex),
            let end = content.location(start, offsetBy: 1),
            let range = NSTextRange(location: start, end: end)
        else { return nil }
        var frame: CGRect?
        layout.enumerateTextSegments(in: range, type: .standard, options: []) { _, segment, _, _ in
            frame = segment
            return false
        }
        return frame
    }

    // MARK: - Focus and appearance

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        isFirstResponder = true
        editing?.focusChanged()
        return true
    }

    override func resignFirstResponder() -> Bool {
        guard super.resignFirstResponder() else { return false }
        isFirstResponder = false
        editing?.focusChanged()
        return true
    }

    /// The panel keeps its first responder while another app is active, so key state is focus too.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        keyObservers = []
        guard let window else { return }
        let center = NotificationCenter.default
        keyObservers = [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification].map { name in
            let token = center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.editing?.focusChanged() }
            }
            return NotificationToken(token, center: center)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        editing?.appearanceChanged()
    }
}
