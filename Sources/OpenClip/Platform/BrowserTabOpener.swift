// BrowserTabOpener.swift
// OpenClip
//
// Opens a URL in the browser the selection came from, preferring the browser's own scripting so the
// tab lands in the window the user is actually in. macOS routes externally-opened URLs to the
// regular (non-incognito) profile, so handing the URL to LaunchServices spawns a new window when the
// only window is private; `tell front window to make new tab` targets the front window directly.
//
// Every step is best-effort: if the browser can't be scripted (Automation denied, no window, or an
// unsupported dictionary) this falls back to the previous LaunchServices behaviour, so nothing ever
// gets worse than before. The AppleScript budget is its own short constant, deliberately independent
// of the shared script timeout.
import Foundation
import AppKit
import ApplicationServices
import Core

@MainActor
public struct BrowserTabOpener {
    public init() {}
    /// Runs an AppleScript source and returns its trimmed result. Injected so tests can drive the
    /// success and failure paths without touching `osascript`.
    var runAppleScript: @MainActor @Sendable (String, TimeInterval) async throws -> String = { source, timeout in
        try await AppleScriptRunner.shared.run(source, timeout: timeout)
    }
    /// Hands the URL to the app through LaunchServices. Returns whether LaunchServices accepted it.
    var openWithApplication: @MainActor @Sendable (URL, String) async -> Bool = { url, bundleID in
        guard let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return false
        }
        let configuration = NSWorkspace.OpenConfiguration()
        return await withCheckedContinuation { continuation in
            NSWorkspace.shared.open(
                [url],
                withApplicationAt: applicationURL,
                configuration: configuration
            ) { application, error in
                continuation.resume(returning: application != nil && error == nil)
            }
        }
    }
    /// Whether the app's focused window is a Firefox private window. Firefox only marks this in the
    /// title ("… Private Browsing"), and the suffix is localized, so this is best-effort: other
    /// languages just keep the normal-window path.
    var isPrivateWindow: @MainActor @Sendable (String) -> Bool = { bundleID in
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier else {
            return false
        }
        let app = AXUIElementCreateApplication(pid)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return false }
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success,
              let title = title as? String else { return false }
        return title.hasSuffix("Private Browsing")
    }
    /// Runs `firefox --private-window URL` against the running instance. No shell involved.
    var launchPrivateWindow: @MainActor @Sendable (URL, String) -> Bool = { url, bundleID in
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              let executable = Bundle(url: appURL)?.executableURL else { return false }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--private-window", url.absoluteString]
        do { try process.run() } catch { return false }
        return true
    }
    /// Last resort: the system default handler.
    var openDefault: @MainActor @Sendable (URL) -> Void = { url in
        NSWorkspace.shared.open(url)
    }

    /// Budget for the scripting attempt. Short deliberately: opening a tab is a quick ask, and a
    /// busy browser must never hold the action up.
    static let appleScriptTimeout: TimeInterval = 5

    /// Mozilla's own channels; forks name their binary and private title differently.
    static let firefoxPrivateCapable: Set<String> = [
        "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly"
    ]

    public func open(_ url: URL, inApp bundleID: String) async {
        // Firefox has no tab scripting and sends external URLs to a normal window (#205).
        if Self.firefoxPrivateCapable.contains(bundleID), isPrivateWindow(bundleID), launchPrivateWindow(url, bundleID) {
            return
        }
        if BrowserDetector.isBrowser(bundleIdentifier: bundleID) {
            do {
                _ = try await runAppleScript(Self.appleScript(url: url, bundleID: bundleID), Self.appleScriptTimeout)
                return
            } catch {
                Log.resultHandler.error("browser tab via AppleScript failed for \(bundleID, privacy: .public): \(error.localizedDescription, privacy: .private); falling back to LaunchServices")
            }
        }
        if !(await openWithApplication(url, bundleID)) {
            openDefault(url)
        }
    }

    /// The script that adds a tab to the browser's front window. Safari's dictionary spells the
    /// focus step differently from the Chromium family.
    static func appleScript(url: URL, bundleID: String) -> String {
        let escaped = escape(url.absoluteString)
        if bundleID.hasPrefix("com.apple.Safari") || bundleID == "com.kagi.kagimacOS" {
            return """
            tell application id "\(bundleID)"
                activate
                tell front window to set current tab to (make new tab with properties {URL:"\(escaped)"})
            end tell
            """
        }
        return """
        tell application id "\(bundleID)"
            activate
            tell front window to make new tab with properties {URL:"\(escaped)"}
            set active tab index of front window to (count of tabs of front window)
        end tell
        """
    }

    /// AppleScript string escaping — backslashes then quotes, the same order `AppleScriptAction`
    /// uses for the selection it injects.
    static func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
