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
}
