import XCTest
@testable import Core
@testable import OpenClip

/// Exercises the composite `SecretActionOptionStore` against `SecretStore`: secrets go to SecretStore
/// (Keychain, in memory under test) and never to UserDefaults; non-secrets round-trip through SettingsStore.
final class SecretActionOptionStoreTests: XCTestCase {
    private var store: SecretActionOptionStore!
    private let actionIDPrefix = "com.test.secret.\(UUID().uuidString)"

    private var writtenAccounts: [String] = []
    private var writtenDefaultsKeys: [String] = []

    private func actionID(_ suffix: String) -> String { "\(actionIDPrefix).\(suffix)" }

    private func secretOption(_ id: String, defaultValue: String? = nil) -> ExtensionOption {
        ExtensionOption(identifier: id, label: id, type: .secret, defaultValue: defaultValue)
    }

    private func stringOption(_ id: String, defaultValue: String? = nil) -> ExtensionOption {
        ExtensionOption(identifier: id, label: id, type: .string, defaultValue: defaultValue)
    }

    private func account(for actionID: String, option: ExtensionOption) -> String {
        ActionOptionKey.defaultsKey(actionID: actionID, optionID: option.identifier)
    }

    override func setUp() async throws {
        try await super.setUp()
        SecretStore.setBackendForTesting(MemorySecretBackend())
        store = SecretActionOptionStore()
        writtenAccounts = []
        writtenDefaultsKeys = []
    }

    override func tearDown() async throws {
        for account in writtenAccounts {
            _ = SecretStore.delete(account: account)
        }
        for key in writtenDefaultsKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        writtenAccounts = []
        writtenDefaultsKeys = []
        SecretStore.resetBackendForTesting()
        try await super.tearDown()
    }

    func testSecretWritesToSecretStoreAndNeverUserDefaults() {
        let option = secretOption("apiKey")
        let aid = actionID("writeSecret")
        let account = account(for: aid, option: option)
        writtenAccounts.append(account)

        store.setStringValue("supersecret", actionID: aid, option: option)

        XCTAssertEqual(SecretStore.get(account: account), "supersecret")
        XCTAssertNil(
            UserDefaults.standard.string(forKey: ActionOptionKey.defaultsKey(actionID: aid, optionID: option.identifier)),
            "Secret option values must never be stored in UserDefaults"
        )
    }

    func testUnsetSecretReadsDefaultValue() {
        let withDefault = secretOption("withDefault", defaultValue: "fallback")
        XCTAssertEqual(store.stringValue(actionID: actionID("unset1"), option: withDefault), "fallback")

        let withoutDefault = secretOption("withoutDefault")
        XCTAssertEqual(store.stringValue(actionID: actionID("unset2"), option: withoutDefault), "")
    }

    func testEmptySetAndClearDeleteSecretStoreEntry() {
        let option = secretOption("apiKey")
        let aid = actionID("clearSecret")
        let account = account(for: aid, option: option)
        writtenAccounts.append(account)

        store.setStringValue("v", actionID: aid, option: option)
        XCTAssertEqual(SecretStore.get(account: account), "v")

        store.setStringValue("", actionID: aid, option: option)
        XCTAssertNil(SecretStore.get(account: account), "Empty secret value should delete the SecretStore entry")

        store.setStringValue("v2", actionID: aid, option: option)
        XCTAssertEqual(SecretStore.get(account: account), "v2")

        store.clearValue(actionID: aid, option: option)
        XCTAssertNil(SecretStore.get(account: account), "clearValue should delete the SecretStore entry")
    }

    func testNonSecretRoundTripsThroughSettingsStore() {
        let option = stringOption("prefix", defaultValue: "DEFAULT")
        let aid = actionID("nonSecret")
        let defaultsKey = ActionOptionKey.defaultsKey(actionID: aid, optionID: option.identifier)
        writtenDefaultsKeys.append(defaultsKey)

        XCTAssertEqual(store.stringValue(actionID: aid, option: option), "DEFAULT")
        store.setStringValue("SET", actionID: aid, option: option)
        XCTAssertEqual(store.stringValue(actionID: aid, option: option), "SET")
        store.clearValue(actionID: aid, option: option)
        XCTAssertEqual(store.stringValue(actionID: aid, option: option), "DEFAULT")
    }

    func testSecretHasNoUserDefaultsReadOrMigrationFallback() {
        let option = secretOption("apiKey", defaultValue: "DEFAULT")
        let aid = actionID("noFallback")
        let defaultsKey = ActionOptionKey.defaultsKey(actionID: aid, optionID: option.identifier)
        UserDefaults.standard.set("stale-legacy-secret", forKey: defaultsKey)
        defer { UserDefaults.standard.removeObject(forKey: defaultsKey) }

        XCTAssertEqual(
            store.stringValue(actionID: aid, option: option), "DEFAULT",
            "Secret reads must not fall back to UserDefaults"
        )
        XCTAssertNil(
            SecretStore.get(account: account(for: aid, option: option)),
            "No legacy UserDefaults secret should be migrated into the SecretStore"
        )
    }

    func testSecretStoreRoundTripsAndDeletes() {
        XCTAssertTrue(SecretStore.set("test-key-value", account: "testAccount"))
        XCTAssertEqual(SecretStore.get(account: "testAccount"), "test-key-value")
        XCTAssertTrue(SecretStore.set("replaced", account: "testAccount"))
        XCTAssertEqual(SecretStore.get(account: "testAccount"), "replaced")
        XCTAssertTrue(SecretStore.delete(account: "testAccount"))
        XCTAssertNil(SecretStore.get(account: "testAccount"))
        XCTAssertTrue(SecretStore.delete(account: "testAccount"), "Deleting a missing entry succeeds")
    }

    func testFailedWriteReportsFailureAndKeepsOldValue() {
        let backend = MemorySecretBackend()
        SecretStore.setBackendForTesting(backend)
        XCTAssertTrue(SecretStore.set("old", account: "acc"))
        backend.setFailsWrites(true)
        XCTAssertFalse(SecretStore.set("new", account: "acc"))
        XCTAssertEqual(SecretStore.get(account: "acc"), "old")
    }

    func testKeychainBackendRoundTripsUnderThrowawayService() {
        let backend = KeychainSecretBackend(service: "com.olegy.openclip.tests.\(UUID().uuidString)")
        defer { _ = backend.remove(account: "acc") }
        XCTAssertNil(backend.read(account: "acc"))
        XCTAssertTrue(backend.write("one", account: "acc"))
        XCTAssertEqual(backend.read(account: "acc"), "one")
        XCTAssertTrue(backend.write("two", account: "acc"))
        XCTAssertEqual(backend.read(account: "acc"), "two")
        XCTAssertTrue(backend.remove(account: "acc"))
        XCTAssertNil(backend.read(account: "acc"))
    }
}
