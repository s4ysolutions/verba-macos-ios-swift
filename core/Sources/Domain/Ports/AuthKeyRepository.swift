import Foundation

/// Port responsible for persisting the RSA key pair used for authentication.
public protocol AuthKeyRepository: Sendable {
    /// Returns the existing RSA key pair from the Keychain, or generates and stores a new one.
    func getOrCreateKeyPair() async throws -> KeyPair
}
