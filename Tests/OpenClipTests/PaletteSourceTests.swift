import XCTest
import AppKit
@testable import OpenClip
@testable import Core

/// Fork (T13): the palette reads both the selection and the clipboard, shows which one it acts
/// on, and switches between them.
@MainActor
final class PaletteSourceTests: XCTestCase {
    private var originalSelectionReader: (@MainActor (AppIdentity, AppPolicyContext) async -> TextResult?)?

    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run {
            TestIsolation.reset()
            HotkeyManager.shared.selectionMonitor = nil
            originalSelectionReader = HotkeyManager.shared.selectionReader
            HotkeyManager.shared.selectionReader = { _, _ in nil }
        }
    }

    override func tearDown() async throws {
        await MainActor.run {
            if let originalSelectionReader {
                HotkeyManager.shared.selectionReader = originalSelectionReader
            }
        }
        try await super.tearDown()
    }

    func testSelectionReadAlsoReturnsTheClipboardText() async {
        let manager = HotkeyManager.shared
        manager.selectionReader = { _, _ in TextResult(text: "selected text", bounds: nil) }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("clipboard text", forType: .string)

        let trigger = await manager.resolvePaletteTrigger(frontmostApp: PaletteMockApp(bundleID: "com.apple.TextEdit"))

        XCTAssertEqual(trigger?.context.text, "selected text")
        XCTAssertEqual(trigger?.context.isClipboardFallback, false)
        XCTAssertEqual(trigger?.clipboard?.text, "clipboard text")
        XCTAssertEqual(trigger?.clipboard?.isClipboardFallback, true)
        XCTAssertEqual(trigger?.clipboard?.sourceApp.bundleIdentifier, "com.apple.TextEdit")
    }

    func testClipboardFallbackHasNoAlternate() async {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("clipboard text", forType: .string)

        let trigger = await HotkeyManager.shared.resolvePaletteTrigger(frontmostApp: PaletteMockApp(bundleID: "com.apple.TextEdit"))

        XCTAssertEqual(trigger?.context.text, "clipboard text")
        XCTAssertEqual(trigger?.context.isClipboardFallback, true)
        XCTAssertNil(trigger?.clipboard)
    }

    /// A file copied in Finder also puts its name on the clipboard as a string — not text to act on.
    func testCopiedFileIsNotClipboardText() async {
        let manager = HotkeyManager.shared
        manager.selectionReader = { _, _ in TextResult(text: "selected text", bounds: nil) }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([URL(fileURLWithPath: "/tmp/report.pdf") as NSURL])
        pasteboard.setString("report.pdf", forType: .string)

        let withSelection = await manager.resolvePaletteTrigger(frontmostApp: PaletteMockApp(bundleID: "com.apple.TextEdit"))
        XCTAssertEqual(withSelection?.context.text, "selected text")
        XCTAssertNil(withSelection?.clipboard)

        manager.selectionReader = { _, _ in nil }
        let withoutSelection = await manager.resolvePaletteTrigger(frontmostApp: PaletteMockApp(bundleID: "com.apple.TextEdit"))
        XCTAssertEqual(withoutSelection?.context.text, "")
        XCTAssertNil(withoutSelection?.clipboard)
    }

    func testSwitchingSourcesSwapsTheContextAndKeepsTheOtherOne() {
        let controller = PopupWindowController(settingsStore: MemorySettingsStore())
        defer { controller.hide() }
        let selection = SelectionContext(text: "selected text", isClipboardFallback: false)
        let clipboard = SelectionContext(text: "clipboard text", isClipboardFallback: true)

        controller.showPalette(for: selection, alternate: clipboard, pasteAvailable: true)
        XCTAssertEqual(controller.currentActionContext?.selection.text, "selected text")
        XCTAssertTrue(controller.modeStore.paletteHasAlternateSource)

        XCTAssertTrue(controller.switchPaletteSource(keeping: "trans"))
        XCTAssertEqual(controller.currentActionContext?.selection.text, "clipboard text")
        XCTAssertEqual(controller.currentActionContext?.selection.isClipboardFallback, true)
        XCTAssertEqual(controller.modeStore.mode, .search)
        XCTAssertEqual(controller.modeStore.canPaste, true)
        XCTAssertEqual(controller.modeStore.paletteSeedQuery, "")

        XCTAssertTrue(controller.switchPaletteSource(keeping: ""))
        XCTAssertEqual(controller.currentActionContext?.selection.text, "selected text")

        controller.hide()
        XCTAssertFalse(controller.modeStore.paletteHasAlternateSource)
        XCTAssertNil(controller.paletteAlternateContext)
    }

    func testSingleSourceCannotSwitch() {
        let controller = PopupWindowController(settingsStore: MemorySettingsStore())
        defer { controller.hide() }
        controller.showPalette(for: SelectionContext(text: "clipboard text", isClipboardFallback: true), alternate: nil, pasteAvailable: nil)

        XCTAssertFalse(controller.modeStore.paletteHasAlternateSource)
        XCTAssertFalse(controller.switchPaletteSource(keeping: ""))
        XCTAssertEqual(controller.currentActionContext?.selection.text, "clipboard text")
    }

    func testPreviewLineCollapsesWhitespaceAndLineBreaks() {
        XCTAssertEqual(PaletteSourceFooter.previewLine("  first line\n\n\tsecond   line \n"), "first line second line")
        XCTAssertLessThanOrEqual(PaletteSourceFooter.previewLine(String(repeating: "word ", count: 1000)).count, 400)
    }
}

private final class PaletteMockApp: NSRunningApplication {
    private let bundleID: String?

    init(bundleID: String?) {
        self.bundleID = bundleID
        super.init()
    }

    override var bundleIdentifier: String? { bundleID }
}
