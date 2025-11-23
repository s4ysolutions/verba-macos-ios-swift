public protocol TranslationRepository: Sendable {
    func translate(from translationRequest: TranslationRequest, byUser: User) async -> Result<TranslationResponse, ApiError>
    func providers() async -> Result<[TranslationProvider], ApiError>
}
