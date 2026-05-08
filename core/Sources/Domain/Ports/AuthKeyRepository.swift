import Foundation

/// Port responsible for persisting the RSA key pair and the server-assigned numeric user ID.
public protocol AuthKeyRepository: Sendable {
    /// Returns the existing RSA key pair from the Keychain, or generates and stores a new one.
    func getOrCreateKeyPair() async throws -> KeyPair

    /// Persists the numeric user ID returned by the server after public-key registration.
    func saveUserId(_ userId: Int64) async throws

    /// Returns the previously saved user ID, or `nil` if the device has never registered.
    func loadUserId() async -> Int64?
}

