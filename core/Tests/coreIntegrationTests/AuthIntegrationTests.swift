import Foundation
import Security
import Testing

@testable import core

// MARK: - Helpers

/// Deletes an RSA private key from the Keychain by tag.
/// Used in `defer` blocks so test keys don't accumulate.
private func deleteKeychainKey(tag: String) {
    let query: [String: Any] = [
        kSecClass as String: kSecClassKey,
        kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
        kSecAttrApplicationTag as String: tag.data(using: .utf8)!,
    ]
    SecItemDelete(query as CFDictionary)
}

/// Returns a fresh `AuthService` backed by a `KeychainAuthKeyRepository` using `keyTag`.
private func makeAuth(keyTag: String) -> AuthService {
    let keyRepo = KeychainAuthKeyRepository(keyTag: keyTag)
    return AuthService(keyRepository: keyRepo)
}

// MARK: - registerPublicKey

@Suite(
    "registerPublicKey — Integration",
    // .enabled(if: ProcessInfo.processInfo.environment["INTEGRATION"] == "1")
)
struct RegisterPublicKeyIntegrationTests {

    /// First-ever registration: a fresh key pair is generated and POSTed to the server.
    /// Expect `me()` to succeed and return a non-empty user id (the key hash).
    @Test("fresh key pair registers successfully")
    func fresh_key_registers() async throws {
        let tag = "solutions.s4y.verba.test.\(UUID().uuidString)"
        defer { deleteKeychainKey(tag: tag) }

        let auth = makeAuth(keyTag: tag)
        let result = await auth.me()

        switch result {
        case .success(let user):
            #expect(!user.id.isEmpty, "user.id (key hash) must not be empty")
        case .failure(let err):
            Issue.record("First registration failed: \(err)")
        }
    }

    /// Re-registering the exact same SPKI must be idempotent (server returns 200 {}).
    /// Simulated by creating a second `AuthService` instance with the same keychain tag —
    /// `registered` is `false` on the new actor, so it calls `registerPublicKey` again.
    @Test("re-registering same key is idempotent")
    func re_register_is_idempotent() async throws {
        let tag = "solutions.s4y.verba.test.\(UUID().uuidString)"
        defer { deleteKeychainKey(tag: tag) }

        // First registration
        let auth1 = makeAuth(keyTag: tag)
        guard case .success(let user1) = await auth1.me() else {
            Issue.record("First registration failed — cannot continue idempotency check")
            return
        }

        // New actor instance, same keychain key → will POST the same SPKI again
        let auth2 = makeAuth(keyTag: tag)
        switch await auth2.me() {
        case .success(let user2):
            #expect(user1.id == user2.id, "Both instances must resolve to the same key hash")
        case .failure(let err):
            Issue.record("Re-registration failed: \(err)")
        }
    }
}

