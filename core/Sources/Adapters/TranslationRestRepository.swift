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
    private static let translationUrl = BackendConfig.restBaseURL.appendingPathComponent("translation")
    private static let providersUrl = BackendConfig.restBaseURL.appendingPathComponent("providers")

    private let tokenProvider: BearerTokenProvider
    private let httpClient: HttpClient

    /// - Parameters:
    ///   - tokenProvider: Builds and signs the Bearer token for every request.
    ///     Typically an `AuthService` instance.
    ///   - httpClient: Defaults to `URLSession.shared`.
    public init(
        tokenProvider: BearerTokenProvider,
        httpClient: HttpClient = URLSession.shared
    ) {
        self.tokenProvider = tokenProvider
        self.httpClient = httpClient
    }

    public func providers() async -> Result<[TranslationProvider], ApiError> {
        var request = URLRequest(url: Self.providersUrl)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let token = try await tokenProvider.makeToken(payload: "")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } catch {
            return .failure(.unexpected(error.localizedDescription))
        }

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
                return .failure(
                    .decodingFailed(NSLocalizedString("msg.get-providers", comment: ""), data, error.localizedDescription))
            }
        }
    }

    public func translate(from translationRequest: TranslationRequest, byUser: User) async -> Result<TranslationResponse, ApiError> {
        var request = URLRequest(url: Self.translationUrl)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let token = try await tokenProvider.makeToken(payload: "")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } catch {
            return .failure(.unexpected(error.localizedDescription))
        }

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
            "userId": byUser.id,
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: bodyDict, options: [])
            request.httpBody = data
        } catch {
            return .failure(.encodingFailed(NSLocalizedString("error.api.encoding.json", comment: "Error while encoding translation request as JSON"), error))
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
                return .failure(
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


    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "verba-masos", category: "TranslationRestRepository")
}
