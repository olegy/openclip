import XCTest
@testable import OpenClip

/// A palette row lists alias → hotkey → ⌘N, each only when the action has it.
@MainActor
final class PaletteRowAccessoriesTests: XCTestCase {
    func testInlinePreviewIsWideEnoughForRowAccessories() {
        XCTAssertGreaterThanOrEqual(PopupMetrics.inlineSearchAccessoryMaxWidth, 240)
    }

    func testItemsKeepAliasHotkeyDigitOrder() {
        XCTAssertEqual(
            PaletteRowAccessories.items(alias: "md", hotkey: "⌃⌥M", commandDigit: 3),
            [.alias("md"), .hotkey("⌃⌥M"), .commandDigit(3)]
        )
    }

    func testItemsLeaveOutWhatIsNotSet() {
        XCTAssertEqual(PaletteRowAccessories.items(alias: "", hotkey: nil, commandDigit: 1), [.commandDigit(1)])
        XCTAssertEqual(PaletteRowAccessories.items(alias: "", hotkey: "", commandDigit: nil), [])
        // Rows past the ninth have no ⌘-digit but still show their alias and hotkey.
        XCTAssertEqual(
            PaletteRowAccessories.items(alias: "md", hotkey: "⌘M", commandDigit: nil),
            [.alias("md"), .hotkey("⌘M")]
        )
    }
}
