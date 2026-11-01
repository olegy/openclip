// PopupMetrics.swift
// OpenClip
//
// UI-facing layout and timing constants for the floating popup panel: the command palette, the
// result card and toasts. These are presentation concerns — they live in the App target (not `Core`) so
// `Sources/Core/` stays free of UI vocabulary. The popup panel and every view that sizes the
// popup reads from here.
import CoreGraphics
import Foundation
import SwiftUI
import AppKit

public enum PopupMetrics {
    /// Cross-fade duration (seconds) between a palette row's accessories and its inline result.
    /// Benchmark (Tier 1 p95=0.01ms, Tier 2 p50=12.9ms): perceptual floor of 0.20s
    /// plus 2× Tier 2 p50 → 0.046s raw; rounded up to 0.05s, then bumped to 0.22s so
    /// results arriving from async Tier 3 don't snap in harshly. (was 0.18s)
    public static let inlineCrossFadeDuration: Double = 0.22

    /// Resolved spring animation or immediate cut respecting macOS Reduce Motion accessibility setting.
    public static func springOrImmediate(response: Double = 0.28, dampingFraction: Double = 0.8) -> Animation {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            return .linear(duration: 0.05)
        }
        return .spring(response: response, dampingFraction: dampingFraction)
    }

    /// Hard execution timeout for inline action evaluation.
    /// Benchmark (Tier 3 heavy JS p99=737ms × 1.20 safety = 884ms → ceil 0.90s).
    /// Previous 0.50s cut off heavy JS at the p50; 0.90s covers p99 with margin. (was 0.50s)
    public static let inlineEvaluationTimeout: TimeInterval = 0.90
    /// Maximum width (pt) for the trailing inline accessory in the search palette.
    public static let inlineSearchAccessoryMaxWidth: CGFloat = 240.0
    /// Corner radius for modal result cards and the action-search palette.
    public static let cardCornerRadius: CGFloat = 16.0
    /// Corner radius for the action-search palette; equal to the card radius so both match the radius of a plain macOS window (16 pt).
    public static let searchCornerRadius: CGFloat = 16.0
    /// Corner radius for individual search palette result rows.
    public static let searchRowCornerRadius: CGFloat = 10.0
    /// Shared radius for footer controls in the search palette and result card.
    public static let footerButtonCornerRadius: CGFloat = 10.0
    /// Corner radius for floating toast bubbles.
    public static let toastCornerRadius: CGFloat = 14.0
    /// Maximum character length displayed in floating toast bubbles before truncating with an ellipsis.
    public static let toastMaxCharacterLength: Int = 40
    /// Prefer clearing the popup above, without moving feedback far past a tall card.
    public static let toastPreferredAboveDistance: CGFloat = 140.0
    public static let popupPadding: CGFloat = 8.0
    /// Action-search palette sizing: content width, visible result rows and result row height.
    public static let searchPanelContentWidth: CGFloat = 680.0
    public static let searchMaxRows: Int = 6
    public static let searchResultRowHeight: CGFloat = 30
    /// Smallest width the palette allows; matches the default content width.
    public static let searchPaletteMinWidth: CGFloat = searchPanelContentWidth
    /// The minimum wins over `PopupSearchView.defaultHeight`, so this is the palette's height; the
    /// result card takes the same size (`PopupWindowController.showResultCard`).
    public static let searchPaletteMinHeight: CGFloat = 414.0
    /// Native result card sizing. The content-driven default is `aiCardIdealWidth` wide and
    /// between `aiCardMinHeight` and `aiCardMaxHeight` tall, so a long response scrolls instead of
    /// growing the panel without bound. The card's right/bottom resize handles can take it past
    /// the maximums (up to the screen, see `PopupResizeGeometry`) but never below the
    /// minimums.
    public static let aiCardMinWidth: CGFloat = 220
    public static let aiCardIdealWidth: CGFloat = 320
    public static let aiCardMinHeight: CGFloat = 200
    public static let aiCardMaxHeight: CGFloat = 280
    /// How long an info/error toast stays up before auto-dismissing (1.2 s — long enough to read
    /// "Copied"-style feedback). Loading toasts have no timer — they live until the action's
    /// result lands.
    public static let toastDurationNanoseconds: UInt64 = 1_200_000_000
    /// How long after a session starts an app-activation notification does not dismiss the popup.
    /// macOS can deliver a queued activation for the destination app just after the popup opens —
    /// common when a clipboard manager dismisses itself. A later activation is a real focus switch.
    public static let focusSwitchGracePeriod: TimeInterval = 0.3

    /// Converts a 1...5 discrete scale level to a visual scaling multiplier.
    /// Level 3 is the normal default (1.0).
    public static func scaleMultiplier(for level: Int) -> CGFloat {
        switch level {
        case 1: return 0.85
        case 2: return 0.925
        case 3: return 1.00
        case 4: return 1.10
        case 5: return 1.22
        default: return 1.00
        }
    }
}
