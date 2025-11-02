public enum TranslationProvider: Sendable {
    case OpenAI
    case Gemini

    public static func from(string: String) -> Result<TranslationProvider, ValidationError> {
        let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "openai": return .success(.OpenAI)
        case "google", "gemini": return .success(.Gemini)
        default: return .failure(.invalidProvider(string))
        }
    }
}
