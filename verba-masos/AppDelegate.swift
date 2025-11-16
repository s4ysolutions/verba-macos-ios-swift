//
//  AppDelegate.swift
//  verba-masos
//

import Cocoa
import core
import os
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var translateUseCase: TranslateUseCase?
    var getProvidersUseCase: GetProvidersUseCase? // TranslationService<TranslationRestRepository>?

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "verba-masos", category: "AppDelegate")
    private var doubleCmdCDetector: GlobalDoubleCmdCDetector?
    private let selectionCapture = SelectionCapture()

    private var statusBarController: StatusBarController?
    private var mainWindow: NSWindow? // keep a strong reference

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusBarController = StatusBarController(
            onShow: { [weak self] in
                Self.logger.debug("Show clicked self=<\(self)>")
                // self?.showWindow()
                self?.bringMainWindowToFront()
            },
            onQuit: {
                NSApp.terminate(nil)
            }
        )

        doubleCmdCDetector = GlobalDoubleCmdCDetector {
            Self.logger.debug("Double Cmd+C detected!")
            self.selectionCapture.captureSelection { [weak self] _ in
                guard let self = self else {
                    Self.logger.warning("No text captured")
                    return
                }
                self.bringMainWindowToFront()
            }
        }

        let started = doubleCmdCDetector?.start() ?? false
        Self.logger.debug("Double Cmd+C detection \(started ? "started" : "not started")")
    }

    private func showWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Reopen window if needed
        if NSApp.windows.isEmpty {
            // Trigger window creation through your SwiftUI scene
            NotificationCenter.default.post(name: NSNotification.Name("ShowMainWindow"), object: nil)
        } else {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }

    // Bring the SwiftUI WindowGroup window to front and focus it.
    private func bringMainWindowToFront() {
        // Single async is enough - let status item event finish
        DispatchQueue.main.async {
            Self.logger.debug("Bringing window to front")

            // Activate app first
            // NSApp.unhide(nil)
            // NSApp.activate(ignoringOtherApps: true)
            NSApp.setActivationPolicy(.regular)
            // NSApp.activate(ignoringOtherApps: true)
            self.activateApp()

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
            let hosting = NSHostingController(rootView: ContentView(
                translateUseCase: self.translateUseCase!,
                getProvidersUseCase: self.getProvidersUseCase!
            ))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Verba"
            window.contentViewController = hosting
            window.isReleasedWhenClosed = false
            window.delegate = self

            self.mainWindow = window
            self.repositionIfNeeded(window)
            self.present(window)
        }
    }

    // MARK: - NSWindowDelegate

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        NSApp.setActivationPolicy(.accessory)
        return false
    }

    func windowWillClose(_ notification: Notification) {
        Self.logger.debug("windowWillClose")
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

        activateApp()

        // Make key and order front

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            /*
             Switches from whatever app is active to yours
             The ignoringOtherApps: true means "steal focus even if user is typing in another app"
             */
            NSApp.activate(ignoringOtherApps: true)
            /*
             "Make this window the key window (receives keyboard input) AND bring it to front"

             makeKey = this window gets keyboard events
             orderFront = move window to front of all windows
             */
            window.makeKeyAndOrderFront(nil)
            /*
             More aggressive than orderFront
             Ignores some window ordering restrictions
             Added because makeKeyAndOrderFront sometimes fails for menu bar apps
             */
            window.orderFrontRegardless()
            /*
             firstResponder = the thing that gets keyboard events
             Setting it to contentView should trigger SwiftUI to focus its first field
             Often doesn't work because SwiftUI manages its own focus
             */
            window.makeFirstResponder(window.contentView)
            /*
             Redundant with makeKeyAndOrderFront above
             Added out of desperation when that didn't work
             window.makeKey()
             */
            /*
             AppKit maintains a "key view loop" (tab order between fields)
             This recalculates it in case it's stale
             Might help AppKit find the first text field... might not
             */
            window.recalculateKeyViewLoop()
        }

        Self.logger.debug("Window presented")
    }

    private func activateApp() {
        // Activate with strong options
        let options: NSApplication.ActivationOptions = [.activateIgnoringOtherApps]
        NSRunningApplication.current.activate(options: options)
    }

    private func isUsableContentWindow(_ window: NSWindow) -> Bool {
        Self.logger.debug("check isUsableContentWindow: \(window)...")
        if String(describing: type(of: window)).contains("NSStatusBarWindow") { return false }
        if !window.canBecomeKey { return false }
        if window.contentViewController == nil && !window.isVisible { return false }
        Self.logger.debug("... true")
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
