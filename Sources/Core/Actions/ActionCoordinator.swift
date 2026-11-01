// ActionCoordinator.swift
// OpenClip
//
// Composition root that connects builtin actions and disk extensions to the central
// ActionRegistry. Wires the onRegister/onUnregister callbacks that ExtensionManager
// uses to report changes, so the manager never touches ActionRegistry directly.
import Foundation
import Combine

/// Deep module unifying action discovery, extension scanning, and custom action persistence.
@MainActor
public final class ActionCoordinator: ObservableObject, Sendable {
    public static let shared = ActionCoordinator()
    
    @Published public private(set) var actions: [any Action] = []
    
    private let registry: ActionRegistry
    private let extensionManager: ExtensionManager
    private let settingsStore: any SettingsStore
    private var cancellables = Set<AnyCancellable>()
    
    internal init(
        registry: ActionRegistry = .shared,
        extensionManager: ExtensionManager = .shared,
        settingsStore: any SettingsStore = DefaultSettingsStore.shared
    ) {
        self.registry = registry
        self.extensionManager = extensionManager
        self.settingsStore = settingsStore
        registry.$actions
            .assign(to: &$actions)
    }
    
    public func loadInitialState(
        extensionsDirectory: URL = Constants.extensionsDirectory,
        dictionaryLookup: @escaping @Sendable (String) -> String? = { _ in nil }
    ) async {
        // Wire the extension manager to the registry through callbacks — it never touches
        // ActionRegistry directly.
        extensionManager.onRegister = { [registry] action in
            registry.register(action: action)
        }
        extensionManager.onUnregister = { [registry] actionID in
            registry.unregister(actionID: actionID)
        }

        // 1. Core builtins
        let coreBuiltins = BuiltinRegistry.makeCoreBuiltins(
            settingsStore: settingsStore,
            dictionaryLookup: dictionaryLookup
        )
        registry.register(builtIns: coreBuiltins)
        
        // 2. Disk extensions (manifests, standalone scripts, snippets)
        await extensionManager.loadExtensions(from: extensionsDirectory)

        // 3. First-class custom actions
        loadCustomActions()
    }
    

    /// Catalog for the action-search palette, filtered to actions that can perform given `context`.
    /// Settings-disabled actions remain visible; contextually-unable ones (no selection, regex/app
    /// gate, clipboard fallback) are dropped.
    public func searchCatalog(for context: ActionContext) -> [any Action] {
        registry.searchCatalog(for: context)
    }
    
    public func register(action: any Action) {
        registry.register(action: action)
    }
    
    public func unregister(actionID: String) {
        registry.unregister(actionID: actionID)
    }

    public func replaceActions(matching isMatch: @escaping (any Action) -> Bool, with newActions: [any Action]) {
        registry.replaceRegisteredActions(matching: isMatch, with: newActions)
        self.actions = registry.actions
    }

    // MARK: - Custom Actions

    public private(set) var customActions: [CustomAction] = []

    public func loadCustomActions() {
        if let data = settingsStore.get(.customActions),
           let document = try? SettingsDocument<[CustomAction]>.decode(from: data) {
            self.customActions = document.payload
        } else {
            self.customActions = []
        }
        for action in customActions {
            registry.register(action: action)
        }
    }

    public func saveCustomAction(_ action: CustomAction) {
        var updated = customActions
        if let idx = updated.firstIndex(where: { $0.id == action.id }) {
            updated[idx] = action
        } else {
            updated.append(action)
        }
        persistCustomActions(updated)
        registry.register(action: action)
        self.actions = registry.actions
    }

    public func deleteCustomAction(actionID: String) {
        var updated = customActions
        updated.removeAll(where: { $0.id == actionID })
        persistCustomActions(updated)
        registry.unregister(actionID: actionID)
        self.actions = registry.actions

        var disabled = settingsStore.get(.disabledActionIDs)
        if disabled.contains(actionID) {
            disabled.remove(actionID)
            settingsStore.set(.disabledActionIDs, value: disabled)
        }
        // A deleted action's palette alias must go with it, or it stays reserved and a new action
        // can never claim it ("That alias is already used").
        ActionBindingStore.shared.setAlias(nil, for: actionID)
        ActionCustomizationManager.shared.resetOverride(for: actionID)
        PinnedActionStore.shared.unpin(actionID)
    }

    @discardableResult
    public func duplicateCustomAction(actionID: String) -> CustomAction? {
        guard let original = customActions.first(where: { $0.id == actionID }) else {
            return nil
        }
        let newID = "custom.\(UUID().uuidString.prefix(8).lowercased())"
        let override = ActionCustomizationManager.shared.override(for: actionID)
        let baseTitle = override?.customTitle ?? original.title
        let baseIcon = override?.customIconSymbol ?? original.iconName
        let copyTitle = "\(baseTitle) Copy"

        let duplicated = CustomAction(
            id: newID,
            title: copyTitle,
            iconName: baseIcon,
            type: original.type,
            chrome: original.chrome,
            rules: original.rules
        )

        saveCustomAction(duplicated)
        return duplicated
    }

    private func persistCustomActions(_ actions: [CustomAction]) {
        self.customActions = actions
        if let encoded = try? SettingsDocument(payload: actions).encoded() {
            settingsStore.set(.customActions, value: encoded)
        }
    }
}
