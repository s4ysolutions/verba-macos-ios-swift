import Foundation
public struct TranslationRestRepository: TranslationRepository {
    static let url = URL(string: "http://127.0.0.1/translation")!
    static let bearerToken: String = "token-expected-as-bearer"

    public init() {

    }

    public func translate(from translationRequest: TranslationRequest) async -> Result<String, TranslationError> {
        // Build request
        var request = URLRequest(url: Self.url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(Self.bearerToken)", forHTTPHeaderField: "Authorization")

        // Map enums to server-expected strings
        let modeString: String = {
            switch translationRequest.mode {
                case .TranslateSentence: return "translate"
                case .ExplainWords: return "explain"
                case .Auto: return "auto"
            }
        }()

        let providerString: String = {
            switch translationRequest.provider {
                case .OpenAI: return "openai"
                case .Gemini: return "google"
            }
        }()

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
            "quality": qualityString
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

            // Basic error mapping by status code
            switch http.statusCode {
                case 200...299:
                    break
                case 401, 403:
                    return .failure(.api(.invalidKey))
                case 429:
                    return .failure(.api(.rateLimitExceeded))
                default:
                    let bodyPreview = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
                    return .failure(.api(.unexpected("HTTP \(http.statusCode): \(bodyPreview)")))
            }

            // Try to decode either JSON { "text": "..."} or plain text
            if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let translated = json["text"] as? String {
                return .success(translated)
            } else if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                return .success(text)
            } else {
                return .failure(.api(.decodingFailed("translation response", NSError(domain: "Empty response", code: -1))))
            }
        } catch {
            return .failure(.api(.networking(error)))
        }
    }
}

