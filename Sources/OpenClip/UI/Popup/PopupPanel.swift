// PopupPanel.swift
// OpenClip
//
// Defines a custom floating, non-activating NSPanel for the command palette and the result card.
// The panel stays non-key by default (rule #9); `allowsKey` is enabled while it shows so the
// search field / card component can receive typing.
// Also re-anchors content-driven window growth: the top edge stays fixed, and when
// `recentersOnResize` is set a width change keeps the panel centered on its current center.
import AppKit
import SwiftUI
import Core

@MainActor
public class PopupPanel: NSPanel {
    /// When true the panel may become the key/main window (while the palette or result card shows).
    public var allowsKey: Bool = false
    /// Height cap `setFrame` applies to every frame request; the controller sets it to the height
    /// of the screen the popup shows on.
    public var heightCap: CGFloat = .greatestFiniteMagnitude
    /// When true, a width change keeps the panel centered on its current center. Off for a fresh
    /// placement and once the user drags the panel.
    public var recentersOnResize: Bool = false

    /// True for the duration of a user drag of the panel (result card or search header). The controller's
    /// hover tracking stops toggling `ignoresMouseEvents` while it is set: a fast drag can take the
    /// cursor outside the panel, and making the panel ignore mouse events
    /// mid-drag would strand it under the pointer.
    public private(set) var isUserDragging = false

    public init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.level = .popUpMenu
        // Explicitly eligible to join another app's fullscreen Space (macOS 13+).
        self.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        self.backgroundColor = .clear
        self.isOpaque = false
        // The system draws the drop shadow around the card's alpha. The window frame is exactly the
        // card, so nothing transparent sits around it (window-border tools and the like see the
        // card's real edge).
        self.hasShadow = true
        self.acceptsMouseMovedEvents = true
        self.isMovable = true    // borderless; SwiftUI header gestures move the panel
    }

    /// Opens a user drag of the panel (the result card or search header). The move itself is driven
    /// by `PopupWindowController.handleCardDrag` — AppKit's own `performDrag` is unreachable here,
    /// since `NSHostingView` answers `hitTest` for the whole card and never lets an AppKit handle
    /// see the `mouseDown`. The user placing the panel deliberately outranks automatic placement,
    /// so re-centering on width changes is switched off for the rest of the session (`hide()`
    /// resets the anchor).
    public func prepareForUserDrag() {
        recentersOnResize = false
        isUserDragging = true
    }

    public func endUserDrag() {
        isUserDragging = false
    }

    override public var canBecomeKey: Bool { allowsKey }
    override public var canBecomeMain: Bool { allowsKey }

    /// Root content view of the popup panel; it also keeps the system shadow in step with the
    /// content, since the shadow is cached until the window is told its shape changed.
    public final class ContentView: NSHostingView<PopupView> {
        private var trackingAreaRef: NSTrackingArea?

        /// Hover tracking for the case the event monitors cannot cover: while OpenClip is inactive
        /// (notably with the popup floating over *another* app's fullscreen Space) neither the global
        /// monitor (own-window events are not "global") nor the local monitor (the app is not active
        /// and the panel is not key) delivers `mouseMoved`, and SwiftUI `.onHover` does not fire for
        /// an inactive non-key window either. An `.activeAlways` tracking area still delivers
        /// moved/entered/exited to the view, so the controller routes these into the same hover
        /// pipeline and hover comes back. Enter/exit also route here: a SwiftUI relayout can remove and
        /// re-add the tracking area, emitting a spurious exit while the cursor is still on the popup,
        /// so the controller must recompute from the live pointer rather than blind-clear.
        /// Click-through toggling is skipped on this path (see `handleTrackingMouseMoved`) because
        /// there is no monitor to notice re-entry.
        var onMouseMoved: (() -> Void)?

        public override func layout() {
            super.layout()
            window?.invalidateShadow()
        }

        public override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let existing = trackingAreaRef {
                removeTrackingArea(existing)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.cursorUpdate, .activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            self.trackingAreaRef = area
        }

        public override func cursorUpdate(with event: NSEvent) {
            NSCursor.arrow.set()
        }

        public override func mouseEntered(with event: NSEvent) {
            super.mouseEntered(with: event)
            NSCursor.arrow.set()
            onMouseMoved?()
        }

        public override func mouseMoved(with event: NSEvent) {
            super.mouseMoved(with: event)
            onMouseMoved?()
        }

        public override func mouseExited(with event: NSEvent) {
            super.mouseExited(with: event)
            onMouseMoved?()
        }

        public override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(bounds, cursor: .arrow)
        }
    }

    /// The hosting view auto-resizes the panel window top-anchored when its SwiftUI content grows
    /// (e.g. the result card replacing the palette), with no callback to the controller — but
    /// every resize funnels through `setFrame`, so intercept here, clamp maximum width/height
    /// bounds, and pin the anchored edge(s) before the frame is displayed. Pure origin moves (repositioning) and the
    /// first placement (zero-sized frame) pass through untouched.
    override public func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var clamped = frameRect
        let heightWasClamped = clamped.size.height > heightCap
        let activeScreenFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame
        if let screenFrame = activeScreenFrame {
            let maxWidth = max(0, screenFrame.width - PopupMetrics.popupPadding * 2)
            clamped.size.width = min(clamped.size.width, maxWidth)
        }
        clamped.size.height = min(clamped.size.height, heightCap)

        // If height clamping altered the requested height, adjust origin.y to preserve the requested frame's top edge (maxY)
        if clamped.height != frameRect.height {
            clamped.origin.y = frameRect.maxY - clamped.height
        }

        if self.frame.width > 0, recentersOnResize, clamped.width != self.frame.width {
            let unconstrainedX = self.frame.midX - clamped.width / 2

            if let screenFrame = activeScreenFrame {
                let padding = PopupMetrics.popupPadding
                let minX = screenFrame.minX + padding
                let maxX = screenFrame.maxX - clamped.width - padding
                if maxX >= minX {
                    clamped.origin.x = max(minX, min(unconstrainedX, maxX))
                } else {
                    clamped.origin.x = minX
                }
            } else {
                clamped.origin.x = unconstrainedX
            }
        }

        // Keep the top edge whenever the request changed the panel size OR was height-clamped. A
        // clamped request reaches this block with clamped.height == frame.height (the panel already
        // grew to the cap), yet its top-anchored origin still encodes the un-clamped height —
        // without re-anchoring, the clamped-off delta leaks into the origin and the top edge drifts.
        let sizeChangedOrClamped = frame.height > 0 && recentersOnResize
            && (clamped.height != frame.height || heightWasClamped)
        if sizeChangedOrClamped {
            clamped.origin.y = frame.maxY - clamped.height
        }

        super.setFrame(clamped, display: flag)
    }
}
