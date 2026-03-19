import Foundation
import Security

/// Persists the AES session key, key ID, and ingestor URL in the Keychain.
/// Survives app restarts. Cleared on handshake failure (401/403).
struct SessionData: Codable {
    let aesKeyBase64: String
    let keyID: String
    let ingestorURL: String
    let maxBatchSize: Int
}

enum KeychainStore {
    private static let service = "io.logflux.sdk"
    private static let account = "session-key"

    static func save(_ session: SessionData) -> Bool {
        guard let data = try? JSONEncoder().encode(session) else { return false }

        // Delete existing entry first
        delete()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func load() -> SessionData? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(SessionData.self, from: data)
    }

    @discardableResult
    static func delete() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
