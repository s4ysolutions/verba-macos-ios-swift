import Foundation

/// Errors produced by the RSA-based authentication infrastructure.
public enum AuthError: Error, LocalizedError {
    case keychainError(OSStatus)
    case keyGenerationFailed(String)
    /// The registration endpoint returned a non-success HTTP status or an unexpected body.
    case registrationFailed(String)
    case tokenCreationFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .keychainError(status):
            return "Keychain error (OSStatus \(status))"
        case let .keyGenerationFailed(msg):
            return "RSA key generation failed: \(msg)"
        case let .registrationFailed(msg):
            return "Public-key registration failed: \(msg)"
        case let .tokenCreationFailed(msg):
            return "Bearer token creation failed: \(msg)"
        }
    }
}

