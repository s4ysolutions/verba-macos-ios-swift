import Foundation
import Security

/// Holds an RSA key pair together with the pre-computed SPKI bytes and their SHA-256 hash.
/// Marked `@unchecked Sendable` because `SecKey` is a Core Foundation opaque type that is
/// safe to use across concurrency boundaries (the OS manages its own locking internally).
public struct KeyPair: @unchecked Sendable {
    /// RSA private key (stored in the Keychain; retrieved as a `SecKey` reference).
    public let privateKey: SecKey
    /// X.509 SubjectPublicKeyInfo DER encoding of the public key (sent to the server once
    /// during registration).
    public let publicKeySPKI: Data
    /// SHA-256 digest of `publicKeySPKI`, Base64-encoded. Identifies the key in every token.
    public let publicKeyHashBase64: String
}

