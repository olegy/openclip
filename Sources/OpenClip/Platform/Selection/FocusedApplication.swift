// FocusedApplication.swift
// OpenClip
//
// The app that owns keyboard focus, which is not always the frontmost app. A non-activating
// panel (`NSPanel` with `.nonactivatingPanel` — Tinycast's Note, launcher palettes) becomes key
// without activating its app, so `NSWorkspace.frontmostApplication` still reports the app
// underneath while the selection, the AX focus and a synthetic ⌘C all belong to the panel's
// process. Targeting the frontmost app there made the selection cascade see a foreign focused
// element and report `targetChanged`, which dropped the palette hotkey.
import AppKit
import ApplicationServices

public enum FocusedApplication {
    /// The focus owner when it is a running app other than the frontmost one; otherwise the
    /// frontmost app. A focus owner that is not a running app (no `NSRunningApplication`, or
    /// already terminated) keeps the frontmost app, and so does OpenClip itself: its palette is a
    /// non-activating panel too, and while it is key the source app is still the one underneath.
    @MainActor
    public static func current(
        frontmost: NSRunningApplication? = NSWorkspace.shared.frontmostApplication,
        ownerPID: pid_t? = focusOwnerPID(),
        ownPID: pid_t = ProcessInfo.processInfo.processIdentifier,
        runningApplication: (pid_t) -> NSRunningApplication? = { NSRunningApplication(processIdentifier: $0) }
    ) -> NSRunningApplication? {
        guard let ownerPID, ownerPID > 0, ownerPID != frontmost?.processIdentifier, ownerPID != ownPID,
              let owner = runningApplication(ownerPID), !owner.isTerminated else { return frontmost }
        return owner
    }

    /// The PID of the system-wide AX focused application, or `nil` when AX does not answer
    /// (no Accessibility permission, or nothing focused). No messaging timeout is set: on the
    /// system-wide element it would change the process-global AX timeout (as OpenSelection's
    /// inspector and `CollapsedCaretProbe` also avoid).
    public static func focusOwnerPID() -> pid_t? {
        let systemWide = AXUIElementCreateSystemWide()
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(value as! AXUIElement, &pid) == .success, pid > 0 else { return nil }
        return pid
    }
}
