// PinnedActionStore.swift
// OpenClip
//
// The actions pinned to the top of the palette. The palette has no other manual order: pinned
// actions come first, in the order the user dragged them into, and everything else follows by
// how recently it was used (`PaletteOrder`). The list is capped at `limit` — what an open palette
// shows without scrolling — so pinning stays a short list of favourites rather than a second
// way to sort everything.
//
// Ids are kept as written, even for an action that is not registered right now (an extension
// mid-reload, a package switched off). Every edit takes the ids that exist and rewrites the list
// from them, so a stale id is dropped the next time the user changes the pins, never while an
// action is only briefly missing.
import Foundation
import Combine

@MainActor
public final class PinnedActionStore: ObservableObject, Sendable {
    public static let shared = PinnedActionStore()

    /// How many actions can be pinned: the rows an open palette shows without scrolling.
    public static let limit = 10

    @Published public private(set) var ids: [String] = []
    private let settingsStore: SettingsStore

    public init(settingsStore: SettingsStore = DefaultSettingsStore.shared) {
        self.settingsStore = settingsStore
        ids = settingsStore.get(.pinnedActionIDs)
    }

    public func isPinned(_ actionID: String) -> Bool {
        ids.contains(actionID)
    }

    /// The pinned ids that name one of `existingIDs`, in pin order.
    public func resolved(in existingIDs: Set<String>) -> [String] {
        ids.filter { existingIDs.contains($0) }
    }

    /// Whether another action can be pinned, counting only pins that still exist.
    public func canPin(existingIDs: Set<String>) -> Bool {
        resolved(in: existingIDs).count < Self.limit
    }

    /// Pins `actionID` at the end of the pinned list. Returns false when it is already pinned or
    /// the list is full.
    @discardableResult
    public func pin(_ actionID: String, existingIDs: Set<String>) -> Bool {
        var current = resolved(in: existingIDs)
        guard !current.contains(actionID), current.count < Self.limit else { return false }
        current.append(actionID)
        persist(current)
        return true
    }

    public func unpin(_ actionID: String) {
        guard ids.contains(actionID) else { return }
        persist(ids.filter { $0 != actionID })
    }

    /// Moves a pinned action into `gap` of the resolved list: 0 is above the first pin, `count`
    /// is below the last.
    public func move(_ actionID: String, toGap gap: Int, existingIDs: Set<String>) {
        var current = resolved(in: existingIDs)
        guard let from = current.firstIndex(of: actionID) else { return }
        current.remove(at: from)
        let target = min(max(0, from < gap ? gap - 1 : gap), current.count)
        current.insert(actionID, at: target)
        persist(current)
    }

    public func reset() {
        persist([])
    }

    private func persist(_ newIDs: [String]) {
        ids = newIDs
        settingsStore.set(.pinnedActionIDs, value: newIDs)
    }
}

/// The order of the palette when nothing is typed: pinned actions first, in pin order; then the
/// rest by how recently they ran, most recent first; then by title. A query re-ranks by match
/// quality (`ActionSearch`), and this order only breaks the ties that are left.
public enum PaletteOrder {
    public static func ordered(
        _ actions: [any Action],
        pinnedIDs: [String],
        usageRecency: [String: Int],
        title: (any Action) -> String
    ) -> [any Action] {
        let pinRank = Dictionary(pinnedIDs.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let titles = Dictionary(actions.map { ($0.id, title($0)) }, uniquingKeysWith: { first, _ in first })
        return actions.sorted { lhs, rhs in
            switch (pinRank[lhs.id], pinRank[rhs.id]) {
            case let (left?, right?): return left < right
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): break
            }
            let leftRecency = usageRecency[lhs.id] ?? 0
            let rightRecency = usageRecency[rhs.id] ?? 0
            if leftRecency != rightRecency { return leftRecency > rightRecency }
            let order = (titles[lhs.id] ?? lhs.title).localizedStandardCompare(titles[rhs.id] ?? rhs.title)
            if order != .orderedSame { return order == .orderedAscending }
            return lhs.id < rhs.id
        }
    }
}
