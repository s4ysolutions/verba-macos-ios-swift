import CryptoKit
import Foundation
import OSLog

private struct QualityDTO: Codable {
    let value: String
}

private struct ProviderDTO: Codable {
    let name: String
    let qualities: [QualityDTO]
}

private struct StateDTO: Codable {
    let providers: [ProviderDTO]
}

private struct TranslationResponseDTO: Codable {
    let translated: String
    let inputTokenCount: Int
    let outputTokenCount: Int
    let time: Int // milliseconds
    let state: StateDTO
}

public struct TranslationRestRepository: TranslationRepository {
    private static let baseURL = "https://verba.s4y.solutions"
    // private static let baseURL = "http://localhost:4000"
    private static let translationUrl = URL(string: "\(baseURL)/translation")!
    private static let providersUrl = URL(string: "\(baseURL)/providers")!
    private let secret: String
    private let httpClient: HttpClient

    public init(httpClient: HttpClient = URLSession.shared) {
        secret = Bundle.main.object(forInfoDictionaryKey: "VERBA_SECRET") as! String
        self.httpClient = httpClient
    }

    public func providers() async -> Result<[TranslationProvider], ApiError> {
        var request = URLRequest(url: Self.providersUrl)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let username = "verba"
        let wsseHeader = makeWsseHeader(username: username, secret: secret)
        request.setValue(wsseHeader, forHTTPHeaderField: "Authorization")

        return await executeRequest(request) { data in
            do {
                let dtos = try JSONDecoder().decode([ProviderDTO].self, from: data)
                let providers = dtos.map { dto in
                    TranslationProvider(
                        id: dto.name,
                        displayName: dto.name,
                        qualities: dto.qualities.compactMap { TranslationQuality(rawValue: $0.value) }
                    )
                }
                return .success(providers)
            } catch {
                let string = String(data: data, encoding: .utf8) ?? "<binary data>"
                logger.error("Get providers expected JSON array in response, got: \(string)\n\(error)")
                return
                    .failure(
                        .decodingFailed(NSLocalizedString("msg.get-providers", comment: ""), data, error.localizedDescription))
            }
        }
    }

    public func translate(from translationRequest: TranslationRequest) async -> Result<TranslationResponse, ApiError> {
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
            return .failure(.encodingFailed(NSLocalizedString("error.api.encoding.json", comment: "Error while encoding translation requst as JSON"), error))
        }
        return await executeRequest(request) { data in
            do {
                let dto = try JSONDecoder().decode(TranslationResponseDTO.self, from: data)

                let providers = dto.state.providers.map { providerDTO in
                    TranslationProvider(
                        id: providerDTO.name,
                        displayName: providerDTO.name,
                        qualities: providerDTO.qualities.compactMap {
                            TranslationQuality(rawValue: $0.value)
                        }
                    )
                }

                return .success(TranslationResponse(
                    translated: dto.translated,
                    inputTokenCount: dto.inputTokenCount,
                    outputTokenCount: dto.outputTokenCount,
                    timeMs: dto.time,
                    providers: providers
                ))
            } catch {
                let string = String(data: data, encoding: .utf8) ?? "<binary data>"
                logger.error("Failed to decode translation response, got \(string):\n\(error)")
                return
                    .failure(
                        .decodingFailed(NSLocalizedString("msg.translate", comment: ""), data, error.localizedDescription))
            }
        }
    }

    // MARK: - Common request execution

    func executeRequest<T>(
        _ request: URLRequest,
        parser: @escaping (Data) -> Result<T, ApiError>
    ) async -> Result<T, ApiError> {
        do {
            let (data, response) = try await httpClient.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.unexpected(
                    NSLocalizedString(
                        "error.api.http.non-http-response",
                        comment: "HTTP responded with Non-HTTP response")))
            }
            switch http.statusCode {
            case 200 ... 299:
                break
            case 401, 403:
                logger.error("Authorization error")
                return .failure(.invalidKey)
            case 413:
                logger.error("request too big")
                return .failure(.requestTooBig)
            case 429:
                logger.error("Rate limit exceeded")
                return .failure(.rateLimitExceeded)
            default:
                let bodyString: String = String(data: data, encoding: .utf8) ?? ""
                logger.error("HTTP error: \(http.statusCode)\n \(bodyString)")
                // check is body is html formatted by extracting <body> part and
                // if it is use that part as error description, use the
                // whole bodyString overwise
                let errorMessage: String = {
                    let lowercased = bodyString.lowercased()
                    if let startRange = lowercased.range(of: "<body>"),
                       let endRange = lowercased.range(of: "</body>", range: startRange.upperBound ..< lowercased.endIndex) {
                        let bodyRange = startRange.upperBound ..< endRange.lowerBound
                        // Map the range from the lowercased string back to the original string indices by offset
                        let startOffset = lowercased.distance(from: lowercased.startIndex, to: bodyRange.lowerBound)
                        let endOffset = lowercased.distance(from: lowercased.startIndex, to: bodyRange.upperBound)
                        let start = bodyString.index(bodyString.startIndex, offsetBy: startOffset)
                        let end = bodyString.index(bodyString.startIndex, offsetBy: endOffset)
                        return String(bodyString[start ..< end])
                    } else {
                        return bodyString
                    }
                }()
                return .failure(.http(http.statusCode, errorMessage))
            }

            return parser(data)
        } catch {
            return .failure(.networking(error))
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
