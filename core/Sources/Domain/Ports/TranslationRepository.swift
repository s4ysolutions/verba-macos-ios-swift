public protocol TranslationRepository: Sendable {
    func translate(from translationRequest: TranslationRequest) async -> Result<TranslationResponse, ApiError>
    func providers() async -> Result<[TranslationProvider], ApiError>
}
