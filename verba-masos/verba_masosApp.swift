import SwiftUI

@main
struct verba_masosApp: App {
   // private let translationService = TranslationService(repository: TranslationRestRepository())

    // Attach AppDelegate to integrate AppKit status item and activation behavior.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        appScene
    }

    // MARK: - Scene Builders

    @available(macOS 13.0, *)
    private var modernScene: some Scene {
        WindowGroup("MainWindow") {
            ContentView()
        }
        .defaultSize(width: 800, height: 600)
        .windowResizability(.contentSize)
        .windowToolbarStyle(.automatic)
        .commands {
        }
    }

    @available(macOS, introduced: 11.0, obsoleted: 13.0)
    private var legacyScene: some Scene {
        WindowGroup("MainWindow") {
            ContentView()
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
}
