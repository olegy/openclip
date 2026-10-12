import XCTest
@testable import Core

/// Covers `RulesFileGuard`, which fails any test that writes the real `~/.openclip/rules.json`.
final class RulesFileGuardTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("rules-guard-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    func testGuardIsTheTestBundlePrincipalClass() {
        let bundle = Bundle(for: RulesFileGuardTests.self)
        XCTAssertEqual(bundle.object(forInfoDictionaryKey: "NSPrincipalClass") as? String, RulesFileGuard.principalClassName)
        XCTAssertTrue(bundle.principalClass == RulesFileGuard.self)
    }

    func testUnchangedFileIsLeftAlone() throws {
        let url = directory.appendingPathComponent("rules.json")
        try Data(#"{"rules":[]}"#.utf8).write(to: url)
        let snapshot = FileSnapshot(url: url)

        XCTAssertFalse(snapshot.restoreIfChanged())
    }

    func testRewrittenFileIsRestoredWithItsModificationDate() throws {
        let url = directory.appendingPathComponent("rules.json")
        let original = Data(#"{"rules":[]}"#.utf8)
        try original.write(to: url)
        let originalDate = Date(timeIntervalSince1970: 1_000_000)
        try FileManager.default.setAttributes([.modificationDate: originalDate], ofItemAtPath: url.path)
        let snapshot = FileSnapshot(url: url)

        try Data(#"{"rules":[{"bundleIdentifiers":["com.test"]}]}"#.utf8).write(to: url)

        XCTAssertTrue(snapshot.restoreIfChanged())
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertTrue(snapshot.isCurrent)
    }

    func testSameBytesWithNewModificationDateCountAsAWrite() throws {
        let url = directory.appendingPathComponent("rules.json")
        let original = Data(#"{"rules":[]}"#.utf8)
        try original.write(to: url)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000)], ofItemAtPath: url.path)
        let snapshot = FileSnapshot(url: url)

        try original.write(to: url)

        XCTAssertTrue(snapshot.restoreIfChanged())
        XCTAssertTrue(snapshot.isCurrent)
    }

    func testFileCreatedByATestIsRemoved() throws {
        let url = directory.appendingPathComponent("rules.json")
        let snapshot = FileSnapshot(url: url)

        try Data(#"{"rules":[]}"#.utf8).write(to: url)

        XCTAssertTrue(snapshot.restoreIfChanged())
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
