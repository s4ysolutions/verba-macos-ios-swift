import Foundation
import OSLog

private struct HFMessageDTO: Codable {
    let role: String
    let content: String
}

private struct HFChoiceMessageDTO: Codable {
    let content: String
}

private struct HFChoiceDTO: Codable {
    let message: HFChoiceMessageDTO
}

private struct HFUsageDTO: Codable {
    let prompt_tokens: Int?
    let completion_tokens: Int?
}

private struct HFChatCompletionDTO: Codable {
    let choices: [HFChoiceDTO]
    let usage: HFUsageDTO?
}

public struct HuggingFaceTranslationRepository: TranslationRepository {
    private let tokenProvider: OAuthAccessTokenProvider
    private let httpClient: HttpClient

    public init(
        tokenProvider: OAuthAccessTokenProvider,
        httpClient: HttpClient = URLSession.shared
    ) {
        self.tokenProvider = tokenProvider
        self.httpClient = httpClient
    }

    public func providers() async -> Result<[TranslationProvider], ApiError> {
        .success(HuggingFaceConfig.providers)
    }

    public func translate(from translationRequest: TranslationRequest) async -> Result<TranslationResponse, ApiError> {
        var request = URLRequest(url: HuggingFaceConfig.chatCompletionsURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let token = try await tokenProvider.accessToken()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } catch {
            return .failure(.authRequired("Sign in to Hugging Face to translate."))
        }

        let systemPrompt = "You are a translation assistant. Return only final user-facing output with no meta commentary."
        let userPrompt = makePrompt(from: translationRequest)

        let temperature: Double = switch translationRequest.quality {
        case .Fast: 0.1
        case .Optimal: 0.2
        case .Thinking: 0.2
        }

        let body: [String: Any] = [
            "model": translationRequest.provider.id,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt],
            ],
            "temperature": temperature,
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            return .failure(.encodingFailed("huggingface.chatCompletions", error))
        }

        do {
            let start = Date()
            let (data, response) = try await httpClient.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.unexpected("Non-HTTP response"))
            }

            switch http.statusCode {
            case 200 ... 299:
                break
            case 401, 403:
                return .failure(.invalidKey)
            case 413:
                return .failure(.requestTooBig)
            case 429:
                return .failure(.rateLimitExceeded)
            default:
                let bodyString = String(data: data, encoding: .utf8)
                return .failure(.http(http.statusCode, bodyString))
            }

            let dto = try JSONDecoder().decode(HFChatCompletionDTO.self, from: data)
            guard let translated = dto.choices.first?.message.content, !translated.isEmpty else {
                return .failure(.decodingFailed("huggingface.choices", data, "Missing choices[0].message.content"))
            }

            let duration = Int(Date().timeIntervalSince(start) * 1000)
            return .success(
                TranslationResponse(
                    translated: translated.trimmingCharacters(in: .whitespacesAndNewlines),
                    inputTokenCount: dto.usage?.prompt_tokens ?? 0,
                    outputTokenCount: dto.usage?.completion_tokens ?? 0,
                    timeMs: duration,
                    providers: HuggingFaceConfig.providers
                )
            )
        } catch let decodeError as DecodingError {
            return .failure(.decodingFailed("huggingface.decode", Data(), decodeError.localizedDescription))
        } catch {
            logger.error("HF request failed: \(error.localizedDescription)")
            return .failure(.networking(error))
        }
    }

    private func makePrompt(from request: TranslationRequest) -> String {
        let modeInstruction: String = switch request.mode {
        case .TranslateSentence:
            "Translate text to the target language."
        case .ExplainWords:
            "Translate and briefly explain key words/phrases."
        case .Auto:
            "Choose between translation and explanation based on input ambiguity."
        }

        let sourceLabel = request.sourceLang?.isEmpty == false ? request.sourceLang! : "auto-detect"
        let ipaInstruction = request.ipa ? "Include IPA pronunciation on a new line." : "Do not include IPA."

        return """
        \(modeInstruction)
        Source language: \(sourceLabel)
        Target language: \(request.targetLang)
        \(ipaInstruction)

        Text:
        \(request.sourceText)
        """
    }

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "verba", category: "HuggingFaceTranslationRepository")
}
