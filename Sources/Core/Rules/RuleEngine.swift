// RuleEngine.swift
// OpenClip
//
// Resolves the per-app selection policy (how to read the selection, whether pasting is safe) from
// the built-in rule catalog (`DefaultAppRules`).
import Foundation

@MainActor
public final class RuleEngine: Sendable {
    public static let shared = RuleEngine()

    private init() {}

    public func resolvePolicies(for bundleIdentifier: String) -> AppPolicyContext {
        resolvePolicies(for: AppIdentity(bundleIdentifier: bundleIdentifier))
    }

    /// Later catalog rules override earlier ones, field by field.
    public func resolvePolicies(for identity: AppIdentity) -> AppPolicyContext {
        var context = AppPolicyContext.default
        for rule in DefaultAppRules.catalog
        where rule.bundleIdentifiers.contains(where: { DefaultAppRules.matches(pattern: $0, identity: identity) }) {
            context = AppPolicyContext(
                denyPaste: rule.denyPaste ?? context.denyPaste,
                retrievalMode: rule.retrievalMode ?? context.retrievalMode,
                gate: context.gate
            )
        }
        return context
    }
}
