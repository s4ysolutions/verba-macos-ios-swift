/// Port that the adapter layer uses to obtain a signed Bearer token for a single request.
public protocol BearerTokenProvider: Sendable {
    /// Builds and signs the 6-field `<userId>.<payload>.<keyHash>.<timestamp>.<nonce>.<sig>`
    /// token string.  Pass an empty string for `payload` when no per-request context is needed.
    func makeToken(payload: String) async throws -> String
}

