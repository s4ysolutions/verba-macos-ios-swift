import core
import SwiftUI
@main
struct verba_masosApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        appScene
    }

    init() {
        appDelegate.translationService = translationService
        UserDefaults.standard.register(defaults: [
            autoCopyKey: true
        ])
        UserDefaults.standard.register(defaults: [
            autoPasteKey: true
        ])
        UserDefaults.standard.register(defaults: [
            requestIpaKey: true
        ])
    }

    // MARK: - Scene Builders

    @available(macOS 13.0, *)
    private var modernScene: some Scene {
        Settings {
        }
        .windowResizability(.contentSize)
        .windowToolbarStyle(.automatic)
        .commands {
            CommandGroup(replacing: .appSettings) {
                // Empty - removes Settings menu item
            }
        }
    }

    @available(macOS, introduced: 11.0, obsoleted: 13.0)
    private var legacyScene: some Scene {
        Settings {
        }
        .windowToolbarStyle(.automatic)
        .commands {
            CommandGroup(replacing: .appSettings) {
                // Empty - removes Settings menu item
            }
        }
    }

    private var appScene: some Scene {
        if #available(macOS 13.0, *) {
            return modernScene
        } else {
            return legacyScene
        }
    }

    private let translationService = TranslationService(translationRepository: TranslationRestRepository())
}
