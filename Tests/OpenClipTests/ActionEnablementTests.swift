// ActionEnablementTests.swift
// OpenClip
//
// The enable switch's rules (`ActionEnablement`) for extension packages and the groups inside them.
import XCTest
import SwiftUI
@testable import Core
@testable import OpenClip

@MainActor
final class ActionEnablementTests: XCTestCase {
    private var settingsStore: MemorySettingsStore!
    private var coordinator: ActionCoordinator!
    private var registry: ActionRegistry!

    override func setUp() {
        super.setUp()
        settingsStore = MemorySettingsStore()
        registry = ActionRegistry(settingsStore: settingsStore)
        coordinator = ActionCoordinator(registry: registry, settingsStore: settingsStore)
        for index in 1...4 {
            coordinator.register(action: DummyAction(
                id: "action.\(index)",
                title: "Action \(index)",
                chrome: ActionChrome(source: .extensionPkg(packageID: "com.pkg.leafy"))
            ))
        }
    }

    func testActionEnablementToggleIndividualActionInsideDisabledPackage() {
        var disabledPackages: Set<String> = ["com.pkg.leafy"]
        var disabledActionIDs: Set<String> = []

        let action1 = DummyAction(id: "action.1", title: "Action 1", chrome: ActionChrome(source: .extensionPkg(packageID: "com.pkg.leafy")))
        let binding1 = ActionEnablement.binding(
            for: action1,
            disabledActionIDs: Binding(get: { disabledActionIDs }, set: { disabledActionIDs = $0 }),
            disabledPackages: Binding(get: { disabledPackages }, set: { disabledPackages = $0 }),
            coordinator: coordinator
        )

        XCTAssertFalse(binding1.wrappedValue)

        // Turning one action on re-enables the package and keeps its siblings off.
        binding1.wrappedValue = true

        XCTAssertFalse(disabledPackages.contains("com.pkg.leafy"))
        XCTAssertFalse(disabledActionIDs.contains("action.1"))
        XCTAssertTrue(disabledActionIDs.contains("action.2"))
        XCTAssertTrue(disabledActionIDs.contains("action.3"))
        XCTAssertTrue(disabledActionIDs.contains("action.4"))
        XCTAssertTrue(binding1.wrappedValue)

        binding1.wrappedValue = false
        XCTAssertTrue(disabledActionIDs.contains("action.1"))
        XCTAssertFalse(binding1.wrappedValue)
    }

    func testPackageBindingEnableAndDisable() {
        var disabledPackages: Set<String> = []
        var disabledActionIDs: Set<String> = ["action.1", "action.2", "action.3", "action.4"]

        let pkgBinding = ActionEnablement.packageBinding(
            packageID: "com.pkg.leafy",
            gatedReason: nil,
            disabledPackages: Binding(get: { disabledPackages }, set: { disabledPackages = $0 }),
            disabledActionIDs: Binding(get: { disabledActionIDs }, set: { disabledActionIDs = $0 }),
            coordinator: coordinator
        )

        // When all actions are disabled, package reads as false
        XCTAssertFalse(pkgBinding.wrappedValue)

        // Turn package on: clears all action disables and clears disabledPackages
        pkgBinding.wrappedValue = true
        XCTAssertFalse(disabledPackages.contains("com.pkg.leafy"))
        XCTAssertTrue(disabledActionIDs.isEmpty)
        XCTAssertTrue(pkgBinding.wrappedValue)

        // Turn package off: adds to disabledPackages
        pkgBinding.wrappedValue = false
        XCTAssertTrue(disabledPackages.contains("com.pkg.leafy"))
        XCTAssertFalse(pkgBinding.wrappedValue)
    }

    func testActionEnablementToggleChildOfExtensionGroupEnablesParentGroup() {
        let group1 = DummyAction(
            id: "com.pkg.leafy.g1",
            title: "Group 1",
            chrome: ActionChrome(rowStyle: .actionGroup, popupBehavior: .showSubActions, source: .extensionPkg(packageID: "com.pkg.leafy"))
        )
        let group2 = DummyAction(
            id: "com.pkg.leafy.g2",
            title: "Group 2",
            chrome: ActionChrome(rowStyle: .actionGroup, popupBehavior: .showSubActions, source: .extensionPkg(packageID: "com.pkg.leafy"))
        )
        let child2 = DummyAction(
            id: "com.pkg.leafy.g2.child",
            title: "Child 2",
            chrome: ActionChrome(source: .extensionPkg(packageID: "com.pkg.leafy"))
        )
        coordinator.register(action: group1)
        coordinator.register(action: group2)
        coordinator.register(action: child2)

        var disabledPackages: Set<String> = []
        var disabledActionIDs: Set<String> = ["com.pkg.leafy.g1", "com.pkg.leafy.g2", "com.pkg.leafy.g2.child"]

        let childBinding = ActionEnablement.binding(
            for: child2,
            disabledActionIDs: Binding(get: { disabledActionIDs }, set: { disabledActionIDs = $0 }),
            disabledPackages: Binding(get: { disabledPackages }, set: { disabledPackages = $0 }),
            coordinator: coordinator
        )

        XCTAssertFalse(childBinding.wrappedValue)
        childBinding.wrappedValue = true

        // Child's specific parent group (g2) must be un-disabled
        XCTAssertFalse(disabledActionIDs.contains("com.pkg.leafy.g2"))
        XCTAssertFalse(disabledActionIDs.contains("com.pkg.leafy.g2.child"))
        // Other group (g1) remains disabled
        XCTAssertTrue(disabledActionIDs.contains("com.pkg.leafy.g1"))
        XCTAssertTrue(childBinding.wrappedValue)
    }

    func testActionEnablementToggleGroupContainerKeepsChildCommandsEnabled() {
        let group = DummyAction(
            id: "com.pkg.leafy.g1",
            title: "Group 1",
            chrome: ActionChrome(rowStyle: .actionGroup, popupBehavior: .showSubActions, source: .extensionPkg(packageID: "com.pkg.leafy"))
        )
        let child1 = DummyAction(
            id: "com.pkg.leafy.g1.c1",
            title: "Child 1",
            chrome: ActionChrome(source: .extensionPkg(packageID: "com.pkg.leafy"))
        )
        let child2 = DummyAction(
            id: "com.pkg.leafy.g1.c2",
            title: "Child 2",
            chrome: ActionChrome(source: .extensionPkg(packageID: "com.pkg.leafy"))
        )
        let standalone = DummyAction(
            id: "com.pkg.leafy.standalone",
            title: "Standalone",
            chrome: ActionChrome(source: .extensionPkg(packageID: "com.pkg.leafy"))
        )
        coordinator.register(action: group)
        coordinator.register(action: child1)
        coordinator.register(action: child2)
        coordinator.register(action: standalone)

        var disabledPackages: Set<String> = ["com.pkg.leafy"]
        var disabledActionIDs: Set<String> = []

        let groupBinding = ActionEnablement.binding(
            for: group,
            disabledActionIDs: Binding(get: { disabledActionIDs }, set: { disabledActionIDs = $0 }),
            disabledPackages: Binding(get: { disabledPackages }, set: { disabledPackages = $0 }),
            coordinator: coordinator
        )

        XCTAssertFalse(groupBinding.wrappedValue)
        groupBinding.wrappedValue = true

        // Package un-disabled
        XCTAssertFalse(disabledPackages.contains("com.pkg.leafy"))
        // Group container un-disabled
        XCTAssertFalse(disabledActionIDs.contains("com.pkg.leafy.g1"))
        // Group children must NOT be disabled
        XCTAssertFalse(disabledActionIDs.contains("com.pkg.leafy.g1.c1"))
        XCTAssertFalse(disabledActionIDs.contains("com.pkg.leafy.g1.c2"))
        // Sibling outside the group is disabled
        XCTAssertTrue(disabledActionIDs.contains("com.pkg.leafy.standalone"))
        XCTAssertTrue(groupBinding.wrappedValue)
    }
}

private struct DummyAction: Action, Sendable {
    let id: String
    let title: String
    var icon: ActionIcon { .symbol("star") }
    let chrome: ActionChrome

    init(id: String, title: String, chrome: ActionChrome = ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin)) {
        self.id = id
        self.title = title
        self.chrome = chrome
    }

    @MainActor func isEnabled(for context: ActionContext) -> Bool { true }
    @MainActor func perform(_ context: ActionContext) async throws -> ActionResult { .none }
}
