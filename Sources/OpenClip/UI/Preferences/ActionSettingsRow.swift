// ActionSettingsRow.swift
// OpenClip
//
// One action as a row of a settings list: its icon and name, its palette alias and hotkey as the
// palette shows them, whether it is on, and the chevron that says the row is a way in.
//
// Every list of actions in the window is this row: Palette, Built-in, Custom and the commands on
// an extension's page. Nothing is edited in the row except the switch — a click anywhere else
// opens the action's own page, where its name, icon, alias, hotkey and options live. That is how
// the AI actions list has always worked, and one rule everywhere is easier than inline fields in
// some lists and not in others.

import SwiftUI
import Core

@MainActor
struct ActionSettingsRow: View {
    let action: any Action
    @Binding var disabledActionIDs: Set<String>
    @Binding var disabledPackages: Set<String>
    /// A second line under the name, where a list has something worth saying about each row (the
    /// kind of a custom action, the extension a command comes from). Nil keeps the row one line.
    var subtitle: String?

    init(
        action: any Action,
        disabledActionIDs: Binding<Set<String>>,
        disabledPackages: Binding<Set<String>>,
        subtitle: String? = nil
    ) {
        self.action = action
        _disabledActionIDs = disabledActionIDs
        _disabledPackages = disabledPackages
        self.subtitle = subtitle
    }

    @ObservedObject private var customizationManager = ActionCustomizationManager.shared
    @ObservedObject private var bindingStore = ActionBindingStore.shared

    var body: some View {
        let presentation = customizationManager.presented(action, surface: .table)
        let isEnabled = ActionEnablement.binding(
            for: action,
            disabledActionIDs: $disabledActionIDs,
            disabledPackages: $disabledPackages
        )

        HStack(spacing: 10) {
            Button {
                SettingsDestination.open(action)
            } label: {
                HStack(spacing: 10) {
                    ActionIconView(icon: presentation.icon, size: 14)
                        .frame(width: 18, height: 18)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(presentation.title)
                            .font(.system(size: 13))
                            .foregroundStyle(isEnabled.wrappedValue ? .primary : .secondary)
                            .lineLimit(1)
                        if let subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 8)

                    if ActionIdentity.isBindable(action) {
                        PaletteRowAccessories(
                            items: PaletteRowAccessories.items(
                                alias: bindingStore.alias(for: action.id) ?? "",
                                hotkey: PaletteRowAccessories.hotkey(for: action.id),
                                commandDigit: nil
                            ),
                            isSelected: false,
                            effectiveTheme: "",
                            tint: .secondary
                        )
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Configure Action")

            Toggle("", isOn: isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel(String(localized: "Enable \(presentation.title)"))

            Button {
                SettingsDestination.open(action)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Configure \(presentation.title)"))
        }
        .padding(.vertical, 3)
    }
}
