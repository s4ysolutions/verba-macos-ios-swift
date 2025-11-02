//
//  AppDelegate.swift
//  verba-masos
//

import Cocoa
import SwiftUI
import os

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "verba-masos", category: "AppDelegate")

    private var statusBarController: StatusBarController?
    private var mainWindow: NSWindow? // keep a strong reference

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController(
            onShow: { [weak self] in
                self?.bringMainWindowToFront()
            },
            onQuit: {
                NSApp.terminate(nil)
            }
        )
    }

    // Bring the SwiftUI WindowGroup window to front and focus it.
    private func bringMainWindowToFront() {
        // Single async is enough - let status item event finish
        DispatchQueue.main.async {
            Self.logger.debug("Bringing window to front")

            // Activate app first
            NSApp.unhide(nil)
            NSApp.activate(ignoringOtherApps: true)

            // Find or create window (no extra async needed here)
            if let window = self.mainWindow, self.isUsableContentWindow(window) {
                Self.logger.debug("Using existing mainWindow")
                self.repositionIfNeeded(window)
                self.present(window)
                return
            } else if let window = self.mainWindow, !self.isUsableContentWindow(window) {
                Self.logger.debug("Clearing invalid mainWindow")
                self.mainWindow = nil
            }

            if let window = NSApp.windows.first(where: { self.isUsableContentWindow($0) }) {
                Self.logger.debug("Found existing window in NSApp.windows")
                self.mainWindow = window
                self.repositionIfNeeded(window)
                self.present(window)
                return
            }

            Self.logger.debug("Creating new window")
            let hosting = NSHostingController(rootView: ContentView())
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "App"
            window.contentViewController = hosting
            window.isReleasedWhenClosed = false
            window.delegate = self

            self.mainWindow = window
            self.repositionIfNeeded(window)
            self.present(window)
        }
    }

    // MARK: - NSWindowDelegate
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === mainWindow {
            mainWindow = nil
        }
    }

    // MARK: - Helpers
    private func present(_ window: NSWindow) {
        Self.logger.debug("present")

        // If minimized, restore first
        if window.isMiniaturized {
            Self.logger.debug("window.deminiaturize")
            window.deminiaturize(nil)
        }

        // Activate with strong options
        let options: NSApplication.ActivationOptions = [.activateIgnoringOtherApps]
        NSRunningApplication.current.activate(options: options)

        // Make key and order front
        window.makeKeyAndOrderFront(nil)

        Self.logger.debug("Window presented")
    }

    private func isUsableContentWindow(_ window: NSWindow) -> Bool {
        if String(describing: type(of: window)).contains("NSStatusBarWindow") { return false }
        if !window.canBecomeKey { return false }
        if window.contentViewController == nil && !window.isVisible { return false }
        return true
    }

    private func repositionIfNeeded(_ window: NSWindow) {
        let frame = window.frame
        let minWidth: CGFloat = max(window.minSize.width, 400)
        let minHeight: CGFloat = max(window.minSize.height, 300)
        var needsReset = false

        if frame.width < 50 || frame.height < 50 { needsReset = true }
        let anyIntersection = NSScreen.screens.contains { screen in
            screen.visibleFrame.insetBy(dx: 20, dy: 20).intersects(frame)
        }
        if !anyIntersection { needsReset = true }

        if needsReset {
            let screen = NSScreen.main ?? NSScreen.screens.first
            let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
            let newWidth = min(max(minWidth, 800), visible.width)
            let newHeight = min(max(minHeight, 600), visible.height)
            let newX = visible.origin.x + (visible.width - newWidth) / 2.0
            let newY = visible.origin.y + (visible.height - newHeight) / 2.0
            let newFrame = NSRect(x: newX, y: newY, width: newWidth, height: newHeight)
            window.setFrame(newFrame, display: true, animate: false)
        }
    }
}
