import XCTest
@testable import Core
@testable import OpenClip

@MainActor
final class StatusBarControllerTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run { TestIsolation.reset() }
    }

    override func tearDown() async throws {
        await MainActor.run { TestIsolation.reset() }
        try await super.tearDown()
    }

    func testStartsWithoutStatusItemWhenPreferenceIsDisabled() {
        let store = MemorySettingsStore()
        store.set(.showMenuBarIcon, value: false)
        let controller = StatusBarController(settingsStore: store, notificationCenter: NotificationCenter())

        XCTAssertFalse(controller.isMenuBarIconVisible)
    }

    /// The menu holds no actions: Settings is the first item, followed only by Quit.
    func testMenuStartsWithSettingsAndListsNoActions() {
        let controller = StatusBarController(settingsStore: MemorySettingsStore(), notificationCenter: NotificationCenter())
        guard let items = controller.rootMenu?.items else {
            return XCTFail("Expected the status menu")
        }

        XCTAssertEqual(items.first, controller.settingsMenuItem)
        XCTAssertFalse(items.contains { $0.submenu != nil })
    }

    func testVisibilityNotificationRemovesAndRecreatesStatusItem() {
        let store = MemorySettingsStore()
        let notificationCenter = NotificationCenter()
        let controller = StatusBarController(settingsStore: store, notificationCenter: notificationCenter)

        XCTAssertTrue(controller.isMenuBarIconVisible)

        store.set(.showMenuBarIcon, value: false)
        notificationCenter.post(name: .openClipMenuBarVisibilityChanged, object: false)
        XCTAssertFalse(controller.isMenuBarIconVisible)

        store.set(.showMenuBarIcon, value: true)
        notificationCenter.post(name: .openClipMenuBarVisibilityChanged, object: true)
        XCTAssertTrue(controller.isMenuBarIconVisible)

        store.set(.showMenuBarIcon, value: false)
        notificationCenter.post(name: .openClipMenuBarVisibilityChanged, object: false)
    }
}
