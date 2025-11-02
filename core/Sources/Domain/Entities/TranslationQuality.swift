public enum TranslationQuality: Sendable {
    case Fast
    case Optimal
    case Thinking

    public static func from(string: String) -> Result<TranslationQuality, ValidationError> {
        let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "fast": return .success(.Fast)
        case "optimal": return .success(.Optimal)
        case "high", "think", "thinking", "deep": return .success(.Thinking)
        default: return .failure(.invalidQuality(string))
        }
    }
}
