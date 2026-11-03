import AppKit
import Carbon.HIToolbox

/// Editor and switcher differ only in style mask and chords, so one panel serves both.
final class NotesPanel: NSPanel {
    var onEscape: (() -> Void)?
    /// ⌘⌫ is keyed separately: only its key code survives every keyboard layout.
    var onDeleteChord: (() -> Bool)?
    /// The ⌘-letter chords this window claims, by lowercased character.
    var commandChords: [String: () -> Void] = [:]
    /// The same, for ⌥⌘-letter chords.
    var optionCommandChords: [String: () -> Void] = [:]
    /// False for the heading menu, so the editor keeps its caret, reveal and chords beneath it.
    var acceptsKey = true
    var onMouseDown: (() -> Void)?

    private let acceptsMain: Bool

    init(
        content: NSView, size: CGSize, styleMask: NSWindow.StyleMask, acceptsMain: Bool,
        activatesApp: Bool = false
    ) {
        self.acceptsMain = acceptsMain
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: styleMask.union(activatesApp ? .fullSizeContentView : [.fullSizeContentView, .nonactivatingPanel]),
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        hidesOnDeactivate = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .documentWindow
        isReleasedWhenClosed = false
        isRestorable = false
        contentView = content
    }

    /// Fixed at creation: the window server keeps refusing activation after the flag is removed.
    var activatesApp: Bool { !styleMask.contains(.nonactivatingPanel) }

    func apply(_ mode: NoteWindowMode) {
        switch mode {
        case .floating:
            isFloatingPanel = true
            level = .floating
            collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        case .standard:
            isFloatingPanel = false
            level = .normal
            collectionBehavior = []
        }
    }

    /// A child takes its host's level and paper, or it floats over apps a standard host sits under.
    func attach(to host: NSWindow) {
        level = host.level
        appearance = host.appearance
        guard parent !== host else { return }
        parent?.removeChildWindow(self)
        host.addChildWindow(self, ordered: .above)
    }

    /// The main menu is offered chords first, so this is the fallback for a non-activating panel.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        guard !event.isARepeat else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key = ASCIIKeyboardLayout.chordKey(for: event)
        if modifiers == [.command, .option] {
            guard let key, let chord = optionCommandChords[key] else { return false }
            chord()
            return true
        }
        guard modifiers == .command else { return false }
        if Int(event.keyCode) == kVK_Delete { return onDeleteChord?() == true }
        guard let key, let chord = commandChords[key] else { return false }
        chord()
        return true
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown { onMouseDown?() }
        // The search and rename fields own Escape while they are editing.
        guard event.type == .keyDown, Int(event.keyCode) == kVK_Escape, !event.isARepeat,
            (firstResponder as? NSTextView)?.isFieldEditor != true
        else {
            super.sendEvent(event)
            return
        }
        onEscape?()
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    static var refusesInheritedKey = false

    override var canBecomeKey: Bool { acceptsKey && !Self.refusesInheritedKey }
    override var canBecomeMain: Bool { acceptsMain }
}
