public struct TranslationResponse: Sendable {
    public let translated: String
    public let inputTokenCount: Int
    public let outputTokenCount: Int
    public let timeMs: Int
    public let providers: [TranslationProvider]
}
