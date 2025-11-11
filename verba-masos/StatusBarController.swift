//
//  StatusBarController.swift
//  verba-masos
//

import Cocoa
import os

final class StatusBarController {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "verba-masos", category: "StatusBar")

    // UserDefaults keys

    private let statusItem: NSStatusItem
    private let menu: NSMenu

    private let onShow: () -> Void
    private let onQuit: () -> Void

    init(onShow: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.onShow = onShow
        self.onQuit = onQuit

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        menu = NSMenu()
        buildMenu(into: menu)

        if let button = statusItem.button {
            button.image = NSImage(named: "verba-png-16") // NSImage(systemSymbolName: "text.bubble", accessibilityDescription: nil)
            button.image?.isTemplate = false // use colors for dark/light menu bar
            Self.logger.debug("Status item button configured with template image")

            // Set up action handling for clicks.
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            // IMPORTANT: Use mouseDown so the action fires even when the app is inactive.
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
            Self.logger.debug("Status item button actions set for left and right mouse down")
        } else {
            Self.logger.error("Failed to get status item button")
        }
    }

    private func buildMenu(into menu: NSMenu) {
        /*
        let showTitle = NSLocalizedString("menu.show", value: "Show", comment: "Show main window")
        let showItem = NSMenuItem(title: showTitle, action: #selector(didTapShow), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)
         */


        // Ensure defaults exist and are true by default
        let defaults = UserDefaults.standard

        // Checkable preferences
        let autoCopyTitle = NSLocalizedString("menu.check.autoCopy", value: "Monitor Clipboard", comment: "Toggle monitoring clipboard")
        let autoCopyItem = NSMenuItem(title: autoCopyTitle, action: #selector(toggleAutoCopy(_:)), keyEquivalent: "")
        autoCopyItem.target = self
        autoCopyItem.state = defaults.bool(forKey: autoCopyKey) ? .on : .off
        autoCopyItem.onStateImage = NSImage(named: NSImage.menuOnStateTemplateName)
        menu.addItem(autoCopyItem)

        let autoPasteTitle = NSLocalizedString("menu.check.autoPaste", value: "Auto-Paste Translation", comment: "Toggle auto pasting translation to clipboard")
        let autoPasteItem = NSMenuItem(title: autoPasteTitle, action: #selector(toggleAutoPaste(_:)), keyEquivalent: "")
        autoPasteItem.target = self
        autoPasteItem.state = defaults.bool(forKey: autoPasteKey) ? .on : .off
        autoPasteItem.onStateImage = NSImage(named: NSImage.menuOnStateTemplateName)
        menu.addItem(autoPasteItem)

        let requestIPATitle = NSLocalizedString("menu.requestIPA", value: "Show Transcription", comment: "Request IPA transcription with the translation")
        let requestIpaItem = NSMenuItem(title: requestIPATitle, action: #selector(toggleRequestIpa(_:)), keyEquivalent: "")
        requestIpaItem.state = defaults.bool(forKey: requestIpaKey) ? .on : .off
        requestIpaItem.onStateImage = NSImage(named: NSImage.menuOnStateTemplateName)
        requestIpaItem.target = self
        menu.addItem(requestIpaItem)

        menu.addItem(NSMenuItem.separator())

        let quitTitle = NSLocalizedString("menu.quit", value: "Quit", comment: "Quit application")
        let quitItem = NSMenuItem(title: quitTitle, action: #selector(didTapQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            Self.logger.warning("statusItemClicked: No current event; defaulting to onShow()")
            onShow()
            return
        }

        Self.logger.debug("statusItemClicked: eventType=\(String(describing: event.type.rawValue))")

        switch event.type {
        case .rightMouseDown:
            Self.logger.info("Right click detected; showing menu")
            showMenu()
        case .leftMouseDown:
            Self.logger.info("Left click detected; invoking onShow()")
            // Defer to next runloop turn to let status item tracking finish cleanly.
            DispatchQueue.main.async { [onShow] in
                onShow()
            }
        default:
            // Ignore mouseUp and other types to prevent double-handling.
            Self.logger.debug("Ignoring event type: \(String(describing: event.type.rawValue))")
            break
        }
    }

    private func showMenu() {
        guard let button = statusItem.button else { return }
        statusItem.menu = menu
        button.performClick(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.statusItem.menu = nil
        }
    }

    @objc private func toggleAutoCopy(_ sender: NSMenuItem) {
        sender.state = (sender.state == .on) ? .off : .on
        let newValue = (sender.state == .on)
        UserDefaults.standard.set(newValue, forKey: autoCopyKey)
    }

    @objc private func toggleAutoPaste(_ sender: NSMenuItem) {
        sender.state = (sender.state == .on) ? .off : .on
        let newValue = (sender.state == .on)
        UserDefaults.standard.set(newValue, forKey: autoPasteKey)
    }

    @objc private func toggleRequestIpa(_ sender: NSMenuItem) {
        sender.state = (sender.state == .on) ? .off : .on
        let newValue = (sender.state == .on)
        UserDefaults.standard.set(newValue, forKey: requestIpaKey)
    }

    @objc private func didTapShow() {
        onShow()
        //hideApp()
    }

    @objc private func didTapQuit() {
        onQuit()
    }
}
