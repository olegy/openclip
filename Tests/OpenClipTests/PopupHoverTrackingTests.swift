import AppKit
import XCTest
@testable import Core
@testable import OpenClip

@MainActor
private final class VisibleTestPanel: PopupPanel {
    override var isVisible: Bool { true }
    override func orderOut(_ sender: Any?) {}
    override func orderFront(_ sender: Any?) {}
}

@MainActor
final class PopupHoverTrackingTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TestIsolation.reset()
    }

    private func fixture() -> (PopupWindowController, VisibleTestPanel) {
        let controller = PopupWindowController(settingsStore: MemorySettingsStore())
        let panel = VisibleTestPanel()
        controller.panel = panel
        controller.startTestSession(for: SelectionContext(text: "private selection",
            sourceApp: AppIdentity(bundleIdentifier: "com.test.source", processIdentifier: 99999), traceID: 42))
        return (controller, panel)
    }

    /// Regression: the panel's `.activeAlways` tracking area feeds hover while OpenClip is inactive
    /// (floating over another app's fullscreen Space), where no event monitor sees the pointer. That
    /// path must not toggle click-through (`ignoresMouseEvents`), or the panel would stop receiving
    /// its own tracking events and strand hover.
    func testTrackingHoverDoesNotToggleClickThrough() {
        let (controller, panel) = fixture()
        panel.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
        panel.setFrame(NSRect(x: 300, y: 300, width: 200, height: 80), display: false)
        PopupHoverState.shared.usesGlobalMouseMonitoring = true
        defer {
            PopupHoverState.shared.usesGlobalMouseMonitoring = false
            PopupHoverState.shared.location = nil
        }
        let outside = CGPoint(x: panel.frame.maxX + 40, y: panel.frame.maxY + 40)

        panel.ignoresMouseEvents = false
        controller.updatePopupHover(at: outside, toggleClickThrough: false)
        XCTAssertFalse(panel.ignoresMouseEvents)

        // The event-monitor path keeps its click-through behavior.
        controller.updatePopupHover(at: outside, toggleClickThrough: true)
        XCTAssertTrue(panel.ignoresMouseEvents)
        controller.hide()
    }
}
