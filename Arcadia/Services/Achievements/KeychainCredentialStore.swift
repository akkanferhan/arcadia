import Foundation
import Security

/// Keeps the RetroAchievements username and token as one generic password in the login Keychain.
struct KeychainCredentialStore: AchievementsCredentialStore {
    var service = "dev.ferhanakkan.Arcadia.RetroAchievements"

    struct Failure: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
            return String(localized: "The Keychain couldn't save your sign-in: \(message)")
        }
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
    }

    func load() -> RetroAchievementsAPI.Login? {
        var request = query
        request[kSecReturnAttributes as String] = true
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let item = result as? [String: Any],
              let username = item[kSecAttrAccount as String] as? String,
              let data = item[kSecValueData as String] as? Data,
              let token = String(data: data, encoding: .utf8), !username.isEmpty, !token.isEmpty else { return nil }
        return RetroAchievementsAPI.Login(username: username, token: token)
    }

    func save(_ login: RetroAchievementsAPI.Login) throws {
        try delete()
        var item = query
        item[kSecAttrAccount as String] = login.username
        item[kSecAttrLabel as String] = "Arcadia RetroAchievements"
        item[kSecValueData as String] = Data(login.token.utf8)
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure(status: status) }
    }

    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
    }
}
