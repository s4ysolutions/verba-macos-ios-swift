import Foundation
import Security

public final class KeychainOAuthTokenProvider: OAuthAccessTokenProvider, @unchecked Sendable {
    private let account: String
    private let service: String

    public init(
        account: String = "huggingface-user-token",
        service: String = "solutions.s4y.verba.oauth"
    ) {
        self.account = account
        self.service = service
    }

    public func accessToken() async throws -> String {
        guard let token = try getToken(), !token.isEmpty else {
            throw AuthError.tokenCreationFailed("Missing OAuth access token")
        }
        return token
    }

    public func setToken(_ token: String) throws {
        let data = Data(token.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service,
        ]

        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw AuthError.keychainError(addStatus)
            }
            return
        }

        guard updateStatus == errSecSuccess else {
            throw AuthError.keychainError(updateStatus)
        }
    }

    public func clearToken() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AuthError.keychainError(status)
        }
    }

    public func hasToken() -> Bool {
        (try? getToken())?.isEmpty == false
    }

    private func getToken() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw AuthError.keychainError(status)
        }

        guard let data = item as? Data else {
            throw AuthError.tokenCreationFailed("Keychain item was not Data")
        }

        return String(data: data, encoding: .utf8)
    }
}
