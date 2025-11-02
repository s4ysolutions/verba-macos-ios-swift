import SwiftUI
import core

private struct TranslationServiceKey: EnvironmentKey {
    typealias Value = TranslationService<TranslationRestRepository>

    static let defaultValue = TranslationService(repository: TranslationRestRepository())
}

extension EnvironmentValues {
    var translationService: TranslationService<TranslationRestRepository> {
        get { self[TranslationServiceKey.self] }
        set { self[TranslationServiceKey.self] = newValue }
    }
}
