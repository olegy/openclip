import XCTest
import AppKit
import SwiftUI
@testable import OpenClip
@testable import Core

/// Minimal fake action for palette index tests (no real builtin dependencies).
private struct GroupScopeAction: Action {
    let id: String
    var title: String { id }
    var icon: ActionIcon { .symbol("gearshape") }
    var chrome: ActionChrome { ActionChrome(source: .builtin) }
    @MainActor func isEnabled(for context: ActionContext) -> Bool { true }
    @MainActor func perform(_ context: ActionContext) async throws -> ActionResult { .success }
}

@MainActor
final class PopupSearchIndexTests: XCTestCase {

    override func setUp() {
        super.setUp()
        TestIsolation.reset()
    }

    @MainActor
    func testGroupKeywordsIndexMembersByGroupTitle() {
        let copyAction = GroupScopeAction(id: "com.pkg.clip.copy")
        let pasteAction = GroupScopeAction(id: "com.pkg.clip.paste")
        let group = GroupAction(
            id: "com.pkg.clip",
            title: "Clipboard Helpers",
            icon: .symbol("folder"),
            chrome: ActionChrome(rowStyle: .actionGroup, popupBehavior: .showSubActions, source: .extensionPkg(packageID: "com.pkg"))
        )
        let catalog: [any Action] = [group, copyAction, pasteAction]
        let app = AppIdentity(NSRunningApplication.current)
        let context = ActionContext(
            selection: SelectionContext(text: "hi", sourceApp: app, cursorPosition: .zero, selectionBounds: nil, timestamp: Date(), appPolicy: .default)
        )
        let view = PopupSearchView(
            catalog: catalog,
            context: context,
            onResult: { _ in },
            onExit: {},
            onRunAI: { _ in }
        )
        // Rebuild index and search for "Clipboard"
        let index = PopupSearchView.buildIndex(
            catalog: catalog,
            usageRecency: [:],
            presenter: ActionCustomizationManager.shared
        )
        let results = ActionSearch.search("Clipboard", in: index)
        let resultIDs = Set(results.map { $0.id })
        XCTAssertTrue(resultIDs.contains("com.pkg.clip.copy"), "A group member must be found when searching by the group's title")
        XCTAssertTrue(resultIDs.contains("com.pkg.clip.paste"), "A group member must be found when searching by the group's title")
    }

    @MainActor
    func testAIPresetTableIconUsesSparklesSymbol() {
        let aiAction = AIAction(presetID: "proofread", title: "Proofread")
        let presentation = ActionCustomizationManager.shared.presented(aiAction, surface: .table)
        XCTAssertEqual(presentation.icon, .symbol(Constants.defaultAIIconSymbol))
    }

}