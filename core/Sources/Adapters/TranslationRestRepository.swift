import CryptoKit
import Foundation
import OSLog

public struct TranslationRestRepository: TranslationRepository {
    private static let baseURL = "https://verba.s4y.solutions"
    //private static let baseURL = "http://localhost:4000"
    private static let translationUrl = URL(string: "\(baseURL)/translation")!
    private static let providersUrl = URL(string: "\(baseURL)/providers")!
    private let secret: String

    public init() {
        secret = Bundle.main.object(forInfoDictionaryKey: "VERBA_SECRET") as! String
    }

    public func providers() async -> Result<[TranslationProvider], ApiError> {
        var request = URLRequest(url: Self.providersUrl)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let username = "verba"
        let wsseHeader = makeWsseHeader(username: username, secret: secret)
        request.setValue(wsseHeader, forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.unexpected("Non-HTTP response"))
            }
            switch http.statusCode {
            case 200 ... 299:
                break
            case 401, 403:
                return .failure(.invalidKey)
            case 429:
                return .failure(.rateLimitExceeded)
            default:
                let bodyPreview = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
                let msg = "HTTP \(http.statusCode): \(bodyPreview)"
                logger.error("\(msg)")
                return .failure(.unexpected(msg))
            }
            if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String] {
                let providers = json.map { TranslationProvider(id: $0, displayName: $0) }
                return .success(providers)
            }
            let msg = "Get providers expected JSON array in response, got: \(data)"
            logger.error("\(msg)")
            return .failure(.decodingFailed("\(msg)", NSError(domain: "Empty response", code: -1)))
        } catch {
            let msg = "Failed to fetch providers: \(error)"
            return .failure(.networking(error))
        }
    }

    public func translate(from translationRequest: TranslationRequest) async -> Result<String, TranslationError> {
        // Build request
        var request = URLRequest(url: Self.translationUrl)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let username = "verba"
        let wsseHeader = makeWsseHeader(username: username, secret: secret)
        request.setValue(wsseHeader, forHTTPHeaderField: "Authorization")

        // Map enums to server-expected strings
        let modeString: String = {
            switch translationRequest.mode {
            case .TranslateSentence: return "translate"
            case .ExplainWords: return "explain"
            case .Auto: return "auto"
            }
        }()

        let providerString = translationRequest.provider.id

        let qualityString: String = {
            switch translationRequest.quality {
            case .Fast: return "fast"
            case .Optimal: return "optimal"
            case .Thinking: return "deep"
            }
        }()

        // Build JSON body expected by the backend
        let bodyDict: [String: Any] = [
            "text": translationRequest.sourceText,
            "from": translationRequest.sourceLang,
            "to": translationRequest.targetLang,
            "mode": modeString,
            "provider": providerString,
            "quality": qualityString,
            "ipa": translationRequest.ipa,
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: bodyDict, options: [])
            request.httpBody = data
        } catch {
            return .failure(.api(.encodingFailed("translation request body", error)))
        }

        // Execute request
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.api(.unexpected("Non-HTTP response")))
            }

            switch http.statusCode {
            case 200 ... 299:
                break
            case 401, 403:
                return .failure(.api(.invalidKey))
            case 429:
                return .failure(.api(.rateLimitExceeded))
            default:
                let bodyPreview = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
                return .failure(.api(.unexpected("HTTP \(http.statusCode): \(bodyPreview)")))
            }

            if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let translated = json["text"] as? String {
                return .success(translated)
            }

            // Try to decode as top-level JSON string
            if let topLevelString = try? JSONDecoder().decode(String.self, from: data) {
                return .success(topLevelString)
            }

            // Fallback to plain text
            if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                return .success(text)
            } else {
                return .failure(.api(.decodingFailed("translation response", NSError(domain: "Empty response", code: -1))))
            }

        } catch {
            return .failure(.api(.networking(error)))
        }
    }

    // MARK: - WSSE helpers

    // Builds a WSSE UsernameToken header string:
    // UsernameToken Username="...", PasswordDigest="...", Nonce="...", Created="..."
    private func makeWsseHeader(username: String, secret: String) -> String {
        let nonceData = secureRandomData(count: 16)
        let nonceB64 = nonceData.base64EncodedString()

        let created = iso8601NowUTC()

        // Digest = Base64(SHA-256(Nonce + Created + Secret))
        let digestB64 = wsseDigestBase64(nonceB64: nonceB64, created: created, secret: secret)

        return #"UsernameToken Username="\#(username)", PasswordDigest="\#(digestB64)", Nonce="\#(nonceB64)", Created="\#(created)""#
    }

    // Returns Base64(SHA-256(Nonce + Created + Secret)), concatenating as UTF-8 bytes
    private func wsseDigestBase64(nonceB64: String, created: String, secret: String) -> String {
        let concatenated = nonceB64 + created + secret
        let data = Data(concatenated.utf8)
        let hash = SHA256.hash(data: data)
        let digestData = Data(hash)
        return digestData.base64EncodedString()
    }

    // Generates cryptographically secure random bytes
    private func secureRandomData(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        if status == errSecSuccess {
            return Data(bytes)
        } else {
            // Fallback to CryptoKit random if SecRandom fails (unlikely)
            var buffer = Data(count: count)
            _ = buffer.withUnsafeMutableBytes { ptr in
                guard let base = ptr.baseAddress else { return }
                // Fill using random bytes from UInt64
                var remaining = count
                var offset = 0
                while remaining > 0 {
                    let rnd = UInt64.random(in: UInt64.min ... UInt64.max)
                    var rndLE = rnd.littleEndian
                    let toCopy = min(remaining, MemoryLayout.size(ofValue: rndLE))
                    withUnsafeBytes(of: &rndLE) { src in
                        memcpy(base.advanced(by: offset), src.baseAddress!, toCopy)
                    }
                    remaining -= toCopy
                    offset += toCopy
                }
            }
            return buffer
        }
    }

    // ISO-8601 UTC timestamp with 'Z', no fractional seconds, e.g. 2025-11-04T12:34:56Z
    private func iso8601NowUTC() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        // Use internet date time without fractions to match Instant.parse expectations
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime, .withTimeZone]
        return formatter.string(from: Date())
    }

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "verba-masos", category: "TranslationRestRepository")
}
