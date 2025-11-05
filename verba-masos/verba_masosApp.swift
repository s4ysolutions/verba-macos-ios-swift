import SwiftUI
import core

@main
struct verba_masosApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        appScene
    }

    init() {
        appDelegate.translationService = translationService
    }

    // MARK: - Scene Builders

    @available(macOS 13.0, *)
    private var modernScene: some Scene {
        WindowGroup("Verba") {
            ContentView(translateUseCase: translationService)
        }
        .defaultSize(width: 800, height: 600)
        .windowResizability(.contentSize)
        .windowToolbarStyle(.automatic)
        .commands {
        }
    }

    @available(macOS, introduced: 11.0, obsoleted: 13.0)
    private var legacyScene: some Scene {
        WindowGroup("Verba") {
            ContentView(translateUseCase: translationService)
        }
        .commands {
        }
    }

    private var appScene: some Scene {
        if #available(macOS 13.0, *) {
            return modernScene
        } else {
            return legacyScene
        }
    }

    private let translationService = TranslationService(repository: TranslationRestRepository())
}
