public protocol OAuthAccessTokenProvider: Sendable {
    func accessToken() async throws -> String
}
