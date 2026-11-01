// PopupThemeModel.swift
// OpenClip
//
// Pure resolution logic for the popup appearance storage, shared by PopupView, ResultCardView
// and the toasts. The only axis is the color mode stored under "popupThemeColor":
// "system", "light" or "dark".
import SwiftUI

/// Resolves the popup theme storage into the tokens the rendering code switches on.
enum PopupThemeModel {
    /// Resolves the classic appearance token ("light"/"dark"), honoring "system".
    static func classicToken(appearance: String, systemIsDark: Bool) -> String {
        if appearance == "system" { return systemIsDark ? "dark" : "light" }
        return appearance
    }

    /// The color scheme the popup subtree should render under so `.primary`/`.secondary` and
    /// materials match the effective theme. "system" follows the Mac;
    /// "light"/"dark" pin it regardless of the system. Applied only within the popup subtree so
    /// it never changes the surrounding Preferences window.
    static func effectiveScheme(appearance: String, systemIsDark: Bool) -> ColorScheme {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return systemIsDark ? .dark : .light
        }
    }

    /// The resting (non-hover) foreground color for content on the given effective theme
    /// token ("light"/"dark").
    static func restForeground(for effectiveTheme: String) -> Color {
        switch effectiveTheme {
        case "light": return .black.opacity(0.85)
        case "dark": return .white.opacity(0.90)
        default: return .primary
        }
    }

    /// Slightly softened accent for popup highlights.
    static var barHoverFill: Color {
        Color(nsColor: NSColor.controlAccentColor.blended(withFraction: 0.08, of: .white) ?? .controlAccentColor)
    }

    /// The secondary foreground color (hints, badges) for the given effective theme token.
    static func restSecondary(for effectiveTheme: String) -> Color {
        switch effectiveTheme {
        case "light": return .black.opacity(0.55)
        case "dark": return .white.opacity(0.60)
        default: return .secondary
        }
    }

    /// The divider color between rows for the given effective theme token.
    static func dividerColor(for effectiveTheme: String) -> Color {
        switch effectiveTheme {
        case "light": return .black.opacity(0.12)
        case "dark": return .white.opacity(0.14)
        default: return .white.opacity(0.20)
        }
    }

    /// The background fill for the solid popup surface.
    @ViewBuilder
    public static func classicSurfaceBackground(for colorScheme: ColorScheme, in shape: RoundedRectangle) -> some View {
        shape.fill(
            Color(
                red: colorScheme == .dark ? 0.15 : 0.94,
                green: colorScheme == .dark ? 0.15 : 0.94,
                blue: colorScheme == .dark ? 0.165 : 0.96
            )
        )
    }
}

// MARK: - Bottom Dissolve

/// Fades scroll content out into the card at the bottom edge by masking the content itself, rather
/// than painting a fade layer over it. The footer chrome sits on the card's own surface, so there is
/// no blur and no tint band at the bottom — rows simply lose opacity as they trail under the footer.
struct PopupBottomDissolve: ViewModifier {
    /// Height over which the content fades to clear.
    let height: CGFloat

    func body(content: Content) -> some View {
        content.mask(
            VStack(spacing: 0) {
                Rectangle().fill(.black)
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: height)
            }
        )
    }
}

extension View {
    func popupBottomDissolve(height: CGFloat) -> some View {
        modifier(PopupBottomDissolve(height: height))
    }

    @ViewBuilder
    func paletteSafeAreaBar<Content: View>(
        edge: VerticalEdge,
        spacing: CGFloat? = 0,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if #available(macOS 26.0, *), !ProcessInfo.processInfo.arguments.contains("-XCTest") && NSClassFromString("XCTestCase") == nil {
            safeAreaBar(edge: edge, spacing: spacing, content: content)
        } else {
            safeAreaInset(edge: edge, spacing: spacing) {
                content()
                    .background(.ultraThinMaterial)
            }
        }
    }
}

// MARK: - Effective Theme Environment Key

/// Empty by default — "not set" — so a view hosted outside `PopupView` (previews, tests) falls
/// back to the shared `.primary`/`.secondary` tokens and stays readable under either color
/// scheme. A "dark" default painted white text onto a light card whenever the host forced a
/// light scheme without also setting this key. `PopupView` always sets it explicitly.
struct PopupEffectiveThemeKey: EnvironmentKey {
    static let defaultValue = ""
}

public extension EnvironmentValues {
    var popupEffectiveTheme: String {
        get { self[PopupEffectiveThemeKey.self] }
        set { self[PopupEffectiveThemeKey.self] = newValue }
    }
}

// MARK: - Shared Card Chrome

/// Fill and hairline shared by the palette's and the result card's round or rounded button chrome.
private struct PopupButtonSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    let colorScheme: ColorScheme
    let isHovered: Bool
    let tint: Color?

    func body(content: Content) -> some View {
        content
            .background(
                shape.fill(
                    tint?.opacity(isHovered ? 0.85 : 1.0)
                        ?? Color.primary.opacity(isHovered
                            ? (colorScheme == .dark ? 0.18 : 0.12)
                            : (colorScheme == .dark ? 0.12 : 0.07))
                )
            )
            .overlay(
                shape.stroke(
                    tint == nil
                        ? (colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08))
                        : Color.white.opacity(0.20),
                    lineWidth: 0.5
                )
            )
    }
}

extension View {
    /// Footer control surface for the search palette and result card.
    func popupFooterButtonChrome(
        colorScheme: ColorScheme,
        isHovered: Bool,
        tint: Color? = nil
    ) -> some View {
        modifier(
            PopupButtonSurface(
                shape: RoundedRectangle(cornerRadius: PopupMetrics.footerButtonCornerRadius, style: .continuous),
                colorScheme: colorScheme,
                isHovered: isHovered,
                tint: tint
            )
        )
    }

    /// Compact circular chrome for the result card's header controls.
    func popupHeaderButtonChrome(
        colorScheme: ColorScheme,
        isHovered: Bool,
        tint: Color? = nil
    ) -> some View {
        modifier(PopupButtonSurface(shape: Circle(), colorScheme: colorScheme, isHovered: isHovered, tint: tint))
    }
}

public struct PopupCardChromeModifier: ViewModifier {
    public let cornerRadius: CGFloat
    public let colorScheme: ColorScheme

    public init(
        cornerRadius: CGFloat = PopupMetrics.cardCornerRadius,
        colorScheme: ColorScheme
    ) {
        self.cornerRadius = cornerRadius
        self.colorScheme = colorScheme
    }

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .clipShape(shape)
            .background { PopupThemeModel.classicSurfaceBackground(for: colorScheme, in: shape) }
            .overlay(outerBorder(shape))
            .overlay(rimHighlight(shape))
    }

    /// The outer hairline: a top-to-bottom gradient, slightly brighter at the top where ambient
    /// light hits.
    private func outerBorder(_ shape: RoundedRectangle) -> some View {
        shape.stroke(
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color.white.opacity(0.20), Color.white.opacity(0.08)]
                    : [Color.black.opacity(0.16), Color.black.opacity(0.06)],
                startPoint: .top,
                endPoint: .bottom
            ),
            lineWidth: 1.0
        )
    }

    /// A 1px specular line just inside the top edge, fading out by the bottom: the highlight that
    /// makes the surface read as a lit pane rather than a flat slab. Inset so it never touches the
    /// outer hairline.
    private func rimHighlight(_ shape: RoundedRectangle) -> some View {
        shape.inset(by: 0.5).stroke(
            LinearGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.32 : 0.65),
                    Color.white.opacity(0.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            ),
            lineWidth: 1.0
        )
        .allowsHitTesting(false)
    }
}

public extension View {
    func popupCardChrome(
        cornerRadius: CGFloat = PopupMetrics.cardCornerRadius,
        colorScheme: ColorScheme
    ) -> some View {
        modifier(PopupCardChromeModifier(cornerRadius: cornerRadius, colorScheme: colorScheme))
    }
}

// MARK: - Row Highlight

extension View {
    /// Search-style neutral highlight; inset chrome preserves the full button hit area.
    func popupBarHighlight(
        _ fill: Color,
        scale: CGFloat,
        isText: Bool = false,
        leadingEdge: Bool = false,
        trailingEdge: Bool = false,
        outerInset: CGFloat = 3,
        isHovered: Bool,
        namespace: Namespace.ID
    ) -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: (leadingEdge ? 10 : 7) * scale,
            bottomLeadingRadius: (leadingEdge ? 10 : 7) * scale,
            bottomTrailingRadius: (trailingEdge ? 10 : 7) * scale,
            topTrailingRadius: (trailingEdge ? 10 : 7) * scale,
            style: .continuous
        )
        return background {
            Group {
                if isHovered {
                    shape.fill(fill)
                        .matchedGeometryEffect(id: "barHover", in: namespace)
                } else {
                    shape.fill(fill)
                }
            }
            .padding(.leading, (leadingEdge ? outerInset : (isText ? 0 : 2)) * scale)
            .padding(.trailing, (trailingEdge ? outerInset : (isText ? 0 : 2)) * scale)
            .padding(.vertical, 3 * scale)
        }
    }
}
