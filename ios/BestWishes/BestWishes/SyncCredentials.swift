import Foundation
import Security

/// The sync token lives in the Keychain, never in UserDefaults, files, or git.
nonisolated enum SyncCredentials {
    private static let service = "com.davidgeorgehope.hopesvoice.sync"
    private static let account = "device-token"

    /// Unsigned simulator builds (CI, tests) have no Keychain entitlement. The token then lives
    /// in memory for this launch only; it is never written to a file.
    nonisolated(unsafe) private static var memoryToken: String?

    static func token() -> String? {
        if let memoryToken { return memoryToken }
        var query = base()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let token = String(data: data, encoding: .utf8), !token.isEmpty else { return nil }
        return token
    }

    static func setToken(_ token: String?) {
        SecItemDelete(base() as CFDictionary)
        memoryToken = nil
        guard let token = token?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else { return }
        var item = base()
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        if SecItemAdd(item as CFDictionary, nil) != errSecSuccess { memoryToken = token }
    }

    private static func base() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}
