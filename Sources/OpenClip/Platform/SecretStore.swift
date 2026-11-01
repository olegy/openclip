// SecretStore.swift
// OpenClip
//
// Secrets (the cloud AI API key and secret action options) live in the login Keychain as generic
// passwords, one item per account under the service `<bundle id>.secrets`. The release build is
// signed with a stable identity, so access survives updates without prompts. Under XCTest the
// store is in memory, so tests never touch the real Keychain.
import Foundation
import Core
import Security

public protocol SecretBackend: Sendable {
    func read(account: String) -> String?
    func write(_ value: String, account: String) -> Bool
    func remove(account: String) -> Bool
}

public enum SecretStore {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var backend: SecretBackend = defaultBackend()

    /// Replaces the backend; tests use it to inject failures or a throwaway Keychain service.
    public static func setBackendForTesting(_ newBackend: SecretBackend) {
        lock.lock()
        defer { lock.unlock() }
        backend = newBackend
    }

    /// Restores the default backend, which is in memory under XCTest.
    public static func resetBackendForTesting() {
        setBackendForTesting(defaultBackend())
    }

    public static func get(account: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return backend.read(account: account)
    }

    @discardableResult
    public static func set(_ value: String, account: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return backend.write(value, account: account)
    }

    @discardableResult
    public static func delete(account: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return backend.remove(account: account)
    }

    private static func defaultBackend() -> SecretBackend {
        NSClassFromString("XCTestCase") == nil ? KeychainSecretBackend() : MemorySecretBackend()
    }
}

public struct KeychainSecretBackend: SecretBackend {
    private let service: String

    public init(service: String = "\(Bundle.main.bundleIdentifier ?? "com.olegy.openclip").secrets") {
        self.service = service
    }

    public func read(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            Log.settings.error("Keychain read failed (status \(status))")
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public func write(_ value: String, account: String) -> Bool {
        let data = Data(value.utf8)
        let lookup = baseQuery(account: account)
        var status = SecItemUpdate(lookup as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var addition = lookup
            addition[kSecValueData as String] = data
            status = SecItemAdd(addition as CFDictionary, nil)
        }
        if status != errSecSuccess {
            Log.settings.error("Keychain write failed (status \(status))")
        }
        return status == errSecSuccess
    }

    public func remove(account: String) -> Bool {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            Log.settings.error("Keychain delete failed (status \(status))")
        }
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

public final class MemorySecretBackend: SecretBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    private var failsWrites = false

    public init() {}

    /// Makes `write` fail, like a locked or denied Keychain.
    public func setFailsWrites(_ fails: Bool) {
        lock.lock()
        defer { lock.unlock() }
        failsWrites = fails
    }

    public func read(account: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[account]
    }

    public func write(_ value: String, account: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !failsWrites else { return false }
        values[account] = value
        return true
    }

    public func remove(account: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        values.removeValue(forKey: account)
        return true
    }
}
