import Foundation
import OSLog
import Security

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "verba", category: "AuthService")

/// Application-layer actor that drives the RSA-based authentication lifecycle:
///
/// 1. **Key generation** — calls `AuthKeyRepository.getOrCreateKeyPair()` on first use.
/// 2. **Registration** — `POST /registerPublicKey` with the SPKI-encoded public key.
///    The server responds `200 {}` — no `userId` is returned.  The operation is idempotent.
/// 3. **Token creation** — builds and signs the 5-field Bearer token on every request:
///    `<payload>.<publicKeyHash>.<timestamp>.<nonce>.<signature>`
///
/// The actor also implements `UserRepository` so it can be injected wherever a
/// `UserRepository` is expected (e.g. `TranslationService`).  `User.id` is the
/// Base64-encoded SHA-256 hash of the public key SPKI — this never exposes a server-side
/// numeric identity.
public actor AuthService: UserRepository, BearerTokenProvider {

    private let keyRepository: AuthKeyRepository
    private let httpClient: HttpClient
    private let registrationURL: URL

    // In-memory cache; reset if the actor is re-created.
    private var cachedKeyPair: KeyPair?
    private var registered: Bool = false

    /// - Parameters:
    ///   - keyRepository: Persists the RSA key pair.
    ///   - httpClient: Used for the one-time registration call.
    ///   - registrationURL: `POST` endpoint that accepts `{"type":"Anonymous","spki":"..."}`.
    public init(
        keyRepository: AuthKeyRepository,
        httpClient: HttpClient = URLSession.shared,
        registrationURL: URL = BackendConfig.registrationURL
    ) {
        self.keyRepository = keyRepository
        self.httpClient = httpClient
        self.registrationURL = registrationURL
    }

    // MARK: - UserRepository

    /// Returns a `User` whose `id` is the Base64-encoded SHA-256 hash of the public key SPKI.
    /// This is computed locally — no server round-trip needed.
    public func me() async -> Result<User, ApiError> {
        do {
            let keyPair = try await ensureRegistered()
            return .success(User(id: keyPair.publicKeyHashBase64))
        } catch {
            return .failure(.unexpected(error.localizedDescription))
        }
    }

    // MARK: - BearerTokenProvider

    /// Builds the signed 5-field token:
    /// `<payload>.<keyHash>.<timestamp>.<nonce>.<signature>`
    ///
    /// The `signature` covers the first 4 fields joined by `.` using SHA256withRSA.
    public func makeToken(payload: String) async throws -> String {
        let keyPair = try await ensureRegistered()

        let timestamp = iso8601Now()
        let nonce = Int64.random(in: 0 ... Int64.max)
        let keyHash = keyPair.publicKeyHashBase64

        let message = "0.\(payload).\(keyHash).\(timestamp).\(nonce)"
        let signature = try rsaSign(message: message, privateKey: keyPair.privateKey)

        return "\(message).\(signature)"
    }

    // MARK: - Private

    /// Guarantees a registered `KeyPair`, running registration if this is the first call.
    @discardableResult
    private func ensureRegistered() async throws -> KeyPair {
        let keyPair: KeyPair
        if let cached = cachedKeyPair {
            logger.debug("Using cached key pair. SPKI hash: \(cached.publicKeyHashBase64, privacy: .public)")
            keyPair = cached
        } else {
            keyPair = try await keyRepository.getOrCreateKeyPair()
            logger.debug("Fetched key pair from repository. SPKI hash: \(keyPair.publicKeyHashBase64, privacy: .public)")
            cachedKeyPair = keyPair
        }

        if !registered {
            logger.debug("Registering public key…")
            try await registerPublicKey(spki: keyPair.publicKeySPKI)
            registered = true
            logger.debug("Public key registered (idempotent).")
        }

        return keyPair
    }

    /// Calls `POST <registrationURL>` with `{"type":"Anonymous","spki":"<Base64>"}`.
    /// The server returns `200 OK {}` — no body is parsed.
    private func registerPublicKey(spki: Data) async throws {
        var request = URLRequest(url: registrationURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "type": "Anonymous",
            "spki": spki.base64EncodedString(),
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await httpClient.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AuthError.registrationFailed("Non-HTTP response from registration endpoint")
        }

        guard (200 ... 299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            throw AuthError.registrationFailed("HTTP \(http.statusCode): \(body)")
        }
    }

    /// Signs `message` (UTF-8) with RSA-SHA256 PKCS#1 v1.5 and returns a Base64 string.
    private func rsaSign(message: String, privateKey: SecKey) throws -> String {
        guard let messageData = message.data(using: .utf8) else {
            throw AuthError.tokenCreationFailed("Cannot encode message as UTF-8")
        }

        var cfError: Unmanaged<CFError>?
        guard let signatureData = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            messageData as CFData,
            &cfError
        ) as Data? else {
            throw AuthError.tokenCreationFailed(
                cfError?.takeRetainedValue().localizedDescription ?? "SecKeyCreateSignature returned nil"
            )
        }

        return signatureData.base64EncodedString()
    }

    private func iso8601Now() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime,
                                   .withDashSeparatorInDate,
                                   .withColonSeparatorInTime,
                                   .withTimeZone]
        return formatter.string(from: Date())
    }
}
