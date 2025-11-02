public protocol TranslationRepository: Sendable {
    func translate(from translationRequest: TranslationRequest) async -> Result<String, TranslationError>
}
