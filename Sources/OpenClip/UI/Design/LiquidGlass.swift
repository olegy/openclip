// LiquidGlass.swift
// OpenClip
//
// Shared view modifiers for adopting Apple's Liquid Glass material on macOS 26+,
// with graceful standard-material fallbacks for macOS 14-15.
// Liquid Glass is a macOS 26 / iOS 26 material reserved for the navigation/functional
// layer (sidebars, toolbars, tab bars) that floats above content — see HIG "Materials".
// The regular variant adapts to what scrolls beneath it; the clear variant is only for
// media-rich backgrounds. Both variants need a dimming layer for legibility.
import SwiftUI
import AppKit

/// Chooses which Liquid Glass variant a surface uses.
public enum LiquidGlassVariant {
    /// Adaptive glass that maintains legibility over any content. Default.
    case regular
    /// Permanently more transparent; for media-rich backgrounds only.
    case clear
}

@MainActor
public extension View {
    /// Renders the view as a glass surface using Liquid Glass on macOS 26+ or thin material for a frosted look, or solid background when Reduce Transparency is enabled.
    @ViewBuilder
    func glassSurface(
        _ variant: LiquidGlassVariant = .regular,
        cornerRadius: CGFloat = 14
    ) -> some View {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            background(
                Color(nsColor: .windowBackgroundColor),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            if #available(macOS 26.0, *) {
                self.glassEffect(variant == .clear ? .clear : .regular, in: .rect(cornerRadius: cornerRadius))
            } else {
                background(
                    variant == .clear ? .ultraThinMaterial : .thinMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
            }
        }
    }
}

/// A SwiftUI wrapper around AppKit's `NSVisualEffectView` for behind-window frosted glass, falling back to solid window background under Reduce Transparency.
@MainActor
public struct VisualEffectView: NSViewRepresentable {
    public var material: NSVisualEffectView.Material
    public var blendingMode: NSVisualEffectView.BlendingMode
    public var state: NSVisualEffectView.State

    public init(
        material: NSVisualEffectView.Material = .sidebar,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        state: NSVisualEffectView.State = .active
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.state = state
    }

    public func makeNSView(context: Context) -> NSView {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            let solidView = NSView()
            solidView.wantsLayer = true
            solidView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            return solidView
        }
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        if let ve = nsView as? NSVisualEffectView {
            ve.material = material
            ve.blendingMode = blendingMode
            ve.state = state
        } else {
            nsView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
    }
}

