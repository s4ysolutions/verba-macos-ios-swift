//
//  StatusBarController.swift
//  verba-masos
//

import Cocoa
import os

final class StatusBarController {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "verba-masos", category: "StatusBar")

    private let statusItem: NSStatusItem
    private let menu: NSMenu

    private let onShow: () -> Void
    private let onQuit: () -> Void

    init(onShow: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.onShow = onShow
        self.onQuit = onQuit

        // Create a variable-length status item.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        Self.logger.info("Status item created")

        // Prepare menu (we’ll attach it only when needed to avoid auto-popup on left click).
        menu = NSMenu()
        buildMenu(into: menu)

        if let button = statusItem.button {
            // Use a default system template icon for now; you can replace later.
            button.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: nil)
            button.image?.isTemplate = true // Adapts for dark/light menu bar
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
        let showTitle = NSLocalizedString("menu.show", value: "Show", comment: "Show main window")
        let quitTitle = NSLocalizedString("menu.quit", value: "Quit", comment: "Quit application")

        let showItem = NSMenuItem(title: showTitle, action: #selector(didTapShow), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: quitTitle, action: #selector(didTapQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        Self.logger.info("Menu built: items = [Show, Quit]")
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
        guard let button = statusItem.button else {
            Self.logger.error("showMenu: statusItem.button is nil; using fallback presentation")
            if let anchorView = NSApp.keyWindow?.contentView ?? NSApp.mainWindow?.contentView ?? NSApp.windows.first?.contentView {
                if let currentEvent = NSApp.currentEvent {
                    Self.logger.debug("showMenu: Using popUpContextMenu with current event and anchor view")
                    NSMenu.popUpContextMenu(menu, with: currentEvent, for: anchorView)
                } else {
                    // No current event; fall back to showing at mouse location.
                    let mouseLocation = NSEvent.mouseLocation
                    Self.logger.debug("showMenu: No current event; popping up at mouse location: x=\(mouseLocation.x, privacy: .public), y=\(mouseLocation.y, privacy: .public)")
                    menu.popUp(positioning: nil, at: mouseLocation, in: nil)
                }
            } else {
                // As a last resort, show the menu at the current mouse location without a view.
                let mouseLocation = NSEvent.mouseLocation
                Self.logger.debug("showMenu: No anchor view; popping up at mouse location: x=\(mouseLocation.x, privacy: .public), y=\(mouseLocation.y, privacy: .public)")
                menu.popUp(positioning: nil, at: mouseLocation, in: nil)
            }
            return
        }

        // Attach the menu so AppKit will present it for the status item,
        // then simulate a click to open it. Clear afterward to keep left-click custom behavior.
        statusItem.menu = menu
        Self.logger.debug("showMenu: Menu attached to status item; performing click to open")
        button.performClick(nil)
        // Clear the menu on the next runloop tick after the menu dismisses.
        DispatchQueue.main.async { [weak statusItem] in
            if statusItem?.menu != nil {
                Self.logger.debug("showMenu: Clearing statusItem.menu after presentation")
            }
            statusItem?.menu = nil
        }
    }

    @objc private func didTapShow() {
        Self.logger.info("Menu action: Show")
        onShow()
    }

    @objc private func didTapQuit() {
        Self.logger.info("Menu action: Quit")
        onQuit()
    }
}
