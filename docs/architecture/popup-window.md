# Floating Popup Panel Architecture

The popup is a single floating panel that shows the **command palette** and, while an action's result is on screen, the **native result card** in its place. It consists of `PopupPanel` (an `NSPanel` subclass), the Spotlight-style frame math in `PopupPositioner`, SwiftUI rendering in `PopupView` / `PopupSearchView` / `ResultCardView`, shared state in `PopupModeStore`, and lifecycle coordination in `PopupWindowController`. Status feedback is a separate floating toast (`ToastPanelController`).

---

## Window Components

```
+-----------------------------------------------------------------------------+
| PopupWindowController                                                       |
| ├── PopupPanel (NSPanel, non-activating, borderless, popUpMenu level)       |
| │   └── PopupPanel.ContentView (NSHostingView<PopupView>)                   |
| │       ├── PopupSearchView  (PopupMode.search — the command palette)       |
| │       └── ResultCardView   (PopupMode.content — the result card)          |
| ├── Event monitors (global / local NSEvent) + workspace notifications       |
| └── ToastPanelController (status toast, its own panel outside the popup)    |
+-----------------------------------------------------------------------------+
```

### 1. [`PopupPanel`](../../Sources/OpenClip/UI/Popup/PopupPanel.swift)
- **Window style**: `.nonactivatingPanel`, `.borderless`, `.fullSizeContentView`; level `.popUpMenu`; joins all Spaces and fullscreen apps (`.canJoinAllSpaces`, `.fullScreenAuxiliary`).
- **Key window**: `PopupPanel.allowsKey` gates `canBecomeKey`/`canBecomeMain`. It is set while the palette or the card shows, so the search field and the card can receive typing. Because the panel is non-activating, it becomes key without activating OpenClip; the source app stays active.
- **Properties**: `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = true`: the system draws the drop shadow around the card, so the window frame is exactly the card with no transparent margin (window-border utilities see its real edge). `PopupPanel.ContentView.layout()` calls `invalidateShadow()` so the shadow follows mode and size changes.
- **Click-through**: while the pointer is outside the panel, `updatePopupHover` sets `panel.ignoresMouseEvents = true`, so a click outside reaches the app underneath and dismisses the popup. The ignore toggle needs the global monitor (Accessibility); without it, dismissal still works through `isOverPanelContent`.
- **Resize funnel**: every frame change goes through `setFrame`, which clamps the width to the screen and the height to `heightCap`, keeps the top edge fixed on a content-driven size change, and, while `recentersOnResize` is set, keeps the panel centered on its current `midX` when its width changes. A user drag (`prepareForUserDrag`) turns re-centering off for the rest of the session.

### 2. [`PopupWindowController`](../../Sources/OpenClip/UI/Popup/PopupWindowController.swift)
- **Responsibility**: window creation, `show(for:pasteAvailable:)` / `hide()`, the `.search` ↔ `.content` switch, event monitoring, hover, drag and resize of the card, and result delivery (`deliverResult` → `handleActionResult` / `handleEffect`).
- **Entry points**: `HotkeyManager` calls `show(for:pasteAvailable:)` after reading the selection (see [Text Selection](text-selection.md)); a second palette hotkey press calls `toggleMode()`, which hides a visible popup. Per-action hotkeys call `runBoundAction`.
- **Event monitors**: global and local `NSEvent` monitors for `.leftMouseDown`, `.rightMouseDown`, `.rightMouseUp`, `.mouseMoved` and `.keyDown`, plus notifications for app deactivation, panel resigning key, app activation, Space changes and Settings opening.
- **Dismissal**: a click outside the panel content, the panel resigning key, another app activating (after the `PopupMetrics.focusSwitchGracePeriod` of 0.3 s, which ignores queued activations from clipboard managers) or a Space change hides the popup. A result card the user dragged or pinned (`cardIsModal`) survives outside clicks and focus changes until Copy, Paste, Close or Esc; a Space change still hides it.
- **Key mode**: `enterKeyMode()` captures `previousFrontmostApp` once per session, sets `allowsKey` and makes the panel key; `exitKeyMode()` clears `allowsKey` and re-activates `previousFrontmostApp`. Only `hide()` clears `previousFrontmostApp`. The search field gets focus on the next run-loop turn (`focusSearchField()`), because a focus request before the panel is key is dropped.

### 3. [`PopupModeStore`](../../Sources/OpenClip/UI/Popup/PopupModeStore.swift)
Observable state shared by the controller and `PopupView`: `mode` (`PopupMode.search` / `.content`), the card payload `resultCard` (`ResultCardPayload`), `resultCardSize` / `isSurfaceUserSized`, `canPaste`, `isProcessingAI`, `isCardPinned`, and `inlineResults` (inline previews keyed by action ID).

### 4. Hover
`PopupHoverState.shared` (`PopupHoverSupport.swift`) holds the pointer location fed by the controller's monitors. `PopupPanel.ContentView` adds an `.activeAlways` tracking area so hover keeps working while OpenClip is inactive (for example over another app's fullscreen Space), where neither monitor nor SwiftUI `.onHover` delivers moves.

---

## Placement: [`PopupPositioner`](../../Sources/OpenClip/UI/Popup/PopupPositioner.swift)

`PopupPositioner` is a pure static struct:

- `screen(containing:)` picks the screen with the mouse (2 pt inclusive margin).
- `spotlightFrame(size:in:)` centers the panel horizontally on that screen's visible frame, with its center `spotlightLift` (10 %) of the screen height above the middle, clamped inside the bounds.

`show(for:)` places the palette through `placeSpotlight`, which suspends `recentersOnResize` for the move (otherwise `setFrame` would keep the previous frame's `midX`), then re-arms it so later width changes keep the panel centered. The palette is 680 × 414 pt (`PopupMetrics.searchPanelContentWidth` × `searchPaletteMinHeight`). The result card opens at the same size and frame.

---

## Command Palette (`PopupSearchView`)

- **Catalog**: `ActionCoordinator.searchCatalog` → `ActionRegistry.searchCatalog` lists what can run now. Actions switched off in settings are absent (per action, per package, a disabled group's members, AI presets whose toggle is off or with AI disabled). Context gating drops the rest: `isEnabled(for:)`, and actions with `ActionChrome.requiresLiveSelection` when the input is not a live selection. `ActionSearch` ranks by alias, then prefix, contains and keyword matches, with usage recency from `ActionUsageStore`.
- **Paste gating**: the trigger starts `preparePasteProbe(for:policy:)` alongside the selection read and passes the result to `show(for:pasteAvailable:)`, which stores `modeStore.canPaste` before the first frame. The value is the unified `PasteAvailability` answer: the per-app `denyPaste` rule overrides the live AX probe. `false` hides the card's Paste button; `nil` keeps it.
- **Rows**: icons render `[icon | text]` (`ActionCustomizationManager.tableIcon`). The trailing side (`PaletteRowAccessories`) shows the alias, the action's hotkey and the ⌘-digit hint, each only when set. An inline result (`InlineResultEvaluator`, actions with `chrome.isInlineResult`) covers them until ⌘ is held, up to `PopupMetrics.inlineSearchAccessoryMaxWidth` (240 pt).
- **Text source**: when the palette opens on a selection and the clipboard holds different text, the clipboard is offered as an alternate source (`alternateClipboardSearchContext`). Tab or the footer's `PaletteSourceFooter` switch toggles between them; the footer also shows the start of the active text ("No text" when empty). Copied Finder files are not clipboard text (`HotkeyManager.clipboardHoldsFiles`).
- **Keys**: arrows move the selection, ⏎ runs the selected row, ⇧⏎ runs it as a copy/replace (secondary intent), Esc closes the palette. ⌘1…⌘9 run the first nine rows; they are global hot keys (`PaletteRowShortcuts`) active only while the palette is visible, since a non-activating panel does not receive command-modified keys. Opening Settings (⌘,) closes the palette first (`preferencesWindowWillShow`), so the source app does not come back over Settings.
- **AI rows**: with AI enabled, a query that matches nothing offers **Ask AI** and **Save as AI tool** rows (`PaletteAIPrompt`). ⏎ shows the answer in the result card (`runAIPrompt` → `runAIPreset`); ⇧⏎ pastes it over the selection (`runAIPromptReplacing`), downgraded to a copy when pasting is not possible or the source app is no longer frontmost. Save stores the instruction as a custom `AIActionPreset` and runs it.
- **Click intent**: the mouse monitor records `pendingClickIntent` at mouse-down (right-click or ⇧-click = secondary). The palette passes its intent explicitly through `onWillPerformAction` / `onRunLoadingAction`, so the perform context (`ActionContext.isSecondaryClick`) and the delivery decision (`DeliveryContext.clickIntent`) agree.
- **Loading actions**: `showsLoading` actions (manifest `"loading"`) close the popup and run under a cancellable spinner toast (`runLoadingAction`); a text result re-opens the popup on the result card (`settleLoadingResult`).

---

## Result Card (`ResultCardView`, `PopupMode.content`)

Any action whose outcome is text or a file renders in the card, inside the same panel. AI presets stream into it; extension results land through the delivery snapshot in `handleEffect`. `showResultCard` sets `modeStore.resultCard` (`ResultCardPayload { text, isError, title, icon, isStreaming, original, canFollowUp, file }`), places the card at the palette's size and frame, switches to `.content` and enters key mode. Deliveries are stamped with the AI session (`aiSessionID`), so a chunk from a stream abandoned by `hide()` is dropped.

- **Header**: back chevron (`exitContent()` reopens the palette on the same input), the action's icon and title, an optional diff toggle, a pin button, and close (`✕`, also Esc → `hide()`). Dragging the header moves the panel (`handleCardDrag`, computed from the absolute cursor position against the anchor taken at `.began`); the search header has the same drag strip. Dragging or pinning sets `hasUserMovedCard`, which makes the card modal.
- **Footer**: Copy and Paste route through `onCardEffect` → `performCardEffect`, an explicit request that bypasses the paste-vs-copy re-decision; both close the popup. ⏎ pastes (copies when pasting is unavailable), ⇧⏎ copies, ⌘D toggles the diff. Error cards show Dismiss.
- **Diff**: `Core/Utils/TextDiff.swift` diffs `original` → `text` per grapheme cluster (Myers, bounded by `maxComparableLength` and `maxEditDistance`). The toggle only appears for in-place edits (`TextDiff.isMeaningfulEdit(from:to:)`), never while streaming.
- **Follow-up**: the card's instruction field (`ResultCardView.followUpField`) refines the answer in place (`runFollowUp` → `refineCard`): the previous answer stays dimmed until the first chunk, the size is frozen (`freezeCardSizeForRefinement`), and `cardConversation` carries the earlier steps as context. Esc cancels a refinement in flight (`cancelFollowUp`) and keeps the previous answer.
- **Files**: a `.file(FileOutputPayload)` result previews by `FileOutputKind` — images (SVG via SDWebImageSVGCoder), PDFs (`FilePreviews/PDFPreviewView.swift`), text up to 100 KB, and Quick Look for the rest, with a generic icon card as the fallback. Copy File (⌘C) and Save (⏎ / ⌘S, to `SettingKey.fileSaveLocation`, default `~/Downloads`) act on it.
- **Resize**: the right edge, bottom edge and corner are `PopupResizeHandles` (SwiftUI drag gestures, since the borderless panel has no AppKit resize edges) reporting to `handleResize`. `PopupResizeGeometry` computes and clamps the size against `aiCardMinWidth` × `aiCardMinHeight` and the screen, keeping the top-left corner fixed; the size lasts until the card closes.

---

## Toasts ([`ToastPanelController`](../../Sources/OpenClip/UI/Popup/ToastPanelController.swift))

Every `StatusFeedback` renders as a one-line toast in its own `ToastPanel` (`ToastView`), independent of the popup. A toast tied to the popup centers on the popup's last frame (`lastPopupFrame`); without one it shows near the cursor. Info and error toasts auto-dismiss after `PopupMetrics.toastDurationNanoseconds` (1.2 s) unless `keepVisible`; hovering pauses the countdown. Loading toasts have no timer and are swapped (`swapTo`) for the settled status. The paste→copy downgrade shows "Copied", or the action's declared `primaryToast` / `secondaryToast`. The toast size follows the "Notification Size" setting in General → Appearance.
