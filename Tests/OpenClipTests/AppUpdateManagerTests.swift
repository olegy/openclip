import XCTest
import AppKit
@testable import OpenClip
@testable import Core

@MainActor
final class AppUpdateManagerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TestIsolation.reset()
        AppUpdateManager.shared.setUpdateReminderForTesting(false)
    }

    override func tearDown() {
        AppUpdateManager.shared.setUpdateReminderForTesting(false)
        super.tearDown()
    }

    /// Guard: the build ships Lite's own appcast and Ed25519 key, never upstream's — with those,
    /// Sparkle would replace this build with an upstream release.
    func testBuildShipsLiteUpdateFeedNotUpstreams() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
                       "https://github.com/olegy/openclip/releases/latest/download/appcast.xml")
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        XCTAssertFalse(key?.isEmpty ?? true)
        XCTAssertNotEqual(key, "JbyKx5LUkYkM+ovsJ1NPDR2W+1ptfdsu6b51KBsKhWo=", "upstream's update key")
        XCTAssertTrue(AppUpdateManager.isEnabled)
        XCTAssertEqual(AppUpdateManager.defaultFeedURL, Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String)
    }

    /// Sparkle checks on its own once a day but never downloads or installs without the user.
    func testSparkleChecksDailyAndNeverInstallsOnItsOwn() {
        let info = Bundle.main.infoDictionary ?? [:]
        XCTAssertEqual(info["SUEnableAutomaticChecks"] as? Bool, true)
        XCTAssertEqual(info["SUScheduledCheckInterval"] as? Int, 86400)
        XCTAssertEqual(info["SUAutomaticallyUpdate"] as? Bool, false)
        XCTAssertEqual(info["SUAllowsAutomaticUpdates"] as? Bool, false)
    }

    /// The test host is the Debug build (com.olegy.openclip.dev), which never updates itself; only
    /// the Release bundle does.
    func testOnlyReleaseBundleUpdates() {
        XCTAssertFalse(AppUpdateManager.shared.updatesEnabled)
        XCTAssertFalse(AppUpdateManager.shared.canPresentUpdate)
        XCTAssertTrue(AppUpdateManager(bundleIdentifier: "com.olegy.openclip", hasUpdateFeed: true).updatesEnabled)
        XCTAssertFalse(AppUpdateManager(bundleIdentifier: "com.olegy.openclip", hasUpdateFeed: false).updatesEnabled)
        XCTAssertFalse(AppUpdateManager.supportsUpdates(bundleIdentifier: "com.olegy.openclip.dev"))
        XCTAssertFalse(AppUpdateManager.supportsUpdates(bundleIdentifier: nil))
    }

    func testDevelopmentBuildCannotStartUpdate() {
        let manager = AppUpdateManager(bundleIdentifier: "com.olegy.openclip.dev")
        manager.checkForUpdates()
        XCTAssertFalse(manager.canPresentUpdate)
        XCTAssertFalse(manager.canCheckForUpdates)
    }

    /// A scheduled check shows the menu bar dot until the user looks at the update; a check the
    /// user started does not.
    func testScheduledUpdateRemindsUntilSessionEnds() {
        let manager = AppUpdateManager(bundleIdentifier: "test")
        manager.handleUpdatePresentation(showsWindow: false, userInitiated: false)
        XCTAssertTrue(manager.hasUpdateReminder)
        manager.standardUserDriverWillFinishUpdateSession()
        XCTAssertFalse(manager.hasUpdateReminder)

        manager.handleUpdatePresentation(showsWindow: false, userInitiated: true)
        XCTAssertFalse(manager.hasUpdateReminder)
    }

    /// The status menu has no update item: Settings and Quit only.
    func testStatusMenuHasNoUpdateItem() throws {
        let store = MemorySettingsStore()
        store.set(.showMenuBarIcon, value: true)
        let controller = StatusBarController(settingsStore: store)
        let titles = try XCTUnwrap(controller.rootMenu?.items).filter { !$0.isSeparatorItem }.map(\.title)
        XCTAssertEqual(titles, ["Settings…", "Quit"])
    }
}
