import XCTest
@testable import OpenClip

final class PopupPositionerTests: XCTestCase {
    func testSpotlightFrameCentersHorizontallyAndSitsAboveMiddle() {
        // A secondary screen with a non-zero origin, as on multi-monitor setups.
        let screenBounds = CGRect(x: 1440, y: 100, width: 1920, height: 1000)
        let size = CGSize(width: 736, height: 470)

        let frame = PopupPositioner.spotlightFrame(size: size, in: screenBounds)

        XCTAssertEqual(frame.size, size)
        XCTAssertEqual(frame.midX, screenBounds.midX)
        XCTAssertEqual(frame.midY, screenBounds.midY + screenBounds.height * PopupPositioner.spotlightLift)
        XCTAssertTrue(screenBounds.contains(frame))
    }

    func testSpotlightFrameStaysInsideShortScreens() {
        let screenBounds = CGRect(x: 0, y: 0, width: 800, height: 500)
        let frame = PopupPositioner.spotlightFrame(size: CGSize(width: 736, height: 470), in: screenBounds)

        XCTAssertEqual(frame.maxY, screenBounds.maxY)
        XCTAssertTrue(screenBounds.contains(frame))
    }

    func testSpotlightFrameShrinksToScreensSmallerThanThePanel() {
        let screenBounds = CGRect(x: 0, y: 0, width: 600, height: 400)
        let frame = PopupPositioner.spotlightFrame(size: CGSize(width: 736, height: 470), in: screenBounds)

        XCTAssertEqual(frame, screenBounds)
    }
}
