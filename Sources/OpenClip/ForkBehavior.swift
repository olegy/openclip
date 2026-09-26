// ForkBehavior.swift
// OpenClip
//
// Behavior switches where this fork departs from upstream. Keeping them in one place lets the
// fork turn upstream features off without deleting their code, so upstream changes still merge.
import SwiftUI

enum ForkBehavior {
    /// Upstream watches every mouse/keyboard selection in the background (`MacSelectionMonitor`)
    /// to show the action bar and keep a selection cache warm. The fork does nothing until a
    /// hotkey fires — `HotkeyManager` reads the selection on demand — so the monitor is never
    /// started, and the settings that only configure it ("Appear Automatically", "Hold Mouse to
    /// Trigger", the per-app "Hotkey Only" rule) are hidden.
    static let passiveSelectionMonitoring = false

    /// Upstream anchors the search palette and the result card on the cursor, and the card sizes
    /// itself to its text. The fork opens both Spotlight-style — centered, a little above the
    /// middle of the screen with the mouse — and gives the card the palette's size. The loading
    /// toast centers on the palette's frame, so it follows.
    static let spotlightPlacement = true
}

extension View {
    /// Removes an upstream control from the layout when the fork has turned its feature off.
    @ViewBuilder
    func hiddenInFork(_ hidden: Bool) -> some View {
        if hidden {
            EmptyView()
        } else {
            self
        }
    }
}
