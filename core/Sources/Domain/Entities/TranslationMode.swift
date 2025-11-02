public enum TranslationMode: Sendable {
    case TranslateSentence
    case ExplainWords
    case Auto

    public static func from(string: String) -> Result<TranslationMode, ValidationError> {
        let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "translatesentence", "translate_sentence", "sentence", "translate":
            return .success(.TranslateSentence)
        case "explainwords", "explain_words", "explain", "words", "word":
            return .success(.ExplainWords)
        case "auto", "":
            return .success(.Auto)
        default:
            return .failure(.invalidMode(string))
        }
    }
}
