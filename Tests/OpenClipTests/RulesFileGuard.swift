import XCTest
@testable import Core

/// Keeps the suite off the developer's real `~/.openclip/rules.json`.
///
/// `RuleEngine.addOrUpdateRule(_:saveURL:)` and `removeRule(id:saveURL:)` default `saveURL` to
/// `Constants.rulesFileURL`, so a test that leaves it out silently replaces the app's rules with
/// test rules. Pass a temporary file as `saveURL` instead.
///
/// This class is the test bundle's principal class (`INFOPLIST_KEY_NSPrincipalClass` in
/// `project.yml`), so XCTest instantiates it before any test runs. It snapshots the rules file as
/// each test starts and, in a teardown block, fails that test and puts the file back if it changed.
@objc(OpenClipRulesFileGuard)
final class RulesFileGuard: NSObject, XCTestObservation {
    static let principalClassName = "OpenClipRulesFileGuard"

    override init() {
        super.init()
        XCTestObservationCenter.shared.addTestObserver(self)
    }

    func testCaseWillStart(_ testCase: XCTestCase) {
        let snapshot = FileSnapshot(url: Constants.rulesFileURL)
        testCase.addTeardownBlock {
            if snapshot.restoreIfChanged() {
                XCTFail("Test wrote the real \(snapshot.url.path); pass a temporary saveURL. The original file has been restored.")
            }
        }
    }
}

/// The bytes and modification date of a file (or its absence), and a way to put them back.
struct FileSnapshot: Sendable {
    let url: URL
    let contents: Data?
    let modificationDate: Date?

    init(url: URL) {
        self.url = url
        contents = try? Data(contentsOf: url)
        modificationDate = Self.modificationDate(of: url)
    }

    var isCurrent: Bool {
        (try? Data(contentsOf: url)) == contents && Self.modificationDate(of: url) == modificationDate
    }

    /// Returns `true` when the file differed from the snapshot and was restored.
    @discardableResult
    func restoreIfChanged() -> Bool {
        guard !isCurrent else { return false }
        if let contents {
            // A non-atomic write keeps the existing file's permissions (rules.json is 0600).
            try? contents.write(to: url)
            if let modificationDate {
                try? FileManager.default.setAttributes([.modificationDate: modificationDate], ofItemAtPath: url.path)
            }
        } else {
            try? FileManager.default.removeItem(at: url)
        }
        return true
    }

    private static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}
