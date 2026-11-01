// PopupHoverSupport.swift
// OpenClip
//
// Shared hover-state plumbing for the popup: the global hover location singleton fed by the
// controller's event monitors, and the content-size preference key PopupView reports its size by.
import SwiftUI
import Core

@MainActor
public final class PopupHoverState: ObservableObject {
    public static let shared = PopupHoverState()

    @Published public var location: CGPoint?
    @Published public var usesGlobalMouseMonitoring = false

    public init() {}
}

struct PopupContentSizePreferenceKey: PreferenceKey {
    static let defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
