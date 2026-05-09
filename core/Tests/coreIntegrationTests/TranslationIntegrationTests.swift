import Foundation
import Security
import Testing
@testable import core
// MARK: - Helpers
private func deleteKeychainKey(tag: String) {
    let query: [String: Any] = [
        kSecClass as String: kSecClassKey,
        kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
        kSecAttrApplicationTag as String: tag.data(using: .utf8)!,
    ]
    SecItemDelete(query as CFDictionary)
}
/// Builds a wired-up (repo, tag) pair using a unique Keychain tag so each
/// test is isolated from the live app key and from other tests.
private func makeRepo() -> (repo: TranslationRestRepository, tag: String) {
    let tag = "solutions.s4y.verba.test.\(UUID().uuidString)"
    let keyRepo = KeychainAuthKeyRepository(keyTag: tag)
    let auth = AuthService(keyRepository: keyRepo)
    let repo = TranslationRestRepository(tokenProvider: auth)
    return (repo, tag)
}
// MARK: - Providers
@Suite(
    "TranslationRestRepository.providers — Integration",
    // .enabled(if: ProcessInfo.processInfo.environment["INTEGRATION"] == "1")
)
struct ProvidersIntegrationTests {
    @Test("providers() returns at least one provider")
    func providers_returns_non_empty_list() async throws {
        let (repo, tag) = makeRepo()
        defer { deleteKeychainKey(tag: tag) }
        let result = await repo.providers()
        switch result {
        case .success(let providers):
            #expect(!providers.isEmpty, "Expected at least one provider from the backend")
            for provider in providers {
                #expect(!provider.id.isEmpty, "Provider id must not be empty")
                #expect(!provider.qualities.isEmpty, "Provider must expose at least one quality")
            }
        case .failure(let err):
            Issue.record("providers() failed: \(err)")
        }
    }
}
// MARK: - Translation
@Suite(
    "TranslationRestRepository.translate — Integration",
    //.enabled(if: ProcessInfo.processInfo.environment["INTEGRATION"] == "1")
)
struct TranslationIntegrationTests {
    @Test("translate() returns a non-empty translated string")
    func translate_english_to_french() async throws {
        let (repo, tag) = makeRepo()
        defer { deleteKeychainKey(tag: tag) }
        // Fetch providers first so we use one the server actually knows about.
        let providersResult = await repo.providers()
        guard case .success(let providers) = providersResult, let provider = providers.first else {
            Issue.record("Could not fetch providers — skipping translation test")
            return
        }
        let requestResult = TranslationRequest.create(
            sourceText: "Hello",
            sourceLang: "eng",
            targetLang: "fra",
            mode: .TranslateSentence,
            provider: provider,
            quality: .Fast,
            ipa: false
        )
        guard case .success(let request) = requestResult else {
            Issue.record("Failed to build TranslationRequest: \(requestResult)")
            return
        }
        let result = await repo.translate(from: request)
        switch result {
        case .success(let response):
            #expect(!response.translated.isEmpty, "Translated text must not be empty")
            #expect(response.inputTokenCount > 0, "Input token count should be positive")
            #expect(response.outputTokenCount > 0, "Output token count should be positive")
            #expect(response.timeMs >= 0, "Time measurement must be non-negative")
            #expect(!response.providers.isEmpty, "Response should carry updated providers list")
        case .failure(let err):
            Issue.record("translate() failed: \(err)")
        }
    }
}
