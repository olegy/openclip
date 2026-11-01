import XCTest
@testable import Core

struct MockAction: Action {
    let id: String
    let title = "Mock"
    let icon = ActionIcon.symbol("star")
    let shouldBeEnabled: Bool
    let chrome: ActionChrome
    
    init(id: String, shouldBeEnabled: Bool, chrome: ActionChrome = ActionChrome()) {
        self.id = id
        self.shouldBeEnabled = shouldBeEnabled
        self.chrome = chrome
    }
    
    @MainActor
    func isEnabled(for context: ActionContext) -> Bool {
        return shouldBeEnabled
    }
    
    @MainActor
    func perform(_ context: ActionContext) async throws -> ActionResult {
        return .success
    }
}

/// Stands in for the AI Tools launcher: a row that resolves its children out of the catalog
/// (`chrome.source == .ai`), exactly as `AIToolsAction` does.
struct MockLauncherAction: Action, SubActionProviding {
    let id: String
    let title = "Launcher"
    let icon = ActionIcon.symbol("sparkles")
    var chrome: ActionChrome { ActionChrome(source: .builtin, launchesAI: true) }

    @MainActor
    func isEnabled(for context: ActionContext) -> Bool { true }

    @MainActor
    func perform(_ context: ActionContext) async throws -> ActionResult { .success }

    @MainActor
    func subActions(in catalog: [any Action]) -> [any Action] {
        catalog.filter { ActionIdentity.isAIPreset($0) }
    }
}

final class ActionRegistryTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run { TestIsolation.reset() }
    }

    @MainActor
    func testActionRegistrationAndAvailability() {
        let registry = ActionRegistry.shared
        
        let action1 = MockAction(id: "mock.1", shouldBeEnabled: true)
        let action2 = MockAction(id: "mock.2", shouldBeEnabled: false)
        
        let initialCount = registry.actions.count
        registry.register(builtIns: [action1, action2])
        
        XCTAssertEqual(registry.actions.count, initialCount + 2)
        
        let selection = SelectionContext(text: "test", sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default)
        let context = ActionContext(selection: selection, modifiers: [])
        let available = registry.searchCatalog(for: context)
        
        XCTAssertTrue(available.contains(where: { $0.id == "mock.1" }))
        XCTAssertFalse(available.contains(where: { $0.id == "mock.2" }))
    }
    
    func testActionContext() {
        let selection = SelectionContext(text: "hello", sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default)
        let context = ActionContext(selection: selection, modifiers: .shift)
        
        XCTAssertEqual(context.selection.text, "hello")
        XCTAssertEqual(context.modifiers, .shift)
    }

    
    @MainActor
    func testDisabledActionsAreFiltered() {
        let store = MemorySettingsStore()
        let registry = ActionRegistry(settingsStore: store)
        
        let action = MockAction(id: "mock.disabled.test", shouldBeEnabled: true)
        registry.register(action: action)
        
        store.set(.disabledActionIDs, value: Set(["mock.disabled.test"]))
        
        let selection = SelectionContext(text: "test", sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default)
        let context = ActionContext(selection: selection, modifiers: [])
        let available = registry.searchCatalog(for: context)
        
        XCTAssertFalse(available.contains(where: { $0.id == "mock.disabled.test" }))
    }
    
    @MainActor
    func testDisabledPackageHidesAllPackageActions() {
        let store = MemorySettingsStore()
        let registry = ActionRegistry(settingsStore: store)
        
        let packageID = "com.test.pkg"
        let pkgChrome = ActionChrome(
            badge: .extensionPkg(packageID),
            rowStyle: .standard,
            popupBehavior: .perform,
            source: .extensionPkg(packageID: packageID)
        )
        let a1 = MockAction(id: "\(packageID).action.1", shouldBeEnabled: true, chrome: pkgChrome)
        let a2 = MockAction(id: "\(packageID).action.2", shouldBeEnabled: true, chrome: pkgChrome)
        registry.register(builtIns: [a1, a2])
        
        store.set(.disabledPackages, value: Set([packageID]))
        
        let selection = SelectionContext(text: "test", sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default)
        let context = ActionContext(selection: selection, modifiers: [])
        let available = registry.searchCatalog(for: context)
        
        XCTAssertFalse(available.contains(where: { $0.id == a1.id }))
        XCTAssertFalse(available.contains(where: { $0.id == a2.id }))
    }

    @MainActor
    func testDisabledGroupRowHidesItsSubActions() {
        let store = MemorySettingsStore()
        let registry = ActionRegistry(settingsStore: store)
        let groupID = "mock.group"
        let groupChrome = ActionChrome(
            badge: .none,
            rowStyle: .actionGroup,
            popupBehavior: .showSubActions,
            source: .builtin
        )
        let group = MockAction(id: groupID, shouldBeEnabled: true, chrome: groupChrome)
        let subA = MockAction(id: "\(groupID).a", shouldBeEnabled: true)
        let subB = MockAction(id: "\(groupID).b", shouldBeEnabled: true)
        registry.register(builtIns: [group, subA, subB])

        store.set(.disabledActionIDs, value: Set([groupID]))

        let selection = SelectionContext(text: "test", sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default)
        let context = ActionContext(selection: selection, modifiers: [])
        let available = registry.searchCatalog(for: context)

        XCTAssertFalse(available.contains { $0.id == groupID })
        XCTAssertFalse(available.contains { $0.id == subA.id })
        XCTAssertFalse(available.contains { $0.id == subB.id })
    }

    @MainActor
    func testEnabledGroupRowKeepsSubActionsAvailable() {
        let store = MemorySettingsStore()
        let registry = ActionRegistry(settingsStore: store)
        let groupID = "mock.group.visible"
        let groupChrome = ActionChrome(
            badge: .none,
            rowStyle: .actionGroup,
            popupBehavior: .showSubActions,
            source: .builtin
        )
        let group = MockAction(id: groupID, shouldBeEnabled: true, chrome: groupChrome)
        let sub = MockAction(id: "\(groupID).x", shouldBeEnabled: true)
        registry.register(builtIns: [group, sub])

        store.set(.disabledActionIDs, value: Set([]))

        let selection = SelectionContext(text: "test", sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default)
        let context = ActionContext(selection: selection, modifiers: [])
        let available = registry.searchCatalog(for: context)

        XCTAssertTrue(available.contains { $0.id == groupID })
        XCTAssertTrue(available.contains { $0.id == sub.id })
    }

    @MainActor
    func testSearchCatalogDropsContextuallyUnableAndSettingsDisabled() {
        let store = MemorySettingsStore()
        let registry = ActionRegistry(settingsStore: store)
        let groupChrome = ActionChrome(
            badge: .none,
            rowStyle: .actionGroup,
            popupBehavior: .showSubActions,
            source: .builtin
        )
        let group = MockAction(id: "mock.searchgroup", shouldBeEnabled: true, chrome: groupChrome)
        let sub = MockAction(id: "mock.searchgroup.a", shouldBeEnabled: true)
        // Contextually unable: `isEnabled(for:)` is false, so the palette must not offer it.
        let contextuallyUnable = MockAction(id: "mock.searchdisabled", shouldBeEnabled: false)
        // Settings-disabled (`.disabledActionIDs`): a row toggled off in Preferences is not
        // offered anywhere, the palette included.
        let settingsDisabled = MockAction(id: "mock.settingsdisabled", shouldBeEnabled: true)
        let normal = MockAction(id: "mock.searchnormal", shouldBeEnabled: true)
        registry.register(builtIns: [group, sub, contextuallyUnable, settingsDisabled, normal])
        store.set(.disabledActionIDs, value: Set(["mock.settingsdisabled"]))

        let selection = SelectionContext(text: "test", sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default)
        let catalog = registry.searchCatalog(for: ActionContext(selection: selection, modifiers: []))

        XCTAssertTrue(catalog.contains { $0.id == "mock.searchgroup" })
        XCTAssertTrue(catalog.contains { $0.id == "mock.searchgroup.a" })
        XCTAssertFalse(catalog.contains { $0.id == "mock.searchdisabled" })
        XCTAssertFalse(catalog.contains { $0.id == "mock.settingsdisabled" },
                       "an action switched off in Preferences must not be offered in the palette")
        XCTAssertTrue(catalog.contains { $0.id == "mock.searchnormal" })
    }

    @MainActor
    func testAIPresetsRemainInAvailableCatalogForGroupResolution() {
        // Own store: `ActionRegistry()` reads the real preferences domain (the test host shares
        // OpenClip's bundle id), so a developer disabling Copy in the app would fail this test.
        let registry = ActionRegistry(settingsStore: MemorySettingsStore())
        let aiChrome = ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .ai)
        let aiAction = MockAction(id: "ai.preset.proofread", shouldBeEnabled: true, chrome: aiChrome)
        let normal = MockAction(id: "mock.normal", shouldBeEnabled: true)
        registry.register(builtIns: [aiAction, normal])

        let selection = SelectionContext(text: "test", sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default)
        let context = ActionContext(selection: selection, modifiers: [])
        let available = registry.searchCatalog(for: context)

        // The popup resolves group children from this catalog before hiding them at the top level.
        XCTAssertTrue(available.contains { $0.id == "ai.preset.proofread" })
        XCTAssertTrue(available.contains { $0.id == "mock.normal" })
        XCTAssertTrue(registry.searchCatalog(for: context).contains { $0.id == "ai.preset.proofread" })
    }

    @MainActor
    func testAIToolsLauncherExcludedFromPalette() {
        let registry = ActionRegistry(settingsStore: MemorySettingsStore())
        let launcher = MockAction(id: "builtin.aiTools", shouldBeEnabled: true, chrome: ActionChrome(launchesAI: true))
        let normal = MockAction(id: "mock.normal", shouldBeEnabled: true)
        registry.register(builtIns: [launcher, normal])

        let selection = SelectionContext(text: "test", sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default)
        let context = ActionContext(selection: selection, modifiers: [])
        let available = registry.searchCatalog(for: context)

        // The palette excludes the launcher — the AI presets already cover AI there.
        XCTAssertFalse(available.contains { $0.id == "builtin.aiTools" })
        XCTAssertTrue(available.contains { $0.id == "mock.normal" })
    }

    @MainActor
    private static func palette(_ registry: ActionRegistry) -> [String] {
        let selection = SelectionContext(text: "test", sourceApp: AppIdentity(bundleIdentifier: "com.test", localizedName: "Test"), cursorPosition: .zero, timestamp: Date(), appPolicy: .default)
        return registry.searchCatalog(for: ActionContext(selection: selection, modifiers: [])).map(\.id)
    }

    @MainActor
    func testDisabledAIPresetIsNotOfferedInThePalette() {
        let store = MemorySettingsStore()
        let registry = ActionRegistry(settingsStore: store)
        let enabled = MockAction(id: "ai.preset.proofread", shouldBeEnabled: true,
                                 chrome: ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .ai))
        // `shouldBeEnabled: false` stands in for the preset's toggle being off: the real AIAction
        // answers `isEnabled` from AIServiceManager's preset list.
        let disabled = MockAction(id: "ai.preset.rewrite", shouldBeEnabled: false,
                                  chrome: ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .ai))
        registry.register(builtIns: [enabled, disabled])

        XCTAssertEqual(Self.palette(registry), ["ai.preset.proofread"])
    }

    /// A disabled group takes its sub-actions with it: the palette lists the members rather than
    /// the group row, so the row's toggle has to reach them.
    @MainActor
    func testDisabledGroupHidesItsSubActionsFromThePalette() {
        let store = MemorySettingsStore()
        let registry = ActionRegistry(settingsStore: store)
        let groupChrome = ActionChrome(badge: .none, rowStyle: .actionGroup, popupBehavior: .showSubActions, source: .builtin)
        let group = MockAction(id: "mock.group", shouldBeEnabled: true, chrome: groupChrome)
        let member = MockAction(id: "mock.group.member", shouldBeEnabled: true)
        let other = MockAction(id: "mock.other", shouldBeEnabled: true)
        registry.register(builtIns: [group, member, other])
        XCTAssertEqual(Self.palette(registry), ["mock.group", "mock.group.member", "mock.other"])

        store.set(.disabledActionIDs, value: Set(["mock.group"]))
        XCTAssertEqual(Self.palette(registry), ["mock.other"])
    }

    /// A disabled extension package hides its actions from the palette as well as the bar.
    @MainActor
    func testDisabledPackageIsNotOfferedInThePalette() {
        let store = MemorySettingsStore()
        let registry = ActionRegistry(settingsStore: store)
        let extChrome = ActionChrome(source: .extensionPkg(packageID: "com.ext.pkg"))
        registry.register(builtIns: [
            MockAction(id: "com.ext.pkg.action", shouldBeEnabled: true, chrome: extChrome),
            MockAction(id: "mock.other", shouldBeEnabled: true)
        ])
        XCTAssertEqual(Self.palette(registry), ["com.ext.pkg.action", "mock.other"])

        store.set(.disabledPackages, value: Set(["com.ext.pkg"]))
        XCTAssertEqual(Self.palette(registry), ["mock.other"])
    }

    @MainActor
    func testCatalogKeepsRegistrationOrder() {
        let store = MemorySettingsStore()
        let registry = ActionRegistry(settingsStore: store)

        let b1 = MockAction(id: "builtin.1", shouldBeEnabled: true, chrome: ActionChrome(source: .builtin))
        let b2 = MockAction(id: "builtin.2", shouldBeEnabled: true, chrome: ActionChrome(source: .builtin))
        let b3 = MockAction(id: "builtin.3", shouldBeEnabled: true, chrome: ActionChrome(source: .builtin))
        let b4 = MockAction(id: "builtin.4", shouldBeEnabled: true, chrome: ActionChrome(source: .builtin))

        registry.register(action: b1)
        registry.register(action: b2)
        registry.register(action: b3)
        registry.register(action: b4)

        XCTAssertEqual(registry.actions.map(\.id), ["builtin.1", "builtin.2", "builtin.3", "builtin.4"])
    }

    @MainActor
    func testClipboardFallbackExcludesRequiresLiveSelectionActions() {
        let registry = ActionRegistry(settingsStore: MemorySettingsStore())
        let live = MockAction(id: "ext.live", shouldBeEnabled: true, chrome: ActionChrome(requiresLiveSelection: true))
        let search = MockAction(id: "builtin.search", shouldBeEnabled: true)
        registry.register(builtIns: [live, search])

        let app = AppIdentity(bundleIdentifier: "com.test", localizedName: "Test")
        let fallbackSelection = SelectionContext(text: "hello", sourceApp: app, cursorPosition: .zero, timestamp: Date(), appPolicy: .default, isClipboardFallback: true)
        let available = registry.searchCatalog(for: ActionContext(selection: fallbackSelection, modifiers: []))

        XCTAssertFalse(available.contains { $0.id == "ext.live" })
        XCTAssertTrue(available.contains { $0.id == "builtin.search" })

        // Same text, real selection (no fallback flag): the live-selection action comes back.
        let normalSelection = SelectionContext(text: "hello", sourceApp: app, cursorPosition: .zero, timestamp: Date(), appPolicy: .default)
        let normal = registry.searchCatalog(for: ActionContext(selection: normalSelection, modifiers: []))
        XCTAssertTrue(normal.contains { $0.id == "ext.live" })
    }

    func testMemorySettingsStorePublisherReentrancyDoesNotDeadlock() {
        let store = MemorySettingsStore()
        let key = SettingKey<Set<String>>("test.reentrancy.key", defaultValue: [])
        var received: Set<String>? = nil
        let cancellable = store.publisher(for: key).sink { val in
            received = store.get(key)
        }
        
        store.set(key, value: Set(["item1"]))
        XCTAssertEqual(received, Set(["item1"]))
        _ = cancellable
    }
}
