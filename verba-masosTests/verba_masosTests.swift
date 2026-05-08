import Foundation
import Testing
import core

struct verba_masosTests {

    @Test("Integration: TranslationRestRepository returns providers")
    func translationRestRepositoryProvidersShouldReturnNonEmptyList() async throws {
        let authService = AuthService(keyRepository: KeychainAuthKeyRepository())
        let repository = TranslationRestRepository(tokenProvider: authService)

        let result = await repository.providers()

        switch result {
        case let .success(providers):
            #expect(!providers.isEmpty)
            #expect(providers.allSatisfy { !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            #expect(providers.contains { !$0.qualities.isEmpty })
        case let .failure(error):
            Issue.record("providers() failed with: \(error.localizedDescription)")
            #expect(Bool(false))
        }
    }
}
