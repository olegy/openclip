import XCTest
@testable import OpenClip
@testable import Core

/// Fork guards: behavior this fork deliberately turns off must stay off.
@MainActor
final class ForkBehaviorTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run { TestIsolation.reset() }
    }

    /// Nothing may read the selection until a hotkey fires: passive monitoring is off, and the
    /// "Appear Automatically" menu item that only configured it is hidden.
    func testPassiveSelectionMonitoringIsOffAndItsMenuItemHidden() {
        XCTAssertFalse(ForkBehavior.passiveSelectionMonitoring)

        let store = MemorySettingsStore()
        store.set(.showMenuBarIcon, value: true)
        store.set(.isAppEnabled, value: false)
        let controller = StatusBarController(settingsStore: store)
        XCTAssertEqual(controller.toggleEnabledItem?.isHidden, true)
    }

    /// The hotkey is pressed on purpose, so the menu bar menu offers no "Pause in <App>" or timed
    /// "Pause" items. "Resume OpenClip" still appears while a pause is active.
    func testPauseMenuItemsAreHiddenButResumeStillShows() throws {
        XCTAssertFalse(ForkBehavior.pauseMenuItems)

        let store = MemorySettingsStore()
        store.set(.showMenuBarIcon, value: true)
        let controller = StatusBarController(settingsStore: store)
        controller.currentTargetApp = NSRunningApplication.current
        controller.updateRootMenuDynamicItems()
        XCTAssertEqual(controller.pauseAppItem?.isHidden, true)
        let pauseSubmenu = try XCTUnwrap(controller.pauseSubmenu)
        let pauseParent = controller.pauseAppItem?.menu?.items.first { $0.submenu === pauseSubmenu }
        XCTAssertEqual(pauseParent?.isHidden, true)

        store.set(.pauseUntilTimestamp, value: Date().timeIntervalSince1970 + 1800)
        controller.updateRootMenuDynamicItems()
        XCTAssertEqual(controller.resumeItem?.isHidden, false)
    }

    /// "Report Issue…" leads to upstream's tracker, so the menu bar menu hides it (Settings →
    /// About keeps it), and no empty section is left behind it.
    func testReportIssueMenuItemIsHidden() throws {
        XCTAssertFalse(ForkBehavior.reportIssueMenuItem)

        let store = MemorySettingsStore()
        store.set(.showMenuBarIcon, value: true)
        let controller = StatusBarController(settingsStore: store)
        let menu = try XCTUnwrap(controller.pauseAppItem?.menu)
        let reportItem = try XCTUnwrap(menu.items.first { $0.title.hasPrefix("Report Issue") })
        XCTAssertTrue(reportItem.isHidden)

        let visible = menu.items.filter { !$0.isHidden }
        XCTAssertFalse(visible.first?.isSeparatorItem ?? true)
        XCTAssertFalse(visible.last?.isSeparatorItem ?? true)
        for (above, below) in zip(visible, visible.dropFirst()) {
            XCTAssertFalse(above.isSeparatorItem && below.isSeparatorItem, "adjacent visible separators")
        }
    }

    /// An AI or loading result re-shows the popup as a bar at the cursor before its card appears.
    /// The card must still land Spotlight-style at the palette's size — `PopupPanel`'s center
    /// anchor used to keep the bar's midX, so the card opened off-center near the cursor.
    func testResultCardOpenedFromTheBarIsCenteredAtThePaletteSize() throws {
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
        controller.show(for: context, initialMode: .actions)

        controller.showResultCard(text: "result", isError: false, title: "AI", session: controller.aiSessionID)

        let frame = try XCTUnwrap(controller.panel?.frame)
        let inset = 2 * PopupMetrics.popupShadowInset
        let expected = PopupPositioner.spotlightFrame(
            size: CGSize(width: PopupMetrics.searchPanelContentWidth + inset,
                         height: PopupMetrics.searchPaletteMinHeight + inset),
            in: screenBounds
        )
        XCTAssertEqual(frame.midX, expected.midX, accuracy: 1)
        XCTAssertEqual(frame.maxY, expected.maxY, accuracy: 1)
        XCTAssertEqual(controller.modeStore.resultCardSize,
                       CGSize(width: PopupMetrics.searchPanelContentWidth, height: PopupMetrics.searchPaletteMinHeight))
    }
}
