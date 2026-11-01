import XCTest
@testable import Core

final class RuleEngineTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        await MainActor.run { TestIsolation.reset() }
    }
    
    
    @MainActor
    func testCopyModesResolveForEditorsAndTerminals() async throws {
        let vsCodeContext = RuleEngine.shared.resolvePolicies(for: "com.microsoft.VSCode")
        XCTAssertEqual(vsCodeContext.retrievalMode, .keyboardCopy, "VS Code should resolve keyboard-copy retrieval mode")
        
        let zedContext = RuleEngine.shared.resolvePolicies(for: "dev.zed.Zed")
        XCTAssertEqual(zedContext.retrievalMode, .keyboardCopy, "Zed should resolve keyboard-copy retrieval mode")
        
        let alacrittyContext = RuleEngine.shared.resolvePolicies(for: "org.alacritty")
        XCTAssertEqual(alacrittyContext.retrievalMode, .menuCopy, "Alacritty should resolve menu-copy retrieval mode")
        
        let randomContext = RuleEngine.shared.resolvePolicies(for: "com.random.app")
        XCTAssertEqual(randomContext.retrievalMode, .axTextControl, "Random app should stay on the default retrieval mode")
        XCTAssertEqual(randomContext.gate, .default, "Apps keep the default gate")
    }

    @MainActor
    func testBrowserScriptModeResolvesForBrowserGroups() async throws {
        let safariContext = RuleEngine.shared.resolvePolicies(for: "com.apple.Safari")
        XCTAssertEqual(safariContext.retrievalMode, .axWebArea)
        
        let firefoxContext = RuleEngine.shared.resolvePolicies(for: "org.mozilla.firefox")
        XCTAssertEqual(firefoxContext.retrievalMode, .axWebArea)
        
        let arcContext = RuleEngine.shared.resolvePolicies(for: "company.thebrowser.Browser")
        XCTAssertEqual(arcContext.retrievalMode, .axWebArea)
    }

    @MainActor
    func testKeyboardCopyModeResolvesForCodeEditorApps() async throws {
        let vsCodeContext = RuleEngine.shared.resolvePolicies(for: "com.microsoft.VSCode")
        XCTAssertEqual(vsCodeContext.retrievalMode, .keyboardCopy)
        XCTAssertFalse(vsCodeContext.denyPaste)
    }

    @MainActor
    func testDenyPasteModeResolvesForTerminalAndGhostty() async throws {
        let terminalContext = RuleEngine.shared.resolvePolicies(for: "com.apple.Terminal")
        XCTAssertTrue(terminalContext.denyPaste)
        XCTAssertEqual(terminalContext.retrievalMode, .keyboardCopy)

        let itermContext = RuleEngine.shared.resolvePolicies(for: "com.googlecode.iterm2")
        XCTAssertTrue(itermContext.denyPaste)
        XCTAssertEqual(itermContext.retrievalMode, .keyboardCopy)

        let ghosttyContext = RuleEngine.shared.resolvePolicies(for: "com.mitchellh.ghostty")
        XCTAssertTrue(ghosttyContext.denyPaste)
        XCTAssertEqual(ghosttyContext.retrievalMode, .menuCopy)
    }

}
