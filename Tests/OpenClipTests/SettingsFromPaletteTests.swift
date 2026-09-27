import XCTest
@testable import OpenClip
@testable import Core

/// Opening Settings while the palette is up (⌘,) must close the palette before Settings takes key.
/// Dismissed by that key change instead, the palette handed focus back to the source app, which
/// then covered Settings.
@MainActor
final class SettingsFromPaletteTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run { TestIsolation.reset() }
    }

    func testPaletteClosesWhenSettingsIsAboutToShow() {
        let controller = PopupWindowController(settingsStore: MemorySettingsStore())
        defer { controller.hide() }
        controller.show(for: SelectionContext(text: "hello"), pasteAvailable: nil, initialMode: .search)
        XCTAssertTrue(controller.isVisible)

        NotificationCenter.default.post(name: .openClipPreferencesWindowWillShow, object: nil)

        XCTAssertFalse(controller.isVisible)
        XCTAssertEqual(controller.modeStore.mode, .actions)
    }
}
