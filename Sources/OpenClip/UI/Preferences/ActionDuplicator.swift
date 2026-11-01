// ActionDuplicator.swift
// OpenClip
//
// Duplicates a custom action or an installed extension. The copy is made from the action's own
// page.

import Core

enum ActionDuplicator {
    /// Returns the copy's id, or nil when the action cannot be duplicated or the copy failed (the
    /// failure is reported in the window).
    @MainActor
    static func duplicate(actionID id: String) async -> String? {
        let coordinator = ActionCoordinator.shared
        guard let action = coordinator.actions.first(where: { $0.id == id }),
              ActionIdentity.canDuplicate(action) else { return nil }

        if action.chrome.source == .custom || action is CustomAction || action.id.hasPrefix("custom.") {
            return coordinator.duplicateCustomAction(actionID: id)?.id
        }

        guard case .extensionPkg = action.chrome.source else { return nil }
        do {
            return try await ExtensionManager.shared.duplicateExtension(actionID: id)
        } catch {
            Log.extensions.error("Failed to duplicate extension '\(id, privacy: .public)': \(error.localizedDescription)")
            SettingsRouter.shared.notifyError(
                title: String(localized: "Duplicate Failed"),
                message: String(localized: "OpenClip could not duplicate extension: \(error.localizedDescription)")
            )
            return nil
        }
    }
}
