import SwiftUI
import core

@main
struct verba_iosApp: App {
    // Create a shared service that conforms to both TranslateUseCase and GetProvidersUseCase
    private let translationService = TranslationService(translationRepository: TranslationRestRepository())

    var body: some Scene {
        WindowGroup {
            ContentView(
                translateUseCase: translationService,
                getProvidersUseCase: translationService
            )
        }
    }
}
