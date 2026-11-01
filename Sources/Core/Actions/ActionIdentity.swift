// ActionIdentity.swift
// OpenClip
//
// Canonical "loaded by" classification for an action, derived from its chrome metadata. Every UI
// surface (palette, Preferences, onboarding) previously re-wrote `if case .X = action.chrome.*`
// heuristics; this is the single home so classification can't drift between surfaces. Pure Core —
// no AppKit/SwiftUI, no `switch action.id` string matching.
import Foundation

public enum ActionIdentity {
    /// True for first-party builtin rows (Search/Calculate/… and the AI Tools launcher).
    public static func isBuiltin(_ action: any Action) -> Bool {
        if case .builtin = action.chrome.source { return true }
        return false
    }

    /// True for actions shipped by an installed extension package (matches on either the chrome
    /// source or the badge — both legacy carriers of the same fact).
    public static func isExtension(_ action: any Action) -> Bool {
        if case .extensionPkg = action.chrome.source { return true }
        if case .extensionPkg = action.chrome.badge { return true }
        return false
    }

    /// The extension package identifier for an extension-loaded action, if any.
    public static func extensionPackageID(of action: any Action) -> String? {
        if case .extensionPkg(let packageID) = action.chrome.source { return packageID }
        if case .extensionPkg(let name) = action.chrome.badge { return name }
        return nil
    }

    /// The set of unique installed extension package IDs present in an action list.
    public static func installedPackageIDs(in actions: [any Action]) -> Set<String> {
        Set(actions.compactMap { extensionPackageID(of: $0) })
    }

    /// True for AI-preset actions (`.ai` source), grouped under AI Tools by default.
    public static func isAIPreset(_ action: any Action) -> Bool {
        if case .ai = action.chrome.source { return true }
        return false
    }

    /// Whether a user can assign an alias and a per-action hotkey. Only leaf actions that
    /// actually run: groups and the AI Tools launcher are containers.
    public static func isBindable(_ action: any Action) -> Bool {
        !action.chrome.launchesAI &&
        action.chrome.popupBehavior != .showSubActions &&
        action.chrome.rowStyle != .actionGroup
    }

    /// Whether an action can be duplicated by the user.
    /// Custom actions and installed extension actions can be duplicated.
    /// Builtins, AI presets and AI launchers cannot.
    public static func canDuplicate(_ action: any Action) -> Bool {
        if isAIPreset(action) || action.chrome.launchesAI {
            return false
        }
        if isBuiltin(action) {
            return false
        }
        return true
    }
}
