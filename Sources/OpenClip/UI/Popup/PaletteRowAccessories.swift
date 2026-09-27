// PaletteRowAccessories.swift
// OpenClip
//
// Fork: the trailing side of a palette result row. Upstream shows only the ⌘-digit hint; the fork
// puts the action's alias and its hotkey from Settings in front of it, so the row lists every way
// to reach the action: alias → hotkey → ⌘N. An inline preview still takes their place until ⌘ is
// held (`ForkBehavior.paletteRowAccessories`).
import SwiftUI
import KeyboardShortcuts
import Core

struct PaletteRowAccessories: View {
    enum Item: Equatable {
        case alias(String)
        case hotkey(String)
        /// The 1-based row number of the ⌘-digit hint.
        case commandDigit(Int)
    }

    let items: [Item]
    let isSelected: Bool
    let effectiveTheme: String

    @Environment(\.colorScheme) private var colorScheme

    /// What the row shows, in order; each part is left out when the action doesn't have it.
    static func items(alias: String, hotkey: String?, commandDigit: Int?) -> [Item] {
        var items: [Item] = []
        if !alias.isEmpty { items.append(.alias(alias)) }
        if let hotkey, !hotkey.isEmpty { items.append(.hotkey(hotkey)) }
        if let commandDigit { items.append(.commandDigit(commandDigit)) }
        return items
    }

    /// The action's hotkey from Settings, spelled like a menu shortcut (⌃⌥⇧⌘D).
    static func hotkey(for actionID: String) -> String? {
        KeyboardShortcuts.getShortcut(for: .actionHotkey(actionID))?.description
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                switch item {
                case .alias(let alias):
                    Text(alias)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(foreground)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(foreground.opacity(0.45), lineWidth: 0.5)
                        )
                        .accessibilityLabel(String(localized: "Alias \(alias)"))
                case .hotkey(let hotkey):
                    keycap(hotkey)
                case .commandDigit(let number):
                    keycap("⌘\(number)")
                        .monospacedDigit()
                        .accessibilityLabel("Command \(number)")
                }
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    private var foreground: Color {
        isSelected
            ? PopupThemeModel.restForeground(for: effectiveTheme)
            : PopupThemeModel.restSecondary(for: effectiveTheme)
    }

    /// The ⌘-digit hint's look, shared by the hotkey.
    private func keycap(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundColor(foreground)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05),
                in: RoundedRectangle(cornerRadius: 4, style: .continuous)
            )
    }
}
