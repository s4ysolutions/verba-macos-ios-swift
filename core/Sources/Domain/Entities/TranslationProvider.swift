public struct TranslationProvider: Codable, Hashable, Identifiable, Sendable, CustomStringConvertible {
    // Stable identifier, e.g., "openai", "google"
    public let id: String
    public let displayName: String
    public let qualities: [TranslationQuality]

    public init(id: String, displayName: String, qualities: [TranslationQuality]) {
        self.id = id
        self.displayName = displayName
        self.qualities = qualities
    }

    public var description: String {
        "\(displayName) (id: \(id), qualities: \(qualities))"
    }
}
