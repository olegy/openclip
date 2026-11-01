// SettingsCatalog.swift
// OpenClip
//
// The list of known settings, in erased form, so code can walk every setting without knowing its
// type (snapshot, export/import, diagnostics). Keeping the list here — referencing the existing
// `SettingKey` declarations — means the "what settings exist" answer lives in one place.
//
// Dynamic per-action keys (`action.<id>.option.<id>`) are intentionally not enumerated here; they
// are scoped to their action and are not part of the global settings snapshot.
import Foundation

public enum SettingsCatalog {
    /// Every setting declared in Core.
    public static var coreKeys: [AnySettingKey] {
        [
            // Action pinning / enablement
            SettingKey.pinnedActionIDs.erased,
            SettingKey.disabledActionIDs.erased,
            SettingKey.disabledPackages.erased,
            SettingKey.actionUsageRecency.erased,
            SettingKey.actionAliases.erased,

            // Extensions
            SettingKey.extensionTrust.erased,
            SettingKey.extensionTrustHashes.erased,
            SettingKey.extensionSources.erased,
            SettingKey.automaticallyUpdatesExtensions.erased,
            SettingKey.extensionsLastUpdateCheck.erased,
            SettingKey.extensionTrustMigrated.erased,

            // App / behavior toggles
            SettingKey.isAIEnabled.erased,
            SettingKey.hasCompletedOnboarding.erased,
            SettingKey.startAtLogin.erased,
            SettingKey.completionCopyToClipboard.erased,

            // Popup presentation
            SettingKey.popupScale.erased,
            SettingKey.popupThemeColor.erased,

            // Gesture / lifecycle
            SettingKey.lastRunVersion.erased,
            SettingKey.lastRunBuild.erased,

            // Builtin action config
            SettingKey.calendarProvider.erased,
            SettingKey.searchURL.erased,
            SettingKey.fileSaveLocation.erased,

            // Structured blobs
            SettingKey.actionCustomizations.erased,
            SettingKey.customActions.erased
        ]
    }
}
