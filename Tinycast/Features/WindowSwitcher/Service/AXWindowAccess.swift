import AppKit
// `@preconcurrency` downgrades AX diagnostics: `kAX…` are mutable C globals, but constant.
@preconcurrency import ApplicationServices

/// Every `AXUIElement` call the switcher makes, so the sweep and the switch agree on a window.
@MainActor
enum AXWindowAccess {
    static func application(for pid: pid_t, timeout: Float) -> AXUIElement {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, timeout)
        return application
    }

    /// Every window the app reports, unfiltered and in its own order.
    static func windows(in application: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value)
                == .success,
            let windows = value as? [AXUIElement]
        else { return [] }
        return windows
    }

    static func isFullScreen(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &value) == .success
        else { return false }
        return (value as? Bool) ?? false
    }

    static func unminimize(_ window: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            == .success
    }

    static func minimize(_ window: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
            == .success
    }

    static func focus(
        _ window: AXUIElement, in application: AXUIElement, of app: NSRunningApplication
    ) {
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        // Belt and braces with `activate()`: an agent-policy app's request can be ignored.
        AXUIElementSetAttributeValue(
            application, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        app.activate()
    }

    /// The fallback for an app that refuses `NSRunningApplication.hide()` or `unhide()`.
    static func setHidden(_ hidden: Bool, application: AXUIElement) {
        AXUIElementSetAttributeValue(
            application, kAXHiddenAttribute as CFString, hidden ? kCFBooleanTrue : kCFBooleanFalse)
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
            let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        // Type checked by CFGetTypeID above; `as?` on a CF type is a compile error.
        return (value as! AXUIElement)
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? Bool
    }
}
