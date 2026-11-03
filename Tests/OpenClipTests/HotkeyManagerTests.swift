import XCTest
import AppKit
import KeyboardShortcuts
@testable import OpenClip
@testable import Core

/// Regression coverage for the hotkey trigger path: the palette hotkey must obey the gating that
/// applies to an explicit request — app exclusion (including OpenClip itself) and the text
/// substantiality/length contract — instead of retrieving and injecting a synthetic ⌘C into any
/// frontmost app unconditionally.
@MainActor
final class HotkeyManagerTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run {
            TestIsolation.reset()
            HotkeyManager.shared.retriever = nil
            HotkeyManager.shared.frontmostPIDProvider = { 1001 }
        }
    }

    override func tearDown() async throws {
        HotkeyManager.shared.frontmostPIDProvider = { NSWorkspace.shared.frontmostApplication?.processIdentifier }
        HotkeyManager.shared.retriever = nil
        try await super.tearDown()
    }

    func testPerActionRetrievalRejectsChangedTargetWithoutRequestedPID() async {
        let manager = HotkeyManager.shared
        manager.frontmostPIDProvider = { 2002 }
        let result = await manager.collectTrigger(frontmostApp: MockFrontmostApp(bundleID: "com.apple.TextEdit"))
        XCTAssertNil(result)
    }

    func testPerActionRetrievalRejectsSwitchDuringFreshRetrieval() async {
        let manager = HotkeyManager.shared
        manager.retriever = SelectionRetrievalCoordinator(
            inspect: { _ in AXElementInspector.Target() },
            copyCapture: { _ in
                await MainActor.run { manager.frontmostPIDProvider = { 2002 } }
                return Core.TextResult(text: "stale text")
            }
        )
        let result = await manager.collectTrigger(frontmostApp: MockFrontmostApp(bundleID: "com.sublimetext.4"))
        XCTAssertNil(result)
    }

    func testStructuredOutcomeExplainsTargetSwitchDuringRetrieval() async {
        let manager = HotkeyManager.shared
        manager.retriever = SelectionRetrievalCoordinator(
            inspect: { _ in AXElementInspector.Target() },
            copyCapture: { _ in
                await MainActor.run { manager.frontmostPIDProvider = { 2002 } }
                return Core.TextResult(text: "old selection")
            })
        let response = await manager.collectTriggerResponse(frontmostApp: MockFrontmostApp(bundleID: "com.sublimetext.4"))
        XCTAssertEqual(response.status, .targetChanged)
        XCTAssertNil(response.context)
    }

    func testClipboardFallbackRetainsReadFailure() async {
        let manager = HotkeyManager.shared
        let board = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(board)
        defer { snapshot.restore(to: board) }
        board.clearContents()
        board.setString("fallback text", forType: .string)
        manager.retriever = SelectionRetrievalCoordinator(
            inspect: { _ in AXElementInspector.Target() },
            detailedCopyCapture: { _ in SelectionReadResponse(status: .copyBlocked) })
        let response = await manager.collectTriggerResponse(frontmostApp: MockFrontmostApp(bundleID: "com.sublimetext.4"))
        XCTAssertEqual(response.status, .clipboardFallback)
        XCTAssertEqual(response.retrievalStatus, .copyBlocked)
        XCTAssertEqual(response.context?.text, "fallback text")
    }

    func testNoIdentifiableTargetNeverTriggers() {
        // Covers both a nil frontmost app and one without a bundle ID: previously this fell back
        // to OpenClip itself.
        XCTAssertFalse(HotkeyManager.triggerAllowed(frontmost: nil))
        XCTAssertFalse(HotkeyManager.triggerAllowed(frontmost: MockFrontmostApp(bundleID: nil)))
    }

    func testExcludedAppsNeverTrigger() {
        // A bundle from AppFilter's exclusion list must be rejected even when enabled.
        let excluded = MockFrontmostApp(bundleID: "com.adobe.photoshop")
        XCTAssertFalse(HotkeyManager.triggerAllowed(frontmost: excluded))
    }

    func testOrdinaryForegroundAppTriggers() {
        let ordinary = MockFrontmostApp(bundleID: "com.apple.TextEdit")
        XCTAssertTrue(HotkeyManager.triggerAllowed(frontmost: ordinary))
    }

    func testActionHotkeyNameIsDeterministicAndUnique() {
        let nameA = KeyboardShortcuts.Name.actionHotkey("com.example.one")
        let nameA2 = KeyboardShortcuts.Name.actionHotkey("com.example.one")
        let nameB = KeyboardShortcuts.Name.actionHotkey("com.example.two")
        XCTAssertEqual(nameA, nameA2)
        XCTAssertNotEqual(nameA, nameB)
    }

    func testRunBoundActionPerformsActionOnController() async throws {
        let controller = PopupWindowController()
        let performedExpectation = expectation(description: "Bound action performed")
        let action = BoundTestAction(id: "test.bound") {
            performedExpectation.fulfill()
        }
        let app = AppIdentity(NSRunningApplication.current)
        let selection = SelectionContext(
            text: "sample text",
            sourceApp: app,
            cursorPosition: .zero,
            selectionBounds: nil,
            timestamp: Date(),
            appPolicy: .default
        )
        let context = ActionContext(selection: selection, modifiers: [])
        controller.runBoundAction(action, with: context)
        await fulfillment(of: [performedExpectation], timeout: 2.0)
    }

    func testResolveSynchronousTriggerFallsBackToClipboard() {
        let manager = HotkeyManager.shared

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("fallback clipboard text", forType: .string)

        let frontmost = MockFrontmostApp(bundleID: "com.apple.TextEdit")
        let trigger = manager.resolveSynchronousTrigger(frontmostApp: frontmost)

        let result = try? XCTUnwrap(trigger)
        XCTAssertEqual(result?.context.text, "fallback clipboard text")
        XCTAssertEqual(result?.context.isClipboardFallback, true)
    }

    func testResolveSynchronousTriggerFallsBackToEmptyContextWhenClipboardEmpty() {
        let manager = HotkeyManager.shared

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let frontmost = MockFrontmostApp(bundleID: "com.apple.TextEdit")
        let trigger = manager.resolveSynchronousTrigger(frontmostApp: frontmost)

        let result = try? XCTUnwrap(trigger)
        XCTAssertEqual(result?.context.text, "")
        XCTAssertEqual(result?.context.isClipboardFallback, false)
    }

    /// Issue #74: When a clipboard manager (Paste, Raycast, Maccy) dismisses itself, macOS may
    /// report `frontmostApp` as `nil` during the transition. The trigger should still fire using
    /// clipboard text rather than silently dropping the hotkey.
    func testResolveSynchronousTriggerFallsBackToClipboardWhenFrontmostAppIsNil() {
        let manager = HotkeyManager.shared

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("clipboard from Paste app", forType: .string)

        let trigger = manager.resolveSynchronousTrigger(frontmostApp: nil)

        let result = try? XCTUnwrap(trigger)
        XCTAssertEqual(result?.context.text, "clipboard from Paste app")
        XCTAssertEqual(result?.context.isClipboardFallback, true)
        // No identifiable app → sourceApp has nil bundle ID
        XCTAssertNil(result?.context.sourceApp.bundleIdentifier)
    }

    func testResolveSynchronousTriggerFallsBackToEmptyWhenFrontmostAppNilAndClipboardEmpty() {
        let manager = HotkeyManager.shared

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let trigger = manager.resolveSynchronousTrigger(frontmostApp: nil)

        let result = try? XCTUnwrap(trigger)
        XCTAssertEqual(result?.context.text, "")
        XCTAssertEqual(result?.context.isClipboardFallback, false)
    }

    func testCollectTriggerRejectsMismatchedRequestedPID() async throws {
        let manager = HotkeyManager.shared

        let frontmost = MockFrontmostApp(bundleID: "com.apple.TextEdit", pid: 99999)
        // With a requestedPID that does not match the actual frontmost app, trigger is refused
        let trigger = await manager.collectTrigger(frontmostApp: frontmost, requestID: nil, requestedPID: 99999)
        XCTAssertNil(trigger)
    }

    func testCollectTriggerRejectsMismatchedRequestID() async throws {
        let manager = HotkeyManager.shared

        let frontmost = MockFrontmostApp(bundleID: "com.apple.TextEdit")
        // Pass a random request ID that does not match manager.popupTriggerRequestID
        let trigger = await manager.collectTrigger(frontmostApp: frontmost, requestID: UUID())
        XCTAssertNil(trigger)
    }

    func testHandleActionHotkeyExecutesWhenEnabled() async throws {
        let manager = HotkeyManager.shared
        let controller = PopupWindowController()
        manager.setup(popupController: controller)

        let performedExpectation = expectation(description: "Action executed")
        let action = BoundTestAction(id: "test.enabled.hotkey") {
            performedExpectation.fulfill()
        }
        ActionCoordinator.shared.register(action: action)

        let app = AppIdentity(NSRunningApplication.current)
        let selection = SelectionContext(
            text: "sample text",
            sourceApp: app,
            cursorPosition: .zero,
            selectionBounds: nil,
            timestamp: Date(),
            appPolicy: .default
        )
        controller.startTestSession(for: selection)

        let store = MemorySettingsStore()
        manager.handleActionHotkey("test.enabled.hotkey", settingsStore: store)
        await fulfillment(of: [performedExpectation], timeout: 2.0)
    }

    func testHandleActionHotkeyRejectsDisabledAction() async throws {
        let manager = HotkeyManager.shared
        let controller = PopupWindowController()
        manager.setup(popupController: controller)

        var performed = false
        let action = BoundTestAction(id: "test.disabled.hotkey") {
            performed = true
        }
        ActionCoordinator.shared.register(action: action)

        let app = AppIdentity(NSRunningApplication.current)
        let selection = SelectionContext(
            text: "sample text",
            sourceApp: app,
            cursorPosition: .zero,
            selectionBounds: nil,
            timestamp: Date(),
            appPolicy: .default
        )
        controller.startTestSession(for: selection)

        let store = MemorySettingsStore()
        store.set(.disabledActionIDs, value: ["test.disabled.hotkey"])

        manager.handleActionHotkey("test.disabled.hotkey", settingsStore: store)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(performed)
    }

    func testHandleActionHotkeyRejectsDisabledPackage() async throws {
        let manager = HotkeyManager.shared
        let controller = PopupWindowController()
        manager.setup(popupController: controller)

        var performed = false
        let action = BoundTestAction(
            id: "pkg123.action",
            chrome: ActionChrome(source: .extensionPkg(packageID: "pkg123"))
        ) {
            performed = true
        }
        ActionCoordinator.shared.register(action: action)

        let app = AppIdentity(NSRunningApplication.current)
        let selection = SelectionContext(
            text: "sample text",
            sourceApp: app,
            cursorPosition: .zero,
            selectionBounds: nil,
            timestamp: Date(),
            appPolicy: .default
        )
        controller.startTestSession(for: selection)

        let store = MemorySettingsStore()
        store.set(.disabledPackages, value: ["pkg123"])

        manager.handleActionHotkey("pkg123.action", settingsStore: store)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(performed)
    }

    func testHandleActionHotkeyRejectsDisabledExtensionGroupParent() async throws {
        let manager = HotkeyManager.shared
        let controller = PopupWindowController()
        manager.setup(popupController: controller)

        var performed = false
        let parentGroup = BoundTestAction(
            id: "pkg123.group",
            chrome: ActionChrome(popupBehavior: .showSubActions)
        ) {}
        let childAction = BoundTestAction(
            id: "pkg123.group.child",
            chrome: ActionChrome()
        ) {
            performed = true
        }
        ActionCoordinator.shared.register(action: parentGroup)
        ActionCoordinator.shared.register(action: childAction)

        let app = AppIdentity(NSRunningApplication.current)
        let selection = SelectionContext(
            text: "sample text",
            sourceApp: app,
            cursorPosition: .zero,
            selectionBounds: nil,
            timestamp: Date(),
            appPolicy: .default
        )
        controller.startTestSession(for: selection)

        let store = MemorySettingsStore()
        store.set(.disabledActionIDs, value: ["pkg123.group"])

        manager.handleActionHotkey("pkg123.group.child", settingsStore: store)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(performed)
    }

    func testCollectTriggerPreservesCompletePayloadInFreshPath() async throws {
        let manager = HotkeyManager.shared

        let app = MockFrontmostApp(bundleID: "com.sublimetext.4")
        let sampleFlavors = [
            RichPasteboardFlavor(type: "public.html", data: Data("<p>Fresh text</p>".utf8)),
            RichPasteboardFlavor(type: "com.apple.custom", data: Data([10, 20, 30]))
        ]

        manager.retriever = SelectionRetrievalCoordinator(
            inspect: { _ in
                AXElementInspector.Target()
            },
            copyCapture: { _ in
                Core.TextResult(
                    text: "Fresh text",
                    bounds: CGRect(x: 10, y: 20, width: 30, height: 40),
                    html: "<p>Fresh text</p>",
                    rtf: "{\\rtf1 Fresh text}",
                    flavors: sampleFlavors
                )
            }
        )

        let trigger = await manager.collectTrigger(frontmostApp: app)
        let resolved = try XCTUnwrap(trigger)
        XCTAssertEqual(resolved.context.text, "Fresh text")
        XCTAssertEqual(resolved.context.html, "<p>Fresh text</p>")
        XCTAssertEqual(resolved.context.rtf, "{\\rtf1 Fresh text}")
        XCTAssertEqual(resolved.context.flavors, sampleFlavors)
    }

    // MARK: - Another app's non-activating panel

    /// A Tinycast Note: a non-activating panel holds key focus while Zap stays frontmost.
    nonisolated private static let zapPID: pid_t = 1001
    nonisolated private static let panelPID: pid_t = 3003

    nonisolated private static func panelTextArea(selectedText: String?) -> AXElementInspector.Target {
        AXElementInspector.Target(
            focusedApp: AXUIElementCreateApplication(panelPID),
            role: "AXTextArea",
            selectedText: selectedText
        )
    }

    /// The root cause: reading for the frontmost app while the AX focus belongs to the panel's
    /// process makes the cascade reject the foreign focused element as `targetChanged`.
    func testReadForFrontmostAppRejectsFocusInAnotherProcess() async {
        let manager = HotkeyManager.shared
        manager.retriever = SelectionRetrievalCoordinator(
            inspect: { _ in Self.panelTextArea(selectedText: "note text") }, copyCapture: nil)
        let response = await manager.collectTriggerResponse(
            frontmostApp: MockFrontmostApp(bundleID: "dev.zap.Zap", pid: Self.zapPID), allowsEmptyText: true)
        XCTAssertEqual(response.status, .targetChanged)
        XCTAssertNil(response.context)
    }

    func testTriggerTargetIsTheFocusedPanelsApp() {
        let zap = MockFrontmostApp(bundleID: "dev.zap.Zap", pid: Self.zapPID)
        let tinycast = MockFrontmostApp(bundleID: "com.olegy.tinycast", pid: Self.panelPID)
        let target = FocusedApplication.current(frontmost: zap, ownerPID: Self.panelPID, ownPID: 1,
            runningApplication: { $0 == Self.panelPID ? tinycast : nil })
        XCTAssertTrue(target === tinycast)
    }

    func testTriggerTargetStaysFrontmostWithoutAnotherFocusOwner() {
        let zap = MockFrontmostApp(bundleID: "dev.zap.Zap", pid: Self.zapPID)
        let tinycast = MockFrontmostApp(bundleID: "com.olegy.tinycast", pid: Self.panelPID)
        let running: (pid_t) -> NSRunningApplication? = { $0 == Self.panelPID ? tinycast : nil }
        // Ordinary app: focus and frontmost agree.
        XCTAssertTrue(FocusedApplication.current(frontmost: zap, ownerPID: Self.zapPID, ownPID: 1, runningApplication: running) === zap)
        // AX does not answer.
        XCTAssertTrue(FocusedApplication.current(frontmost: zap, ownerPID: nil, ownPID: 1, runningApplication: running) === zap)
        // The focus owner is not a running app.
        XCTAssertTrue(FocusedApplication.current(frontmost: zap, ownerPID: 4004, ownPID: 1, runningApplication: running) === zap)
        // OpenClip's own palette is key: the source app is still the one underneath.
        XCTAssertTrue(FocusedApplication.current(frontmost: zap, ownerPID: Self.panelPID, ownPID: Self.panelPID, runningApplication: running) === zap)
    }

    func testPaletteReadsSelectionInAnotherAppsNonActivatingPanel() async {
        let manager = HotkeyManager.shared
        manager.frontmostPIDProvider = { Self.panelPID }
        manager.retriever = SelectionRetrievalCoordinator(
            inspect: { _ in Self.panelTextArea(selectedText: "note text") }, copyCapture: nil)
        let response = await manager.collectTriggerResponse(
            frontmostApp: MockFrontmostApp(bundleID: "com.olegy.tinycast", pid: Self.panelPID), allowsEmptyText: true)
        XCTAssertEqual(response.status, .selection)
        XCTAssertEqual(response.context?.text, "note text")
        XCTAssertEqual(response.context?.sourceApp.bundleIdentifier, "com.olegy.tinycast")
    }

    func testPaletteOverPanelWithoutSelectionFallsBackToClipboard() async {
        let manager = HotkeyManager.shared
        let board = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(board)
        defer { snapshot.restore(to: board) }
        board.clearContents()
        board.setString("clipboard text", forType: .string)
        manager.frontmostPIDProvider = { Self.panelPID }
        manager.retriever = SelectionRetrievalCoordinator(
            inspect: { _ in Self.panelTextArea(selectedText: nil) }, copyCapture: nil)
        let response = await manager.collectTriggerResponse(
            frontmostApp: MockFrontmostApp(bundleID: "com.olegy.tinycast", pid: Self.panelPID), allowsEmptyText: true)
        XCTAssertEqual(response.status, .clipboardFallback)
        XCTAssertEqual(response.context?.text, "clipboard text")
    }

    /// The race guard still holds for the panel: focus leaving it during the read drops the result.
    func testFocusLeavingPanelDuringReadStillReportsTargetChanged() async {
        let manager = HotkeyManager.shared
        manager.frontmostPIDProvider = { Self.panelPID }
        manager.retriever = SelectionRetrievalCoordinator(
            inspect: { _ in Self.panelTextArea(selectedText: nil) },
            copyCapture: { _ in
                await MainActor.run { manager.frontmostPIDProvider = { Self.zapPID } }
                return Core.TextResult(text: "stale text")
            })
        let response = await manager.collectTriggerResponse(
            frontmostApp: MockFrontmostApp(bundleID: "com.olegy.tinycast", pid: Self.panelPID), allowsEmptyText: true)
        XCTAssertEqual(response.status, .targetChanged)
        XCTAssertNil(response.context)
    }
}


private struct BoundTestAction: Action {
    let id: String
    var title: String = "Test Bound"
    var icon = ActionIcon.symbol("star")
    var chrome: ActionChrome = ActionChrome()
    let onPerform: @MainActor () -> Void

    @MainActor func isEnabled(for context: ActionContext) -> Bool { true }
    @MainActor func matchInfo(for context: ActionContext) -> ActionMatchInfo? { nil }
    @MainActor func perform(_ context: ActionContext) async throws -> ActionResult {
        onPerform()
        return .success
    }
}

/// `NSRunningApplication` cannot be constructed with an arbitrary bundle ID; the gate only reads
/// `bundleIdentifier`, so a lightweight stand-in keeps the tests hermetic. `triggerAllowed` takes
/// an `NSRunningApplication?`, so the mock subclasses it.
private final class MockFrontmostApp: NSRunningApplication {
    private let bundleID: String?
    private let pid: pid_t

    init(bundleID: String?, pid: pid_t = 1001) {
        self.bundleID = bundleID
        self.pid = pid
        super.init()
    }

    override var bundleIdentifier: String? { bundleID }
    override var processIdentifier: pid_t { pid }
    override var isTerminated: Bool { false }
}
