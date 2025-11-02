import OSLog

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "verba-masos", category: "TranslationService")

public actor TranslationService<R: TranslationRepository>  {
    private let respository: R

    public init(repository: R) {
        self.respository = repository
    }

    public func translate(from translationRequest: TranslationRequest) async -> Result<String, TranslationError> {
        logger.debug("request: \(translationRequest.sourceText)")
        let response = await respository.translate(from: translationRequest)
        return response
    }
}
