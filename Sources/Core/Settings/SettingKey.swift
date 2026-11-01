// SettingKey.swift
// OpenClip
//
// Defines strongly-typed setting keys and default values for central configuration management via the Settings Door.
import Foundation

public struct SettingKey<Value: Sendable>: Sendable {
    public let name: String
    public let defaultValue: Value
    /// Bumped when the meaning or shape of this setting's stored value changes, so a future
    /// migration can tell old data from new. Brand-new keys start at 1.
    public let schemaVersion: Int

    public init(_ name: String, defaultValue: Value, schemaVersion: Int = 1) {
        self.name = name
        self.defaultValue = defaultValue
        self.schemaVersion = schemaVersion
    }
}

/// Stable per-action option namespaces (Phase 7). `defaultsKey` is the SettingsStore/UserDefaults
/// key for non-secret options; `keychainAccount` names the Keychain account for `.secret` options.
/// Both produce the same `action.<actionID>.option.<optionID>` string — one namespace, two backends
/// (secrets never touch UserDefaults).
public enum ActionOptionKey {
    public static func defaultsKey(actionID: String, optionID: String) -> String {
        "action.\(actionID).option.\(optionID)"
    }

    public static func keychainAccount(actionID: String, optionID: String) -> String {
        defaultsKey(actionID: actionID, optionID: optionID)
    }
}

public extension SettingKey where Value == [String] {
    /// The actions pinned to the top of the palette, in the order the user dragged them into.
    /// At most `PinnedActionStore.limit` of them.
    static var pinnedActionIDs: SettingKey<[String]> { SettingKey<[String]>("action.pinned", defaultValue: []) }
}

public extension SettingKey where Value == Set<String> {
    static var disabledActionIDs: SettingKey<Set<String>> { SettingKey<Set<String>>("disabledActionIDs", defaultValue: []) }
    static var disabledPackages: SettingKey<Set<String>> { SettingKey<Set<String>>("disabledPackages", defaultValue: []) }
}

public extension SettingKey where Value == [String: Int] {
    static var actionUsageRecency: SettingKey<[String: Int]> { SettingKey<[String: Int]>("actionUsageRecency", defaultValue: [:]) }
}

public extension SettingKey where Value == [String: String] {
    /// packageID -> "seen" | "trusted" | "revoked"
    static var extensionTrust: SettingKey<[String: String]> { SettingKey<[String: String]>("extension.trust", defaultValue: [:]) }
    /// packageID -> content hash recorded at enable time (tamper-watch baseline)
    static var extensionTrustHashes: SettingKey<[String: String]> { SettingKey<[String: String]>("extension.trustHashes", defaultValue: [:]) }
    /// packageID -> "store" | "local"
    static var extensionSources: SettingKey<[String: String]> { SettingKey<[String: String]>("extension.sources", defaultValue: [:]) }
    /// actionID -> lowercase exact-match search alias
    static var actionAliases: SettingKey<[String: String]> { SettingKey<[String: String]>("action.aliases", defaultValue: [:]) }
}

public extension SettingKey where Value == Bool {
    static var isAIEnabled: SettingKey<Bool> { SettingKey<Bool>("aiEnabled", defaultValue: true) }
    static var hasCompletedOnboarding: SettingKey<Bool> { SettingKey<Bool>("hasCompletedOnboarding", defaultValue: false) }
    static var startAtLogin: SettingKey<Bool> { SettingKey<Bool>("startAtLogin", defaultValue: false) }
    static var completionCopyToClipboard: SettingKey<Bool> { SettingKey<Bool>("completionCopyToClipboard", defaultValue: false) }
    /// True once the one-time migration (auto-trust existing installs) has run.
    static var extensionTrustMigrated: SettingKey<Bool> { SettingKey<Bool>("extension.trustMigrated", defaultValue: false) }
    static var automaticallyUpdatesExtensions: SettingKey<Bool> { SettingKey<Bool>("extension.automaticallyUpdates", defaultValue: true) }
}

public extension SettingKey where Value == Int {
    /// Visual scaling level for the popup from 1 to 5 (3 = Normal / Default).
    static var popupScale: SettingKey<Int> { SettingKey<Int>("popupScale", defaultValue: 3) }
}

public extension SettingKey where Value == Double {
    /// When the store was last checked for extension updates (seconds since 1970; 0 = never).
    /// Automatic checks run at most once a day (`ExtensionUpdateManager.automaticCheckInterval`).
    static var extensionsLastUpdateCheck: SettingKey<Double> { SettingKey<Double>("extension.lastUpdateCheck", defaultValue: 0) }
}

public extension SettingKey where Value == Data? {
    static var actionCustomizations: SettingKey<Data?> { SettingKey<Data?>("action.customizations", defaultValue: nil) }
    static var customActions: SettingKey<Data?> { SettingKey<Data?>("customActions", defaultValue: nil) }
}

public extension SettingKey where Value == String {
    static var calendarProvider: SettingKey<String> { SettingKey<String>("action.calendar.provider", defaultValue: "native") }
    static var searchURL: SettingKey<String> { SettingKey<String>("action.search.url", defaultValue: "https://www.google.com/search?q={query}") }


    /// Default directory where action file outputs are saved. Defaults to empty string (which resolves to ~/Downloads).
    static var fileSaveLocation: SettingKey<String> { SettingKey<String>("fileSaveLocation", defaultValue: "") }

    /// Popup appearance: "system"/"light"/"dark".
    static var popupThemeColor: SettingKey<String> { SettingKey<String>("popupThemeColor", defaultValue: "system") }

    /// The last version string (CFBundleShortVersionString) the app was launched on.
    /// Used to classify launch scenarios (First Install, App Update, Reinstall, Normal Launch).
    static var lastRunVersion: SettingKey<String> { SettingKey<String>("app.lastRunVersion", defaultValue: "") }
    /// The last build number (CFBundleVersion) the app was launched on.
    static var lastRunBuild: SettingKey<String> { SettingKey<String>("app.lastRunBuild", defaultValue: "") }

    /// Per-action option value key. The key name matches the legacy `action.<id>.option.<optID>`
    /// convention so existing stored values migrate over with zero data changes.
    static func actionOption(actionID: String, optionID: String, default defaultValue: String = "") -> SettingKey<String> {
        SettingKey<String>("action.\(actionID).option.\(optionID)", defaultValue: defaultValue)
    }
}
