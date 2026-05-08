import Foundation
import OSLog
import Security

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "verba", category: "AuthService")

/// Application-layer actor that drives the RSA-based authentication lifecycle:
///
/// 1. **Key generation** — calls `AuthKeyRepository.getOrCreateKeyPair()` on first use.
/// 2. **Registration** — `POST /registerPublicKey` with the SPKI-encoded public key;
///    persists the returned numeric `userId`.  The operation is idempotent on the server
///    side, so re-registering the same key always yields the same user.
/// 3. **Token creation** — builds and signs the 6-field Bearer token on every request.
///
/// The actor also implements `UserRepository` so it can be injected wherever a
/// `UserRepository` is expected (e.g. `TranslationService`).
public actor AuthService: UserRepository, BearerTokenProvider {

    private let keyRepository: AuthKeyRepository
    private let httpClient: HttpClient
    private let registrationURL: URL

    // In-memory cache; reset if the actor is re-created.
    private var cachedKeyPair: KeyPair?
    private var cachedUserId: Int64?

    /// - Parameters:
    ///   - keyRepository: Persists the RSA key pair and the numeric user ID.
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

    /// Returns a `User` whose `id` is the string representation of the server-assigned
    /// numeric user ID (e.g. `"42"`).
    public func me() async -> Result<User, ApiError> {
        do {
            let (_, userId) = try await ensureRegistered()
            return .success(User(id: String(userId)))
        } catch {
            return .failure(.unexpected(error.localizedDescription))
        }
    }

    // MARK: - BearerTokenProvider

    /// Builds the signed 6-field token:
    /// `<userId>.<payload>.<keyHash>.<timestamp>.<nonce>.<signature>`
    ///
    /// The `signature` covers the first 5 fields joined by `.` using SHA256withRSA.
    public func makeToken(payload: String) async throws -> String {
        let (keyPair, userId) = try await ensureRegistered()

        let timestamp = iso8601Now()
        let nonce = Int64.random(in: 0 ... Int64.max)
        let keyHash = keyPair.publicKeyHashBase64

        let message = "\(userId).\(payload).\(keyHash).\(timestamp).\(nonce)"
        let signature = try rsaSign(message: message, privateKey: keyPair.privateKey)

        return "\(message).\(signature)"
    }

    // MARK: - Private

    /// Guarantees a valid `(KeyPair, userId)` pair, running registration if necessary.
    private func ensureRegistered() async throws -> (KeyPair, Int64) {
        if let kp = cachedKeyPair, let uid = cachedUserId {
            return (kp, uid)
        }

        let keyPair = try await keyRepository.getOrCreateKeyPair()
        cachedKeyPair = keyPair

        if let storedId = await keyRepository.loadUserId() {
            logger.debug("Loaded stored userId: \(storedId)")
            cachedUserId = storedId
            return (keyPair, storedId)
        }

        logger.debug("No stored userId — registering public key…")
        let userId = try await registerPublicKey(spki: keyPair.publicKeySPKI)
        try await keyRepository.saveUserId(userId)
        cachedUserId = userId
        logger.debug("Registered; userId = \(userId)")
        return (keyPair, userId)
    }

    /// Calls `POST <registrationURL>` with `{"type":"Anonymous","spki":"<Base64>"}` and
    /// returns the server-assigned numeric `userId`.
    ///
    /// - Note: CLIENT.md states the response is `200 OK {}`.  In practice the server must
    ///   return the `userId` for the client to construct valid tokens; this implementation
    ///   expects `{"userId": <Int64>}` in the response body.  If that field is absent
    ///   `AuthError.missingUserId` is thrown.
    private func registerPublicKey(spki: Data) async throws -> Int64 {
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

        // Parse userId from the JSON response.
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let userId = json["userId"] as? Int64 {
                return userId
            }
            // JSONSerialization may decode large integers as Int or Double on some platforms.
            if let userId = json["userId"] as? Int {
                return Int64(userId)
            }
            if let userId = json["userId"] as? Double {
                return Int64(userId)
            }
        }

        throw AuthError.missingUserId
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

