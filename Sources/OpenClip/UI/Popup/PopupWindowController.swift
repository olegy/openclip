// PopupWindowController.swift
// OpenClip
//
// Manages the window lifecycle, event tracking and positioning of the floating popup panel: the
// command palette, replaced by the native result card while an action's result is on screen. The
// panel is key while it shows (a scoped exception to the never-key rule) and restores focus to the
// previous app when it hides; Esc belongs to the SwiftUI palette/card (the controller-level key
// monitor only answers it when the card lost key). A dragged or pinned card (`cardIsModal`)
// survives every automatic dismissal (outside click, app switch) until Copy, Paste or Esc.
// Implements the decision-8 ActionResult tree-walk (handleActionResult): presentation results render
// here, leaf effects route to DefaultActionResultHandler, and dismissal is decided once via
// ActionResult.dismissesPopup.
import AppKit
import SwiftUI
import Core

@MainActor
public class PopupWindowController {
    var panel: PopupPanel?
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?
    private var currentContext: SelectionContext?
    public var sourceAppBundleID: String? { currentContext?.sourceApp.bundleIdentifier }
    var currentActionContext: ActionContext?
    /// What the popup shows (palette or result card), observed by PopupView.
    public let modeStore = PopupModeStore()

    /// Records action usage for search recency ranking.
    private let usageStore = ActionUsageStore()
    /// Frontmost app before the panel became key; captured once per session in show(for:),
    /// reactivated on exitKeyMode/hide, cleared only by hide(). Internal for tests.
    var previousFrontmostApp: NSRunningApplication?

    /// Monotonic timestamp recorded when a session starts (`show(for:)`). Used by
    /// `workspaceDidActivateApp` to suppress the race where macOS delivers a queued
    /// app-activation notification for the destination app within ~300 ms of the popup
    /// opening — common after a clipboard manager dismisses itself.
    var sessionShowTime: TimeInterval = 0

    private var isMenuTracking = false

    /// Tracks whether a right-click mouse-down originated within the popup.
    private var isRightClickInProgress = false

    /// How the most recent palette action was triggered (left-click vs right/⇧-click). Set by
    /// the mouse monitor on mouse-down and reset by hide(). Snapshotted into a `DeliveryContext`
    /// when an action performs — never read as live state after an await. Drives the standardized
    /// paste-vs-copy delivery decision (`ActionResultDelivery`).
    private var pendingClickIntent: ActionResultDelivery.ClickIntent = .primary

    /// The most recent palette action's declared delivery (secondary outcome + per-click
    /// toasts). Set by the perform paths (`onWillPerformAction`, `runAction`,
    /// `runLoadingAction`) right before the action runs, consumed once by the next
    /// `deliverResult` snapshot (which clears it — single-use per perform), and reset by hide().
    /// Snapshotted into a `DeliveryContext` with `pendingClickIntent`, so `resolveDelivery` sees
    /// the action's declared delivery — never read as live state after an await. Internal for
    /// tests so a test can model the `onWillPerformAction` snapshot directly.
    var pendingDelivery: ActionDelivery? = nil

    /// The most recent palette action's title, for the result card header. Set by the perform
    /// paths (`onWillPerformAction`, `runAction`, `runLoadingAction`) alongside `pendingDelivery`,
    /// consumed once by the next `deliverResult` snapshot (which clears it), reset by hide(). Internal
    /// for tests.
    var pendingActionTitle: String? = nil

    /// The most recent palette action's display icon (customization-resolved), for the result card
    /// header. Lifecycle mirrors `pendingActionTitle`. Internal for tests.
    var pendingActionIcon: ActionIcon? = nil

    /// The most recent palette action's ID, for delivery preference resolution. Lifecycle mirrors
    /// `pendingActionTitle`. Internal for tests.
    var pendingActionID: String? = nil

    /// The most recent palette action's recommended result. Lifecycle mirrors `pendingActionTitle`. Internal for tests.
    var pendingActionRecommendedResult: ActionResultDeliveryMode? = nil

    /// The most recent palette action's output kind. Lifecycle mirrors `pendingActionTitle`. Internal for tests.
    var pendingActionOutputKind: ActionOutputKind? = nil

    /// In-flight delivery context snapshotted before an action performs, preserved across hide()
    /// so an asynchronous action that finishes after popup dismissal or app-switching delivers with
    /// its original context. Internal for tests.
    var inFlightDeliveryContext: DeliveryContext? = nil

    /// Provider for the app that owns keyboard focus — the frontmost app, or another app whose
    /// non-activating panel is key (`FocusedApplication`). Injected for testing app-switching scenarios.
    var frontmostApplicationProvider: @MainActor () -> NSRunningApplication? = {
        FocusedApplication.current()
    }

    /// Probes whether the frontmost app supports Paste. Injected for tests.
    private let pasteProbe: PasteAvailabilityProbing

    /// The floating toast surface for statuses and the paste→copy "Copied" notice. Independent of
    /// the popup panel: it shows whether the popup is up or has already hidden. Injected for tests.
    let toastController: ToastPanelController

    /// Frame of the popup during its most recent on-screen session (screen coords), captured right
    /// after each placement so toasts stay linked to where the popup actually was even after
    /// hide() — never falling back to the pointer. Internal for tests.
    var lastPopupFrame: NSRect?

    /// The settings store resolving the per-click result-delivery preference. Injected for tests.
    private let settingsStore: SettingsStore

    /// Session token for AI streaming deliveries, bumped by hide() and show(for:). Streaming
    /// closures are stamped with the session they were built under and dropped on mismatch, so
    /// chunks from an abandoned stream (popup dismissed mid-stream) can never flip a later
    /// session into content mode or re-stick isProcessingAI.
    public private(set) var aiSessionID = UUID()

    /// The live AI streaming task for the current session, registered by PopupView when it
    /// starts streaming and cancelled by hide() — session-scoped cancellation that does not
    /// depend on SwiftUI view teardown racing AppKit's hide().
    var activeStreamingTask: Task<Void, Never>?

    /// Active loading action task reference so clicking the loading toast can cancel in-flight execution.
    var activeLoadingTask: Task<Void, Never>?
    private var activeLoadingID: UUID?

    public init(resultHandler: ActionResultHandler = DefaultActionResultHandler(),
                 pasteProbe: PasteAvailabilityProbing = PasteAvailabilityProbe(),
                 toastController: ToastPanelController = ToastPanelController(),
                 settingsStore: SettingsStore = DefaultSettingsStore.shared) {
        self.resultHandler = resultHandler
        self.pasteProbe = pasteProbe
        self.toastController = toastController
        self.settingsStore = settingsStore
    }

    /// Kicks off the paste-availability probe for the given target app (rules first, then the AX
    /// menu walk on its own queue). Trigger sites run this in parallel with selection retrieval,
    /// then hand the awaited result to `show(for:pasteAvailable:)` so the palette renders Paste/
    /// Cut correctly on the first frame. Nothing is cached: paste availability tracks the target
    /// app's *focus context* (editable field vs read-only view), which can differ between shows in
    /// the same app — unless a per-app rule (assume/deny paste) answers definitively.
    public func preparePasteProbe(for app: NSRunningApplication?, policy: AppPolicyContext) -> Task<Bool?, Never> {
        Task { @MainActor in
            await pasteProbe.canPaste(in: app, policy: policy)
        }
    }

    public func show(for context: SelectionContext, pasteAvailable: Bool? = nil) {
        show(for: context, pasteAvailable: pasteAvailable, preservingSessionID: nil, streamingTask: nil)
    }

    /// Opens the palette on `context`, Spotlight-style on the mouse's screen. The AI and loading
    /// flows re-show it with the session they started (`preservingSessionID`) and switch it to the
    /// result card right away.
    func show(for context: SelectionContext, pasteAvailable: Bool?, preservingSessionID: UUID?, streamingTask: Task<Void, Never>?) {
        let evaluator = InlineResultEvaluator.shared
        let aiSession: UUID
        if let preservingSessionID {
            aiSession = preservingSessionID
            aiSessionID = preservingSessionID
            activeStreamingTask = streamingTask
        } else {
            // A new session invalidates any still-running stream from the previous one: cancel its
            // task and bump the token so late chunks are dropped even before the old view unwinds.
            activeStreamingTask?.cancel()
            activeStreamingTask = nil
            activeLoadingTask?.cancel()
            activeLoadingTask = nil
            evaluator.cancelSession(aiSessionID)
            aiSession = UUID()
            aiSessionID = aiSession
        }

        isMenuTracking = false
        let selectionContext = context.with(
            pasteTargetAvailable: PasteAvailability.effective(policy: context.appPolicy, probe: pasteAvailable)
        )
        currentContext = selectionContext
        sessionShowTime = ProcessInfo.processInfo.systemUptime

        // The source app is frontmost when the popup shows; capture it once for the whole session.
        // Skip the capture while OpenClip itself is frontmost (e.g. a preference window, or a mid-
        // session re-show): storing ourselves makes the later re-activation a no-op that loses the real
        // source app.
        captureFrontmostAppIfNeeded()

        let actionContext = ActionContext(selection: selectionContext, modifiers: [])
        currentActionContext = actionContext

        let panel = self.panel ?? PopupPanel()
        self.panel = panel
        // A fresh show is an intentional placement: never re-anchor it.
        panel.recentersOnResize = false
        modeStore.resultCardSize = nil
        modeStore.isSurfaceUserSized = false

        let screen = PopupPositioner.screen(containing: context.cursorPosition) ?? NSScreen.main
        let screenBounds = screen?.visibleFrame ?? Self.fallbackScreenBounds
        panel.heightCap = screenBounds.height

        modeStore.mode = .search
        PaletteRowShortcuts.setActive(true)
        // Probed before selection retrieval by the trigger sites and resolved before this frame,
        // so the palette gates Paste/Cut correctly on the first render. `nil` keeps them visible.
        modeStore.canPaste = pasteAvailable

        modeStore.inlineResults.removeAll()
        let inlineActions = ActionCoordinator.shared.searchCatalog(for: actionContext).filter { $0.chrome.isInlineResult }
        for action in inlineActions {
            if let syncResult = evaluator.evaluateSynchronous(action: action, context: actionContext) {
                modeStore.inlineResults[action.id] = syncResult
            } else {
                evaluator.startEvaluation(action: action, context: actionContext, sessionID: aiSession) { [weak self] result in
                    guard let self, let result, !result.isEmpty else { return }
                    guard self.aiSessionID == aiSession else { return }
                    self.modeStore.inlineResults[action.id] = result
                }
            }
        }

        let rootView = PopupView(
            settingsStore: settingsStore,
            context: actionContext,
            alternateSearchContext: alternateClipboardSearchContext(for: context),
            onSearchContextChanged: { [weak self] selection in
                self?.updateSearchContext(selection)
            },
            modeStore: modeStore,
            onExitSearch: { [weak self] in self?.hide() },
            onExitContent: { [weak self] in self?.exitContent() },
            onDismissContent: { [weak self] in self?.hide() },
            onCardDrag: { [weak self] phase in self?.handleCardDrag(phase) },
            onResize: { [weak self] edge, phase in self?.handleResize(edge, phase: phase) },
            onPinCard: { [weak self] in self?.pinCard() },
            onCardEffect: { [weak self] result in
                self?.performCardEffect(result)
            },
            onResult: { [weak self] result in
                self?.deliverResult(result)
            },
            onContentSizeChange: { [weak self] size in
                self?.resizePanel(to: size)
                self?.keepPanelOnScreen()
                self?.updateToastPlacement()
            },
            onActionPerformed: { [weak self] actionID in
                self?.usageStore.record(actionID)
            },
            onWillPerformAction: { [weak self] action, clickIntent in
                guard let self, let context = self.currentActionContext,
                      self.canPerformAction(action, in: context) else { return false }
                self.pendingDelivery = action.delivery
                self.pendingActionTitle = action.title
                self.pendingActionIcon = action.displayIcon(using: ActionCustomizationManager.shared)
                self.pendingActionID = action.id
                self.pendingActionRecommendedResult = action.chrome.recommendedResult
                self.pendingActionOutputKind = action.chrome.outputKind
                self.inFlightDeliveryContext = self.deliverySnapshot(for: action, clickIntent: clickIntent)
                return true
            },
            onRunLoadingAction: { [weak self] action, clickIntent in
                guard let self, let context = self.currentActionContext else { return }
                self.runLoadingAction(action, with: context, isSecondaryClick: clickIntent == .secondary)
            },
            onRunAI: { [weak self] actionID in
                guard let self, let preset = AIServiceManager.shared.preset(forActionID: actionID) else { return }
                let prompt = AIServiceManager.shared.promptForPreset(preset)
                self.runAIPreset(prompt: prompt, title: preset.title)
            },
            onRunAIPrompt: { [weak self] instruction, replace, includeContext in
                self?.runAIPrompt(instruction, replace: replace, includeContext: includeContext)
            },
            onSaveAIPrompt: { [weak self] instruction, replace in
                self?.saveAndRunAIPrompt(instruction, replace: replace)
            },
            onFollowUp: { [weak self] instruction in
                self?.runFollowUp(instruction)
            },
            onCancelFollowUp: { [weak self] in
                self?.cancelFollowUp()
            },
            onClickIntent: { [weak self] in self?.pendingClickIntent ?? .primary }
        )
        syncPanelAppearance(panel)
        let hosting = PopupPanel.ContentView(rootView: rootView)
        hosting.onMouseMoved = { [weak self] in self?.handleTrackingMouseMoved() }
        panel.contentView = hosting
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = sanitizedPopupSize(panel.contentView?.fittingSize)
        placeSpotlight(panel, size: size, in: screenBounds)
        lastPopupFrame = panel.frame
        // Later width changes re-center; the field at the top stays put as the list follows the
        // query (the palette is placed at its size, so it is not bottom-pinned).
        panel.recentersOnResize = true
        if NSClassFromString("XCTestCase") == nil {
            panel.orderFront(nil)
        }

        setupMonitors()
        enterKeyMode()
        Task { @MainActor in
            await Task.yield()
            self.focusSearchField()
        }
        scheduleKeepPanelOnScreen()
    }

    public var isVisible: Bool { (panel?.isVisible == true) || (currentContext != nil) }

    /// Starts a session without creating AppKit window monitors or ordering windows on screen. Internal for tests.
    func startTestSession(for context: SelectionContext, pasteAvailable: Bool? = nil, initialMode: PopupMode = .search) {
        isMenuTracking = false
        let selectionContext = context.with(
            pasteTargetAvailable: PasteAvailability.effective(policy: context.appPolicy, probe: pasteAvailable)
        )
        currentContext = selectionContext
        captureFrontmostAppIfNeeded()
        let actionContext = ActionContext(selection: selectionContext, modifiers: [])
        currentActionContext = actionContext
        modeStore.mode = initialMode
        modeStore.canPaste = pasteAvailable
    }

    /// Hotkey-driven toggle: dismisses the popup if already visible.
    public func toggleMode() {
        guard panel?.isVisible == true else { return }
        hide()
    }

    /// Records the app that was frontmost before the panel made itself key. Captures only when no
    /// session value exists yet — mid-session re-entry must keep the original source app — and only
    /// when that app is not OpenClip itself. Used by show(for:) (session start) and enterKeyMode();
    /// hide() is the only thing that clears it.
    private func captureFrontmostAppIfNeeded() {
        guard previousFrontmostApp == nil,
              let app = FocusedApplication.current(),
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        previousFrontmostApp = app
    }

    /// Makes the panel key (a scoped, user-initiated exception to the never-key rule) so a key
    /// component can receive typing. A nonactivating panel can become key without activating this
    /// app, so the source app stays active throughout. Captures the frontmost app only when no
    /// session value exists yet — mid-session re-entry (content → search) must keep the original
    /// source app — and only when that app is not OpenClip itself.
    private func enterKeyMode() {
        guard let panel else { return }
        captureFrontmostAppIfNeeded()
        panel.allowsKey = true
        if NSClassFromString("XCTestCase") == nil {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// Restores the never-key invariant and hands keyboard focus back to the source app. Deliberately
    /// does NOT clear previousFrontmostApp: only hide() ends the session, so the same source app is
    /// re-activated on the next exit and re-used on the next enter.
    private func exitKeyMode() {
        panel?.allowsKey = false
        if NSApp.isActive {
            previousFrontmostApp?.activate(options: [.activateAllWindows])
        }
    }

    private func alternateClipboardSearchContext(for selection: SelectionContext) -> SelectionContext? {
        guard !selection.isClipboardFallback,
              !selection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let pasteboard = NSPasteboard.general
        // Files copied in Finder also put their names on the clipboard; not text to act on.
        if HotkeyManager.clipboardHoldsFiles(pasteboard) { return nil }
        guard let text = pasteboard.string(forType: .string),
              TextSanitizer.isSubstantial(text),
              text.utf8.count <= Constants.maxTextLength,
              text != selection.text else { return nil }
        return SelectionContext(
            text: text,
            sourceApp: selection.sourceApp,
            cursorPosition: selection.cursorPosition,
            selectionBounds: nil,
            timestamp: selection.timestamp,
            appPolicy: selection.appPolicy,
            isClipboardFallback: true,
            html: pasteboard.string(forType: .html),
            rtf: pasteboard.string(forType: .rtf),
            isEditable: false,
            pasteTargetAvailable: selection.pasteTargetAvailable
        )
    }

    private func updateSearchContext(_ selection: SelectionContext) {
        guard modeStore.mode == .search else { return }
        currentActionContext = ActionContext(
            selection: selection,
            modifiers: currentActionContext?.modifiers ?? []
        )
        // Inline values were evaluated for the original selection. Clear them so the palette
        // cannot show a stale preview; running the action evaluates it against the active context.
        modeStore.inlineResults.removeAll()
    }

    /// The hosting view grows the panel to the palette on its own, after the current run-loop turn
    /// (and sometimes a display pass later); a remembered palette can be tall enough for that
    /// growth to run off a screen edge, so nudge it back once the growth has landed. Same two
    /// retries as `showResultCard`.
    private func scheduleKeepPanelOnScreen() {
        DispatchQueue.main.async { [weak self] in self?.keepPanelOnScreen() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.keepPanelOnScreen() }
    }

    private func focusSearchField() {
        guard let panel, panel.isVisible, modeStore.mode == .search else { return }
        guard let field = findTextInput(in: panel.contentView) else { return }
        panel.makeFirstResponder(field)
    }

    private func findTextInput(in view: NSView?) -> NSView? {
        guard let view else { return nil }
        if view is NSTextView || view is NSTextField { return view }
        for subview in view.subviews {
            if let found = findTextInput(in: subview) { return found }
        }
        return nil
    }

    // MARK: - AI Result Card

    /// True while the result card is on screen AND the user has dragged it aside to keep it open.
    /// An un-dragged result card remains standard and dismisses on outside clicks.
    public var cardIsModal: Bool { modeStore.mode == .content && hasUserMovedCard }
    public private(set) var hasUserMovedCard: Bool = false

    /// Applies a streaming "processing" flag update, but only for the session the update
    /// belongs to. A stale stream (popup dismissed mid-stream, superseded by a new selection)
    /// must never re-stick isProcessingAI after hide() cleared it.
    func setAIProcessing(_ active: Bool, session: UUID) {
        guard session == aiSessionID else { return }
        modeStore.isProcessingAI = active
    }

    /// Shows an action's returned text (or error) in the native result card, replacing the
    /// palette; the panel stays key so Esc can close the card. Any text-returning action
    /// renders here — AI presets stream into it via `onAIResult`, extensions land via the
    /// delivery snapshot with their own icon. Paste/Copy are explicit user requests routed
    /// through `performCardEffect`, so they bypass the paste-vs-copy re-decision — an explicit
    /// Paste always pastes. The selection the action ran on is carried in the payload so the card
    /// can render a character-level diff of what changed. Probes (AX) whether the target app can
    /// paste so the card can hide its Paste button; the probe targets the captured source app,
    /// never OpenClip itself. Deliveries
    /// are session-stamped: a chunk from an abandoned stream is dropped instead of hijacking the
    /// current popup into content mode. Internal for tests.
    func showResultCard(
        text: String,
        isError: Bool,
        title: String,
        icon: ActionIcon? = nil,
        isStreaming: Bool = false,
        session: UUID,
        originalText: String? = nil,
        overrideOriginal: Bool = false,
        canFollowUp: Bool = true,
        file: FileOutputPayload? = nil
    ) {
        guard session == aiSessionID else { return }
        if toastController.isLoading {
            toastController.hide()
        }
        modeStore.isProcessingAI = isStreaming
        let original = overrideOriginal ? originalText : currentActionContext?.selection.text
        // The selection the action ran on rides along so the card can diff input → output.
        modeStore.resultCard = ResultCardPayload(
            text: text,
            isError: isError,
            title: title,
            icon: icon,
            isStreaming: isStreaming,
            original: original,
            canFollowUp: canFollowUp,
            file: file
        )
        if !isStreaming {
            // A settled card hands the keyboard to its instruction field so the next refinement
            // is just typing.
            Task { @MainActor in
                await Task.yield()
                self.focusCardField()
            }
        }
        if modeStore.mode != .content {
            hasUserMovedCard = false
            PaletteRowShortcuts.setActive(false)
            if let panel {
                // The card takes the palette's size and place. A fixed size renders verbatim, so
                // later fits keep the frame; the card's own clamps keep it on-screen.
                panel.heightCap = screenBounds(for: panel).height
                        panel.recentersOnResize = true
                let cardSize = CGSize(width: PopupMetrics.searchPanelContentWidth, height: PopupMetrics.searchPaletteMinHeight)
                modeStore.resultCardSize = cardSize
                modeStore.isSurfaceUserSized = true
                placeSpotlight(panel, size: cardSize, in: screenBounds(for: panel))
            }
            modeStore.mode = .content
            enterKeyMode()
        }

        // Tell the hosting view its intrinsic content size has changed so AppKit
        // re-measures on the next display cycle (the mode change schedules a SwiftUI
        // re-evaluation, but NSHostingView won't re-measure without this nudge).
        fitPanelToContent()
        // Retry after the current AppKit display cycle completes — DispatchQueue.main.async
        // fires after the run-loop turn, unlike Task.yield() which only yields in the
        // cooperative pool without guaranteeing a display pass.
        DispatchQueue.main.async { [weak self] in
            self?.fitPanelToContent()
        }
        // Safety-net retry for the first content-mode entry where SwiftUI swaps
        // the entire view tree (palette → ResultCardView) and needs an extra
        // layout pass to settle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.modeStore.mode == .content else { return }
            self.fitPanelToContent()
        }
    }

    /// Re-measures the hosting view and grows/shrinks the panel to its content, then nudges the
    /// panel back inside the screen, so the anchored growth never runs off a screen edge.
    private func fitPanelToContent() {
        guard let contentView = panel?.contentView else { return }
        contentView.invalidateIntrinsicContentSize()
        contentView.layoutSubtreeIfNeeded()
        resizePanel(to: sanitizedPopupSize(contentView.fittingSize))
        keepPanelOnScreen()
    }

    /// Moves the panel the minimum distance needed to sit inside its screen (by `popupPadding`)
    /// while a resizable surface shows. Only automatic placement is corrected: a card the user
    /// dragged stays where they put it.
    private func keepPanelOnScreen() {
        guard let panel, panel.isVisible, resizableSurface != nil, !hasUserMovedCard else { return }
        let bounds = screenBounds(for: panel).insetBy(dx: PopupMetrics.popupPadding, dy: PopupMetrics.popupPadding)
        var origin = panel.frame.origin
        origin.x = max(min(origin.x, bounds.maxX - panel.frame.width), bounds.minX)
        origin.y = max(min(origin.y, bounds.maxY - panel.frame.height), bounds.minY)
        if origin != panel.frame.origin {
            panel.setFrameOrigin(origin)
        }
    }

    // MARK: - Resizable Surfaces

    /// The popup surface with resize handles: the native result card. The geometry and the panel
    /// handling live here. The search palette is content-sized and not resizable.
    private enum ResizableSurface {
        case card

        var minSize: CGSize {
            CGSize(width: PopupMetrics.aiCardMinWidth, height: PopupMetrics.aiCardMinHeight)
        }
    }

    /// The resizable surface currently on screen, if the popup is showing one. Only the result
    /// card resizes.
    private var resizableSurface: ResizableSurface? {
        switch modeStore.mode {
        case .content: return .card
        case .search: return nil
        }
    }

    private func setLiveSize(_ size: CGSize?, for surface: ResizableSurface) {
        switch surface {
        case .card: modeStore.resultCardSize = size
        }
    }

    private static let fallbackScreenBounds = NSRect(x: 0, y: 0, width: 800, height: 600)

    private func screenBounds(for panel: PopupPanel) -> CGRect {
        panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? Self.fallbackScreenBounds
    }

    /// Where the panel sat, and where the cursor was, when the current header drag began. Nil while
    /// no drag is in flight.
    private var cardDragAnchor: (mouse: CGPoint, origin: CGPoint)?

    /// Moves the panel with the cursor while the card or search header is dragged. The move is
    /// computed from the *absolute* cursor position against the anchor taken at `.began`, never
    /// from the gesture's own translation: the window moves out from under the pointer, so a
    /// translation-based move would fight itself and crawl. `mouseLocation` is injectable so the
    /// geometry is testable without a real cursor. Internal for tests.
    func handleCardDrag(_ phase: ResultCardDragPhase, mouseLocation: CGPoint? = nil) {
        guard let panel else { return }
        let mouse = mouseLocation ?? NSEvent.mouseLocation
        switch phase {
        case .began:
            panel.prepareForUserDrag()
            cardDragAnchor = (mouse: mouse, origin: panel.frame.origin)
        case .changed:
            guard let anchor = cardDragAnchor else { return }
            panel.setFrameOrigin(CGPoint(x: anchor.origin.x + (mouse.x - anchor.mouse.x),
                                         y: anchor.origin.y + (mouse.y - anchor.mouse.y)))
        case .ended:
            cardDragAnchor = nil
            panel.endUserDrag()
            if modeStore.mode == .content {
                hasUserMovedCard = true
            }
        }
    }

    /// Toggles the explicit pin state of the result card. Pinning makes the card modal — the same
    /// `hasUserMovedCard` gate that dragging the card sets — so the card suppresses auto-dismiss
    /// (outside-click, scroll, cursor distance, app switch). Unpinning restores non-modal behavior.
    func pinCard() {
        let nowPinned = !modeStore.isCardPinned
        modeStore.isCardPinned = nowPinned
        hasUserMovedCard = nowPinned
    }

    // MARK: - Resize

    /// Where the cursor was, how big the surface was, and which surface it was when the current
    /// resize began. Nil while no resize is in flight; `resizePanel` reads it to keep
    /// content-driven size reports anchored at the surface's top-left corner for the duration.
    private var resizeAnchor: (mouse: CGPoint, size: CGSize, surface: ResizableSurface)?

    /// Resizes the result card as one of its handles is dragged. Mirrors `handleCardDrag`: the new
    /// size comes from the *absolute* cursor position
    /// against the anchor taken at `.began` (the dragged edge moves out from under the pointer, so
    /// the gesture's own translation would fight it), the surface's top-left corner stays fixed,
    /// and the size is clamped to the surface minimum and to the screen. `mouseLocation` is injectable so the geometry is testable
    /// without a real cursor. Internal for tests.
    func handleResize(_ edge: PopupResizeEdge, phase: ResultCardDragPhase, mouseLocation: CGPoint? = nil) {
        guard let panel, let surface = resizableSurface else { return }
        let mouse = mouseLocation ?? NSEvent.mouseLocation
        switch phase {
        case .began:
            // Same panel state as a move: no hover-driven click-through mid-drag, and neither
            // re-centering nor bottom-pinning fighting the top-left-anchored frames set below.
            panel.prepareForUserDrag()
                    // The drag starts from the size on screen — smaller than the remembered maximum when
            // the content did not need all of it — so the handle stays under the pointer. From
            // here on the surface renders the dragged size verbatim, for the rest of its session.
            modeStore.isSurfaceUserSized = true
            resizeAnchor = (mouse: mouse, size: currentSurfaceSize(in: panel), surface: surface)
        case .changed:
            guard let anchor = resizeAnchor, anchor.surface == surface else { return }
            let proposed = PopupResizeGeometry.size(
                from: anchor.size, edge: edge, anchorMouse: anchor.mouse, mouse: mouse)
            let size = PopupResizeGeometry.clamp(
                proposed,
                minSize: surface.minSize,
                panelTopLeft: CGPoint(x: panel.frame.minX, y: panel.frame.maxY),
                screenBounds: screenBounds(for: panel))
            applySize(size, for: surface, to: panel)
        case .ended:
            guard let anchor = resizeAnchor, anchor.surface == surface else { return }
            resizeAnchor = nil
            panel.endUserDrag()
            // The dragged size is what the surface keeps until it closes (`isSurfaceUserSized`
            // stays set).
        }
    }

    /// The surface's on-screen size, which is the panel frame. A surface's default size is never
    /// reported to the controller, so this is how the first resize of a session learns where it starts.
    private func currentSurfaceSize(in panel: PopupPanel) -> CGSize {
        panel.frame.size
    }

    /// Applies a size: the surface reads it from the store, and the panel is set to the surface
    /// with the top-left corner fixed (the handles sit on the right/bottom
    /// edges). The hosting view's own top-anchored auto-resize then lands on this same frame.
    private func applySize(_ size: CGSize, for surface: ResizableSurface, to panel: PopupPanel) {
        setLiveSize(size, for: surface)
        panel.setFrame(CGRect(x: panel.frame.minX, y: panel.frame.maxY - size.height,
                              width: size.width, height: size.height), display: true)
    }

    /// The result card's Back: reopens the palette on the same input.
    public func exitContent() {
        guard modeStore.mode == .content else { return }
        if refiningPrevious != nil {
            // Leaving the card drops a follow-up in flight; the stream must not re-open it.
            activeStreamingTask?.cancel()
            activeStreamingTask = nil
            refiningPrevious = nil
            modeStore.isProcessingAI = false
        }
        cardConversation = nil
        modeStore.resultCard = nil
        modeStore.resultCardSize = nil
        modeStore.isSurfaceUserSized = false
        modeStore.isCardPinned = false
        resizeAnchor = nil
        hasUserMovedCard = false
        if let selection = currentActionContext?.selection {
            show(for: selection, pasteAvailable: modeStore.canPaste)
        } else {
            hide()
        }
    }

    /// Runs an explicit card button (Paste/Copy) — an explicit user request, so it carries no
    /// delivery context and bypasses the paste-vs-copy re-decision. Dismissing results hide the
    /// popup first (so exitKeyMode() reactivates the target app) before handling.
    private func performCardEffect(_ result: ActionResult) {
        if result.dismissesPopup {
            hide()
            handleActionResult(result, delivery: nil)
        } else {
            _ = handleEffect(result, delivery: nil)
        }
    }

    // MARK: - Panel Resize

    /// Resize the panel to its content, keeping the top edge fixed (the top-left corner while a
    /// resize handle is dragged). Horizontal re-centering and screen/height clamping are handled by
    /// `PopupPanel.setFrame`, the single funnel both paths go through.
    private func resizePanel(to proposedSize: CGSize) {
        guard let panel, panel.isVisible else { return }
        let size = sanitizedPopupSize(proposedSize)
        let current = panel.frame.size
        if abs(current.width - size.width) < 1, abs(current.height - size.height) < 1 { return }
        panel.setFrame(CGRect(x: panel.frame.minX, y: panel.frame.maxY - size.height,
                              width: size.width, height: size.height), display: true)
        updateToastPlacement()
    }

    private func syncPanelAppearance(_ targetPanel: NSPanel) {
        let appearanceToken = settingsStore.get(SettingKey.popupThemeColor)
        let systemIsDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let isDark = PopupThemeModel.effectiveScheme(appearance: appearanceToken, systemIsDark: systemIsDark) == .dark
        targetPanel.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
    }

    /// Moves `panel` to its Spotlight frame — centered, a little above the middle of the screen
    /// with the mouse. Anchoring is suspended for the move, since `PopupPanel.setFrame` would
    /// otherwise keep the previous frame's midX and top edge.
    private func placeSpotlight(_ panel: PopupPanel, size: CGSize, in screenBounds: CGRect) {
        let recenters = panel.recentersOnResize
        panel.recentersOnResize = false
        panel.setFrame(PopupPositioner.spotlightFrame(size: size, in: screenBounds), display: true)
        panel.recentersOnResize = recenters
    }

    private func sanitizedPopupSize(_ raw: CGSize?) -> CGSize {
        var size = raw ?? CGSize(width: 300, height: 54)
        size.width = max(size.width, 100)
        size.height = max(size.height, 30)
        return size
    }

    public func hide() {
        // End the AI session first: cancel the live stream and invalidate its token so any
        // chunk already in flight is dropped instead of re-flipping state after the resets below.
        activeStreamingTask?.cancel()
        activeStreamingTask = nil
        activeLoadingTask?.cancel()
        activeLoadingTask = nil
        activeLoadingID = nil
        // End the session (cancel in-flight work) but keep the warm inline-result caches so the
        // next selection renders its preview immediately instead of re-evaluating from cold.
        InlineResultEvaluator.shared.endSession(aiSessionID)
        aiSessionID = UUID()
        refiningPrevious = nil
        cardConversation = nil

        if toastController.currentFeedback?.keepVisible == true || toastController.isLoading {
            toastController.hide()
        }
        modeStore.resultCard = nil
        modeStore.resultCardSize = nil
        modeStore.isSurfaceUserSized = false
        modeStore.canPaste = nil
        modeStore.inlineResults.removeAll()
        // A dismissed session must not leak its click intent into the next one (keyboard-driven
        // runs and any later snapshot read the last intent; force-copy must never persist). The
        // declared delivery is snapshotted per-perform, so a stale value must not leak either.
        pendingClickIntent = .primary
        pendingDelivery = nil
        pendingActionTitle = nil
        pendingActionIcon = nil
        pendingActionID = nil
        pendingActionRecommendedResult = nil
        pendingActionOutputKind = nil
        isRightClickInProgress = false
        modeStore.isProcessingAI = false
        modeStore.mode = .search
        PaletteRowShortcuts.setActive(false)
        panel?.recentersOnResize = false
        panel?.endUserDrag()
        cardDragAnchor = nil
        resizeAnchor = nil
        hasUserMovedCard = false
        modeStore.isCardPinned = false
        sessionShowTime = 0
        panel?.ignoresMouseEvents = false // clear any hover-driven click-through from the last session
        exitKeyMode() // allowsKey=false + reactivate previousFrontmostApp
        previousFrontmostApp = nil // hide() is the only thing that ends the key-mode session
        panel?.orderOut(nil)
        removeMonitors()
        currentContext = nil
        currentActionContext = nil
        isMenuTracking = false
        PopupHoverState.shared.location = nil
    }

    /// Cancels any in-flight background tasks (loading actions and AI streaming) and hides the toast.
    @MainActor
    public func cancelActiveTasks() {
        if activeLoadingTask != nil || activeStreamingTask != nil {
            Log.presentation.info("Cancelling active in-flight task(s) via loading toast")
        }
        activeLoadingTask?.cancel()
        activeLoadingTask = nil
        activeLoadingID = nil
        activeStreamingTask?.cancel()
        activeStreamingTask = nil
        inFlightDeliveryContext = nil
        modeStore.isProcessingAI = false
        toastController.hide()
    }
    
    private func setupMonitors() {
        removeMonitors()

        let canMonitorGlobally = PermissionManager.shared.isAccessibilityGranted
        PopupHoverState.shared.usesGlobalMouseMonitoring = canMonitorGlobally
        if canMonitorGlobally {
            globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .rightMouseUp, .mouseMoved, .keyDown]) { [weak self] event in
                self?.handleEvent(event)
            }
        } else {
            Log.presentation.notice("Accessibility permission unavailable; using local hover tracking.")
        }
        
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .leftMouseUp, .rightMouseUp, .mouseMoved, .keyDown]) { [weak self] event in
            self?.handleEvent(event)
            return event
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(menuDidBeginTracking), name: NSMenu.didBeginTrackingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(menuDidEndTracking), name: NSMenu.didEndTrackingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidDeactivate), name: NSApplication.didResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidResignKey(_:)), name: NSWindow.didResignKeyNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(preferencesWindowWillShow), name: .openClipPreferencesWindowWillShow, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(workspaceDidActivateApp(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(workspaceActiveSpaceDidChange), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    }
    
    @objc private func menuDidBeginTracking() {
        isMenuTracking = true
    }
    
    @objc private func menuDidEndTracking() {
        isMenuTracking = false
    }
    
    private func removeMonitors() {
        if let global = globalEventMonitor {
            NSEvent.removeMonitor(global)
            globalEventMonitor = nil
        }
        if let local = localEventMonitor {
            NSEvent.removeMonitor(local)
            localEventMonitor = nil
        }
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    /// Runs the palette row a global ⌘-digit hot key points at (1-based), returning false when
    /// there is no palette or no such row. The row list lives in the SwiftUI palette, so this
    /// reaches it through the catcher view mounted in the panel — the same walk `focusSearchField`
    /// uses to find the text field. Internal for tests.
    func runPaletteRow(_ row: Int) -> Bool {
        guard modeStore.mode == .search, let panel,
              let catcher = Self.findCommandDigitCatcher(in: panel.contentView) else { return false }
        return catcher.run(row: row)
    }

    private static func findCommandDigitCatcher(in view: NSView?) -> CommandDigitCatcher.CatcherView? {
        guard let view else { return nil }
        if let catcher = view as? CommandDigitCatcher.CatcherView { return catcher }
        for subview in view.subviews {
            if let found = findCommandDigitCatcher(in: subview) { return found }
        }
        return nil
    }

    func handleEvent(_ event: NSEvent) {
        if isMenuTracking { return }

        switch event.type {
        case .mouseMoved:
            updatePopupHover(at: NSEvent.mouseLocation)
        case .leftMouseDown:
            let clickLoc = NSEvent.mouseLocation
            let inPopup = isOverPanelContent(clickLoc)
            // Capture the modifier state at click time so the action that runs on mouse-up (via the
            // SwiftUI Button) delivers as a copy when ⇧ is held.
            let isShift = event.modifierFlags.contains(.shift)
            pendingClickIntent = isShift ? .secondary : .primary
            if !inPopup && !cardIsModal {
                hide()
            }
        case .rightMouseDown:
            // Right-click down: prepare force-copy intent and mark right-click in progress.
            let clickLoc = NSEvent.mouseLocation
            if isOverPanelContent(clickLoc) {
                pendingClickIntent = .secondary
                isRightClickInProgress = true
            } else {
                isRightClickInProgress = false
                if !cardIsModal { hide() }
            }
        case .rightMouseUp:
            isRightClickInProgress = false
        case .keyDown:
            // The palette and the card are key, and own Esc (SwiftUI). The card survives a click
            // into another app, though, and a panel that lost key never sees the keystroke: that
            // is the one case the monitor answers Esc itself.
            if modeStore.mode == .content, event.keyCode == 53, panel?.isKeyWindow != true {
                hide()
            }
        default:
            break
        }
    }

    /// Whether the screen point is over the popup. Internal (not private) for tests.
    func isOverPanelContent(_ screenLocation: CGPoint) -> Bool {
        guard let panel, panel.isVisible else { return false }
        return panel.frame.contains(screenLocation)
    }

    func updatePopupHover(at screenLocation: CGPoint, toggleClickThrough: Bool = true) {
        guard let panel, panel.isVisible, let contentView = panel.contentView else {
            PopupHoverState.shared.location = nil
            return
        }

        // Dynamic click-through: while the pointer is outside the panel, the panel ignores mouse
        // events entirely so they reach whatever is underneath. Gated on global monitoring:
        // without it the local monitor is the only way to notice the pointer re-entering the
        // content area, and ignoring events would strand the panel permanently inert.
        // The tracking-area path passes `toggleClickThrough: false` for the same reason: there is no
        // monitor to notice re-entry while inactive/fullscreen, so the panel must stay event-visible.
        let overContent = isOverPanelContent(screenLocation)
        if toggleClickThrough, PopupHoverState.shared.usesGlobalMouseMonitoring, !panel.isUserDragging {
            panel.ignoresMouseEvents = !overContent
        }
        if overContent {
            NSCursor.arrow.set()
        }

        let windowPoint = panel.convertPoint(fromScreen: screenLocation)
        let contentPoint = contentView.convert(windowPoint, from: nil)
        guard contentView.bounds.contains(contentPoint) else {
            PopupHoverState.shared.location = nil
            return
        }

        let y = contentView.isFlipped ? contentPoint.y : contentView.bounds.height - contentPoint.y
        let point = CGPoint(x: contentPoint.x, y: y)
        // The global monitor fires on every mouse move even when the pointer hasn't crossed a new
        // pixel boundary; `@Published` emits on every assignment, so skip identical locations to
        // keep the `.onReceive` hit-tests from re-running at event-monitor rate.
        guard point != PopupHoverState.shared.location else { return }
        PopupHoverState.shared.location = point
    }

    /// Feeds the hover pipeline from the panel's `.activeAlways` tracking area. This is the path
    /// that keeps hover alive while OpenClip is inactive — in particular with the popup floating
    /// over another app's fullscreen Space, where the global monitor gets no own-window events and
    /// SwiftUI `.onHover` does not fire. It is also called on tracking `mouseEntered`/`mouseExited`:
    /// a SwiftUI relayout can remove and re-add the tracking area, emitting a spurious exit while
    /// the pointer is still on the popup, so hover is always recomputed from the live cursor
    /// instead of blind-cleared.
    /// Click-through toggling is skipped here: with no monitor to notice re-entry, making the panel
    /// ignore events would strand it under the cursor.
    func handleTrackingMouseMoved() {
        updatePopupHover(at: NSEvent.mouseLocation, toggleClickThrough: false)
    }

    @objc private func appDidDeactivate() {
        // A right-click fires didResignActiveNotification before rightMouseUp arrives; suppressing
        // hide() here lets the right-click path complete on mouse-up as intended. The result card
        // outlives focus changes entirely (`cardIsModal`).
        if !isMenuTracking && !isRightClickInProgress && !cardIsModal {
            hide()
        }
    }

    /// Settings is about to come forward (⌘, from the palette, or an action asking to be
    /// configured). Close now, before Settings takes key, and without re-activating the source
    /// app: dismissed by that key change instead, `exitKeyMode()` ran with OpenClip already active
    /// and brought the source app back over Settings.
    @objc private func preferencesWindowWillShow() {
        guard !cardIsModal else { return }
        previousFrontmostApp = nil
        hide()
    }

    @objc private func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === panel else { return }
        // Clicking on another window makes the panel resign key. Dismiss immediately unless modal.
        if !cardIsModal {
            hide()
        }
    }

    @objc private func workspaceDidActivateApp(_ notification: Notification) {
        guard let app = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
            ?? NSWorkspace.shared.frontmostApplication else { return }
        if app.bundleIdentifier == Bundle.main.bundleIdentifier { return }
        // The source app where the selection occurred is allowed to activate without dismissing the popup.
        if let sourceBundleID = currentContext?.sourceApp.bundleIdentifier,
           app.bundleIdentifier == sourceBundleID {
            return
        }
        // Grace period: when a clipboard manager (Paste, Raycast, Maccy) dismisses itself, macOS
        // delivers a queued didActivateApplication for the destination app. If the popup just
        // opened (< 300 ms ago) this is almost certainly a leftover transition notification —
        // not an intentional user focus switch — so suppress the dismissal.
        if sessionShowTime > 0,
           (ProcessInfo.processInfo.systemUptime - sessionShowTime) < PopupMetrics.focusSwitchGracePeriod {
            return
        }
        // Modal result cards survive focus changes (parity with appDidDeactivate).
        if cardIsModal { return }
        if !isRightClickInProgress {
            hide()
        }
    }

    @objc private func workspaceActiveSpaceDidChange() {
        hide()
    }

    /// The frontmost app at the moment an in-place answer lands — pasting is only safe into the
    /// app the selection came from. Settable for tests.
    var frontmostBundleIDProvider: @MainActor () -> String? = { FocusedApplication.current()?.bundleIdentifier }

    /// Runs a palette instruction on the selection (or standalone without context if `includeContext` is false).
    /// `replace` pastes the answer over the selection (⏎); otherwise the answer streams into the result card (⇧⏎),
    /// titled after the instruction.
    func runAIPrompt(_ instruction: String, replace: Bool, includeContext: Bool = true) {
        let prompt = PaletteAIPrompt.instruction(from: instruction)
        guard !prompt.isEmpty else { return }
        let taskPrompt = includeContext
            ? PaletteAIPrompt.askAITaskPrompt(for: prompt)
            : PaletteAIPrompt.standaloneQuestionPrompt(for: prompt)
        let inputText: String? = includeContext ? nil : ""
        if replace {
            Log.ai.notice("Running a palette AI prompt, replacing the selection")
            runAIPromptReplacing(prompt: taskPrompt, inputText: inputText)
        } else {
            Log.ai.notice("Running a palette AI prompt into the result card")
            runAIPreset(prompt: taskPrompt, title: PaletteAIPrompt.toolTitle(for: prompt), inputText: inputText)
        }
    }

    /// Saves a palette instruction as a custom AI tool, then runs it with the same ⏎/⇧⏎ meaning
    /// as `runAIPrompt`. The tool is a regular custom preset: searchable in the palette, listed
    /// in Preferences → AI → Actions where it can be renamed, re-prompted or
    /// deleted. A prompt that is already saved reuses its tool rather than minting a duplicate.
    /// The saved tool is recorded as used so it ranks first among equals the next time it is searched.
    func saveAndRunAIPrompt(_ instruction: String, replace: Bool) {
        let prompt = PaletteAIPrompt.instruction(from: instruction)
        guard !prompt.isEmpty else { return }
        let manager = AIServiceManager.shared
        let existing = manager.preset(matchingPrompt: prompt)
        var preset = existing ?? manager.addCustomPreset(title: PaletteAIPrompt.toolTitle(for: prompt), prompt: prompt)
        usageStore.record(AIAction(presetID: preset.id, title: preset.title).id)
        if existing == nil {
            Log.ai.notice("Saved a palette prompt as AI tool \(preset.id, privacy: .public)")
        }

        let taskPrompt = PaletteAIPrompt.saveToolTaskPrompt(for: prompt)
        let onTitle: (String) -> Void = { cleanTitle in
            let trimmed = cleanTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != preset.title else { return }
            preset.title = trimmed
            manager.updatePreset(preset)
        }

        if replace {
            runAIPromptReplacing(
                prompt: taskPrompt,
                loadingMessage: existing == nil ? String(localized: "Saved as AI tool · Replacing…") : nil,
                onGeneratedTitle: onTitle
            )
        } else {
            runAIPreset(
                prompt: taskPrompt,
                title: preset.title,
                loadingMessage: existing == nil ? String(localized: "Saved as AI tool · Generating…") : nil,
                onGeneratedTitle: onTitle
            )
        }
    }

    /// Runs `prompt` on the selection and pastes the answer over it — no card. The popup hides,
    /// a cancellable "Replacing…" toast waits for the whole answer, and the answer goes through
    /// the explicit paste door (`handleActionResult(.paste)`, no delivery re-decision) under a
    /// success toast. The answer is copied instead when the unified paste availability says the
    /// target can't paste, or when the frontmost app is no longer the selection's app.
    func runAIPromptReplacing(prompt: String, loadingMessage: String? = nil, inputText: String? = nil, onGeneratedTitle: ((String) -> Void)? = nil) {
        guard let context = currentActionContext else {
            Log.ai.error("Cannot replace with AI: currentActionContext is nil")
            return
        }
        activeStreamingTask?.cancel()
        activeStreamingTask = nil

        let selection = context.selection
        let selectionText = inputText ?? selection.text
        let anchorFrame = panel?.frame ?? lastPopupFrame
        let targetCanPaste = PasteAvailability.effective(policy: selection.appPolicy, probe: modeStore.canPaste)
        let sourceBundleID = selection.sourceApp.bundleIdentifier

        hide()
        let session = aiSessionID
        toastController.showLoading(message: loadingMessage ?? String(localized: "Replacing…"), anchorFrame: anchorFrame) { [weak self] in
            self?.cancelActiveTasks()
        }

        let task = Task { @MainActor in
            self.modeStore.isProcessingAI = true
            defer {
                if !Task.isCancelled {
                    self.activeStreamingTask = nil
                    self.modeStore.isProcessingAI = false
                }
            }
            do {
                let provider = AIServiceManager.shared.currentProvider
                var accumulated = ""
                for try await chunk in provider.processStream(prompt: prompt, text: selectionText) {
                    guard !Task.isCancelled, session == self.aiSessionID else {
                        self.toastController.hide()
                        return
                    }
                    accumulated += chunk
                    if let generated = AIRequestSupport.extractTitleText(accumulated), !generated.isEmpty {
                        onGeneratedTitle?(generated)
                    }
                }
                guard !Task.isCancelled, session == self.aiSessionID else {
                    self.toastController.hide()
                    return
                }
                if let generated = AIRequestSupport.extractTitleText(accumulated), !generated.isEmpty {
                    onGeneratedTitle?(generated)
                }
                let answer = AIRequestSupport.extractResultText(accumulated)
                guard !answer.isEmpty else { throw AIError.invalidResponse }
                let stillInSourceApp = sourceBundleID == nil || self.frontmostBundleIDProvider() == sourceBundleID
                let pastes = targetCanPaste != false && stillInSourceApp
                self.handleActionResult(pastes ? .paste(answer) : .copy(answer), delivery: nil, suppressDeliveryToast: true)
                let message = pastes
                    ? String(localized: "Replaced with AI result")
                    : (stillInSourceApp ? String(localized: "Copied AI result") : String(localized: "Copied — the app changed"))
                self.toastController.show(StatusFeedback(message: message, style: .success, symbolName: "sparkle"), anchorFrame: anchorFrame)
            } catch is CancellationError {
                self.toastController.hide()
            } catch let error as AIError where error == .cancelled {
                self.toastController.hide()
            } catch {
                guard !Task.isCancelled, session == self.aiSessionID else {
                    self.toastController.hide()
                    return
                }
                Log.ai.error("Replacing with AI failed: \(error.localizedDescription)")
                self.toastController.show(StatusFeedback(error: error), anchorFrame: anchorFrame)
            }
        }
        activeStreamingTask = task
    }

    /// Runs an instruction typed into the card's follow-up field on the card's current text: a
    /// second pass over an answer ("shorter", "in Slovak"). The card re-streams in place, titled
    /// after the instruction, and diffs against the text the instruction ran on.
    func runFollowUp(_ instruction: String) {
        guard let card = modeStore.resultCard, !card.isStreaming, !card.isError, currentActionContext != nil else { return }
        let prompt = PaletteAIPrompt.instruction(from: instruction)
        guard !prompt.isEmpty else { return }
        Log.ai.notice("Running a follow-up instruction in the result card")
        refineCard(card, prompt: prompt, title: PaletteAIPrompt.toolTitle(for: prompt))
    }

    /// The card a follow-up is refining, kept so a cancel or a failure puts it back. Non-nil
    /// exactly while a follow-up is in flight.
    private var refiningPrevious: ResultCardPayload?

    /// What the card has done in this session — the selection and each instruction with its
    /// result — handed to follow-ups as labelled history. Seeded by the run that opened the card,
    /// extended by every settled follow-up, cleared when the card goes away. Internal for tests.
    private(set) var cardConversation: AIConversation?

    /// Runs a follow-up *inside* the card. Unlike a preset run, nothing hides and no loading
    /// toast shows: the card stays on screen with the previous answer dimmed under the field's
    /// spinner (`isRefining`) until the first chunk, then streams the new answer in place and
    /// settles with the diff against the original selection. Esc cancels, a failure restores the
    /// previous answer under an error toast, and leaving content mode drops the stream.
    private func refineCard(_ previous: ResultCardPayload, prompt: String, title: String) {
        activeStreamingTask?.cancel()
        activeStreamingTask = nil
        let session = aiSessionID
        let sourceText = previous.text
        // The history rides along as labelled context; the current instruction stays the task.
        let conversation = cardConversation
            ?? AIConversation(original: previous.original ?? sourceText, steps: [])
        let followUpTask = conversation.followUpTask(current: prompt)
        refiningPrevious = previous
        modeStore.isProcessingAI = true
        freezeCardSizeForRefinement()
        modeStore.resultCard = ResultCardPayload(
            text: sourceText,
            isError: false,
            title: title,
            icon: nil,
            isStreaming: true,
            original: previous.original,
            isRefining: true
        )

        let task = Task { @MainActor in
            defer {
                if !Task.isCancelled {
                    self.activeStreamingTask = nil
                    self.modeStore.isProcessingAI = false
                }
            }
            // The card is the only place this run renders: once the user has left content mode
            // (back chevron) or the session ended, every later chunk is dropped.
            @MainActor func stillRefining() -> Bool {
                if Task.isCancelled { return false }
                if session != self.aiSessionID { return false }
                if self.modeStore.mode != .content { return false }
                return self.refiningPrevious != nil
            }
            do {
                let provider = AIServiceManager.shared.currentProvider
                var accumulated = ""
                var activeTitle = title
                for try await chunk in provider.processStream(prompt: followUpTask, text: sourceText) {
                    guard stillRefining() else { return }
                    accumulated += chunk
                    if let newTitle = AIRequestSupport.extractTitleText(accumulated), !newTitle.isEmpty {
                        activeTitle = newTitle
                    }
                    let cleaned = AIRequestSupport.extractResultText(accumulated)
                    if !cleaned.isEmpty {
                        self.showResultCard(text: cleaned, isError: false, title: activeTitle, isStreaming: true, session: session, originalText: previous.original, overrideOriginal: true)
                    }
                }
                guard stillRefining() else { return }
                if let newTitle = AIRequestSupport.extractTitleText(accumulated), !newTitle.isEmpty {
                    activeTitle = newTitle
                }
                let finalResponse = AIRequestSupport.extractResultText(accumulated)
                if finalResponse.isEmpty {
                    self.restoreRefiningCard()
                    self.toastController.show(StatusFeedback(message: String(localized: "No response generated"), style: .error), anchorFrame: self.panel?.frame)
                } else {
                    self.refiningPrevious = nil
                    self.cardConversation = conversation.appending(instruction: prompt, result: finalResponse)
                    self.showResultCard(text: finalResponse, isError: false, title: activeTitle, isStreaming: false, session: session, originalText: previous.original, overrideOriginal: true)
                }
            } catch is CancellationError {
                // cancelFollowUp / hide already put the card back or took it down.
            } catch let error as AIError where error == .cancelled {
                // same
            } catch {
                guard stillRefining() else { return }
                Log.ai.error("Follow-up failed in the result card: \(error.localizedDescription)")
                self.restoreRefiningCard()
                self.toastController.show(StatusFeedback(error: error), anchorFrame: self.panel?.frame)
            }
        }
        activeStreamingTask = task
    }

    /// Pins the card to the exact size it has right now for the rest of its life on screen. The
    /// card is content-sized — as wide as its longest line, as tall as the wrapped text — so a
    /// refinement streaming in would otherwise re-measure it on every chunk and make the card
    /// jump around under the user's eyes. The frozen size takes the same path as a hand-resized
    /// card (`isSurfaceUserSized` + `resultCardSize`): the body scrolls if the new answer needs
    /// more room, the user can still drag the handles, and nothing is persisted. A card the user
    /// already resized is left alone; a test panel too small to be a card is ignored.
    private func freezeCardSizeForRefinement() {
        guard !modeStore.isSurfaceUserSized, let panel else { return }
        let frozen = panel.frame.size
        guard frozen.width >= PopupMetrics.aiCardMinWidth, frozen.height >= PopupMetrics.aiCardMinHeight else { return }
        modeStore.resultCardSize = frozen
        modeStore.isSurfaceUserSized = true
    }

    /// Puts the answer the follow-up was refining back, settled, with the field focused again.
    private func restoreRefiningCard() {
        guard let previous = refiningPrevious else { return }
        refiningPrevious = nil
        modeStore.isProcessingAI = false
        showResultCard(text: previous.text, isError: previous.isError, title: previous.title, icon: previous.icon, isStreaming: false, session: aiSessionID, originalText: previous.original, overrideOriginal: true, canFollowUp: previous.canFollowUp)
    }

    /// Esc while a follow-up streams: stop it and keep the previous answer on screen.
    func cancelFollowUp() {
        guard refiningPrevious != nil else { return }
        Log.ai.info("Follow-up cancelled in the result card")
        activeStreamingTask?.cancel()
        activeStreamingTask = nil
        restoreRefiningCard()
    }

    /// Focuses the card's instruction field on the next run-loop turn (a `@FocusState` request
    /// during the mode-change render is dropped on macOS, same as the search field). The card's
    /// selectable body is an AppKit text view too; only the instruction field is editable.
    private func focusCardField() {
        guard let panel, panel.isVisible, modeStore.mode == .content else { return }
        guard let field = Self.findEditableTextField(in: panel.contentView) else { return }
        panel.makeFirstResponder(field)
    }

    /// The first editable text field in a view tree (the result card's follow-up field), or nil.
    static func findEditableTextField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField, field.isEditable { return field }
        for subview in view.subviews {
            if let found = findEditableTextField(in: subview) { return found }
        }
        return nil
    }

    func runAIPreset(prompt: String, title: String, loadingMessage: String? = nil, inputText: String? = nil, onGeneratedTitle: ((String) -> Void)? = nil) {
        guard let context = currentActionContext else {
            Log.ai.error("Cannot run AI preset: currentActionContext is nil")
            return
        }
        activeStreamingTask?.cancel()
        activeStreamingTask = nil

        let selection = context.selection
        let selectionText = inputText ?? selection.text
        let originalForCard = inputText != nil ? (inputText!.isEmpty ? nil : inputText) : nil
        let overrideOriginal = inputText != nil
        let anchorFrame = panel?.frame ?? lastPopupFrame
        let targetCanPaste = PasteAvailability.effective(policy: selection.appPolicy, probe: modeStore.canPaste)

        hide()
        let session = aiSessionID

        toastController.showLoading(message: loadingMessage ?? String(localized: "Generating…"), anchorFrame: anchorFrame) { [weak self] in
            self?.cancelActiveTasks()
        }

        let task = Task { @MainActor in
            self.modeStore.isProcessingAI = true
            defer {
                if !Task.isCancelled {
                    self.activeStreamingTask = nil
                    self.modeStore.isProcessingAI = false
                }
            }

            var hasYielded = false
            var activeTitle = title

            do {
                let provider = AIServiceManager.shared.currentProvider

                var accumulated = ""

                for try await chunk in provider.processStream(prompt: prompt, text: selectionText) {
                    guard !Task.isCancelled, session == self.aiSessionID else {
                        self.toastController.hide()
                        return
                    }
                    accumulated += chunk
                    if let newTitle = AIRequestSupport.extractTitleText(accumulated), !newTitle.isEmpty {
                        activeTitle = newTitle
                        onGeneratedTitle?(newTitle)
                    }
                    let cleaned = AIRequestSupport.extractResultText(accumulated)
                    if !cleaned.isEmpty {
                        if !hasYielded {
                            hasYielded = true
                            self.toastController.hide()
                            let canPaste = targetCanPaste
                            guard !Task.isCancelled, session == self.aiSessionID else { return }
                            self.show(for: selection, pasteAvailable: canPaste, preservingSessionID: session, streamingTask: self.activeStreamingTask)
                        }
                        self.showResultCard(text: cleaned, isError: false, title: activeTitle, isStreaming: true, session: session, originalText: originalForCard, overrideOriginal: overrideOriginal)
                    }
                }

                guard !Task.isCancelled, session == self.aiSessionID else {
                    self.toastController.hide()
                    return
                }
                self.toastController.hide()
                if let newTitle = AIRequestSupport.extractTitleText(accumulated), !newTitle.isEmpty {
                    activeTitle = newTitle
                    onGeneratedTitle?(newTitle)
                }
                let finalResponse = AIRequestSupport.extractResultText(accumulated)
                if finalResponse.isEmpty {
                    if !hasYielded {
                        let canPaste = targetCanPaste
                        guard !Task.isCancelled, session == self.aiSessionID else { return }
                        self.show(for: selection, pasteAvailable: canPaste, preservingSessionID: session, streamingTask: self.activeStreamingTask)
                        self.showResultCard(text: "No response generated", isError: true, title: activeTitle, isStreaming: false, session: session, originalText: originalForCard, overrideOriginal: overrideOriginal)
                    }
                } else {
                    if !hasYielded {
                        let canPaste = targetCanPaste
                        guard !Task.isCancelled, session == self.aiSessionID else { return }
                        self.show(for: selection, pasteAvailable: canPaste, preservingSessionID: session, streamingTask: self.activeStreamingTask)
                    }
                    // A fresh run on the selection starts the card's session history; follow-ups
                    // (refineCard) extend it.
                    if inputText == nil {
                        self.cardConversation = AIConversation(original: selectionText, steps: [.init(instruction: prompt, result: finalResponse)])
                    } else {
                        self.cardConversation = AIConversation(original: finalResponse, steps: [.init(instruction: prompt, result: finalResponse)])
                    }
                    self.showResultCard(text: finalResponse, isError: false, title: activeTitle, isStreaming: false, session: session, originalText: originalForCard, overrideOriginal: overrideOriginal)
                }
            } catch is CancellationError {
                Log.ai.info("AI streaming cancelled")
                self.toastController.hide()
            } catch {
                guard !Task.isCancelled, session == self.aiSessionID else {
                    self.toastController.hide()
                    return
                }
                self.toastController.hide()
                Log.ai.error("AI preset execution failed: \(error.localizedDescription)")
                if !hasYielded {
                    let canPaste = targetCanPaste
                    guard !Task.isCancelled, session == self.aiSessionID else { return }
                    self.show(for: selection, pasteAvailable: canPaste, preservingSessionID: session, streamingTask: self.activeStreamingTask)
                }
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.showResultCard(text: message, isError: true, title: title, isStreaming: false, session: session, originalText: originalForCard, overrideOriginal: overrideOriginal)
            }
        }
        activeStreamingTask = task
    }
    
    /// Settable in `init` so the effect-delivery tests can inject a recording handler.
    var resultHandler: ActionResultHandler

    // MARK: - Decision 8: ActionResult Tree-Walk

    /// The inputs to the paste-vs-copy delivery decision, captured synchronously when an action
    /// performs — before `hide()` can clear the live context, and before any async probe await.
    /// `nil` (an explicit user request, e.g. the AI card's Paste/Copy buttons) means the result is never re-decided.
    struct DeliveryContext {
        let policy: AppPolicyContext
        let clickIntent: ActionResultDelivery.ClickIntent
        /// The action's declared delivery (secondary outcome + per-click toasts), snapshotted from
        /// the performing action right before the perform. `nil` means no declaration: the unified
        /// decision derives the secondary and default toasts exactly as before.
        let delivery: ActionDelivery?
        /// The target app the result will be delivered to. Captured synchronously with the other
        /// inputs: while the (non-activating) panel is up, the source app stays frontmost, and
        /// `exitKeyMode()` reactivates exactly this app on hide — so the snapshot is the same app
        /// `pasteProbe` must inspect, without reading frontmost state after hide or an await.
        let application: NSRunningApplication?
        /// The user's per-action override if one was configured in Action Editor.
        let userOverride: ResultDeliveryPreference?
        /// The author's recommended delivery mode.
        let recommendedResult: ActionResultDeliveryMode?
        /// The action's uncommitted output kind.
        let outputKind: ActionOutputKind?
        /// The performing action's title — the result card header. nil for explicit user requests.
        let actionTitle: String?
        /// The performing action's display icon (customization-resolved) — the result card header
        /// icon. Captured alongside `actionTitle` by the same perform paths.
        let actionIcon: ActionIcon?
        /// Input/destination requirements rechecked immediately before effects are executed.
        let inputRequirement: ActionInputRequirement?
        let requiresPasteTarget: Bool
        /// The selection context captured before any early-close (loading actions), used to re-show
        /// the popup as a preview card. nil when the popup never closed.
        let selection: SelectionContext?

        /// Resolves the effective result and consumed delivery context when a declared secondary
        /// is present on a secondary click. Consuming the declaration sets `clickIntent` to `.primary`
        /// and moves `secondaryToast` to `primaryToast` so explicit outcomes (e.g. a declared
        /// sequence containing `.paste`) are not downgraded by the secondary Clipboard Invariant.
        func consumeDeclaredSecondary(for result: ActionResult) -> (result: ActionResult, delivery: DeliveryContext) {
            guard clickIntent == .secondary, let declared = delivery?.secondary else {
                return (result, self)
            }
            let consumed = DeliveryContext(
                policy: policy,
                clickIntent: .primary,
                delivery: ActionDelivery(secondary: nil, primaryToast: delivery?.secondaryToast, secondaryToast: nil),
                application: application,
                userOverride: userOverride,
                recommendedResult: recommendedResult,
                outputKind: outputKind,
                actionTitle: actionTitle,
                actionIcon: actionIcon,
                inputRequirement: inputRequirement,
                requiresPasteTarget: requiresPasteTarget,
                selection: selection
            )
            return (declared, consumed)
        }
    }

    /// Snapshots the delivery inputs from the current session state. Called on the main actor,
    /// synchronously, before any dismissal or await, so the decision never depends on live state
    /// read after `hide()` or after the probe suspension.
    func deliverySnapshot(for action: (any Action)? = nil, clickIntent: ActionResultDelivery.ClickIntent? = nil) -> DeliveryContext {
        let intent = clickIntent ?? pendingClickIntent
        let actionDelivery = action?.delivery ?? pendingDelivery
        let title = action?.title ?? pendingActionTitle
        let icon = action?.displayIcon(using: ActionCustomizationManager.shared) ?? pendingActionIcon
        let actionID = action?.id ?? pendingActionID
        let targetApp = previousFrontmostApp ?? (frontmostApplicationProvider()?.bundleIdentifier != Bundle.main.bundleIdentifier ? frontmostApplicationProvider() : previousFrontmostApp)
        let override = actionID.flatMap { ActionCustomizationManager.shared.override(for: $0)?.deliveryPreference }
        let rec = action?.chrome.recommendedResult ?? pendingActionRecommendedResult
        let outKind = action?.chrome.outputKind ?? pendingActionOutputKind
        return DeliveryContext(
            policy: currentActionContext?.selection.appPolicy ?? .default,
            clickIntent: intent,
            delivery: actionDelivery,
            application: targetApp,
            userOverride: override,
            recommendedResult: rec,
            outputKind: outKind,
            actionTitle: title,
            actionIcon: icon,
            inputRequirement: (action as? any ActionWithRules).map { $0.rules?.requirements?.input ?? .text },
            requiresPasteTarget: (action as? any ActionWithRules)?.rules?.requirements?.requiresPasteTarget ?? false,
            selection: currentActionContext?.selection
        )
    }

    /// Checks if the target application is still the active frontmost application.
    /// If the user switched to a different application while an action was executing asynchronously,
    /// automated paste must not blindly post into the new foreground window.
    private func isTargetApplicationActive(_ targetApp: NSRunningApplication?) -> Bool {
        guard let targetApp else { return true }
        guard let frontmost = frontmostApplicationProvider() else { return true }
        if frontmost.bundleIdentifier == Bundle.main.bundleIdentifier {
            return true
        }
        return frontmost.processIdentifier == targetApp.processIdentifier
    }

    /// A declared paste-target requirement applies through result dispatch, including any async
    /// paste probe performed after the action returns.
    private func requiredPasteTargetIsActive(_ delivery: DeliveryContext?) -> Bool {
        guard let delivery, delivery.requiresPasteTarget else { return true }
        return isTargetApplicationActive(delivery.application)
    }

    /// Routes a performed result into the tree-walk, snapshotting the delivery inputs first.
    /// Decision 8: dismissal is decided once on the top-level result; the tree-walk never hides
    /// per-item. `hide()` runs before `handleActionResult` so `exitKeyMode()` reactivates the target
    /// source app before any synthetic keyboard events (.paste, .cut, etc.) are posted — and the
    /// delivery snapshot is taken before that `hide()` clears the live context. The declared
    /// delivery is single-use per perform: the snapshot is its only consumer, so it is cleared
    /// immediately after — a later `onResult` paste (completion buttons route here directly) must
    /// never reuse a prior action's declaration. Internal for tests.
    func deliverResult(_ result: ActionResult, delivery: DeliveryContext? = nil) {
        let resolvedDelivery = delivery ?? inFlightDeliveryContext ?? deliverySnapshot()
        inFlightDeliveryContext = nil
        pendingDelivery = nil
        pendingActionTitle = nil
        pendingActionIcon = nil
        pendingActionID = nil
        pendingActionRecommendedResult = nil
        pendingActionOutputKind = nil
        let (deliveredResult, effectiveDelivery) = resolvedDelivery.consumeDeclaredSecondary(for: result)
        let effectiveResult = normalizeResult(deliveredResult, delivery: effectiveDelivery)
        if shouldDismiss(effectiveResult, delivery: effectiveDelivery) {
            hide()
        }
        handleActionResult(effectiveResult, delivery: effectiveDelivery, suppressDeliveryToast: effectiveResult.containsToast)
    }

    /// Drops a result whose declared input or paste target no longer holds at delivery time.
    private func normalizeResult(_ result: ActionResult, delivery: DeliveryContext?) -> ActionResult {
        guard let delivery, delivery.inputRequirement != nil || delivery.requiresPasteTarget else { return result }

        let selection = delivery.selection
        let input = delivery.inputRequirement ?? .optional
        let hasText = !(selection?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let liveAndCurrent = selection?.source == .selection
            && isTargetApplicationActive(delivery.application)
        let inputSatisfied: Bool
        switch input {
        case .optional: inputSatisfied = true
        case .text: inputSatisfied = hasText
        case .liveSelection: inputSatisfied = hasText && liveAndCurrent
        case .editableSelection: inputSatisfied = hasText && liveAndCurrent && selection?.isEditable == true
        }
        let pasteTargetSatisfied = !delivery.requiresPasteTarget
            || (selection?.pasteTargetAvailable == true
                && PasteAvailability.effective(policy: delivery.policy, probe: selection?.pasteTargetAvailable) == true
                && isTargetApplicationActive(delivery.application))
        return inputSatisfied && pasteTargetSatisfied ? result : .none
    }

    /// Walks an ActionResult produced by a perform, rendering presentation results in the popup and
    /// routing leaf effects to the effect handler. Never hides the popup per-item — dismissal is
    /// decided once on the top-level result via `dismissesPopup`. `delivery` carries the captured
    /// paste-vs-copy inputs; `nil` means the result is an explicit user request never re-decided.
    /// `suppressDeliveryToast` is true when the top-level result contains a `.toast`: every effect's
    /// delivery companion toast is skipped so the script toast wins (one toast per run).
    /// A `.sequence` runs item N+1 only after item N completes (nested sequences recurse).
    @discardableResult
    func handleActionResult(_ result: ActionResult, delivery: DeliveryContext? = nil, suppressDeliveryToast: Bool = false) -> Task<Void, Never>? {
        let (selectedResult, effectiveDelivery) = delivery?.consumeDeclaredSecondary(for: result) ?? (result, delivery)
        let effectiveResult = normalizeResult(selectedResult, delivery: effectiveDelivery)
        let effectiveSuppressToast = suppressDeliveryToast || effectiveResult.containsToast
        switch effectiveResult {
        case .toast(let feedback):
            presentToast(feedback)
            return nil
        case .openConfiguration(let request):
            presentConfiguration(for: request)
            return nil
        case .sequence(let items):
            return Task { @MainActor in
                for item in items {
                    await self.handleActionResult(item, delivery: effectiveDelivery, suppressDeliveryToast: effectiveSuppressToast)?.value
                }
            }
        default:
            return handleEffect(effectiveResult, delivery: effectiveDelivery, suppressDeliveryToast: effectiveSuppressToast)
        }
    }

    /// Routes a leaf effect to DefaultActionResultHandler and surfaces any thrown error uniformly
    /// (decision 9): an error becomes a dismissing `.toast(.error)`. Returns the task
    /// so a caller can await the posted effect.
    ///
    /// Applies the standardized paste-vs-copy delivery decision (`.paste` → `.copy` when the click
    /// was a force-copy, the app policy forbids paste, or the target app can't Paste). Only leaf
    /// text results routed here are re-decided; explicit user requests (the AI card's Paste/Copy
    /// buttons) pass through untouched via a nil `delivery`.
    @discardableResult
    private func handleEffect(_ result: ActionResult, delivery: DeliveryContext?, suppressDeliveryToast: Bool = false) -> Task<Void, Never> {
        let effect = result
        return Task { @MainActor in
            do {
                let resolved = await resolveDelivery(effect, delivery: delivery, suppressDeliveryToast: suppressDeliveryToast)
                guard requiredPasteTargetIsActive(delivery) else { return }
                if case .text(let text) = resolved.result {
                    // Preview preference: render the returned text in the native AI result card
                    // without delivering any effect. The popup stays open (a top-level `.text` never
                    // dismisses via dismissesPopup); Esc collapses via exitContent. Probe paste
                    // availability when it was never probed (production passes the trigger-site probe
                    // answer into show(for:pasteAvailable:); nil here means it was skipped) so the
                    // card gates its Paste button on the real answer — an unknown probe answer still
                    // normalizes to cannot-paste (safe default).
                    if modeStore.canPaste == nil {
                        modeStore.canPaste = await pasteProbe.canPaste(in: delivery?.application, policy: delivery?.policy ?? .default) ?? false
                    }
                    showResultCard(text: text, isError: false, title: delivery?.actionTitle ?? "Action", icon: delivery?.actionIcon, session: aiSessionID, canFollowUp: false)
                    return
                }
                if case .file(let filePayload) = resolved.result {
                    showResultCard(
                        text: filePayload.displayName,
                        isError: false,
                        title: delivery?.actionTitle ?? filePayload.displayName,
                        icon: delivery?.actionIcon,
                        session: aiSessionID,
                        canFollowUp: false,
                        file: filePayload
                    )
                    return
                }
                try await resultHandler.handle(resolved.result, in: panel?.contentView, targetApp: delivery?.application)
                let toastToShow: StatusFeedback? = {
                    if let toast = resolved.toast {
                        if case .saveFile = resolved.result {
                            let saveDir = settingsStore.get(.fileSaveLocation)
                            let folderName = !saveDir.isEmpty ? URL(fileURLWithPath: (saveDir as NSString).expandingTildeInPath).lastPathComponent : "Downloads"
                            return StatusFeedback(message: String(localized: "Saved to \(folderName)"), style: .success, symbolName: "arrow.down.circle")
                        }
                        return toast
                    }
                    if delivery == nil {
                        switch resolved.result {
                        case .saveFile:
                            let saveDir = settingsStore.get(.fileSaveLocation)
                            let folderName = !saveDir.isEmpty ? URL(fileURLWithPath: (saveDir as NSString).expandingTildeInPath).lastPathComponent : "Downloads"
                            return StatusFeedback(message: String(localized: "Saved to \(folderName)"), style: .success, symbolName: "arrow.down.circle")
                        case .copyFile:
                            return StatusFeedback(message: String(localized: "Copied File"), style: .success, symbolName: "doc.on.doc")
                        default:
                            return nil
                        }
                    }
                    return nil
                }()
                if let toast = toastToShow, !suppressDeliveryToast {
                    toastController.show(toast, anchorFrame: panel?.frame ?? lastPopupFrame)
                }
            } catch {
                handleActionResult(.toast(StatusFeedback(error: error)))
            }
        }
    }

    /// Decides how a text result should be delivered, per the standardized rule, and which
    /// companion toast (if any) surfaces. The click intent, app policy, and the action's declared
    /// delivery come from the snapshot, never from live state read after an await. A nil `delivery`
    /// (an explicit user request, e.g. the AI card's Paste/Copy buttons) passes the result through
    /// untouched with no toast. Only a `.paste` outcome can be downgraded to `.copy`, so the paste
    /// probe runs only when a paste outcome is actually on the table (the raw result is a paste, or
    /// a declared secondary is a paste); the declared secondary and per-click toasts still apply to
    /// any result.
    internal private(set) var lastDeliveryStatus: SelectionReadStatus?

    private func resolveDelivery(_ result: ActionResult, delivery: DeliveryContext?, suppressDeliveryToast: Bool = false) async -> (result: ActionResult, toast: StatusFeedback?) {
        guard let delivery else { return (result, nil) }
        let selected = ActionResultDelivery.select(
            raw: result,
            clickIntent: delivery.clickIntent,
            delivery: delivery.delivery ?? .none,
            preference: delivery.userOverride,
            recommendedResult: delivery.recommendedResult,
            outputKind: delivery.outputKind
        )
        let couldPaste = isPaste(selected)
        let isTargetActive = isTargetApplicationActive(delivery.application)
        var canPaste: Bool
        if !couldPaste || !isTargetActive {
            canPaste = false
        } else if !PasteAvailability.needsProbe(policy: delivery.policy) {
            canPaste = PasteAvailability.effective(policy: delivery.policy, probe: nil) ?? false
        } else {
            canPaste = await pasteProbe.canPaste(in: delivery.application, policy: delivery.policy) ?? false
        }
        // A target may change while the AX paste probe is suspended.
        if couldPaste, !isTargetApplicationActive(delivery.application) {
            canPaste = false
        }
        if couldPaste, !isTargetActive || !isTargetApplicationActive(delivery.application) {
            lastDeliveryStatus = .targetChanged
            Log.selection.debug("delivery outcome: targetChanged")
        } else {
            lastDeliveryStatus = nil
        }
        let resolved = ActionResultDelivery.resolve(
            raw: result,
            clickIntent: delivery.clickIntent,
            canPaste: canPaste,
            delivery: delivery.delivery ?? .none,
            preference: delivery.userOverride,
            recommendedResult: delivery.recommendedResult,
            outputKind: delivery.outputKind
        )
        return (resolved.result, suppressDeliveryToast ? nil : resolved.toast)
    }

    private func isPaste(_ result: ActionResult?) -> Bool {
        guard let result else { return false }
        switch result {
        case .paste, .pasteContent:
            return true
        default:
            return false
        }
    }

    private func isText(_ result: ActionResult) -> Bool {
        guard case .text = result else { return false }
        return true
    }

    /// Dismissal for a top-level result: the popup stays open exactly when the actual *resolved*
    /// outcome is `.text` (preview) or `.file` and dismisses otherwise. Mirroring the resolver's Select step
    /// synchronously (before the delivery task runs) keeps dismissal consistent with the delivered
    /// outcome: a declared secondary beats the picker, so a `.text` raw result whose declared
    /// secondary dismisses still dismisses. `canPaste` is irrelevant here — every probe outcome
    /// (an honored paste or a downgraded copy) dismisses.
    private func shouldDismiss(_ result: ActionResult, delivery: DeliveryContext) -> Bool {
        let (effectiveResult, effectiveDelivery) = delivery.consumeDeclaredSecondary(for: result)
        let resolved = ActionResultDelivery.resolve(
            raw: effectiveResult,
            clickIntent: effectiveDelivery.clickIntent,
            canPaste: false,
            delivery: effectiveDelivery.delivery ?? .none,
            preference: effectiveDelivery.userOverride,
            recommendedResult: effectiveDelivery.recommendedResult,
            outputKind: effectiveDelivery.outputKind
        ).result
        if isText(resolved) { return false }
        if case .file = resolved { return false }
        return resolved.dismissesPopup
    }

    /// Runs a leaf action from a per-action global hotkey. Reuses the on-screen session when the
    /// popup is already up; otherwise opens on the retrieved selection so paste/preview still have
    /// a delivery context, then performs.
    func runBoundAction(_ action: any Action, with context: ActionContext, pasteAvailable: Bool? = nil) {
        guard canPerformAction(action, in: context) else { return }
        if panel?.isVisible != true {
            show(for: context.selection, pasteAvailable: pasteAvailable)
        } else if let pasteAvailable {
            modeStore.canPaste = pasteAvailable
        }
        if ActionIdentity.isAIPreset(action) {
            guard let preset = AIServiceManager.shared.preset(forActionID: action.id) else { return }
            runAIPreset(prompt: AIServiceManager.shared.promptForPreset(preset), title: preset.title)
            return
        }
        runAction(action, with: context, isSecondaryClick: false)
    }

    /// Shared perform-time gate for UI clicks, group actions, and bound hotkeys. Visibility is
    /// recomputed from the captured context, while source-bound requirements also verify that the
    /// target application still matches immediately before run.
    private func canPerformAction(_ action: any Action, in context: ActionContext) -> Bool {
        guard action.isEnabled(for: context) else { return false }
        guard let ruledAction = action as? any ActionWithRules else { return true }
        let requirements = ruledAction.rules?.requirements ?? ActionRequirements()
        let selection = context.selection
        let liveAndCurrent = selection.source == .selection
            && isTargetApplicationActive(previousFrontmostApp)
        switch requirements.input {
        case .optional, .text:
            break
        case .liveSelection:
            guard liveAndCurrent else { return false }
        case .editableSelection:
            guard liveAndCurrent, selection.isEditable == true else { return false }
        }
        if requirements.requiresPasteTarget {
            guard context.pasteTargetAvailable == true,
                  PasteAvailability.effective(policy: selection.appPolicy, probe: context.pasteTargetAvailable) == true,
                  isTargetApplicationActive(previousFrontmostApp) else { return false }
        }
        return true
    }

    /// Performs an action directly (per-action hotkeys, which the palette's SwiftUI Button never
    /// fires) and routes its result through the standard dismissal + tree-walk, recording usage.
    /// Mirrors the left-click perform path in PopupView. The delivery context is built here from
    /// `isSecondaryClick`, so the decision never depends on live state read after the perform await.
    /// Internal for tests (mirrors `runLoadingAction`).
    func runAction(_ action: any Action, with context: ActionContext, isSecondaryClick: Bool) {
        guard canPerformAction(action, in: context) else { return }
        if action.chrome.showsLoading {
            runLoadingAction(action, with: context, isSecondaryClick: isSecondaryClick)
            return
        }
        let clickIntent: ActionResultDelivery.ClickIntent = isSecondaryClick ? .secondary : .primary
        pendingClickIntent = clickIntent
        // The declared delivery + title are snapshotted into the DeliveryContext below — this
        // perform path's only consumer. Unlike the palette path, no `onWillPerformAction`
        // precedes it, so `pendingDelivery`/`pendingActionTitle` must stay untouched: a later
        // `deliverResult` (e.g. a completion-paste from a preview card) must never reuse this
        // perform's declaration.
        let delivery = deliverySnapshot(for: action, clickIntent: clickIntent)
        inFlightDeliveryContext = delivery
        usageStore.record(action.id)
        let match = action.matchInfo(for: context)
        let performContext = ActionContext(
            selection: context.selection,
            modifiers: context.modifiers,
            isSecondaryClick: isSecondaryClick,
            match: match
        )
        Task { @MainActor in
            do {
                let result: ActionResult
                if action.chrome.isInlineResult,
                   let inFlightTask = InlineResultEvaluator.shared.runningTask(for: action.id, sessionID: self.aiSessionID) {
                    if let text = await inFlightTask.value {
                        result = .text(text)
                    } else {
                        result = try await action.perform(performContext)
                    }
                } else if action.chrome.isInlineResult, let cached = self.modeStore.inlineResults[action.id] {
                    result = .text(cached)
                } else {
                    result = try await action.perform(performContext)
                }
                let (effectiveResult, effectiveDelivery) = delivery.consumeDeclaredSecondary(for: result)
                if self.shouldDismiss(effectiveResult, delivery: effectiveDelivery) {
                    self.hide()
                }
                self.handleActionResult(effectiveResult, delivery: effectiveDelivery, suppressDeliveryToast: effectiveResult.containsToast)
                self.inFlightDeliveryContext = nil
            } catch {
                Log.presentation.error("Action failed (id \(action.id, privacy: .public)): \(error.localizedDescription)")
                self.handleActionResult(.toast(StatusFeedback(error: error)))
                self.inFlightDeliveryContext = nil
            }
        }
    }

    /// Performs a `showsLoading` action with early-close: the popup hides immediately, a spinner
    /// toast attaches to the popup's last frame, and the result settles the toast (swap to
    /// description, or fade when the result carries none). Mirrors runAction's delivery snapshot:
    /// captured before the early hide so paste-vs-copy still sees the pre-dismissal context.
    /// Internal for tests.
    func runLoadingAction(_ action: any Action, with context: ActionContext, isSecondaryClick: Bool) {
        guard canPerformAction(action, in: context) else { return }
        let clickIntent: ActionResultDelivery.ClickIntent = isSecondaryClick ? .secondary : .primary
        pendingClickIntent = clickIntent
        // The declared delivery + title are snapshotted into the DeliveryContext below — this
        // perform path's only consumer. Unlike the palette path, no `onWillPerformAction`
        // precedes it, so `pendingDelivery`/`pendingActionTitle` must stay untouched: a later
        // `deliverResult` must never reuse this perform's declaration.
        let delivery = deliverySnapshot(for: action, clickIntent: clickIntent)
        inFlightDeliveryContext = delivery
        usageStore.record(action.id)
        let match = action.matchInfo(for: context)
        let performContext = ActionContext(
            selection: context.selection,
            modifiers: context.modifiers,
            isSecondaryClick: isSecondaryClick,
            match: match
        )
        // Capture before the early hide so the spinner attaches to where the popup actually was.
        let anchorFrame = panel?.frame ?? lastPopupFrame
        hide()
        let message = action.chrome.loadingMessage ?? String(localized: "Opening \(action.title)…")
        toastController.showLoading(message: message, anchorFrame: anchorFrame) { [weak self] in
            self?.cancelActiveTasks()
        }
        let runID = UUID()
        activeLoadingID = runID
        let loadingTask = Task { @MainActor in
            defer {
                if self.activeLoadingID == runID {
                    self.activeLoadingTask = nil
                    self.activeLoadingID = nil
                }
            }
            do {
                let result = try await action.perform(performContext)
                guard !Task.isCancelled else {
                    self.toastController.hide()
                    return
                }
                let (effectiveResult, effectiveDelivery) = delivery.consumeDeclaredSecondary(for: result)
                await self.settleLoadingResult(effectiveResult, delivery: effectiveDelivery, suppressDeliveryToast: effectiveResult.containsToast)
            } catch is CancellationError {
                Log.presentation.info("Loading action cancelled (id \(action.id, privacy: .public))")
                self.toastController.hide()
            } catch {
                guard !Task.isCancelled else {
                    self.toastController.hide()
                    return
                }
                Log.presentation.error("Action failed (id \(action.id, privacy: .public)): \(error.localizedDescription)")
                await self.settleLoadingResult(.toast(StatusFeedback(error: error)), delivery: delivery)
            }
        }
        activeLoadingTask = loadingTask
    }

    /// Resolves a loading action's result into the toast: `.toast` swaps to that status,
    /// a delivered result's companion toast (a paste→copy downgrade's "Copied", a declared per-click
    /// toast) swaps in, and everything else (`.success`, `.openURL`, honored paste, native copy)
    /// fades the spinner. When `suppressDeliveryToast` is true (the top-level result already carries
    /// a `.toast`), the delivery companion is skipped and whatever toast is showing is left alone —
    /// the script toast item in the tree presents itself, one toast per run.
    private func settleLoadingResult(_ result: ActionResult, delivery: DeliveryContext, suppressDeliveryToast: Bool = false) async {
        let (selectedResult, effectiveDelivery) = delivery.consumeDeclaredSecondary(for: result)
        let effectiveResult = normalizeResult(selectedResult, delivery: effectiveDelivery)
        let effectiveSuppressToast = suppressDeliveryToast || effectiveResult.containsToast
        switch effectiveResult {
        case .toast(var feedback):
            feedback.keepVisible = false
            toastController.show(feedback)
        case .openConfiguration(let request):
            toastController.hide()
            presentConfiguration(for: request)
        case .sequence(let items):
            for item in items { await settleLoadingResult(item, delivery: effectiveDelivery, suppressDeliveryToast: effectiveSuppressToast) }
        default:
            let effect = effectiveResult
            do {
                let resolved = await resolveDelivery(effect, delivery: effectiveDelivery, suppressDeliveryToast: effectiveSuppressToast)
                guard requiredPasteTargetIsActive(effectiveDelivery) else {
                    toastController.hide()
                    return
                }
                if case .text(let text) = resolved.result {
                    // Preview preference on a loading action: the popup early-closed for the spinner,
                    // so hide the spinner and re-show the popup as a content-mode card, anchored to
                    // the original selection (captured before the early close). Re-probe so the card
                    // gates its Paste button on the real answer.
                    toastController.hide()
                    if let selection = effectiveDelivery.selection {
                        let canPaste = await pasteProbe.canPaste(in: effectiveDelivery.application, policy: effectiveDelivery.policy) ?? false
                        guard requiredPasteTargetIsActive(effectiveDelivery) else {
                            toastController.hide()
                            return
                        }
                        show(for: selection, pasteAvailable: canPaste)
                        showResultCard(text: text, isError: false, title: effectiveDelivery.actionTitle ?? "Action", icon: effectiveDelivery.actionIcon, session: aiSessionID, canFollowUp: false)
                    }
                    return
                }
                if case .file(let filePayload) = resolved.result {
                    toastController.hide()
                    if let selection = effectiveDelivery.selection {
                        let canPaste = await pasteProbe.canPaste(in: effectiveDelivery.application, policy: effectiveDelivery.policy) ?? false
                        show(for: selection, pasteAvailable: canPaste)
                        showResultCard(
                            text: filePayload.displayName,
                            isError: false,
                            title: effectiveDelivery.actionTitle ?? filePayload.displayName,
                            icon: effectiveDelivery.actionIcon,
                            session: aiSessionID,
                            canFollowUp: false,
                            file: filePayload
                        )
                    }
                    return
                }
                try await resultHandler.handle(resolved.result, in: panel?.contentView)
                let toastToShow: StatusFeedback? = {
                    if let toast = resolved.toast {
                        if case .saveFile = resolved.result {
                            let saveDir = settingsStore.get(.fileSaveLocation)
                            let folderName = !saveDir.isEmpty ? URL(fileURLWithPath: (saveDir as NSString).expandingTildeInPath).lastPathComponent : "Downloads"
                            return StatusFeedback(message: String(localized: "Saved to \(folderName)"), style: .success, symbolName: "arrow.down.circle")
                        }
                        return toast
                    }
                    return nil
                }()
                if let toast = toastToShow, !effectiveSuppressToast {
                    toastController.swapTo(toast)
                } else if !effectiveSuppressToast {
                    toastController.hide()
                }
            } catch {
                await settleLoadingResult(.toast(StatusFeedback(error: error)), delivery: effectiveDelivery)
            }
        }
    }

    /// Feedback lives in its own window; the action panel never grows or shrinks for it.
    func updateToastPlacement() {
        guard toastController.isShowing, toastController.currentPlacement != .overlay, let panel else { return }
        toastController.reposition(anchorFrame: panel.frame)
    }

    /// Shows feedback near an explicit point, or tied to the popup when there is none.
    public func showToast(_ feedback: StatusFeedback, at point: CGPoint? = nil) {
        let placement = point.map { ToastPlacement.nearCursor($0) }
        toastController.show(feedback, anchorFrame: panel?.frame ?? lastPopupFrame, placement: placement)
    }

    /// Status feedback uses its own cursor-relative window even after the popup has hidden.
    private func presentToast(_ feedback: StatusFeedback) {
        showToast(feedback)
    }

    /// Decision 8 config-open path: the popup has already hidden (`.openConfiguration` dismisses it);
    /// post the configuration notification so the Preferences host presents the action's
    /// ActionEditorPage (StatusBarController opens Preferences and drives the sheet).
    private func presentConfiguration(for request: ConfigurationRequest) {
        NotificationCenter.default.post(
            name: .openClipOpenActionConfiguration,
            object: nil,
            userInfo: ["request": request]
        )
    }
}
