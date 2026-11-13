import Foundation
import Security

/// Where the server password lives: the keychain, never `UserDefaults` and
/// never a backup. Kept readable after the first unlock, so an upload that
/// starts as the app goes away still finds it once the phone is locked.
nonisolated struct SyncSecrets: Sendable {
    var read: @Sendable () -> String?
    var write: @Sendable (String?) -> Bool

    static let keychain = SyncSecrets(
        read: {
            var query = baseQuery
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data
            else { return nil }
            return String(data: data, encoding: .utf8)
        },
        write: { password in
            SecItemDelete(baseQuery as CFDictionary)
            guard let password else { return true }
            var item = baseQuery
            item[kSecValueData as String] = Data(password.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
        }
    )

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "HippoTrophy.sync",
            kSecAttrAccount as String: "webdav",
        ]
    }
}
