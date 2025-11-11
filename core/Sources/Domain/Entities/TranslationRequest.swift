public struct TranslationRequest: Sendable {
    public let sourceText: String
    public let sourceLang: String
    public let targetLang: String
    public let mode: TranslationMode
    public let provider: TranslationProvider
    public let quality: TranslationQuality
    public let ipa: Bool

    private init(
        sourceText: String,
        sourceLang: String,
        targetLang: String,
        mode: TranslationMode,
        provider: TranslationProvider,
        quality: TranslationQuality,
        ipa: Bool,
    ) {
        self.sourceText = sourceText
        self.sourceLang = sourceLang
        self.targetLang = targetLang
        self.mode = mode
        self.provider = provider
        self.quality = quality
        self.ipa = ipa
    }

    public static func create(
        sourceText: String,
        sourceLang: String,
        targetLang: String,
        mode: TranslationMode = .Auto,
        provider: TranslationProvider,
        quality: TranslationQuality = .Optimal,
        ipa: Bool
    ) -> Result<TranslationRequest, TranslationError> {
        // Validate sourceText
        let trimmedText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return .failure(.validation(.emptyString))
        }

        guard sourceLang.count <= 16 else {
            return .failure(.validation(.langTooLong(sourceLang)))
        }
        guard sourceLang.count > 2 else {
            return .failure(.validation(.langTooShort(sourceLang)))
        }
        guard targetLang.count <= 16 else {
            return .failure(.validation(.langTooLong(targetLang)))
        }
        guard targetLang.count > 2 else {
            return .failure(.validation(.langTooShort(targetLang)))
        }

        // let modeResult = mode //TranslationMode.from(string: mode)
        // let qualityResult = TranslationQuality.from(string: quality)
        // let providerResult = TranslationProvider.from(string: provider)

        // Short-circuit on any failure
        // switch providerResult {
        // case let .success(provider):
        // All parsed: Create and succeed
        let request = TranslationRequest(
            sourceText: sourceText,
            sourceLang: sourceLang,
            targetLang: targetLang,
            mode: mode,
            provider: provider,
            quality: quality,
            ipa: ipa
        )
        return .success(request)

        // case let .failure(providerErr):
        // return .failure(.validation(providerErr))
        // }
    }
}
