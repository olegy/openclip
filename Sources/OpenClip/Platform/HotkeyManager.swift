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
    public static let captureText = Self("captureText")
    static let cancelCaptureText = Self("cancelCaptureText", initial: .init(.escape))

    static func actionHotkey(_ actionID: String) -> Self {
        Self("actionHotkey.\(actionID)")
    }
}

@MainActor
public final class HotkeyManager {
    public static let shared = HotkeyManager()
    private weak var popupController: PopupWindowController?
    private weak var captureTextController: CaptureTextController?
    internal var retriever: SelectionRetrievalCoordinator?
    internal var frontmostPIDProvider: @MainActor @Sendable () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier }
    private var cancellables = Set<AnyCancellable>()
    private var registeredHotkeyIDs: Set<String> = []
    private var popupTriggerTask: Task<Void, Never>?
    private var popupTriggerRequestID: UUID?
    /// Reports the focused text control's role when its caret is collapsed (nothing
    /// selected). Injectable for tests.
    internal var collapsedCaretRole: @MainActor () async -> String? = { await CollapsedCaretProbe.collapsedCaretRole() }
    
    /// Gating for the hotkeys: never in an excluded app (`AppFilter`) or one that cannot be
    /// identified.
    internal static func triggerAllowed(frontmost: NSRunningApplication?) -> Bool {
        guard let frontmost else { return false }
        if let bundleID = frontmost.bundleIdentifier, AppFilter.isExcluded(bundleID: bundleID) {
            return false
        }
        // A transient helper with no bundle ID, name, or path cannot be identified — never trigger.
        return AppIdentity(frontmost).ruleIdentifier != nil
    }

    func setup(
        popupController: PopupWindowController,
        captureTextController: CaptureTextController? = nil
    ) {
        self.popupController = popupController
        self.captureTextController = captureTextController
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
        KeyboardShortcuts.onKeyDown(for: .captureText) { [weak self] in
            MainActor.assumeIsolated { self?.captureTextController?.toggleCapture() }
        }
        KeyboardShortcuts.onKeyDown(for: .cancelCaptureText) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.captureTextController?.isCapturing == true else { return }
                self.captureTextController?.cancel()
            }
        }
        KeyboardShortcuts.disable(.cancelCaptureText)

        ActionCoordinator.shared.$actions
            .sink { [weak self] actions in
                self?.registerActionHotkeys(actions)
            }
            .store(in: &cancellables)
        registerActionHotkeys(ActionCoordinator.shared.actions)
    }

    func enableCaptureCancellation() { KeyboardShortcuts.enable(.cancelCaptureText) }
    func disableCaptureCancellation() { KeyboardShortcuts.disable(.cancelCaptureText) }

    public func handleTogglePopup(frontmostApp: NSRunningApplication? = NSWorkspace.shared.frontmostApplication) {
        // A second press cancels a selection read that has not presented yet.
        if popupTriggerRequestID != nil {
            popupTriggerTask?.cancel()
            popupTriggerTask = nil
            popupTriggerRequestID = nil
            return
        }
        guard KeyboardShortcuts.isEnabled else { return }
        // Popup already visible: the hotkey dismisses it (toggle off).
        if let popupController = self.popupController, popupController.isVisible {
            popupController.hide()
            return
        }

        let requestID = UUID()
        let requestedPID = frontmostApp?.processIdentifier
        popupTriggerRequestID = requestID
        popupTriggerTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.popupTriggerRequestID == requestID {
                    self.popupTriggerRequestID = nil
                    self.popupTriggerTask = nil
                }
            }

            let trigger = await self.resolvePaletteTrigger(
                frontmostApp: frontmostApp,
                requestID: requestID,
                requestedPID: requestedPID
            )
            guard !Task.isCancelled,
                  KeyboardShortcuts.isEnabled,
                  self.popupTriggerRequestID == requestID,
                  let trigger else { return }
            if let requestedPID, let currentPID = NSWorkspace.shared.frontmostApplication?.processIdentifier, currentPID != requestedPID {
                return
            }
            if let frontmostApp, !Self.triggerAllowed(frontmost: frontmostApp) { return }
            self.showSearch(for: trigger)
        }
    }

    private func showSearch(for trigger: (context: SelectionContext, canPaste: Bool?)) {
        // When both the selection and clipboard are empty, check whether there are any
        // standalone actions (e.g. extensions declaring `input: "optional"`) available to run.
        // If not, avoid showing an empty search palette ("No matching actions" dead end); instead,
        // surface a lightweight floating toast anchored at the mouse cursor.
        if trigger.context.text.isEmpty {
            let actionContext = ActionContext(selection: trigger.context, modifiers: [])
            let catalog = ActionCoordinator.shared.searchCatalog(for: actionContext)
            if catalog.isEmpty {
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

        self.popupController?.show(for: trigger.context, pasteAvailable: trigger.canPaste)
    }

    /// The palette's input — the on-demand read (`collectTrigger`), except that a collapsed caret
    /// sends no ⌘C (`CollapsedCaretProbe`) and copied files are not clipboard text.
    internal func resolvePaletteTrigger(
        frontmostApp: NSRunningApplication? = NSWorkspace.shared.frontmostApplication,
        requestID: UUID? = nil,
        requestedPID: pid_t? = nil
    ) async -> (context: SelectionContext, canPaste: Bool?)? {
        let trigger: (context: SelectionContext, canPaste: Bool?)?
        if let frontmostApp {
            trigger = await collectTrigger(
                frontmostApp: frontmostApp,
                allowsEmptyText: true,
                requestID: requestID,
                requestedPID: requestedPID,
                skipsCopyOnCollapsedCaret: true
            )
        } else {
            trigger = resolveSynchronousTrigger(frontmostApp: nil)
        }
        guard let trigger else { return nil }
        let context = trigger.context
        guard context.isClipboardFallback, Self.clipboardHoldsFiles(NSPasteboard.general) else { return trigger }
        let empty = SelectionContext(
            text: "",
            sourceApp: context.sourceApp,
            cursorPosition: context.cursorPosition,
            selectionBounds: nil,
            timestamp: context.timestamp,
            appPolicy: context.appPolicy,
            isClipboardFallback: false,
            isEditable: false
        )
        return (empty, trigger.canPaste)
    }

    /// Files copied in Finder also put their names on the clipboard as a string; those are
    /// not text to act on.
    static func clipboardHoldsFiles(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.types?.contains(.fileURL) == true
    }

    /// Synchronous retrieve path for the palette hotkey: checks gating, falls back to the
    /// clipboard (paste fallback), or to an empty context so the palette opens with zero delay.
    ///
    /// When `frontmostApp` is `nil` (common during clipboard-manager handoffs) the method skips
    /// the per-app gating, falling straight through to clipboard / empty-context.
    internal func resolveSynchronousTrigger(
        frontmostApp: NSRunningApplication? = NSWorkspace.shared.frontmostApplication
    ) -> (context: SelectionContext, canPaste: Bool?)? {
        // When an identifiable frontmost app exists — including a bundle-less one identified by
        // process name or executable path — apply per-app gating. When it is nil (e.g. during a
        // clipboard-manager → destination app transition) skip the per-app checks and fall
        // through to the clipboard / empty-context path.
        let appIdentity: AppIdentity
        let policy: AppPolicyContext

        if let identity = frontmostApp.map(AppIdentity.init), identity.ruleIdentifier != nil {
            if let bundleID = identity.bundleIdentifier, AppFilter.isExcluded(bundleID: bundleID) { return nil }
            appIdentity = identity
            policy = RuleEngine.shared.resolvePolicies(for: identity)
        } else {
            // No identifiable app — per-app exclusion cannot apply.
            appIdentity = AppIdentity(bundleIdentifier: nil, localizedName: nil)
            policy = .default
        }

        // 1. Paste fallback: read clipboard text synchronously
        let pasteboard = NSPasteboard.general
        var retrievedText = ""
        var isClipboardFallback = false
        if let clipboard = pasteboard.string(forType: .string),
           !clipboard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            retrievedText = clipboard
            isClipboardFallback = true
        }

        if TextSanitizer.isSubstantial(retrievedText),
           retrievedText.utf8.count <= Constants.maxTextLength {
            let context = SelectionContext(
                text: retrievedText,
                sourceApp: appIdentity,
                cursorPosition: NSEvent.mouseLocation,
                selectionBounds: nil,
                timestamp: Date(),
                appPolicy: policy,
                isClipboardFallback: isClipboardFallback,
                html: pasteboard.string(forType: .html),
                rtf: pasteboard.string(forType: .rtf),
                isEditable: false
            )
            return (context, nil)
        }

        // 2. Fallback to empty context so search palette still opens for standalone actions
        let emptyContext = SelectionContext(
            text: "",
            sourceApp: appIdentity,
            cursorPosition: NSEvent.mouseLocation,
            selectionBounds: nil,
            timestamp: Date(),
            appPolicy: policy,
            isClipboardFallback: false,
            isEditable: false
        )
        return (emptyContext, nil)
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

    internal func handleActionHotkey(_ actionID: String, settingsStore: SettingsStore = DefaultSettingsStore.shared) {
        guard let popupController else { return }
        guard let action = ActionCoordinator.shared.actions.first(where: { $0.id == actionID }),
              ActionIdentity.isBindable(action),
              !(action is GatedExtensionAction) else { return }

        // Refuse to run actions or packages that have been disabled in preferences
        let disabledIDs = settingsStore.get(.disabledActionIDs)
        let disabledPackages = settingsStore.get(.disabledPackages)
        guard !disabledIDs.contains(action.id) else { return }
        if let pkgID = ActionIdentity.extensionPackageID(of: action), disabledPackages.contains(pkgID) {
            return
        }
        if action.chrome.launchesAI, !AIServiceManager.shared.isAIEnabled {
            return
        }
        if ActionIdentity.isAIPreset(action) {
            guard AIServiceManager.shared.isAIEnabled,
                  AIServiceManager.shared.preset(forActionID: action.id)?.isEnabled == true else {
                return
            }
        }
        if let parentExtensionGroup = ActionCoordinator.shared.actions.first(where: {
            $0.chrome.popupBehavior == .showSubActions && action.id != $0.id && action.id.hasPrefix($0.id + ".")
        }), disabledIDs.contains(parentExtensionGroup.id) {
            return
        }

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

    /// Shared retrieve path for the palette and per-action hotkeys: gate, probe paste, read selection
    /// (clipboard fallback), reject oversized input and empty input unless explicitly allowed.
    internal private(set) var lastTriggerResponse: SelectionTriggerResponse?
    internal var onTriggerOutcome: ((SelectionTriggerResponse) -> Void)?

    internal func collectTrigger(
        frontmostApp: NSRunningApplication? = NSWorkspace.shared.frontmostApplication,
        allowsEmptyText: Bool = false, requestID: UUID? = nil, requestedPID: pid_t? = nil,
        skipsCopyOnCollapsedCaret: Bool = false
    ) async -> (context: SelectionContext, canPaste: Bool?)? {
        let response = await collectTriggerResponse(frontmostApp: frontmostApp,
            allowsEmptyText: allowsEmptyText, requestID: requestID, requestedPID: requestedPID,
            skipsCopyOnCollapsedCaret: skipsCopyOnCollapsedCaret)
        guard let context = response.context else { return nil }
        return (context, response.canPaste)
    }

    internal func collectTriggerResponse(
        frontmostApp: NSRunningApplication? = NSWorkspace.shared.frontmostApplication,
        allowsEmptyText: Bool = false,
        requestID: UUID? = nil,
        requestedPID: pid_t? = nil,
        skipsCopyOnCollapsedCaret: Bool = false
    ) async -> SelectionTriggerResponse {
        func finish(_ response: SelectionTriggerResponse) -> SelectionTriggerResponse {
            lastTriggerResponse = response
            onTriggerOutcome?(response)
            if let traceID = response.traceID, [.clipboardFallback, .targetChanged, .cancelled, .tooLarge].contains(response.status) {
                Log.selection.debug("[Trace#\(traceID, privacy: .public)] hotkey delivery outcome: \(response.status.rawValue, privacy: .public); readOutcome=\(response.retrievalStatus?.rawValue ?? "unknown", privacy: .public)")
            }
            return response
        }
        guard !Task.isCancelled,
              Self.triggerAllowed(frontmost: frontmostApp),
              let frontApp = frontmostApp else { return finish(.init(status: Task.isCancelled ? .cancelled : .policyBlocked)) }

        let requiredPID = requestedPID ?? frontApp.processIdentifier
        let isTriggerAuthorized: PasteboardCopyEngine.CopyAuthorization = { [weak self] in
            guard !Task.isCancelled,
                  Self.triggerAllowed(frontmost: frontApp) else { return false }
            if let requestID, self?.popupTriggerRequestID != requestID { return false }
            return self?.frontmostPIDProvider() == requiredPID
        }

        var retrievalTraceID: UInt64?
        func denied() -> SelectionTriggerResponse {
            let status: SelectionReadStatus = Task.isCancelled || (requestID != nil && popupTriggerRequestID != requestID)
                ? .cancelled : (!Self.triggerAllowed(frontmost: frontApp) ? .policyBlocked : .targetChanged)
            return finish(.init(status: status, traceID: retrievalTraceID))
        }

        let appIdentity = AppIdentity(frontApp)

        // A collapsed caret in a text control means nothing is selected; no ⌘C, so editors
        // that copy the current line on an empty ⌘C (Obsidian, VS Code) fall through to the clipboard.
        var allowCopyFallback = true
        if skipsCopyOnCollapsedCaret, let role = await collapsedCaretRole() {
            Log.selection.debug("hotkey: collapsed caret in \(role, privacy: .public) of \(appIdentity.bundleIdentifier ?? "unknown", privacy: .public); skipping copy fallback")
            allowCopyFallback = false
        }

        guard isTriggerAuthorized() else { return denied() }
        let policy = RuleEngine.shared.resolvePolicies(for: appIdentity)
        let probeTask = popupController?.preparePasteProbe(for: frontApp, policy: policy)

        var retrievedText = ""
        var selectionBounds: CGRect? = nil
        var selectionHTML: String?
        var selectionRTF: String?
        var selectionFlavors: [RichPasteboardFlavor] = []

        let copyCapture: SelectionRetrievalCoordinator.DetailedCopyCapture = { request in
            await PasteboardCopyEngine(authorizationFailure: {
                if Task.isCancelled { return .cancelled }
                return isTriggerAuthorized() ? nil : .targetChanged
            }, isCopyAuthorized: isTriggerAuthorized).captureResponse(trigger: request.trigger)
        }

        let coordinator = retriever ?? SelectionRetrievalCoordinator(detailedCopyCapture: copyCapture)
        let read = await coordinator.retrieveResponse(
            for: appIdentity,
            policy: policy,
            cursor: CursorClassifier.current.asCore,
            allowCopyFallback: allowCopyFallback,
            requireCopyEvidence: false,
            trigger: .keyboardShortcut
        )
        retrievalTraceID = read.traceID
        if let result = read.result {
            retrievedText = result.text
            selectionBounds = result.bounds
            selectionHTML = result.html
            selectionRTF = result.rtf
            selectionFlavors = result.flavors
        }

        guard isTriggerAuthorized() else { return denied() }

        if read.status == .cancelled || read.status == .targetChanged || read.status == .policyBlocked || read.status == .busy {
            return finish(.init(status: read.status))
        }
        var isClipboardFallback = false
        if retrievedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let pasteboard = NSPasteboard.general
                if let clipboard = pasteboard.string(forType: .string),
               !clipboard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                retrievedText = clipboard
                isClipboardFallback = true
                    selectionHTML = pasteboard.string(forType: .html)
                selectionRTF = pasteboard.string(forType: .rtf)
                selectionFlavors = []
            }
        }

        if Task.isCancelled { return denied() }
        guard retrievedText.utf8.count <= Constants.maxTextLength else {
            return finish(.init(status: .tooLarge, retrievalStatus: read.status, traceID: read.traceID))
        }
        if !TextSanitizer.isSubstantial(retrievedText) {
            guard allowsEmptyText else { return finish(.init(status: read.status, retrievalStatus: read.status, traceID: read.traceID)) }
            retrievedText = ""
            isClipboardFallback = false
            selectionHTML = nil
            selectionRTF = nil
            selectionFlavors = []
        }

        var context = SelectionContext(
            text: retrievedText,
            sourceApp: appIdentity,
            cursorPosition: NSEvent.mouseLocation,
            selectionBounds: selectionBounds,
            timestamp: Date(),
            appPolicy: policy,
            isClipboardFallback: isClipboardFallback,
            html: selectionHTML,
            rtf: selectionRTF,
            flavors: selectionFlavors,
            isEditable: isClipboardFallback ? false : read.isEditable,
            traceID: read.traceID
        )
        let canPaste = await probeTask?.value
        context = context.with(pasteTargetAvailable: canPaste)
        guard isTriggerAuthorized() else { return denied() }
        return finish(.init(context: context, canPaste: canPaste,
            status: isClipboardFallback ? .clipboardFallback : (retrievedText.isEmpty ? .noSelection : .selection),
            retrievalStatus: read.status, traceID: read.traceID))
    }
}
