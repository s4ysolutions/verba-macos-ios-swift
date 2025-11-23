import Foundation

public enum ValidationError: Error, LocalizedError {
    case emptyString
    case invalidProvider(String)
    case invalidQuality(String)
    case invalidMode(String)
    case langTooShort(String)
    case langTooLong(String)

    public var errorDescription: String? {
        switch self {
        case .emptyString:
            return "Field cannot be empty"
        case let .invalidProvider(provider):
            return "Invalid provider: \(provider)"
        case let .invalidQuality(quality):
            return "Invalid quality: \(quality)"
        case let .invalidMode(mode):
            return "Invalid mode: \(mode)"
        case let .langTooLong(lang):
            return "Language too long: \(lang)"
        case let .langTooShort(lang):
            return "Lang too short: \(lang)"
        }
    }
}

public enum TranslationError: Error, LocalizedError {
    case validation(ValidationError)
    case api(ApiError)

    public var category: String {
        switch self {
        case .validation:
            return "Validation"
        case .api:
            return "API"
        }
    }

    public var errorDescription: String? {
        switch self {
        case let .validation(error):
            return error.errorDescription
        case let .api(error):
            return error.errorDescription
        }
    }
}
