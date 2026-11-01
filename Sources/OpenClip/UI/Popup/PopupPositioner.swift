// PopupPositioner.swift
// OpenClip
//
// Places the popup Spotlight-style on the screen with the mouse.
import Foundation
import CoreGraphics
import AppKit

public struct PopupPositioner: Sendable {
    /// Spotlight-style frame for a panel of `size`: horizontally centered in `screenBounds`, its
    /// center `spotlightLift` of the screen height above the middle, clamped inside the bounds.
    public static func spotlightFrame(size: CGSize, in screenBounds: CGRect) -> CGRect {
        let width = min(size.width, screenBounds.width)
        let height = min(size.height, screenBounds.height)
        let x = screenBounds.midX - width / 2
        let centerY = screenBounds.midY + screenBounds.height * spotlightLift
        let y = max(screenBounds.minY, min(centerY - height / 2, screenBounds.maxY - height))
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// How far above the screen's middle a Spotlight-style panel is centered, as a fraction of
    /// the screen height.
    public static let spotlightLift: CGFloat = 0.1

    /// Selects the screen containing `point`, with a 2pt inclusive margin so cursor coordinates
    /// resting exactly on the maxX/maxY boundaries of secondary displays do not fail resolution.
    public static func screen(containing point: CGPoint, in screens: [NSScreen] = NSScreen.screens) -> NSScreen? {
        screens.first { $0.frame.insetBy(dx: -2, dy: -2).contains(point) } ?? screens.first
    }
}
