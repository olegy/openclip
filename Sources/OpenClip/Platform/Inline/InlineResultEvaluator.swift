// InlineResultEvaluator.swift
// OpenClip
//
// Coordinates multi-tier non-blocking inline result evaluation for actions declaring
// `ActionChrome.isInlineResult == true`.
//
// - Tier 1: Instant synchronous pure-Swift evaluation (<0.1ms, e.g. CalculateAction)
// - Tier 2: Results memoized across popups (same text, same action inputs)
// - Tier 3: Asynchronous background execution bounded by hard timeout with session cancellation
import Foundation
import Core

@MainActor
public final class InlineResultEvaluator {
    public static let shared = InlineResultEvaluator()

    /// Identity of one memoized inline result: the selection text, the action, and a fingerprint
    /// of the action's evaluated inputs (script + resolved option values). Including the
    /// fingerprint lets the warm cache survive across popups without serving a stale preview after
    /// the extension's script or a configured option changed.
    private struct MemoKey: Hashable {
        let textHash: Int
        let actionID: String
        let fingerprint: Int
    }

    /// Total memoized entries retained across popups. Bounds memory while keeping the common case
    /// (re-selecting the same or similar text) warm instead of re-evaluating from cold every show.
    private static let maxMemoizedEntries = 200

    /// Results longer than this are shown but never memoized, so a script returning a large string
    /// can't pin unbounded memory in the cross-popup cache.
    private static let maxMemoizedResultLength = 1024

    private var memoizedResults: [MemoKey: String] = [:]
    private var memoizedOrder: [MemoKey] = []
    private var runningTasks: [UUID: [String: Task<String?, Never>]] = [:]

    public init() {}

    private func storeMemoized(key: MemoKey, result: String) {
        guard result.count <= Self.maxMemoizedResultLength else { return }
        if memoizedResults[key] == nil {
            memoizedOrder.append(key)
            if memoizedOrder.count > Self.maxMemoizedEntries {
                let oldest = memoizedOrder.removeFirst()
                memoizedResults.removeValue(forKey: oldest)
            }
        }
        memoizedResults[key] = result
    }

    /// A stable, in-process fingerprint of everything that can change an inline action's output
    /// besides the selected text: its script source and the resolved values of its options.
    /// Pure actions (e.g. Calculate) have no inputs and fingerprint to a constant.
    private func fingerprint(for action: any Action) -> Int {
        guard let javaScriptAction = Self.javaScriptAction(from: action) else { return 0 }
        var hasher = Hasher()
        hasher.combine(javaScriptAction.scriptCode)
        for option in javaScriptAction.actionOptions {
            hasher.combine(option.identifier)
            hasher.combine(javaScriptAction.optionStore.stringValue(actionID: javaScriptAction.id, option: option))
        }
        return hasher.finalize()
    }

    private func memoKey(for action: any Action, textHash: Int) -> MemoKey {
        MemoKey(textHash: textHash, actionID: action.id, fingerprint: fingerprint(for: action))
    }

    /// Tier 1: Evaluates synchronous built-in actions immediately without spawning tasks.
    public func evaluateSynchronous(action: any Action, context: ActionContext) -> String? {
        guard action.chrome.isInlineResult else { return nil }
        if let calculate = action as? CalculateAction {
            return calculate.evaluateSynchronously(context.selection.text)
        }
        return nil
    }

    @MainActor
    private static func javaScriptAction(from action: any Action) -> JavaScriptAction? {
        switch action {
        case let javaScriptAction as JavaScriptAction:
            return javaScriptAction
        case let decorated as DeliveryDecoratedAction:
            return javaScriptAction(from: decorated.base)
        case let decorated as KeywordDecoratedAction:
            return javaScriptAction(from: decorated.base)
        case let decorated as MenuDecoratedAction:
            return javaScriptAction(from: decorated.base)
        default:
            return nil
        }
    }

    @MainActor
    private static func performAction(
        _ action: any Action,
        context: ActionContext,
        timeout: TimeInterval
    ) async -> String? {
        do {
            // Inline evaluation runs before the user clicks the action, so it cannot rely on
            // the click path to populate ActionContext.match. Resolve the same match here so
            // regex based inline actions receive their matched substring (for example `$200`
            // inside a longer selection) instead of trying to parse the entire selection.
            let matchedContext: ActionContext
            if context.match != nil {
                matchedContext = context
            } else if let match = action.matchInfo(for: context) {
                matchedContext = ActionContext(
                    selection: context.selection,
                    modifiers: context.modifiers,
                    isSecondaryClick: context.isSecondaryClick,
                    match: match
                )
            } else {
                matchedContext = context
            }
            let result: ActionResult
            if let javaScriptAction = javaScriptAction(from: action) {
                result = try await javaScriptAction.perform(matchedContext, timeout: timeout)
            } else {
                result = try await action.perform(matchedContext)
            }
            switch result {
            case .text(let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : text
            default:
                return nil
            }
        } catch {
            return nil
        }
    }

    /// Evaluates an inline action asynchronously with a hard execution timeout.
    /// If the action exceeds the timeout budget, the task is cancelled and nil is returned.
    public func evaluateAsync(
        action: any Action,
        context: ActionContext,
        timeout: TimeInterval = PopupMetrics.inlineEvaluationTimeout
    ) async -> String? {
        guard action.chrome.isInlineResult else { return nil }

        let boundedTimeout = max(0.001, timeout)
        return await withTaskGroup(of: String?.self) { group in
            group.addTask {
                await Self.performAction(action, context: context, timeout: boundedTimeout)
            }

            group.addTask {
                let nanos = UInt64(boundedTimeout * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
                return nil
            }

            let first = await group.next()
            group.cancelAll()
            return first ?? nil
        }
    }

    /// Tier 2: The memoized result for `action` on text with `textHash`, valid only while the
    /// action's inputs (script + resolved options) are unchanged.
    public func memoizedResult(for action: any Action, textHash: Int) -> String? {
        memoizedResults[memoKey(for: action, textHash: textHash)]
    }

    /// Clears the memoized results. Full invalidation — use ``endSession(_:)`` to end a popup
    /// while keeping the warm cache for the next selection.
    public func clearMemoized() {
        memoizedResults.removeAll()
        memoizedOrder.removeAll()
    }

    /// Ends a popup session: cancels that session's in-flight evaluations, but **retains** the
    /// warm result cache. Keeping it makes the next selection render instantly instead of paying a
    /// cold JavaScriptCore evaluation on every show.
    public func endSession(_ sessionID: UUID) {
        cancelSession(sessionID)
    }

    /// Tier 3: Registers and starts background evaluation of an inline action for a popup session.
    public func startEvaluation(
        action: any Action,
        context: ActionContext,
        sessionID: UUID,
        timeout: TimeInterval = PopupMetrics.inlineEvaluationTimeout,
        onResult: @escaping @MainActor (String?) -> Void
    ) {
        guard action.chrome.isInlineResult else {
            onResult(nil)
            return
        }

        let hash = context.selection.text.hashValue
        let key = memoKey(for: action, textHash: hash)
        if let cached = memoizedResults[key] {
            onResult(cached)
            return
        }

        let task = Task { @MainActor [weak self] () -> String? in
            guard let self else { return nil }
            guard !Task.isCancelled else { return nil }

            var result: String?
            var attempts = 0

            // A cold-start miss or a timed-out evaluation must not permanently deny the preview:
            // retry once with a fresh budget before giving up, so an occasional slow first
            // evaluation does not silently drop the inline result. At most two attempts total.
            while (result == nil || result?.isEmpty == true), attempts < 2 {
                guard !Task.isCancelled else { return nil }
                result = await self.evaluateAsync(
                    action: action,
                    context: context,
                    timeout: timeout
                )
                attempts += 1
            }

            guard !Task.isCancelled else { return nil }

            if let result, !result.isEmpty {
                self.storeMemoized(key: key, result: result)
            }

            self.runningTasks[sessionID]?.removeValue(forKey: action.id)
            if self.runningTasks[sessionID]?.isEmpty == true {
                self.runningTasks.removeValue(forKey: sessionID)
            }

            onResult(result)
            return result
        }

        if runningTasks[sessionID] == nil {
            runningTasks[sessionID] = [:]
        }
        runningTasks[sessionID]?[action.id] = task
    }

    /// Returns an existing in-flight evaluation task for click-race joining.
    public func runningTask(for actionID: String, sessionID: UUID) -> Task<String?, Never>? {
        runningTasks[sessionID]?[actionID]
    }

    /// Returns an existing in-flight evaluation task across all sessions for click-race joining.
    public func runningTask(for actionID: String) -> Task<String?, Never>? {
        for tasks in runningTasks.values {
            if let task = tasks[actionID] {
                return task
            }
        }
        return nil
    }

    /// Cancels and removes all in-flight evaluation tasks for a popup session.
    public func cancelSession(_ sessionID: UUID) {
        if let sessionTasks = runningTasks.removeValue(forKey: sessionID) {
            for task in sessionTasks.values {
                task.cancel()
            }
        }
    }
}
