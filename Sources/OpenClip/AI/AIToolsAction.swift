// AIToolsAction.swift
// OpenClip
//
// The "AI Tools" launcher: the builtin row that owns the AI presets, so switching AI off hides
// every preset with it. Never a search-palette entry (`chrome.launchesAI` is excluded in
// `ActionRegistry.searchCatalog`). Its enable state is single-sourced to
// `AIServiceManager.isAIEnabled`, which the AI-tab and Actions-tab toggles share.
import Foundation
import Core

public struct AIToolsAction: Action, SubActionProviding {
    private let settingsStore: any SettingsStore

    public init(settingsStore: any SettingsStore = DefaultSettingsStore.shared) {
        self.settingsStore = settingsStore
    }

    public var id: String { "builtin.aiTools" }
    public var title: String { String(localized: "AI Tools") }
    public var icon: ActionIcon { .symbol(Constants.defaultAIIconSymbol) }
    public var chrome: ActionChrome {
        ActionChrome(badge: .none, rowStyle: .standard, popupBehavior: .perform, source: .builtin, launchesAI: true)
    }

    @MainActor
    public func isEnabled(for context: ActionContext) -> Bool {
        settingsStore.get(.isAIEnabled)
    }

    /// Defensive fallback: the palette excludes this
    /// action, so `perform` is never the entry point (same contract as `AIAction`).
    @MainActor
    public func perform(_ context: ActionContext) async throws -> ActionResult {
        .success
    }

    // The AI Tools launcher's sub-actions are the registered AI presets (chrome source `.ai`).
    @MainActor
    public func subActions(in catalog: [any Action]) -> [any Action] {
        catalog.filter { ActionIdentity.isAIPreset($0) }
    }
}
