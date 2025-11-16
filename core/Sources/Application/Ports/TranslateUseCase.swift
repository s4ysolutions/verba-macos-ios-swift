public protocol TranslateUseCase: Sendable {
    func translate(from translationRequest: TranslationRequest) async -> Result<TranslationResponse, TranslationError>
}
