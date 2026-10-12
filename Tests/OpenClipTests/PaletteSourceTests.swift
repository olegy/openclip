import XCTest
import AppKit
@testable import OpenClip
@testable import Core

/// Fork: the palette hotkey's input (T06, T13, T19). Upstream reads the selection on demand and
/// offers the clipboard as the alternate source; the fork adds the collapsed-caret rule, keeps
/// copied files out, and shows the active source in the footer.
@MainActor
final class PaletteSourceTests: XCTestCase {
    private var app: PaletteMockApp { PaletteMockApp(bundleID: "com.sublimetext.4") }

    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run {
            TestIsolation.reset()
            let manager = HotkeyManager.shared
            manager.selectionMonitor = nil
            manager.frontmostPIDProvider = { 1001 }
            manager.collapsedCaretRole = { nil }
            // Never read the real frontmost app's selection from tests.
            manager.retriever = Self.retriever(copying: nil)
        }
    }

    override func tearDown() async throws {
        await MainActor.run {
            let manager = HotkeyManager.shared
            manager.frontmostPIDProvider = { NSWorkspace.shared.frontmostApplication?.processIdentifier }
            manager.collapsedCaretRole = { await CollapsedCaretProbe.collapsedCaretRole() }
            manager.retriever = nil
        }
        try await super.tearDown()
    }

    /// A retriever whose AX read finds nothing and whose ⌘C copies `text`.
    private static func retriever(
        copying text: String?,
        html: String? = nil,
        onCopy: @escaping @MainActor @Sendable () -> Void = {}
    ) -> SelectionRetrievalCoordinator {
        SelectionRetrievalCoordinator(
            inspect: { _ in AXElementInspector.Target() },
            copyCapture: { _ in
                await MainActor.run { onCopy() }
                return text.map { Core.TextResult(text: $0, html: html) }
            }
        )
    }

    func testPaletteTriggerReadsSelectionOnDemand() async {
        let manager = HotkeyManager.shared
        manager.retriever = Self.retriever(copying: "on-demand text", html: "<b>on-demand text</b>")

        let trigger = await manager.resolvePaletteTrigger(frontmostApp: app)

        XCTAssertEqual(trigger?.context.text, "on-demand text")
        XCTAssertEqual(trigger?.context.isClipboardFallback, false)
        XCTAssertEqual(trigger?.context.html, "<b>on-demand text</b>")
    }

    func testPaletteTriggerFallsBackToClipboardWhenReadIsBlank() async {
        HotkeyManager.shared.retriever = Self.retriever(copying: "   ")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("fallback clipboard text", forType: .string)

        let trigger = await HotkeyManager.shared.resolvePaletteTrigger(frontmostApp: app)

        XCTAssertEqual(trigger?.context.text, "fallback clipboard text")
        XCTAssertEqual(trigger?.context.isClipboardFallback, true)
    }

    func testPaletteTriggerFallsBackToEmptyContextWhenClipboardEmpty() async {
        NSPasteboard.general.clearContents()

        let trigger = await HotkeyManager.shared.resolvePaletteTrigger(frontmostApp: app)

        XCTAssertEqual(trigger?.context.text, "")
        XCTAssertEqual(trigger?.context.isClipboardFallback, false)
    }

    func testPaletteTriggerDoesNotReadGatedApps() async {
        let manager = HotkeyManager.shared
        let read = CopyFlag()
        manager.retriever = Self.retriever(copying: "text", onCopy: { read.isSet = true })
        // Never the real ~/.openclip/rules.json.
        let rulesURL = FileManager.default.temporaryDirectory.appendingPathComponent("palette-rules-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: rulesURL) }
        RuleEngine.shared.addOrUpdateRule(AppRule(bundleIdentifiers: ["com.test.disabled"], disabled: true), saveURL: rulesURL)

        let trigger = await manager.resolvePaletteTrigger(frontmostApp: PaletteMockApp(bundleID: "com.test.disabled"))

        XCTAssertNil(trigger)
        XCTAssertFalse(read.isSet)
    }

    /// Issue #74: a clipboard manager dismissing itself can leave no frontmost app; the palette
    /// still opens on the clipboard.
    func testPaletteTriggerFallsBackToClipboardWhenFrontmostAppIsNil() async {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("clipboard from Paste app", forType: .string)

        let trigger = await HotkeyManager.shared.resolvePaletteTrigger(frontmostApp: nil)

        XCTAssertEqual(trigger?.context.text, "clipboard from Paste app")
        XCTAssertEqual(trigger?.context.isClipboardFallback, true)
        XCTAssertNil(trigger?.context.sourceApp.bundleIdentifier)
    }

    func testPaletteTriggerRespectsGlobalPauseEvenWithNilFrontmostApp() async {
        let store = MemorySettingsStore()
        store.set(.pauseUntilTimestamp, value: Date().timeIntervalSince1970 + 1800)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("should not appear", forType: .string)

        let trigger = await HotkeyManager.shared.resolvePaletteTrigger(frontmostApp: nil, settingsStore: store)

        XCTAssertNil(trigger)
    }

    /// A file copied in Finder also puts its name on the clipboard as a string — not text to act on.
    func testCopiedFileIsNotClipboardText() async {
        let manager = HotkeyManager.shared
        manager.retriever = Self.retriever(copying: "selected text")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([URL(fileURLWithPath: "/tmp/report.pdf") as NSURL])
        pasteboard.setString("report.pdf", forType: .string)

        let withSelection = await manager.resolvePaletteTrigger(frontmostApp: app)
        XCTAssertEqual(withSelection?.context.text, "selected text")
        XCTAssertTrue(HotkeyManager.clipboardHoldsFiles(pasteboard))

        manager.retriever = Self.retriever(copying: nil)
        let withoutSelection = await manager.resolvePaletteTrigger(frontmostApp: app)
        XCTAssertEqual(withoutSelection?.context.text, "")
        XCTAssertEqual(withoutSelection?.context.isClipboardFallback, false)
    }

    /// A collapsed caret in a text control sends no ⌘C (Obsidian would copy the current line), so
    /// the palette falls through to the clipboard. Per-action hotkeys keep upstream's copy.
    func testCollapsedCaretSendsNoCopy() async {
        let manager = HotkeyManager.shared
        let copied = CopyFlag()
        manager.retriever = Self.retriever(copying: "current line", onCopy: { copied.isSet = true })
        manager.collapsedCaretRole = { "AXTextArea" }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("clipboard text", forType: .string)

        let trigger = await manager.resolvePaletteTrigger(frontmostApp: app)

        XCTAssertFalse(copied.isSet)
        XCTAssertEqual(trigger?.context.text, "clipboard text")
        XCTAssertEqual(trigger?.context.isClipboardFallback, true)

        let actionTrigger = await manager.collectTrigger(frontmostApp: app)
        XCTAssertTrue(copied.isSet)
        XCTAssertEqual(actionTrigger?.context.text, "current line")
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
    override var processIdentifier: pid_t { 1001 }
}

@MainActor
private final class CopyFlag {
    var isSet = false
}
