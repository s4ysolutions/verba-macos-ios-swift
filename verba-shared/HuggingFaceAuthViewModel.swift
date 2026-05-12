import AuthenticationServices
import Combine
import core
import CryptoKit
import Foundation
import Security

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

@MainActor
final class HuggingFaceAuthViewModel: NSObject, ObservableObject {
    @Published private(set) var isSigningIn = false
    @Published private(set) var isSignedIn: Bool
    @Published var errorMessage: String?

    private let tokenProvider: KeychainOAuthTokenProvider
    private var session: ASWebAuthenticationSession?
    private var currentState: String?
    private var currentCodeVerifier: String?

    private let authorizeURL = URL(string: "https://huggingface.co/oauth/authorize")!
    private let tokenURL = URL(string: "https://huggingface.co/oauth/token")!

    override init() {
        let tokenProvider = KeychainOAuthTokenProvider()
        self.tokenProvider = tokenProvider
        isSignedIn = tokenProvider.hasToken()
        super.init()
    }

    func signIn() {
        guard !isSigningIn else { return }

        guard let config = OAuthConfig.fromBundle() else {
            errorMessage = "Set HUGGING_FACE_CLIENT_ID before signing in."
            return
        }

        let state = Self.randomURLSafeString(byteCount: 32)
        let codeVerifier = Self.randomURLSafeString(byteCount: 64)
        currentState = state
        currentCodeVerifier = codeVerifier

        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI.absoluteString),
            URLQueryItem(name: "scope", value: "openid profile inference-api"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: Self.codeChallenge(for: codeVerifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]

        guard let url = components.url else {
            errorMessage = "Could not build Hugging Face sign-in URL."
            return
        }

        isSigningIn = true
        errorMessage = nil

        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: config.redirectScheme
        ) { [weak self] callbackURL, error in
            Task { @MainActor in
                await self?.handleCallback(callbackURL: callbackURL, error: error, config: config)
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        self.session = session

        if !session.start() {
            isSigningIn = false
            errorMessage = "Could not start Hugging Face sign-in."
        }
    }

    func signOut() {
        do {
            try tokenProvider.clearToken()
            isSignedIn = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleCallback(
        callbackURL: URL?,
        error: Error?,
        config: OAuthConfig
    ) async {
        defer {
            isSigningIn = false
            session = nil
            currentState = nil
            currentCodeVerifier = nil
        }

        if let error = error as? ASWebAuthenticationSessionError,
           error.code == .canceledLogin {
            return
        }

        if let error {
            errorMessage = error.localizedDescription
            return
        }

        guard let callbackURL,
              let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems else {
            errorMessage = "Hugging Face sign-in did not return a callback URL."
            return
        }

        let returnedState = items.first(where: { $0.name == "state" })?.value
        guard returnedState == currentState else {
            errorMessage = "Hugging Face sign-in returned an invalid state."
            return
        }

        guard let code = items.first(where: { $0.name == "code" })?.value,
              let codeVerifier = currentCodeVerifier else {
            errorMessage = "Hugging Face sign-in did not return an authorization code."
            return
        }

        do {
            let token = try await exchangeCode(code, codeVerifier: codeVerifier, config: config)
            try tokenProvider.setToken(token)
            isSignedIn = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exchangeCode(
        _ code: String,
        codeVerifier: String,
        config: OAuthConfig
    ) async throws -> String {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncoded([
            "grant_type": "authorization_code",
            "client_id": config.clientID,
            "code": code,
            "redirect_uri": config.redirectURI.absoluteString,
            "code_verifier": codeVerifier,
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthFlowError.message("Hugging Face token endpoint returned a non-HTTP response.")
        }

        guard (200 ... 299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AuthFlowError.message("Hugging Face token exchange failed: HTTP \(http.statusCode) \(body)")
        }

        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        return token.accessToken
    }

    private static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncodedString()
    }

    private static func formEncoded(_ values: [String: String]) -> Data {
        let body = values
            .map { key, value in
                "\(key.urlFormEncoded)=\(value.urlFormEncoded)"
            }
            .joined(separator: "&")
        return Data(body.utf8)
    }
}

extension HuggingFaceAuthViewModel: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if canImport(UIKit)
            return UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
        #elseif canImport(AppKit)
            return NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
        #else
            return ASPresentationAnchor()
        #endif
    }
}

private struct OAuthConfig {
    let clientID: String
    let redirectScheme: String
    let redirectURI: URL

    static func fromBundle() -> OAuthConfig? {
        let bundle = Bundle.main
        guard let clientID = bundle.object(forInfoDictionaryKey: "HUGGING_FACE_CLIENT_ID") as? String,
              !clientID.isEmpty,
              !clientID.hasPrefix("$(") else {
            return nil
        }

        let redirectScheme = (bundle.object(forInfoDictionaryKey: "HUGGING_FACE_REDIRECT_SCHEME") as? String)
            .flatMap { $0.isEmpty || $0.hasPrefix("$(") ? nil : $0 } ?? "verba"

        guard let redirectURI = URL(string: "\(redirectScheme)://oauth/huggingface/callback") else {
            return nil
        }

        return OAuthConfig(clientID: clientID, redirectScheme: redirectScheme, redirectURI: redirectURI)
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
    }
}

private enum AuthFlowError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case let .message(message):
            return message
        }
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension String {
    var urlFormEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlFormAllowed) ?? self
    }
}

private extension CharacterSet {
    static let urlFormAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        return allowed
    }()
}
