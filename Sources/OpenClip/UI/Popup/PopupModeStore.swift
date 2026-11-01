// PopupModeStore.swift
// OpenClip
//
// Shared observable state for the popup: what it shows (the command palette or the native result
// card) and the payloads those screens render. Statuses render as a floating toast via
// ToastPanelController, not through the store. PopupView observes the store injected by
// PopupWindowController.
import Foundation
import Combine
import Core

@MainActor
public final class PopupModeStore: ObservableObject {
    /// What the popup shows: the command palette or the native result card.
    @Published public var mode: PopupMode = .search
    /// The native result card currently shown (only meaningful while `mode == .content`). Any
    /// action whose resolved outcome is text renders here, not just AI presets.
    @Published public var resultCard: ResultCardPayload? = nil
    /// The result card's size: the palette's size when the card opens, updated live while a resize
    /// handle is dragged; `nil` means the default maximum. Cleared whenever the card leaves the
    /// screen.
    @Published public var resultCardSize: CGSize? = nil
    /// True once the user has dragged a resize handle of the surface on screen. From then on the
    /// surface keeps the dragged size verbatim — any size they want, whatever its content does —
    /// for the rest of its session. Cleared when the surface closes, so the next one opens
    /// content-fitted up to the remembered maximum.
    @Published public var isSurfaceUserSized: Bool = false
    /// Whether the target app can Paste, probed (AX) when the popup shows. `false` hides the
    /// card's Paste button and the palette's Paste + Cut actions; `nil` (unknown/probing) and
    /// `true` keep them visible.
    @Published public var canPaste: Bool? = nil
    /// True while an asynchronous AI action is executing.
    @Published public var isProcessingAI: Bool = false
    /// True once the user has explicitly pinned the result card via the pin button. When `true`
    /// the card behaves as modal (auto-dismiss suppressed), mirroring `hasUserMovedCard` in the
    /// controller. Cleared by `hide()` and `exitContent()`.
    @Published public var isCardPinned: Bool = false
    /// Computed inline results for actions with `chrome.isInlineResult == true`, keyed by action ID.
    @Published public var inlineResults: [String: String] = [:]

    public init() {}
}

/// The payload of the native result card: the action's response text, whether it is an
/// error message (drives the card's styling), the producing action's title and icon, and
/// streaming state. `icon` is nil for AI streaming deliveries, which fall back to the
/// card's sparkles glyph. `original` is the text the action was run on (the selection), kept so
/// the card can show a character-level diff of what the action changed; nil when there is
/// nothing to compare against.
public struct ResultCardPayload: Sendable, Equatable {
    public let text: String
    public let isError: Bool
    public let title: String
    public let icon: ActionIcon?
    public let isStreaming: Bool
    public let original: String?
    /// True while a follow-up is in flight and no chunk has arrived yet: `text` is still the
    /// previous answer, shown dimmed under the field's spinner so the card never goes blank.
    public let isRefining: Bool
    /// True when the result supports AI follow-up refinement (AI results). False for extension/script results.
    public let canFollowUp: Bool
    /// Native file output payload when the result is a file.
    public let file: FileOutputPayload?

    /// Creates the content presented by a result card, including an optional native file.
    public init(text: String, isError: Bool, title: String = String(localized: "AI Tools"), icon: ActionIcon? = nil, isStreaming: Bool = false, original: String? = nil, isRefining: Bool = false, canFollowUp: Bool = true, file: FileOutputPayload? = nil) {
        self.text = text
        self.isError = isError
        self.title = title
        self.icon = icon
        self.isStreaming = isStreaming
        self.original = original
        self.isRefining = isRefining
        self.canFollowUp = canFollowUp
        self.file = file
    }
}
