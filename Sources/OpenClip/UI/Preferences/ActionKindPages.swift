// ActionKindPages.swift
// OpenClip
//
// The sidebar's Actions group, one page per kind of action: Built-in, Custom and Extensions (AI
// has its own page, `AIPage`). Each is the home of its actions — a list whose rows open the
// action's page — so every action is edited in exactly one place. The Palette page lists all of
// them again, but only to pin them and switch them on and off.

import SwiftUI
import Core

/// The hero header on top of an action kind's page: the sidebar tile, large, with the page's
/// title and a line about what lives there.
struct ActionKindHeader: View {
    let page: SettingsPage
    let subtitle: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 14) {
            SettingsIconTile(systemImage: page.systemImage, tint: page.tint, size: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(page.staticTitle ?? "")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SettingsDesignTokens.primaryText)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsDesignTokens.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if let trailing {
                trailing
            }
        }
        .padding(.vertical, 4)
    }
}

/// The actions OpenClip ships.
@MainActor
struct BuiltinActionsPage: View {
    @Binding var disabledActionIDs: Set<String>
    @Binding var disabledPackages: Set<String>

    @ObservedObject private var coordinator = ActionCoordinator.shared
    @ObservedObject private var customizationManager = ActionCustomizationManager.shared

    static func actions(in catalog: [any Action], title: (any Action) -> String) -> [any Action] {
        catalog
            .filter { ActionIdentity.isBuiltin($0) && !$0.chrome.launchesAI && !SettingsDestination.isCustomAction($0) }
            .sorted { title($0).localizedStandardCompare(title($1)) == .orderedAscending }
    }

    var body: some View {
        Form {
            Section {
                ActionKindHeader(
                    page: .builtinActions,
                    subtitle: String(localized: "The actions that come with OpenClip.")
                )
            }

            Section {
                ForEach(Self.actions(in: coordinator.actions, title: title), id: \.id) { action in
                    ActionSettingsRow(
                        action: action,
                        disabledActionIDs: $disabledActionIDs,
                        disabledPackages: $disabledPackages
                    )
                }
            } footer: {
                Text("Turn an action off to hide it from the palette. Open one to change its name, icon, alias, shortcut and options.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func title(_ action: any Action) -> String {
        customizationManager.presented(action, surface: .table).title
    }
}

/// The installed extension packages, each a way into its own page.
@MainActor
struct ExtensionsPage: View {
    @Binding var disabledActionIDs: Set<String>
    @Binding var disabledPackages: Set<String>

    @ObservedObject private var coordinator = ActionCoordinator.shared
    @ObservedObject private var router = SettingsRouter.shared

    /// Installed packages by name, without the single-action packages Custom writes for the
    /// user's own actions.
    static func packages(in catalog: [any Action]) -> [InstalledExtensionInfo] {
        InstalledExtensionInfo.all(from: catalog)
    }

    var body: some View {
        let packages = Self.packages(in: coordinator.actions)
        Form {
            Section {
                ActionKindHeader(
                    page: .extensions,
                    subtitle: String(localized: "Actions installed from the Store or from the extensions folder.")
                )
            }

            Section {
                if packages.isEmpty {
                    Text("No extensions installed.")
                        .foregroundStyle(.secondary)
                }
                ForEach(packages) { info in
                    packageRow(info)
                }

                SettingsDisclosureRow {
                    router.select(.store)
                } content: {
                    Label("Browse the Store", systemImage: "archivebox")
                        .foregroundStyle(Color.accentColor)
                }
            } footer: {
                Text("Turn an extension off to hide all of its actions from the palette.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func packageRow(_ info: InstalledExtensionInfo) -> some View {
        let isEnabled = ActionEnablement.packageBinding(
            packageID: info.packageID,
            gatedReason: info.gatedReason,
            disabledPackages: $disabledPackages,
            disabledActionIDs: $disabledActionIDs
        )
        let path = SettingsDestination.path(forPackage: info.packageID)
        return HStack(spacing: 10) {
            Button {
                router.show(path: path)
            } label: {
                HStack(spacing: 10) {
                    ActionIconView(icon: Self.plainGlyph(info.icon), size: 14)
                        .frame(width: 18, height: 18)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(info.name)
                            .font(.system(size: 13))
                            .foregroundStyle(isEnabled.wrappedValue ? .primary : .secondary)
                            .lineLimit(1)
                        Text(subtitle(for: info))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle("", isOn: isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel(String(localized: "Enable \(info.name)"))

            Button {
                router.show(path: path)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Configure \(info.name)"))
        }
        .padding(.vertical, 3)
    }

    private func subtitle(for info: InstalledExtensionInfo) -> String {
        if info.gatedReason != nil {
            return String(localized: "Needs your approval")
        }
        return info.commands.count == 1
            ? String(localized: "1 action")
            : String(localized: "\(info.commands.count) actions")
    }

    /// A package icon that is a word rather than a glyph reads as noise at row size.
    static func plainGlyph(_ icon: ActionIcon) -> ActionIcon {
        if case .text(let text) = icon, text.count > 2 {
            return .symbol("puzzlepiece.extension")
        }
        return icon
    }
}
