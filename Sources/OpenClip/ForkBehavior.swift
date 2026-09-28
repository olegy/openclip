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

    /// Upstream's menu bar menu offers "Pause in <App>" and a timed "Pause" submenu, which made
    /// sense for the automatic popup. The fork only acts when you press the hotkey, so both are
    /// hidden. Pausing itself still works: "Resume OpenClip" still appears while a pause set
    /// earlier or via `openclip://command/pause` is active, and per-app rules stay in Settings.
    static let pauseMenuItems = false

    /// Upstream's menu bar menu links "Report Issue…" to upstream's issue tracker. The fork hides
    /// it there; Settings → About still has it.
    static let reportIssueMenuItem = false

    /// Upstream's palette footer counts the matching actions. The fork shows where the text
    /// comes from instead — a selection/clipboard switch (Tab toggles it when both were read) —
    /// and the start of that text (`PaletteSourceFooter`).
    static let paletteSourceFooter = true

    /// Upstream's palette row ends with a ⌘-digit hint (first nine rows). The fork shows the
    /// action's alias and its hotkey from Settings in front of it — alias → hotkey → ⌘N, each
    /// only when set (`PaletteRowAccessories`). An inline preview still covers them until ⌘ is
    /// held, and is twice as wide (`PopupMetrics.inlineSearchAccessoryMaxWidth`).
    static let paletteRowAccessories = true

    /// Upstream sends the palette hotkey's synthetic ⌘C whenever AX has no selected text. Editors
    /// such as Obsidian then copy the whole current line, which the palette takes for the
    /// selection. The fork sends no ⌘C when the focused text control reports a collapsed caret
    /// (`CollapsedCaretProbe`), so the palette falls through to the clipboard.
    static let collapsedCaretSkipsCopy = true
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
