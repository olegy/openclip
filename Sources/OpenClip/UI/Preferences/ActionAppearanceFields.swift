// ActionAppearanceFields.swift
// OpenClip
//
// Provides reusable SwiftUI form controls for customizing action titles and icon symbols.
// Hero Header / Shortcuts style: prominent 48x48 hero icon button on the left, action name
// TextField on the right.
import SwiftUI
import Core

/// Reusable appearance configuration form fields: Hero Icon on the left, Title on the right.
struct ActionAppearanceFields: View {
    @Binding var title: String
    @Binding var iconSymbol: String
    /// Symbol the field was seeded with ("" when the action's real icon is not symbol-representable);
    /// used to tell a user-picked symbol apart from the untouched baseline.
    let initialIconSymbol: String
    /// The action's effective current icon (.local/.url/.text/.symbol) shown until the user picks a
    /// replacement; nil when the baseline is already fully described by `iconSymbol`.
    let baseIcon: ActionIcon?
    /// Symbol the icon resolves to for actions with a text-glyph icon while no
    /// replacement has been picked; nil for actions whose icon is already symbol-representable.
    var textGlyphFallbackSymbol: String? = nil
    /// Optional callback when the icon chooser opens.
    var onPickIcon: (() -> Void)? = nil

    @State private var isIconPickerPresented = false
    @State private var isIconHovered = false

    /// What the icon preview should render right now.
    private var previewIcon: ActionIcon {
        Self.resolvedPreviewIcon(
            iconSymbol: iconSymbol,
            initialIconSymbol: initialIconSymbol,
            baseIcon: baseIcon,
            textGlyphFallbackSymbol: textGlyphFallbackSymbol
        )
    }

    /// Preview resolution: keeps the real icon until a genuinely user-picked replacement symbol
    /// exists, falling back to `textGlyphFallbackSymbol` for text-glyph builtins.
    static func resolvedPreviewIcon(
        iconSymbol: String,
        initialIconSymbol: String,
        baseIcon: ActionIcon?,
        textGlyphFallbackSymbol: String? = nil
    ) -> ActionIcon {
        if iconSymbol.isEmpty {
            if case .text? = baseIcon, let fallback = textGlyphFallbackSymbol {
                return .symbol(fallback)
            }
            return baseIcon ?? .symbol(Constants.defaultIconSymbol)
        }
        if iconSymbol == initialIconSymbol, let base = baseIcon {
            return base
        }
        return ActionIcon.resolve(from: iconSymbol)
    }

    /// Hero icon content sized appropriately for the 48x48 hero button.
    @ViewBuilder
    private var heroIconView: some View {
        if case .text(let text) = previewIcon, text.count > 2 {
            Text(text)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .padding(.horizontal, 4)
        } else {
            ActionIconView(icon: previewIcon, size: 22)
        }
    }

    private var iconButtonHelp: String {
        switch previewIcon {
        case .symbol(let name):
            return name.isEmpty ? String(localized: "Choose icon") : String(localized: "Icon: \(name) — click to change")
        case .text(let text):
            return String(localized: "Text glyph “\(text)” — click to replace with an icon")
        case .url:
            return String(localized: "Remote image — click to replace with an icon")
        case .local(let url):
            if url.path.hasPrefix(Constants.customIconsDirectory.path) {
                return String(localized: "Custom icon “\(url.lastPathComponent)” — click to change")
            }
            return String(localized: "Package image “\(url.lastPathComponent)” — click to replace with an icon")
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // Hero Icon Button
            Button {
                isIconPickerPresented = true
                onPickIcon?()
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(isIconHovered ? 0.09 : 0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.primary.opacity(isIconHovered ? 0.22 : 0.10), lineWidth: 1)
                        )
                        .frame(width: 48, height: 48)

                    heroIconView
                        .frame(width: 48, height: 48)

                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 17))
                        .foregroundColor(.secondary)
                        .background(Circle().fill(Color(nsColor: .windowBackgroundColor)).padding(1))
                        .offset(x: 2, y: 2)
                        .opacity(isIconHovered ? 1.0 : 0.6)
                }
            }
            .buttonStyle(.plain)
            .help(iconButtonHelp)
            .onHover { isIconHovered = $0 }
            .accessibilityLabel(String(localized: "Choose icon"))
            .popover(isPresented: $isIconPickerPresented, arrowEdge: .bottom) {
                IconPickerPopover(selectedSymbol: $iconSymbol) {
                    isIconPickerPresented = false
                }
            }

            TextField("Action Name", text: $title)
                .font(.system(size: 13, weight: .medium))
                .textFieldStyle(.roundedBorder)
        }
        .padding(14)
    }
}

// MARK: - Inset Group Card Container

struct InsetGroupCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(cardStroke, lineWidth: 1)
        )
    }

    private var cardFill: Color {
        if colorScheme == .dark {
            return Color.white.opacity(0.065)
        } else {
            return Color.primary.opacity(0.04)
        }
    }

    private var cardStroke: Color {
        if colorScheme == .dark {
            return Color.white.opacity(0.12)
        } else {
            return Color.primary.opacity(0.06)
        }
    }
}

// MARK: - Icon Picker Page

/// The icon chooser as a page of the settings window. It writes to whatever binding the router was
/// handed when the page was pushed — the editor underneath stays mounted with its draft — and
/// picking an icon is what leaves the page.
@MainActor
struct IconPickerPage: View {
    @ObservedObject private var router = SettingsRouter.shared

    var body: some View {
        if let target = router.iconTarget {
            IconPickerView(selectedSymbol: target, fillsAvailableHeight: true) {
                router.pop()
            }
            .padding(20)
            .settingsPaneWidth()
        } else {
            // Nothing to write to: the chooser was reached without an editor underneath it.
            Color.clear.onAppear { router.pop() }
        }
    }
}
