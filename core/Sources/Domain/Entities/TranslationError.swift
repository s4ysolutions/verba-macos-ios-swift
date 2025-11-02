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
            case .invalidProvider(let provider):
                return "Invalid provider: \(provider)"
            case .invalidQuality(let quality):
                return "Invalid quality: \(quality)"
            case .invalidMode(let mode):
                return "Invalid mode: \(mode)"
            case .langTooLong(let lang):
                return "Language too long: \(lang)"
            case .langTooShort(let lang):
                return "Lang too short: \(lang)"
        }
    }
}

public enum ApiError: Error, LocalizedError {
    case invalidKey
    case rateLimitExceeded
    case encodingFailed(String, Error)
    case decodingFailed(String, Error)
    case networking(Error)
    case unexpected(String)

    public var errorDescription: String? {
        switch self {
            case .invalidKey:
                return "Invalid API key"
            case .rateLimitExceeded:
                return "Rate limit exceeded"
            case .encodingFailed(let data, let error):
                return "Failed to encode data: \(data). Error: \(error.localizedDescription)"
            case .decodingFailed(let data, let error):
                return "Failed to decode data: \(data). Error: \(error.localizedDescription)"
            case .networking(let error):
                return "Networking error: \(error.localizedDescription)"
            case .unexpected(let message):
                return "Unexpected error: \(message)"
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
            case .validation(let error):
                return error.errorDescription
            case .api(let error):
                return error.errorDescription
        }
    }
}
