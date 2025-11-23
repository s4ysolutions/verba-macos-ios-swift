import Foundation

public enum ApiError: Error, LocalizedError {
    case invalidKey
    case rateLimitExceeded
    case requestTooBig
    case encodingFailed(String, Error)
    // location, data, error message
    case decodingFailed(String, Data, String)
    case http(Int, String?)
    case networking(Error)
    case unexpected(String)

    public var errorDescription: String? {
        switch self {
        case .invalidKey:
            return "Invalid Application key"
        case .rateLimitExceeded:
            return "Rate limit exceeded"
        case .requestTooBig:
            return NSLocalizedString("error.api.request-too-big", comment: "Request to translate too big")
        case let .encodingFailed(data, error):
            return "Failed to encode data: \(data). Error: \(error.localizedDescription)"
        case let .decodingFailed(location, data, error):
            let string = String(data: data, encoding: .utf8) ?? "<binary data>"
            return String(format: NSLocalizedString("error.api.decoding", comment: ""), location, error, string) ?? NSLocalizedString("error.api.decoding-default", comment: "")
        case let .http(code, message):
            return Self.extractHttpErrorMessage(code, message)
        case let .networking(error):
            return "Networking error: \(error.localizedDescription)"
        case let .unexpected(message):
            return "Unexpected error: \(message)"
        }
    }

    private static func extractHttpErrorMessage(_ code: Int, _ msg: String?) -> String {
        guard let body = msg else {
            return String(format: NSLocalizedString("error.api.http.code-only", comment: "Message to report HTTP status code"), code)
        }

        // Extract <body> content if present
        let content: String
        if let bodyStart = body.range(of: "<body>", options: .caseInsensitive),
           let bodyEnd = body.range(of: "</body>", options: .caseInsensitive, range: bodyStart.upperBound ..< body.endIndex) {
            content = String(body[bodyStart.upperBound ..< bodyEnd.lowerBound])
        } else {
            content = body
        }

        // Remove <center>nginx/...</center> if present
        let withoutNginx: String
        if let centerStart = content.range(of: "<center>nginx", options: .caseInsensitive),
           let centerEnd = content.range(of: "</center>", options: .caseInsensitive, range: centerStart.lowerBound ..< content.endIndex) {
            withoutNginx = content.replacingCharacters(in: centerStart.lowerBound ... centerEnd.upperBound, with: "")
        } else {
            withoutNginx = content
        }

        // Remove all HTML tags and trim
        let cleaned = withoutNginx
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Return appropriate format
        if cleaned.contains("\(code)") {
            return String(format: NSLocalizedString("error.api.http.body-only", comment: "Message to report HTTP status message"), cleaned)
        }
        return String(format: NSLocalizedString("error.api.http.code-and-body", comment: "Message to report HTTP status message along with status code"), code, cleaned)
    }

    private static func removeHTMLTags(_ string: String) -> String {
        return string.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression,
            range: nil
        )
    }
}
