import Foundation

public struct HybridTranslationRepository: TranslationRepository {
    private let backendRepository: TranslationRepository
    private let directRepository: TranslationRepository

    public init(
        backendRepository: TranslationRepository,
        directRepository: TranslationRepository
    ) {
        self.backendRepository = backendRepository
        self.directRepository = directRepository
    }

    public func providers() async -> Result<[TranslationProvider], ApiError> {
        async let backend = backendRepository.providers()
        async let direct = directRepository.providers()

        let backendProviders = await backend
        let directProviders = await direct

        switch (backendProviders, directProviders) {
        case let (.success(backend), .success(direct)):
            var preferredBackend = backend.filter { provider in
                usesBackend(for: provider)
            }
            if preferredBackend.isEmpty {
                preferredBackend = Self.fallbackBackendProviders
            }
            let directOnly = direct.filter { provider in
                !usesBackend(for: provider)
            }
            return .success(Self.deduplicate(preferredBackend + directOnly))
        case let (.success(backend), .failure):
            var preferredBackend = backend.filter { provider in
                usesBackend(for: provider)
            }
            if preferredBackend.isEmpty {
                preferredBackend = Self.fallbackBackendProviders
            }
            return .success(Self.deduplicate(preferredBackend))
        case let (.failure, .success(direct)):
            let backendFallback = Self.fallbackBackendProviders
            let directOnly = direct.filter { provider in
                !usesBackend(for: provider)
            }
            return .success(Self.deduplicate(backendFallback + directOnly))
        case let (.failure(backendError), .failure(directError)):
            // Keep backend error precedence for OpenAI/Gemini-focused setup.
            return .failure(backendError.localizedDescription.isEmpty ? directError : backendError)
        }
    }

    public func translate(from translationRequest: TranslationRequest) async -> Result<TranslationResponse, ApiError> {
        let translationResult: Result<TranslationResponse, ApiError>
        if usesBackend(for: translationRequest.provider) {
            translationResult = await backendRepository.translate(from: translationRequest)
        } else {
            translationResult = await directRepository.translate(from: translationRequest)
        }

        switch translationResult {
        case let .success(response):
            let mergedProvidersResult = await providers()
            let mergedProviders: [TranslationProvider]
            switch mergedProvidersResult {
            case let .success(value):
                mergedProviders = value
            case .failure:
                mergedProviders = response.providers
            }
            return .success(TranslationResponse(
                translated: response.translated,
                inputTokenCount: response.inputTokenCount,
                outputTokenCount: response.outputTokenCount,
                timeMs: response.timeMs,
                providers: mergedProviders
            ))
        case let .failure(error):
            return .failure(error)
        }
    }

    private func usesBackend(for provider: TranslationProvider) -> Bool {
        let id = provider.id.lowercased()
        let name = provider.displayName.lowercased()
        return id.contains("openai") || id.contains("gemini") || id.contains("google") ||
            name.contains("openai") || name.contains("gemini")
    }

    private static let fallbackBackendProviders: [TranslationProvider] = [
        TranslationProvider(
            id: "openai",
            displayName: "OpenAI",
            qualities: [.Fast, .Optimal, .Thinking]
        ),
        TranslationProvider(
            id: "gemini",
            displayName: "Gemini",
            qualities: [.Fast, .Optimal, .Thinking]
        ),
    ]

    private static func deduplicate(_ providers: [TranslationProvider]) -> [TranslationProvider] {
        var seen = Set<String>()
        var result: [TranslationProvider] = []
        for provider in providers {
            if seen.insert(provider.id).inserted {
                result.append(provider)
            }
        }
        return result
    }
}
