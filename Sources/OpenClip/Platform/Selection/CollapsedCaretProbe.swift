// CollapsedCaretProbe.swift
// OpenClip
//
// Fork: tells the palette hotkey that the focused text control has a caret but no selection, so
// no synthetic ⌘C is sent. Editors built on CodeMirror (Obsidian), Monaco (VS Code) and others
// copy the whole current line when ⌘C arrives with nothing selected, which the palette would
// otherwise take for the selection.
import ApplicationServices
import Foundation

enum CollapsedCaretProbe {
    /// Roles whose `AXSelectedTextRange` describes a text selection the user can see.
    static let textControlRoles: Set<String> = ["AXTextField", "AXTextArea", "AXSearchField", "AXComboBox"]

    /// Per-element AX messaging timeout, so an unresponsive app cannot stall the hotkey.
    static let messagingTimeout: Float = 0.25

    /// The focused element's role, when its caret is collapsed; `nil` when anything is selected,
    /// the element is not a text control, or AX does not answer.
    static func collapsedCaretRole() async -> String? {
        await Task.detached(priority: .userInitiated) { readCollapsedCaretRole() }.value
    }

    /// Only a text control that reports a zero-length range with no selected text counts. A
    /// missing range means "unknown", which keeps the copy fallback.
    static func isCollapsedCaret(role: String?, selectedRange: CFRange?, selectedText: String?) -> Bool {
        guard let role, textControlRoles.contains(role), let selectedRange else { return false }
        return selectedRange.length == 0 && (selectedText ?? "").isEmpty
    }

    private static func readCollapsedCaretRole() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        guard let app = element(read(systemWide, kAXFocusedApplicationAttribute)) else { return nil }
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        guard let focused = element(read(app, kAXFocusedUIElementAttribute)) else { return nil }
        AXUIElementSetMessagingTimeout(focused, messagingTimeout)

        let role = read(focused, kAXRoleAttribute) as? String
        var range = CFRange()
        let rangeValue = read(focused, kAXSelectedTextRangeAttribute)
        let hasRange = rangeValue.map {
            CFGetTypeID($0) == AXValueGetTypeID() && AXValueGetValue($0 as! AXValue, .cfRange, &range)
        } ?? false
        let selectedText = read(focused, kAXSelectedTextAttribute) as? String

        return isCollapsedCaret(role: role, selectedRange: hasRange ? range : nil, selectedText: selectedText) ? role : nil
    }

    private static func read(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }

    private static func element(_ value: AnyObject?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}
