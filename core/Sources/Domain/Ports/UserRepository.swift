public protocol UserRepository: Sendable {
    func me() async -> Result<User, ApiError>
}
