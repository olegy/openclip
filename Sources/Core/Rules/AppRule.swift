// AppRule.swift
// OpenClip
//
// Defines the per-app selection policy and the built-in rules that produce it.
import Foundation

public struct AppPolicyContext: Sendable {
    /// Force a text result to be delivered as a copy instead of a paste, even when the app lists a
    /// Paste command. The explicit escape hatch for apps (e.g. Terminal) that advertise Paste but
    /// cannot reliably replace a selection.
    public let denyPaste: Bool
    /// Which mechanism should be used to read the current selection from the target app.
    public let retrievalMode: SelectionRetrievalMode
    /// Gate rules (skip roles / allowed cursors / selection requirement) applied before retrieval.
    public let gate: SelectionGatePolicy

    public static let `default` = AppPolicyContext()

    public init(
        denyPaste: Bool = false,
        retrievalMode: SelectionRetrievalMode = .axTextControl,
        gate: SelectionGatePolicy = .default
    ) {
        self.denyPaste = denyPaste
        self.retrievalMode = retrievalMode
        self.gate = gate
    }
}

/// A built-in per-app rule (`DefaultAppRules.catalog`): the apps it matches and the policy fields
/// it sets.
public struct AppRule: Sendable, Equatable {
    public let bundleIdentifiers: [String]
    public let denyPaste: Bool?
    public let retrievalMode: SelectionRetrievalMode?

    public init(
        bundleIdentifiers: [String],
        denyPaste: Bool? = nil,
        retrievalMode: SelectionRetrievalMode? = nil
    ) {
        self.bundleIdentifiers = bundleIdentifiers
        self.denyPaste = denyPaste
        self.retrievalMode = retrievalMode
    }
}
