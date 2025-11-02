public struct TranslationRequest: Sendable {
    public let sourceText: String
    public let sourceLang: String
    public let targetLang: String
    public let mode: TranslationMode
    public let provider: TranslationProvider
    public let quality: TranslationQuality

    private init(
        sourceText: String,
        sourceLang: String,
        targetLang: String,
        mode: TranslationMode,
        provider: TranslationProvider,
        quality: TranslationQuality
    ) {
        self.sourceText = sourceText
        self.sourceLang = sourceLang
        self.targetLang = targetLang
        self.mode = mode
        self.provider = provider
        self.quality = quality
    }

    public static func create(
        sourceText: String,
        sourceLang: String,
        targetLang: String,
        mode: String = "auto",
        provider: String = "google",
        quality: String = "medium",
    ) -> Result<TranslationRequest, TranslationError> {
        // Validate sourceText
        let trimmedText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return .failure(.validation(.emptyString))
        }

        guard sourceLang.count <= 12 else {
            return .failure(.validation(.langTooLong(sourceLang)))
        }
        guard sourceLang.count > 2 else {
            return .failure(.validation(.langTooShort(sourceLang)))
        }
        guard targetLang.count <= 12 else {
            return .failure(.validation(.langTooLong(targetLang)))
        }
        guard targetLang.count > 2 else {
            return .failure(.validation(.langTooShort(targetLang)))
        }

        let modeResult = TranslationMode.from(string: mode)
        let providerResult = TranslationProvider.from(string: provider)
        let qualityResult = TranslationQuality.from(string: quality)

        // Short-circuit on any failure
        switch (modeResult, providerResult, qualityResult) {
        case let (.success(mode), .success(provider), .success(quality)):
            // All parsed: Create and succeed
            let request = TranslationRequest(
                sourceText: sourceText,
                sourceLang: sourceLang,
                targetLang: targetLang,
                mode: mode,
                provider: provider,
                quality: quality
            )
            return .success(request)

        case let (.failure(modeErr), _, _):
            return .failure(.validation(modeErr))
        case let (_, .failure(providerErr), _):
            return .failure(.validation(providerErr))
        case let (_, _, .failure(qualityErr)):
            return .failure(.validation(qualityErr))
        }
    }
}
