import Foundation

public enum TranslationQuality: String, CaseIterable, Identifiable, Sendable, Codable, CustomStringConvertible, Hashable {
    case Fast
    case Optimal
    case Thinking

    public var id: String { rawValue }

    public var description: String {
        "\(rawValue)"
    }

    public var displayName: String {
        switch self {
        case .Fast: return NSLocalizedString("entity.quality.fast", comment: "Fast")
        case .Optimal: return NSLocalizedString("entity.quality.optimal", comment: "Optimal")
        case .Thinking: return NSLocalizedString("entity.quality.thinking", comment: "Thinking")
        }
    }
}

