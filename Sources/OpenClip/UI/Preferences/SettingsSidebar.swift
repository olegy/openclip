// SettingsSidebar.swift
// OpenClip
//
// The window's table of contents:
// - Sits directly on the window background (no card, border or shadow).
// - Top-left traffic lights space, then the rows.
// - Fixed width (~216pt), ~30pt pitch rows.
// - Every row has a ~20pt rounded-square icon tile with a white glyph on a colored fill.
// - Selection: subtle translucent rounded highlight (~11% opacity, ~10pt radius), NOT accent color.
// - Two groups: the app's own pages, then a dim static "Actions" label over one page per kind of
//   action (AI, Built-in, Custom, Extensions). Eight rows in all, so there is no search field.

import SwiftUI
import AppKit
import Core

// MARK: - Rows

/// One sidebar row.
struct SettingsSidebarRow: Identifiable {
    let page: SettingsPage
    let title: String
    let isDisabled: Bool

    var id: String { page.id }

    init(page: SettingsPage, isDisabled: Bool = false) {
        self.page = page
        self.title = page.staticTitle ?? page.id
        self.isDisabled = isDisabled
    }
}

/// Stable palette and hash-based tints for extensions.
enum SettingsTint {
    static let general = Color(nsColor: .systemGray)
    static let appearance = Color(red: 0.95, green: 0.35, blue: 0.60)
    static let palette = Color(red: 0.65, green: 0.35, blue: 0.95)
    static let orange = Color(red: 0.98, green: 0.52, blue: 0.12)
    static let ai = Color(red: 0.36, green: 0.40, blue: 0.96)
    static let builtin = orange
    static let custom = Color(red: 0.93, green: 0.30, blue: 0.45)
    static let extensions = Color(red: 0.10, green: 0.68, blue: 0.62)
    static let store = Color(red: 0.05, green: 0.52, blue: 0.98)
    static let about = Color(red: 0.20, green: 0.78, blue: 0.42)
    static let neutral = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(red: 0.22, green: 0.22, blue: 0.25, alpha: 1.0)
        } else {
            return NSColor(red: 0.55, green: 0.55, blue: 0.58, alpha: 1.0)
        }
    }))

    static var openClip: Color {
        Color.accentColor
    }

    static let reservedBlueHues: Range<Int> = 190..<270

    static func extensionTint(for packageID: String) -> Color {
        Color(hue: Double(hue(for: packageID)) / 360.0, saturation: 0.74, brightness: 0.88)
    }

    static func hue(for packageID: String) -> Int {
        var hash = 0
        for byte in packageID.utf8 {
            hash = (hash &* 31 &+ Int(byte)) % 360
        }
        let available = 360 - reservedBlueHues.count
        var value = ((hash % available) + available) % available
        if value >= reservedBlueHues.lowerBound {
            value += reservedBlueHues.count
        }
        return value
    }
}

// MARK: - Tiles

/// The ~20pt coloured rounded square with a white glyph on front of every sidebar row.
struct SettingsIconTile: View {
    let systemImage: String
    let tint: Color
    var size: CGFloat = SettingsDesignTokens.iconTileSize

    var body: some View {
        SettingsTileBackground(tint: tint, size: size)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.56, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 0.5, y: 0.5)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The same tile for an extension, drawing whatever icon the package ships.
struct ExtensionIconTile: View {
    let icon: ActionIcon
    let tint: Color
    var size: CGFloat = SettingsDesignTokens.iconTileSize

    var body: some View {
        SettingsTileBackground(tint: tint, size: size)
            .overlay {
                switch icon {
                case .text(let text):
                    Text(String(text.trimmingCharacters(in: .whitespaces).prefix(2)))
                        .font(.system(size: size * 0.48, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                default:
                    ActionIconView(icon: icon, size: size * 0.58)
                        .foregroundStyle(.white)
                        .frame(width: size * 0.72, height: size * 0.72)
                        .clipped()
                }
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private struct SettingsTileBackground: View {
    let tint: Color
    let size: CGFloat

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SettingsDesignTokens.iconTileRadius(for: size), style: .continuous)
    }

    var body: some View {
        shape
            .fill(
                LinearGradient(
                    colors: [tint.opacity(0.96), tint],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), Color.white.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
            }
    }
}

// MARK: - Sidebar

@MainActor
struct SettingsSidebar: View {
    @Binding var selection: SettingsPage?
    let systemRows: [SettingsSidebarRow]
    let actionRows: [SettingsSidebarRow]
    @State private var hoveredRowID: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Space for the traffic lights.
            Color.clear
                .frame(height: 46)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(systemRows) { row in
                        rowView(row)
                    }

                    sectionHeader("Actions")

                    ForEach(actionRows) { row in
                        rowView(row)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
        }
        .frame(width: SettingsDesignTokens.sidebarWidth)
        .background(Color.clear)
    }

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(SettingsDesignTokens.secondaryText.opacity(0.7))
            .padding(.leading, 10)
            .padding(.top, SettingsDesignTokens.sidebarGroupSpacing)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }

    private func rowView(_ row: SettingsSidebarRow) -> some View {
        let isSelected = selection == row.page
        let isHovered = hoveredRowID == row.id && !isSelected

        return Button {
            selection = row.page
        } label: {
            HStack(spacing: 10) {
                SettingsIconTile(systemImage: row.page.systemImage, tint: row.page.tint, size: SettingsDesignTokens.iconTileSize)

                Text(row.title)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(SettingsDesignTokens.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: SettingsDesignTokens.sidebarRowPitch)
            .background(
                RoundedRectangle(cornerRadius: SettingsDesignTokens.sidebarSelectionRadius, style: .continuous)
                    .fill(isSelected ? SettingsDesignTokens.selectedRowBackground : (isHovered ? SettingsDesignTokens.hoveredRowBackground : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(row.isDisabled ? Text("Disabled") : Text(""))
        .onHover { hovering in
            if hovering {
                hoveredRowID = row.id
            } else if hoveredRowID == row.id {
                hoveredRowID = nil
            }
        }
        .opacity(row.isDisabled ? 0.45 : 1.0)
        .saturation(row.isDisabled ? 0.5 : 1.0)
    }
}
