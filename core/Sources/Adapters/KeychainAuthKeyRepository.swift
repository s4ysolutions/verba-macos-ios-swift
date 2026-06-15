import CryptoKit
import OSLog

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "verba", category: "AuthService")
import Foundation
import Security

/// Implements `AuthKeyRepository` using the system Keychain for key storage.
///
/// - The private key is generated once (RSA-2048) and stored as a permanent Keychain item
///   tagged by `keyTag`.
/// - The public key is exported in PKCS#1 DER format by the OS and then wrapped in an
///   X.509 SubjectPublicKeyInfo (SPKI) structure before being sent to the server.
/// - If the Keychain item already exists the existing key is reused; re-registering the same
///   SPKI with the server is idempotent.
public final class KeychainAuthKeyRepository: AuthKeyRepository, @unchecked Sendable {

    private let keyTag: String

    public init(
        keyTag: String = "solutions.s4y.verba.auth.privateKey"
    ) {
        self.keyTag = keyTag
    }

    // MARK: - AuthKeyRepository

    public func getOrCreateKeyPair() async throws -> KeyPair {
        if let existing = try loadExistingKeyPair() {
            return existing
        }
        return try generateAndStoreKeyPair()
    }

    // MARK: - Private — Key management

    private func loadExistingKeyPair() throws -> KeyPair? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrApplicationTag as String: keyTag.data(using: .utf8)!,
            kSecReturnRef as String: true,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw AuthError.keychainError(status) }
        let privateKey = item as! SecKey // Security framework guarantees SecKey when kSecReturnRef + kSecAttrKeyClassPrivate
        return try buildKeyPair(privateKey: privateKey)
    }

    private func generateAndStoreKeyPair() throws -> KeyPair {
        let tagData = keyTag.data(using: .utf8)!

        let params: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: tagData,
            ],
        ]

        var cfError: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(params as CFDictionary, &cfError) else {
            throw AuthError.keyGenerationFailed(
                cfError?.takeRetainedValue().localizedDescription ?? "SecKeyCreateRandomKey returned nil"
            )
        }

        return try buildKeyPair(privateKey: privateKey)
    }

    private func buildKeyPair(privateKey: SecKey) throws -> KeyPair {
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw AuthError.keyGenerationFailed("SecKeyCopyPublicKey returned nil")
        }

        var cfError: Unmanaged<CFError>?
        guard let pkcs1Data = SecKeyCopyExternalRepresentation(publicKey, &cfError) as Data? else {
            throw AuthError.keyGenerationFailed(
                cfError?.takeRetainedValue().localizedDescription ?? "SecKeyCopyExternalRepresentation returned nil"
            )
        }

        let spki = wrapInSPKI(pkcs1Data: pkcs1Data)
        let hashBytes = Data(SHA256.hash(data: spki))
        let hashBase64 = hashBytes.base64EncodedString()

        logger.debug("Generated new RSA key pair with SPKI hash \(hashBase64, privacy: .public)")

        return KeyPair(privateKey: privateKey, publicKeySPKI: spki, publicKeyHashBase64: hashBase64)
    }

    // MARK: - Private — DER / SPKI helpers

    /// Wraps a PKCS#1 RSA public-key DER blob in an X.509 SubjectPublicKeyInfo structure.
    private func wrapInSPKI(pkcs1Data: Data) -> Data {
        let algorithmIdentifier = Data([
            0x30, 0x0d,
            0x06, 0x09,
            0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01,
            0x05, 0x00,
        ])

        var bitStringContent = Data([0x00])
        bitStringContent.append(pkcs1Data)
        let bitString = derEncode(tag: 0x03, content: bitStringContent)

        var spkiContent = algorithmIdentifier
        spkiContent.append(bitString)
        return derEncode(tag: 0x30, content: spkiContent)
    }

    private func derEncode(tag: UInt8, content: Data) -> Data {
        var result = Data([tag])
        let len = content.count
        if len < 0x80 {
            result.append(UInt8(len))
        } else if len < 0x100 {
            result.append(contentsOf: [0x81, UInt8(len)])
        } else {
            result.append(contentsOf: [0x82, UInt8(len >> 8), UInt8(len & 0xff)])
        }
        result.append(content)
        return result
    }
}
