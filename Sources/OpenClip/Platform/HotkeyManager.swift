// HotkeyManager.swift
// OpenClip
//
// Manages global keyboard shortcuts using macOS event monitors and KeyboardShortcuts registrations.
import Foundation
import AppKit
import Combine
import KeyboardShortcuts
import Core

extension KeyboardShortcuts.Name {
    public static let togglePopup = Self("togglePopup", initial: .init(.c, modifiers: [.command, .option]))

    static func actionHotkey(_ actionID: String) -> Self {
        Self("actionHotkey.\(actionID)")
    }
}

@MainActor
public final class HotkeyManager {
    public static let shared = HotkeyManager()
    private weak var popupController: PopupWindowController?
    private var paletteReadTask: Task<Void, Never>?
    /// Reads the frontmost app's selection for the palette hotkey. Injectable for tests.
    internal var selectionReader: @MainActor (AppIdentity, AppPolicyContext) async -> TextResult? = HotkeyManager.readSelection
    public weak var selectionMonitor: (any SelectionMonitoring)?
    private var cancellables = Set<AnyCancellable>()
    private var registeredHotkeyIDs: Set<String> = []
    
    /// Gating for the ⌥⌘C trigger. Deliberately does **not** consult `SettingKey.isAppEnabled`:
    /// that setting is "Appear Automatically" (both in Preferences and the menu bar), so it owns
    /// the selection monitor's automatic popup, not the explicit shortcut — turning automatic
    /// appearance off is the global form of the per-app `hotkeyOnly` rule, which has always kept
    /// the hotkey alive. The real kill switches still apply here: Pause OpenClip
    /// (`pauseUntilTimestamp`), the app-exclusion list, and a per-app `disabled` rule.
    internal static func triggerAllowed(
        frontmost: NSRunningApplication?,
        settingsStore: SettingsStore = DefaultSettingsStore.shared
    ) -> Bool {
        if settingsStore.get(.pauseUntilTimestamp) > Date().timeIntervalSince1970 {
            return false
        }
        guard let frontmost,
              let bundleID = frontmost.bundleIdentifier else { return false }
        if AppFilter.isExcluded(bundleID: bundleID) {
            return false
        }
        let policy = RuleEngine.shared.resolvePolicies(for: bundleID)
        return !policy.disabled
    }

    public func setup(
        popupController: PopupWindowController,
        selectionMonitor: (any SelectionMonitoring)? = nil
    ) {
        self.popupController = popupController
        self.selectionMonitor = selectionMonitor
        // ⌘1…⌘9 pick a palette row. Parked until a palette opens — see PaletteRowShortcuts for why
        // they must be global hot keys rather than key equivalents on the panel.
        PaletteRowShortcuts.install { [weak popupController] row in
            popupController?.runPaletteRow(row) ?? false
        }

        KeyboardShortcuts.onKeyDown(for: .togglePopup) { [weak self] in
            MainActor.assumeIsolated {
                self?.handleTogglePopup()
            }
        }

        ActionCoordinator.shared.$actions
            .sink { [weak self] actions in
                self?.registerActionHotkeys(actions)
            }
            .store(in: &cancellables)
        registerActionHotkeys(ActionCoordinator.shared.actions)
    }

    public func handleTogglePopup(frontmostApp: NSRunningApplication? = NSWorkspace.shared.frontmostApplication) {
        // Popup already visible: if in search mode, the hotkey dismisses the popup (toggle off);
        // if in actions bar mode, the hotkey transitions directly into search mode.
        if let popupController = self.popupController, popupController.isVisible {
            if popupController.modeStore.mode == .search {
                popupController.toggleMode()
            } else {
                popupController.enterSearch()
            }
            return
        }

        // Read the selection on demand (fork: the palette no longer uses the selection monitor's
        // cache). A second press while the read is still in flight is ignored.
        guard paletteReadTask == nil else { return }
        paletteReadTask = Task { @MainActor in
            defer { self.paletteReadTask = nil }
            guard let trigger = await self.resolvePaletteTrigger(frontmostApp: frontmostApp) else { return }
            self.presentPalette(for: trigger)
        }
    }

    private func presentPalette(for trigger: (context: SelectionContext, canPaste: Bool?, clipboard: SelectionContext?)) {
        // When both the selection and clipboard are empty, check whether there are any
        // standalone actions (e.g. extensions declaring `requiresSelection: false`) available to run.
        // If not, avoid showing an empty search palette ("No matching actions" dead end); instead,
        // surface a lightweight floating toast anchored at the mouse cursor.
        if trigger.context.text.isEmpty {
            let actionContext = ActionContext(selection: trigger.context, modifiers: [])
            let catalog = ActionCoordinator.shared.searchCatalog(for: actionContext)
            let hasStandaloneActions = catalog.contains { $0.id != "builtin.paste" }
            if !hasStandaloneActions {
                popupController?.showToast(
                    StatusFeedback(
                        message: String(localized: "No text selected or on clipboard"),
                        style: .info,
                        symbolName: "doc.on.clipboard"
                    ),
                    at: NSEvent.mouseLocation
                )
                return
            }
        }

        self.popupController?.showPalette(for: trigger.context, alternate: trigger.clipboard, pasteAvailable: trigger.canPaste)
    }

    /// Retrieve path for ⌥⌘C: checks gating, reads the selection on demand through
    /// `selectionReader`, falls back to clipboard (paste fallback), or falls back to an empty
    /// context so the search palette still opens for standalone actions.
    ///
    /// The read does not wait for the hotkey's modifiers to be released: synthetic ⌘C carries
    /// explicit flags, and measured reads (10–65 ms) stayed correct with ⌃⌥⇧⌘ physically held.
    ///
    /// When `frontmostApp` is `nil` (common during clipboard-manager handoffs) the method skips
    /// the per-app gating and selection read, falling straight through to clipboard /
    /// empty-context. The global pause check still applies.
    ///
    /// Fork: when the selection is read, the clipboard's text comes back too (`clipboard`), so
    /// the palette can switch between the two. The clipboard is read before the selection, so a
    /// synthetic ⌘C in flight can never be mistaken for it.
    internal func resolvePaletteTrigger(
        frontmostApp: NSRunningApplication? = NSWorkspace.shared.frontmostApplication,
        settingsStore: SettingsStore = DefaultSettingsStore.shared
    ) async -> (context: SelectionContext, canPaste: Bool?, clipboard: SelectionContext?)? {
        // Global pause applies regardless of which app is frontmost.
        if settingsStore.get(.pauseUntilTimestamp) > Date().timeIntervalSince1970 {
            return nil
        }

        // When an identifiable frontmost app exists, apply per-app gating.
        // When it is nil (e.g. during a clipboard-manager → destination app transition)
        // skip the per-app checks and fall through to the clipboard / empty-context path.
        let appIdentity: AppIdentity
        let policy: AppPolicyContext
        let readableApp: NSRunningApplication?

        if let frontApp = frontmostApp,
           let bundleID = frontApp.bundleIdentifier {
            if AppFilter.isExcluded(bundleID: bundleID) { return nil }
            let resolved = RuleEngine.shared.resolvePolicies(for: bundleID)
            if resolved.disabled { return nil }
            appIdentity = AppIdentity(frontApp)
            policy = resolved
            readableApp = frontApp
        } else {
            // No identifiable app — use a neutral identity. Per-app exclusion and disabled
            // rules cannot apply without a bundle ID, so we only honour the global pause
            // (checked above).
            appIdentity = AppIdentity(bundleIdentifier: nil, localizedName: nil)
            policy = .default
            readableApp = nil
        }

        let clipboardText = Self.clipboardText()

        // 1. Read the selection now (requires a known app); the paste probe runs alongside.
        if let readableApp {
            let probeTask = popupController?.preparePasteProbe(for: readableApp, policy: policy)
            if let result = await selectionReader(appIdentity, policy) {
                let text = result.text
                if TextSanitizer.isSubstantial(text),
                   text.utf8.count <= Constants.maxTextLength {
                    let context = SelectionContext(
                        text: text,
                        sourceApp: appIdentity,
                        cursorPosition: NSEvent.mouseLocation,
                        selectionBounds: result.bounds,
                        timestamp: Date(),
                        appPolicy: policy,
                        isClipboardFallback: false,
                        html: result.html,
                        rtf: result.rtf,
                        flavors: result.flavors
                    )
                    let clipboard = clipboardText.map {
                        Self.clipboardContext(text: $0, sourceApp: appIdentity, policy: policy)
                    }
                    return (context, await probeTask?.value, clipboard)
                }
            }
            probeTask?.cancel()
        }

        // 2. Paste fallback: the clipboard text read above
        if let clipboardText {
            return (Self.clipboardContext(text: clipboardText, sourceApp: appIdentity, policy: policy), nil, nil)
        }

        // 3. Fallback to empty context so search palette still opens for standalone actions
        let emptyContext = SelectionContext(
            text: "",
            sourceApp: appIdentity,
            cursorPosition: NSEvent.mouseLocation,
            selectionBounds: nil,
            timestamp: Date(),
            appPolicy: policy,
            isClipboardFallback: false
        )
        return (emptyContext, nil, nil)
    }

    /// The clipboard's text, if it is usable as the palette's input. Files copied in Finder also
    /// put their names on the clipboard as a string; those are not text to act on.
    private static func clipboardText() -> String? {
        let pasteboard = NSPasteboard.general
        if pasteboard.types?.contains(.fileURL) == true { return nil }
        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              TextSanitizer.isSubstantial(text),
              text.utf8.count <= Constants.maxTextLength else { return nil }
        return text
    }

    private static func clipboardContext(text: String, sourceApp: AppIdentity, policy: AppPolicyContext) -> SelectionContext {
        SelectionContext(
            text: text,
            sourceApp: sourceApp,
            cursorPosition: NSEvent.mouseLocation,
            selectionBounds: nil,
            timestamp: Date(),
            appPolicy: policy,
            isClipboardFallback: true
        )
    }

    private func registerActionHotkeys(_ actions: [any Action]) {
        for action in actions where ActionIdentity.isBindable(action) {
            let actionID = action.id
            guard registeredHotkeyIDs.insert(actionID).inserted else { continue }
            KeyboardShortcuts.onKeyUp(for: .actionHotkey(actionID)) { [weak self] in
                Task { @MainActor in
                    self?.handleActionHotkey(actionID)
                }
            }
        }
    }

    private func handleActionHotkey(_ actionID: String) {
        guard let popupController else { return }
        guard let action = ActionCoordinator.shared.actions.first(where: { $0.id == actionID }),
              ActionIdentity.isBindable(action),
              !(action is GatedExtensionAction) else { return }

        if popupController.isVisible, let context = popupController.currentActionContext {
            popupController.runBoundAction(action, with: context)
            return
        }

        Task { @MainActor in
            guard let trigger = await self.collectTrigger() else { return }
            let context = ActionContext(selection: trigger.context, modifiers: [])
            popupController.runBoundAction(action, with: context, pasteAvailable: trigger.canPaste)
        }
    }

    /// Retrieve path for per-action hotkeys: gate, probe paste, read selection
    /// (clipboard fallback), reject empty/oversized input.
    internal func collectTrigger(
        frontmostApp: NSRunningApplication? = NSWorkspace.shared.frontmostApplication
    ) async -> (context: SelectionContext, canPaste: Bool?)? {
        guard Self.triggerAllowed(frontmost: frontmostApp),
              let frontApp = frontmostApp else { return nil }

        // Fast path: reuse active monitored selection without blocking on AX tree walk
        if let monitored = await selectionMonitor?.currentSelection(for: frontApp.bundleIdentifier) {
            let text = monitored.context.text
            if TextSanitizer.isSubstantial(text),
               text.utf8.count <= Constants.maxTextLength {
                let context = SelectionContext(
                    text: text,
                    sourceApp: monitored.context.sourceApp,
                    cursorPosition: NSEvent.mouseLocation,
                    mouseDownLocation: monitored.context.mouseDownLocation,
                    selectionBounds: monitored.context.selectionBounds,
                    timestamp: monitored.context.timestamp,
                    appPolicy: monitored.context.appPolicy,
                    isClipboardFallback: monitored.context.isClipboardFallback,
                    html: monitored.context.html,
                    rtf: monitored.context.rtf
                )
                return (context, monitored.canPaste)
            }
        }

        let policy = RuleEngine.shared.resolvePolicies(for: frontApp.bundleIdentifier ?? "")
        let appIdentity = AppIdentity(frontApp)
        let probeTask = popupController?.preparePasteProbe(for: frontApp, policy: policy)

        var retrievedText = ""
        var selectionBounds: CGRect? = nil

        if let result = await SelectionRetrievalCoordinator().retrieve(
            for: appIdentity,
            policy: policy,
            cursor: CursorClassifier.current.asCore,
            allowCopyFallback: !CopyTriggerGate.isForeignOverlayPresent(at: NSEvent.mouseLocation),
            requireCopyEvidence: false
        ) {
            retrievedText = result.text
            selectionBounds = result.bounds
        }

        var isClipboardFallback = false
        if retrievedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let pasteboard = NSPasteboard.general
            if let clipboard = pasteboard.string(forType: .string),
               !clipboard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                retrievedText = clipboard
                isClipboardFallback = true
            }
        }

        guard TextSanitizer.isSubstantial(retrievedText),
              retrievedText.utf8.count <= Constants.maxTextLength else { return nil }

        let context = SelectionContext(
            text: retrievedText,
            sourceApp: appIdentity,
            cursorPosition: NSEvent.mouseLocation,
            selectionBounds: selectionBounds,
            timestamp: Date(),
            appPolicy: policy,
            isClipboardFallback: isClipboardFallback
        )
        let canPaste = await probeTask?.value
        return (context, canPaste)
    }

    /// Default `selectionReader`: one OpenSelection retrieval with the copy fallback allowed
    /// unless a foreign overlay (e.g. a screenshot tool) sits under the cursor.
    private static func readSelection(_ app: AppIdentity, _ policy: AppPolicyContext) async -> TextResult? {
        // Fork: a collapsed caret in a text control means nothing is selected; no ⌘C.
        var caretCollapsed = false
        if ForkBehavior.collapsedCaretSkipsCopy, let role = await CollapsedCaretProbe.collapsedCaretRole() {
            Log.selection.debug("palette: collapsed caret in \(role, privacy: .public) of \(app.bundleIdentifier ?? "unknown", privacy: .public); skipping copy fallback")
            caretCollapsed = true
        }
        return await SelectionRetrievalCoordinator().retrieveDetails(
            for: app,
            policy: policy,
            cursor: CursorClassifier.current.asCore,
            allowCopyFallback: !caretCollapsed && !CopyTriggerGate.isForeignOverlayPresent(at: NSEvent.mouseLocation),
            requireCopyEvidence: false
        ).result
    }
}
