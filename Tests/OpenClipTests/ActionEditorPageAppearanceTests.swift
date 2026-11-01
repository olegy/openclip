import XCTest
@testable import OpenClip
@testable import Core

/// Regression coverage for the edit-actions sheet's appearance save logic: editing only the title
/// must never replace an action's real icon (package file / remote image / text glyph) with the
/// icon picker's placeholder, and legacy overrides written by that old bug heal on the next save.
@MainActor
final class ActionEditorPageAppearanceTests: XCTestCase {
    private let localIcon = ActionIcon.local(URL(fileURLWithPath: "/tmp/pkg/icon.svg"))

    // MARK: - resolvedSymbolOverride

    func testTitleOnlyEditDoesNotClobberNonSymbolIcon() {
        // Non-symbol-representable icons leave the field empty ("untouched"); saving must not
        // invent a symbol override.
        XCTAssertNil(ActionEditorPage.resolvedSymbolOverride(current: "", initial: "", stored: nil))
    }

    func testUnchangedFieldRoundTripsPreviouslyStoredSymbol() {
        XCTAssertEqual(
            ActionEditorPage.resolvedSymbolOverride(current: "heart.fill", initial: "heart.fill", stored: "heart.fill"),
            "heart.fill"
        )
    }

    func testPickedReplacementSymbolWinsOverStoredOne() {
        XCTAssertEqual(
            ActionEditorPage.resolvedSymbolOverride(current: "bolt.fill", initial: "heart.fill", stored: "heart.fill"),
            "bolt.fill"
        )
    }

    func testPickedSymbolOnNonSymbolBaselinePersists() {
        XCTAssertEqual(
            ActionEditorPage.resolvedSymbolOverride(current: "bolt.fill", initial: "", stored: nil),
            "bolt.fill"
        )
    }

    // MARK: - iconModeFallbackSymbol

    func testIconModeFallbackSymbolForTextGlyphBuiltins() {
        XCTAssertEqual(ActionEditorPage.iconModeFallbackSymbol(for: AIAction(presetID: "proofread", title: "Proofread")),
                       Constants.defaultAIIconSymbol)
        XCTAssertNil(ActionEditorPage.iconModeFallbackSymbol(for: TextGlyphExtensionAction()))
        XCTAssertNil(ActionEditorPage.iconModeFallbackSymbol(for: SearchAction()))
    }

    // MARK: - sanitizedStoredSymbol (legacy clobber healing)

    func testLegacyStarPlaceholderOnNonSymbolIconsIsTreatedAsAbsent() {
        XCTAssertNil(ActionEditorPage.sanitizedStoredSymbol("star", actionIcon: localIcon))
        XCTAssertNil(ActionEditorPage.sanitizedStoredSymbol("star", actionIcon: .text("⌘C")))
        XCTAssertNil(ActionEditorPage.sanitizedStoredSymbol("star", actionIcon: .url(URL(string: "https://example.com/i.png")!)))
    }

    func testGenuineStarPickOnStarIconedActionIsKept() {
        XCTAssertEqual(ActionEditorPage.sanitizedStoredSymbol("star", actionIcon: .symbol("star")), "star")
    }

    func testRealCustomizationsAndAbsenceArePreserved() {
        XCTAssertEqual(ActionEditorPage.sanitizedStoredSymbol("heart.fill", actionIcon: localIcon), "heart.fill")
        XCTAssertNil(ActionEditorPage.sanitizedStoredSymbol(nil, actionIcon: localIcon))
        XCTAssertNil(ActionEditorPage.sanitizedStoredSymbol("", actionIcon: localIcon))
    }

    // MARK: - resolvedPreviewIcon (ActionAppearanceFields)

    private func preview(
        iconSymbol: String = "",
        initial: String = "",
        base: ActionIcon? = nil,
        textGlyphFallbackSymbol: String? = nil
    ) -> ActionIcon {
        ActionAppearanceFields.resolvedPreviewIcon(
            iconSymbol: iconSymbol,
            initialIconSymbol: initial,
            baseIcon: base,
            textGlyphFallbackSymbol: textGlyphFallbackSymbol
        )
    }

    func testPreviewKeepsRealIconUntilReplacementPicked() {
        XCTAssertEqual(preview(base: localIcon), localIcon)
        XCTAssertEqual(preview(iconSymbol: "bolt.fill", base: localIcon), .symbol("bolt.fill"))
    }

    func testUntouchedSymbolBaselineStillPreviewsRealIcon() {
        XCTAssertEqual(preview(iconSymbol: "heart.fill", initial: "heart.fill", base: .text("T")), .text("T"))
    }

    func testPreviewPreviewsBuiltinFallbackSymbolForTextGlyphIcons() {
        XCTAssertEqual(
            preview(base: .text("Copy"), textGlyphFallbackSymbol: "doc.on.doc"),
            .symbol("doc.on.doc")
        )
    }

    func testPreviewKeepsTextGlyphWithoutFallbackSymbol() {
        XCTAssertEqual(preview(base: .text("T")), .text("T"))
    }

    func testPreviewFallbackDoesNotOverwritePickedSymbol() {
        XCTAssertEqual(
            preview(iconSymbol: "bolt.fill", base: .text("Copy"), textGlyphFallbackSymbol: "doc.on.doc"),
            .symbol("bolt.fill")
        )
    }

}

private struct TextGlyphExtensionAction: ConfigurableAction {
    let id = "com.example.textglyph"
    let title = "Text Glyph"
    let icon: ActionIcon = .text("T")
    let chrome: ActionChrome = ActionChrome(
        badge: .script,
        rowStyle: .standard,
        popupBehavior: .perform,
        source: .extensionPkg(packageID: "com.example.textglyph")
    )

    func isEnabled(for context: ActionContext) -> Bool { true }
    func perform(_ context: ActionContext) async throws -> ActionResult { .none }
}
