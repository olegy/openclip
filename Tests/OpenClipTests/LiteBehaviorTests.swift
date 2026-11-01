import XCTest
@testable import OpenClip
@testable import Core

/// OpenClip Lite guards: the palette-only behavior the app is built around.
@MainActor
final class LiteBehaviorTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run { TestIsolation.reset() }
    }

    /// The menu bar menu has no pause, "Appear Automatically", Capture Text or "Report Issue…"
    /// items, and hidden items leave no empty section.
    func testMenuBarMenuOffersOnlyNavigationUpdatesAndQuit() throws {
        let store = MemorySettingsStore()
        store.set(.showMenuBarIcon, value: true)
        let controller = StatusBarController(settingsStore: store)
        let menu = try XCTUnwrap(controller.rootMenu)
        for title in ["Report Issue", "Pause", "Resume", "Appear Automatically", "Capture Text"] {
            XCTAssertNil(menu.items.first { $0.title.hasPrefix(title) }, title)
        }

        let visible = menu.items.filter { !$0.isHidden }
        XCTAssertFalse(visible.first?.isSeparatorItem ?? true)
        XCTAssertFalse(visible.last?.isSeparatorItem ?? true)
        for (above, below) in zip(visible, visible.dropFirst()) {
            XCTAssertFalse(above.isSeparatorItem && below.isSeparatorItem, "adjacent visible separators")
        }
    }

    /// The result card replaces the palette Spotlight-style, at the palette's size, wherever the
    /// cursor was.
    func testResultCardIsCenteredAtThePaletteSize() throws {
        let screenBounds = try XCTUnwrap(NSScreen.main?.visibleFrame)
        let controller = PopupWindowController(settingsStore: MemorySettingsStore())
        defer { controller.hide() }
        let context = SelectionContext(
            text: "hello",
            sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"),
            cursorPosition: CGPoint(x: screenBounds.minX + 60, y: screenBounds.minY + 60),
            timestamp: Date(),
            appPolicy: .default
        )
        controller.show(for: context)

        controller.showResultCard(text: "result", isError: false, title: "AI", session: controller.aiSessionID)

        let frame = try XCTUnwrap(controller.panel?.frame)
        let expected = PopupPositioner.spotlightFrame(
            size: CGSize(width: PopupMetrics.searchPanelContentWidth,
                         height: PopupMetrics.searchPaletteMinHeight),
            in: screenBounds
        )
        XCTAssertEqual(frame.midX, expected.midX, accuracy: 1)
        XCTAssertEqual(frame.maxY, expected.maxY, accuracy: 1)
        XCTAssertEqual(controller.modeStore.resultCardSize,
                       CGSize(width: PopupMetrics.searchPanelContentWidth, height: PopupMetrics.searchPaletteMinHeight))
    }

    /// The palette opens Spotlight-style, away from the pointer, so a toast tied to the popup
    /// centers on the popup's frame; explicit placements stay.
    func testToastTiedToThePopupCentersOnItsFrame() {
        let toast = ToastPanelController(cursorLocation: { CGPoint(x: 5, y: 5) })
        defer { toast.hide() }
        let palette = CGRect(x: 400, y: 300, width: 700, height: 430)

        toast.showLoading(message: "Generating…", anchorFrame: palette)
        XCTAssertEqual(toast.currentPlacement, .overlay)
        toast.swapTo(StatusFeedback(message: "Done", style: .success))
        XCTAssertEqual(toast.currentPlacement, .overlay)

        toast.show(StatusFeedback(message: "Copied", style: .success), anchorFrame: palette,
                   placement: .nearCursor(CGPoint(x: 5, y: 5)))
        XCTAssertEqual(toast.currentPlacement, .nearCursor(CGPoint(x: 5, y: 5)))
    }

    /// A caret with nothing selected in a text control sends no ⌘C: editors such as Obsidian
    /// would copy the whole current line. Anything else — a selection, a non-text element, or
    /// no range at all — keeps the copy fallback.
    func testCollapsedCaretInTextControlSkipsCopy() {
        let caret = CFRange(location: 617, length: 0)
        XCTAssertTrue(CollapsedCaretProbe.isCollapsedCaret(role: "AXTextArea", selectedRange: caret, selectedText: ""))
        XCTAssertTrue(CollapsedCaretProbe.isCollapsedCaret(role: "AXTextField", selectedRange: caret, selectedText: nil))

        XCTAssertFalse(CollapsedCaretProbe.isCollapsedCaret(
            role: "AXTextArea", selectedRange: CFRange(location: 379, length: 8), selectedText: "dropdown"))
        XCTAssertFalse(CollapsedCaretProbe.isCollapsedCaret(role: "AXTextArea", selectedRange: caret, selectedText: "stale"))
        XCTAssertFalse(CollapsedCaretProbe.isCollapsedCaret(role: "AXTextArea", selectedRange: nil, selectedText: nil))
        XCTAssertFalse(CollapsedCaretProbe.isCollapsedCaret(role: "AXGroup", selectedRange: caret, selectedText: nil))
        XCTAssertFalse(CollapsedCaretProbe.isCollapsedCaret(role: nil, selectedRange: caret, selectedText: nil))
    }
}
