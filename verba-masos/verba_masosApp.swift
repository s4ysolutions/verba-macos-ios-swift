//
//  verba_masosApp.swift
//  verba-masos
//
//  Created by Dolin Sergey on 2. 11. 2025..
//

import SwiftUI

@main
struct verba_masosApp: App {
    // Attach AppDelegate to integrate AppKit status item and activation behavior.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Return a single `some Scene` that’s chosen outside the SceneBuilder.
        appScene
    }

    // MARK: - Scene Builders

    // For macOS 13+ with modern window modifiers
    @available(macOS 13.0, *)
    private var modernScene: some Scene {
        WindowGroup("MainWindow") {
            ContentView()
        }
        .defaultSize(width: 800, height: 600)
        .windowResizability(.contentSize)
        .windowToolbarStyle(.automatic)
        .commands {
            // Optional: Add a standard Quit in the app menu (macOS provides one by default).
        }
    }

    // For macOS 12 fallback
    @available(macOS, introduced: 11.0, obsoleted: 13.0)
    private var legacyScene: some Scene {
        WindowGroup("MainWindow") {
            ContentView()
        }
        .commands {
            // Optional: Add a standard Quit in the app menu (macOS provides one by default).
        }
    }

    // Single entry that chooses the appropriate scene at runtime, outside SceneBuilder context.
    private var appScene: some Scene {
        if #available(macOS 13.0, *) {
            return modernScene
        } else {
            return legacyScene
        }
    }
}
