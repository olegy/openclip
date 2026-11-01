// PopupView.swift
// OpenClip
//
// The popup panel's root view: the command palette, replaced by the native result card while an
// action's result is on screen (`PopupModeStore.mode`).
import SwiftUI
import AppKit
import Core

@MainActor
public struct PopupView: View {
    public let context: ActionContext
    private let alternateSearchContext: SelectionContext?
    private let onSearchContextChanged: (@MainActor (SelectionContext) -> Void)?
    public let onResult: @MainActor (ActionResult) -> Void
    public let onContentSizeChange: (@MainActor (CGSize) -> Void)?
    /// Leaves the palette (Esc): the controller hides the popup.
    private let onExitSearch: @MainActor () -> Void
    /// The result card's Back: the controller reopens the palette on the same input.
    public let onExitContent: @MainActor () -> Void
    /// The result card's Close / Esc: the popup goes away.
    public let onDismissContent: @MainActor () -> Void
    /// Called as the result card or search header is dragged, so the controller can move the panel.
    public let onCardDrag: (@MainActor (ResultCardDragPhase) -> Void)?
    /// Called as a resize handle of the result card is dragged, so the controller can resize the
    /// surface (and the panel around it) and remember the size.
    public let onResize: (@MainActor (PopupResizeEdge, ResultCardDragPhase) -> Void)?
    /// Called when the user taps the pin button on the result card. The controller reacts by
    /// setting `hasUserMovedCard = true` (making the card modal) and toggling `modeStore.isCardPinned`.
    public let onPinCard: (@MainActor () -> Void)?
    /// The result card's Paste/Copy/Save buttons — explicit user requests routed through the
    /// controller's keep-open card-effect door (bypasses the paste-vs-copy re-decision).
    public let onCardEffect: @MainActor (ActionResult) -> Void
    /// Called when an action is actually run, so the controller can record usage.
    public let onActionPerformed: (@MainActor (String) -> Void)?
    /// Called right before an action performs (before `onResult` can fire), so the controller can
    /// snapshot the action's declared delivery for the paste-vs-copy decision. The intent is
    /// carried explicitly so the delivery snapshot matches the perform context.
    public let onWillPerformAction: (@MainActor (any Action, ActionResultDelivery.ClickIntent) -> Bool)?
    /// Called when a `showsLoading` action runs: the controller early-closes the popup and runs
    /// the action via the loading toast flow. Carries the same explicit intent as
    /// `onWillPerformAction`.
    public let onRunLoadingAction: (@MainActor (any Action, ActionResultDelivery.ClickIntent) -> Void)?
    /// Called when an AI preset action is run: the controller closes the popup and runs via the
    /// loading toast flow.
    public let onRunAI: (@MainActor (String) -> Void)?
    /// Runs a palette instruction (the "Ask AI" row or a recent prompt) on the selection:
    /// `(instruction, replace, includeContext)` — paste the answer over the selection, or show the
    /// result card.
    public let onRunAIPrompt: (@MainActor (String, Bool, Bool) -> Void)?
    /// Saves the palette's typed query as a reusable AI tool and runs it (the "Save as AI tool"
    /// row), same flag.
    public let onSaveAIPrompt: (@MainActor (String, Bool) -> Void)?
    /// Runs an instruction typed into the result card's follow-up field on the card's current
    /// text (the controller re-streams the card in place). nil hides the field.
    public let onFollowUp: (@MainActor (String) -> Void)?
    /// Cancels a follow-up in flight (Esc while the card refines), keeping the previous answer.
    public let onCancelFollowUp: (@MainActor () -> Void)?
    /// Returns the click intent captured at mouse-down for the current click, so the left-click
    /// perform path can thread a force-copy click (⇧-click) into the action context.
    public let onClickIntent: @MainActor () -> ActionResultDelivery.ClickIntent

    @Setting(SettingKey.popupThemeColor) private var themeColor
    @Environment(\.colorScheme) private var colorScheme

    /// Resolves user-customized action titles/icons (composition-injected, defaults to the shared
    /// customization manager — never a hidden singleton reference inside the Action extension).
    private let presenter: any ActionPresenting
    /// The palette/card state, owned by PopupWindowController.
    @ObservedObject private var modeStore: PopupModeStore

    /// The color scheme the popup content should render as — matching the effective theme
    /// so `.primary`/`.secondary` agree with the
    /// chosen appearance even when the system is the opposite.
    private var effectiveColorScheme: ColorScheme {
        PopupThemeModel.effectiveScheme(appearance: themeColor, systemIsDark: colorScheme == .dark)
    }

    private var effectiveTheme: String {
        return PopupThemeModel.classicToken(appearance: themeColor, systemIsDark: colorScheme == .dark)
    }

    @MainActor
    public init(
        settingsStore: SettingsStore = DefaultSettingsStore.shared,
        context: ActionContext,
        alternateSearchContext: SelectionContext? = nil,
        onSearchContextChanged: (@MainActor (SelectionContext) -> Void)? = nil,
        presenter: any ActionPresenting = ActionCustomizationManager.shared,
        modeStore: PopupModeStore = PopupModeStore(),
        onExitSearch: @escaping @MainActor () -> Void = {},
        onExitContent: @escaping @MainActor () -> Void = {},
        onDismissContent: @escaping @MainActor () -> Void = {},
        onCardDrag: (@MainActor (ResultCardDragPhase) -> Void)? = nil,
        onResize: (@MainActor (PopupResizeEdge, ResultCardDragPhase) -> Void)? = nil,
        onPinCard: (@MainActor () -> Void)? = nil,
        onCardEffect: @escaping @MainActor (ActionResult) -> Void = { _ in },
        onResult: @escaping @MainActor (ActionResult) -> Void,
        onContentSizeChange: (@MainActor (CGSize) -> Void)? = nil,
        onActionPerformed: (@MainActor (String) -> Void)? = nil,
        onWillPerformAction: (@MainActor (any Action, ActionResultDelivery.ClickIntent) -> Bool)? = nil,
        onRunLoadingAction: (@MainActor (any Action, ActionResultDelivery.ClickIntent) -> Void)? = nil,
        onRunAI: (@MainActor (String) -> Void)? = nil,
        onRunAIPrompt: (@MainActor (String, Bool, Bool) -> Void)? = nil,
        onSaveAIPrompt: (@MainActor (String, Bool) -> Void)? = nil,
        onFollowUp: (@MainActor (String) -> Void)? = nil,
        onCancelFollowUp: (@MainActor () -> Void)? = nil,
        onClickIntent: @escaping @MainActor () -> ActionResultDelivery.ClickIntent = { .primary }
    ) {
        _themeColor = Setting(SettingKey.popupThemeColor, store: settingsStore)
        self.context = context
        self.alternateSearchContext = alternateSearchContext
        self.onSearchContextChanged = onSearchContextChanged
        self.presenter = presenter
        self._modeStore = ObservedObject(wrappedValue: modeStore)
        self.onExitSearch = onExitSearch
        self.onExitContent = onExitContent
        self.onDismissContent = onDismissContent
        self.onCardDrag = onCardDrag
        self.onResize = onResize
        self.onPinCard = onPinCard
        self.onCardEffect = onCardEffect
        self.onResult = onResult
        self.onContentSizeChange = onContentSizeChange
        self.onActionPerformed = onActionPerformed
        self.onWillPerformAction = onWillPerformAction
        self.onRunLoadingAction = onRunLoadingAction
        self.onRunAI = onRunAI
        self.onRunAIPrompt = onRunAIPrompt
        self.onSaveAIPrompt = onSaveAIPrompt
        self.onFollowUp = onFollowUp
        self.onCancelFollowUp = onCancelFollowUp
        self.onClickIntent = onClickIntent
    }

    public var body: some View {
        content
            .environment(\.colorScheme, effectiveColorScheme)
            .environment(\.popupEffectiveTheme, effectiveTheme)
            .coordinateSpace(name: "popupHoverSpace")
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: PopupContentSizePreferenceKey.self, value: proxy.size)
                }
            )
            .onPreferenceChange(PopupContentSizePreferenceKey.self) { size in
                MainActor.assumeIsolated {
                    guard size.width > 0, size.height > 0 else { return }
                    onContentSizeChange?(size)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if modeStore.mode == .content, let payload = modeStore.resultCard {
            resultCard(payload)
        } else {
            searchCard
        }
    }

    /// The result card. Paste/Copy/Save are explicit user requests routed through onCardEffect
    /// (bypassing the paste-vs-copy re-decision); the Paste button is hidden when the target app
    /// can't paste. Back reopens the palette, Close / Esc dismiss the popup.
    private func resultCard(_ payload: ResultCardPayload) -> some View {
        ResultCardView(
            payload: payload,
            canPaste: modeStore.canPaste,
            maxSize: modeStore.resultCardSize,
            isUserSized: modeStore.isSurfaceUserSized,
            isPinned: modeStore.isCardPinned,
            onExit: { onExitContent() },
            onDismiss: { onDismissContent() },
            onPaste: {
                if let file = payload.file {
                    onCardEffect(.saveFile(file.url))
                } else {
                    onCardEffect(.paste(payload.text))
                }
            },
            onCopy: {
                if let file = payload.file {
                    onCardEffect(.copyFile(file.url))
                } else {
                    onCardEffect(.copy(payload.text))
                }
            },
            onSave: {
                if let file = payload.file {
                    onCardEffect(.saveFile(file.url))
                }
            },
            onDrag: { phase in onCardDrag?(phase) },
            onResize: { edge, phase in onResize?(edge, phase) },
            onPin: { onPinCard?() },
            onFollowUp: onFollowUp.map { run in { instruction in run(instruction) } },
            onCancelFollowUp: onCancelFollowUp
        )
    }

    /// The command palette.
    private var searchCard: some View {
        PopupSearchView(
            catalog: searchCatalog,
            context: context,
            alternateContext: alternateSearchContext,
            onContextChanged: onSearchContextChanged,
            presenter: presenter,
            modeStore: modeStore,
            usageRecency: ActionUsageStore.shared.recency,
            onResult: onResult,
            onExit: onExitSearch,
            onDrag: { phase in onCardDrag?(phase) },
            onRunAI: { actionID in runAIAction(actionID) },
            onRunAIPrompt: { instruction, replace, includeContext in
                // The controller's flow snapshots the selection and dismisses the popup itself,
                // so the palette must not exit first.
                onRunAIPrompt?(instruction, replace, includeContext)
            },
            onSaveAIPrompt: { instruction, replace in onSaveAIPrompt?(instruction, replace) },
            onActionPerformed: onActionPerformed,
            onWillPerformAction: onWillPerformAction,
            onRunLoadingAction: onRunLoadingAction,
            onClickIntent: onClickIntent
        )
    }

    private var searchCatalog: [any Action] {
        ActionCoordinator.shared.searchCatalog(for: context)
    }

    /// Records the run, then hands the preset to the controller, which snapshots the selection
    /// before dismissing the popup.
    func runAIAction(_ actionID: String) {
        onActionPerformed?(actionID)
        onRunAI?(actionID)
    }
}
