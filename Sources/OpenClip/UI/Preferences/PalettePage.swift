// PalettePage.swift
// OpenClip
//
// Every action the palette can show, in two lists: the ones pinned to the top of the palette,
// dragged into the order the palette opens with, and all the others by name. Right-click a row to
// pin or unpin it; at most `PinnedActionStore.limit` actions are pinned. Each row carries its enable
// switch and opens the action's own page on click — nothing else is edited here. The search field
// lives in the window toolbar, like the Store's.

import SwiftUI
import Core

@MainActor
struct PalettePage: View {
    @Binding var disabledActionIDs: Set<String>
    @Binding var disabledPackages: Set<String>
    /// The toolbar's search field, routed here by the window while this page is on screen.
    @Binding var query: String

    @ObservedObject private var coordinator = ActionCoordinator.shared
    @ObservedObject private var customizationManager = ActionCustomizationManager.shared
    @ObservedObject private var bindingStore = ActionBindingStore.shared
    @ObservedObject private var pinnedStore = PinnedActionStore.shared

    /// The actions the palette can list: runnable leaves, not group rows, the AI launcher or the
    /// placeholder of an extension waiting for approval.
    static func paletteActions(in catalog: [any Action]) -> [any Action] {
        catalog.filter { action in
            action.chrome.popupBehavior != .showSubActions
                && !action.chrome.launchesAI
                && !(action is GatedExtensionAction)
        }
    }

    private var actions: [any Action] {
        Self.paletteActions(in: coordinator.actions)
    }

    private var existingIDs: Set<String> {
        Set(actions.map(\.id))
    }

    private func title(_ action: any Action) -> String {
        customizationManager.presented(action, surface: .table).title
    }

    private func matches(_ action: any Action) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        if title(action).lowercased().contains(needle) { return true }
        if (bindingStore.alias(for: action.id) ?? "").lowercased().contains(needle) { return true }
        if let source = sourceName(of: action), source.lowercased().contains(needle) { return true }
        return action.keywords.contains { $0.lowercased().contains(needle) }
    }

    var body: some View {
        let byID = Dictionary(actions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let pinnedIDs = pinnedStore.resolved(in: existingIDs)
        let pinnedSet = Set(pinnedIDs)
        let isFiltering = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let visiblePinned = pinnedIDs.filter { id in byID[id].map(matches) ?? false }
        let others = actions
            .filter { !pinnedSet.contains($0.id) && matches($0) }
            .sorted { title($0).localizedStandardCompare(title($1)) == .orderedAscending }
        let canPin = pinnedIDs.count < PinnedActionStore.limit

        ZStack {
            Form {
                if !isFiltering || !visiblePinned.isEmpty {
                    Section {
                        if pinnedIDs.isEmpty {
                            Text("Right-click an action and choose Pin to keep it at the top of the palette.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else if isFiltering {
                            // Dragging a filtered list would reorder rows the user cannot see.
                            ForEach(visiblePinned, id: \.self) { id in
                                if let action = byID[id] {
                                    row(action, isPinned: true, canPin: canPin)
                                }
                            }
                        } else {
                            ReorderableRows(
                                ids: pinnedIDs,
                                dragPreviewTitle: { id in byID[id].map(title) ?? id },
                                onMove: { id, gap in pinnedStore.move(id, toGap: gap, existingIDs: existingIDs) }
                            ) { id in
                                if let action = byID[id] {
                                    row(action, isPinned: true, canPin: canPin)
                                }
                            }
                        }
                    } header: {
                        Text("Pinned")
                    } footer: {
                        if !isFiltering {
                            Text("Pinned actions open at the top of the palette, in this order. Drag to reorder. Up to \(PinnedActionStore.limit) actions.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !others.isEmpty {
                    Section {
                        ForEach(others, id: \.id) { action in
                            row(action, isPinned: false, canPin: canPin)
                        }
                    } header: {
                        Text("All Actions")
                    } footer: {
                        Text("The rest of the palette lists the most recently used actions first. Turn an action off to hide it from the palette; open it to change its alias and shortcut.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            if isFiltering && visiblePinned.isEmpty && others.isEmpty {
                ContentUnavailableView.search(text: query)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func row(_ action: any Action, isPinned: Bool, canPin: Bool) -> some View {
        ActionSettingsRow(
            action: action,
            disabledActionIDs: $disabledActionIDs,
            disabledPackages: $disabledPackages,
            subtitle: sourceName(of: action)
        )
        .contextMenu {
            if isPinned {
                Button {
                    pinnedStore.unpin(action.id)
                } label: {
                    Label("Unpin", systemImage: "pin.slash")
                }
            } else {
                Button {
                    pinnedStore.pin(action.id, existingIDs: existingIDs)
                } label: {
                    Label("Pin", systemImage: "pin")
                }
                .disabled(!canPin)
            }

            Divider()

            Button("Open Settings") {
                SettingsDestination.open(action)
            }
        }
    }

    /// Where the action comes from, as the sidebar names it — or the extension's name.
    private func sourceName(of action: any Action) -> String? {
        if ActionIdentity.isAIPreset(action) {
            return SettingsPage.ai.staticTitle
        }
        if SettingsDestination.isCustomAction(action) {
            return SettingsPage.customActions.staticTitle
        }
        if let packageID = ActionIdentity.extensionPackageID(of: action),
           let info = InstalledExtensionInfo.info(for: packageID, in: coordinator.actions) {
            return info.name
        }
        if ActionIdentity.isBuiltin(action) {
            return SettingsPage.builtinActions.staticTitle
        }
        return nil
    }
}
