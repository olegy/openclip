// PinnedActionStoreTests.swift
// OpenClip
//
// The palette's pins (`PinnedActionStore`) and the order an empty palette opens with
// (`PaletteOrder`): pinned first in pin order, then most recently used, then by title.
import XCTest
@testable import Core
@testable import OpenClip

@MainActor
final class PinnedActionStoreTests: XCTestCase {
    private var settingsStore: MemorySettingsStore!
    private var store: PinnedActionStore!

    override func setUp() {
        super.setUp()
        settingsStore = MemorySettingsStore()
        store = PinnedActionStore(settingsStore: settingsStore)
    }

    private let existing: Set<String> = Set((1...20).map { "a.\($0)" })

    func testPinAppendsAndPersists() {
        XCTAssertTrue(store.pin("a.1", existingIDs: existing))
        XCTAssertTrue(store.pin("a.2", existingIDs: existing))
        XCTAssertFalse(store.pin("a.1", existingIDs: existing), "an action is pinned once")
        XCTAssertEqual(store.ids, ["a.1", "a.2"])
        XCTAssertEqual(PinnedActionStore(settingsStore: settingsStore).ids, ["a.1", "a.2"])
    }

    func testPinningStopsAtTheLimit() {
        for index in 1...PinnedActionStore.limit {
            XCTAssertTrue(store.pin("a.\(index)", existingIDs: existing))
        }
        XCTAssertFalse(store.canPin(existingIDs: existing))
        XCTAssertFalse(store.pin("a.\(PinnedActionStore.limit + 1)", existingIDs: existing))
        XCTAssertEqual(store.ids.count, PinnedActionStore.limit)

        store.unpin("a.1")
        XCTAssertTrue(store.canPin(existingIDs: existing))
    }

    func testAMissingActionKeepsItsPinUntilThePinsAreEdited() {
        settingsStore.set(.pinnedActionIDs, value: ["gone", "a.1"])
        store = PinnedActionStore(settingsStore: settingsStore)
        XCTAssertEqual(store.resolved(in: existing), ["a.1"])
        XCTAssertEqual(store.ids, ["gone", "a.1"], "reading never drops a pin: the action may only be reloading")

        store.pin("a.2", existingIDs: existing)
        XCTAssertEqual(store.ids, ["a.1", "a.2"], "an edit rewrites the list from the actions that exist")
    }

    func testAMissingActionDoesNotCountTowardsTheLimit() {
        settingsStore.set(.pinnedActionIDs, value: (1...PinnedActionStore.limit).map { "gone.\($0)" })
        store = PinnedActionStore(settingsStore: settingsStore)
        XCTAssertTrue(store.canPin(existingIDs: existing))
    }

    func testMoveUsesGapsCountedBeforeTheRemoval() {
        for id in ["a.1", "a.2", "a.3"] { store.pin(id, existingIDs: existing) }

        store.move("a.1", toGap: 3, existingIDs: existing)
        XCTAssertEqual(store.ids, ["a.2", "a.3", "a.1"])

        store.move("a.1", toGap: 0, existingIDs: existing)
        XCTAssertEqual(store.ids, ["a.1", "a.2", "a.3"])

        store.move("a.2", toGap: 2, existingIDs: existing)
        XCTAssertEqual(store.ids, ["a.1", "a.2", "a.3"], "dropping a row into the gap below itself changes nothing")
    }

    func testUnpinAndReset() {
        for id in ["a.1", "a.2"] { store.pin(id, existingIDs: existing) }
        store.unpin("a.1")
        XCTAssertEqual(store.ids, ["a.2"])
        store.reset()
        XCTAssertTrue(store.ids.isEmpty)
    }

    // MARK: - Palette order

    func testPaletteOrderPutsPinsFirstThenRecentThenByTitle() {
        let actions: [any Action] = [
            PinStub(id: "zeta", title: "Zeta"),
            PinStub(id: "alpha", title: "Alpha"),
            PinStub(id: "recent", title: "Recent"),
            PinStub(id: "pinned.2", title: "Pinned Two"),
            PinStub(id: "beta", title: "beta"),
            PinStub(id: "pinned.1", title: "Pinned One"),
        ]
        let ordered = PaletteOrder.ordered(
            actions,
            pinnedIDs: ["pinned.1", "pinned.2", "not.in.catalog"],
            usageRecency: ["recent": 5, "pinned.2": 9],
            title: { $0.title }
        )
        XCTAssertEqual(ordered.map(\.id), ["pinned.1", "pinned.2", "recent", "alpha", "beta", "zeta"])
    }

    func testThePaletteIndexOpensInPaletteOrder() {
        let catalog: [any Action] = [
            PinStub(id: "b", title: "B"),
            PinStub(id: "a", title: "A"),
            PinStub(id: "c", title: "C"),
        ]
        let index = PopupSearchView.buildIndex(
            catalog: catalog,
            usageRecency: ["c": 1],
            presenter: ActionCustomizationManager(settingsStore: MemorySettingsStore()),
            aliases: [:],
            pinnedIDs: ["b"]
        )
        XCTAssertEqual(ActionSearch.search("", in: index).map(\.id), ["b", "c", "a"])
    }
}

private struct PinStub: Action, Sendable {
    let id: String
    let title: String
    var icon: ActionIcon { .symbol("star") }
    var chrome: ActionChrome { ActionChrome(source: .builtin) }

    @MainActor func isEnabled(for context: ActionContext) -> Bool { true }
    @MainActor func perform(_ context: ActionContext) async throws -> ActionResult { .none }
}
