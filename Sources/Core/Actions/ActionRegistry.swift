// ActionRegistry.swift
// OpenClip
//
// Stores all registered actions, providing a reactive catalog of available text manipulations in
// registration order, and filters it into the palette's catalog by settings and context.
import Foundation
import Combine

@MainActor
public final class ActionRegistry: ObservableObject, Sendable {
    public static let shared = ActionRegistry()
    
    @Published public private(set) var actions: [any Action] = []
    private var registeredActions: [any Action] = []
    private let settingsStore: SettingsStore
    
    public init(settingsStore: SettingsStore = DefaultSettingsStore.shared) {
        self.settingsStore = settingsStore
    }
    
    public func register(builtIns: [any Action]) {
        // Dedupe against existing registeredActions and against earlier entries within the same batch,
        // so repeated loadInitialState() calls or a duplicate entry in the catalog don't append twice.
        var seenIDs = Set(registeredActions.map(\.id))
        registeredActions.append(contentsOf: builtIns.filter { action in
            guard !seenIDs.contains(action.id) else { return false }
            seenIDs.insert(action.id)
            return true
        })
        publish()
    }
    
    public func register(action: any Action) {
        // Replace if ID already exists, otherwise append
        if let idx = registeredActions.firstIndex(where: { $0.id == action.id }) {
            registeredActions[idx] = action
        } else {
            registeredActions.append(action)
        }
        publish()
    }
    
    /// Publishes the catalog in registration order. There is no user order to apply: the palette
    /// orders its own rows (`PaletteOrder`), and Settings lists actions by name.
    private func publish() {
        actions = registeredActions
    }

    public func unregister(actionID: String) {
        registeredActions.removeAll(where: { $0.id == actionID })
        publish()
    }

    public func replaceRegisteredActions(matching isMatch: (any Action) -> Bool, with newActions: [any Action]) {
        registeredActions.removeAll(where: isMatch)
        registeredActions.append(contentsOf: newActions)
        publish()
    }

    public var registeredActionIDs: Set<String> {
        Set(registeredActions.map(\.id))
    }

    /// Clears all registered actions. Test-isolation hook so the shared singleton does not leak
    /// state across test cases.
    public func reset() {
        actions = []
        registeredActions = []
    }
    
    /// Context gating for the palette: can this action actually perform against the current
    /// selection/app? Settings-disable state is applied separately (see `settingsHiddenIDs`).
    /// Actions that require a live selection are excluded from clipboard input. An AI preset answers through
    /// its own `isEnabled`, which reads the preset's toggle in AI settings, so a preset switched
    /// off there is not offered anywhere.
    private func canPerform(_ action: any Action, in context: ActionContext) -> Bool {
        // Clipboard input is not an editable source selection.
        if context.selection.source != .selection && action.chrome.requiresLiveSelection {
            return false
        }
        return action.isEnabled(for: context)
    }

    /// Whether the user has switched this action off in settings — per action, or through its
    /// whole extension package.
    private func isDisabledInSettings(_ action: any Action, disabledIDs: Set<String>, disabledPackages: Set<String>) -> Bool {
        if disabledIDs.contains(action.id) { return true }
        if let packageID = ActionIdentity.extensionPackageID(of: action), disabledPackages.contains(packageID) {
            return true
        }
        return false
    }

    /// Group rows whose members must be hidden with them: a disabled group never leaks its
    /// sub-actions. `isRowVisible` decides whether a group row itself survives.
    private func hiddenGroupIDs(isRowVisible: (any Action) -> Bool) -> Set<String> {
        Set(
            actions
                .filter { $0.chrome.popupBehavior == .showSubActions || $0.chrome.launchesAI }
                .filter { !isRowVisible($0) }
                .map(\.id)
        )
    }

    /// True when the action belongs to a group in `hiddenGroupIDs` — either by id prefix (extension
    /// groups) or by provider-declared membership (AI presets under the AI launcher).
    private func belongsToHiddenGroup(_ action: any Action, hiddenGroupIDs: Set<String>, memberToGroupID: [String: String]) -> Bool {
        if hiddenGroupIDs.contains(where: { action.id.hasPrefix($0 + ".") }) { return true }
        if let owningGroupID = memberToGroupID[action.id], hiddenGroupIDs.contains(owningGroupID) {
            return true
        }
        return false
    }

    /// Explicit and provider-declared membership, including AI presets with canonical IDs.
    private func groupMembership() -> [String: String] {
        var map: [String: String] = [:]
        let resolver = SubActionResolver()
        for parent in actions {
            for child in resolver.subActions(of: parent, in: actions) {
                map[child.id] = parent.id
            }
        }
        return map
    }

    /// The registered catalog for the action-search palette: what the user can actually run right
    /// now. An action switched off in settings never appears — per action, through its whole
    /// extension package, through a disabled extension group (whose members go with it), or, for an AI
    /// preset, through its toggle in AI settings. Actions that cannot run against this context drop too:
    /// `isEnabled(for:)` failures (no selection, regex/app/expression gates), and clipboard-fallback
    /// actions that require a live selection. Sub-actions appear individually, flat; group rows remain (their sub-actions are
    /// reachable directly from the palette). `chrome.launchesAI` launchers are always excluded.
    public func searchCatalog(for context: ActionContext) -> [any Action] {
        let disabledIDs = settingsStore.get(.disabledActionIDs)
        let disabledPackages = settingsStore.get(.disabledPackages)
        // A group row hides its members here on settings state alone: the palette lists the
        // members, not the row, so "the group is off" has to reach them.
        let hiddenGroups = hiddenGroupIDs { row in
            !isDisabledInSettings(row, disabledIDs: disabledIDs, disabledPackages: disabledPackages)
        }
        let memberToGroupID = groupMembership()

        return actions.filter { action in
            if action.chrome.launchesAI || action is GatedExtensionAction {
                return false
            }
            if isDisabledInSettings(action, disabledIDs: disabledIDs, disabledPackages: disabledPackages) {
                return false
            }
            if belongsToHiddenGroup(action, hiddenGroupIDs: hiddenGroups, memberToGroupID: memberToGroupID) {
                return false
            }
            return canPerform(action, in: context)
        }
    }
}
