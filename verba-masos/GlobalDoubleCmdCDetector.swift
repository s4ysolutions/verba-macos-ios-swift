import Carbon
import Cocoa
import OSLog

class GlobalDoubleCmdCDetector {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retainedSelf: Unmanaged<GlobalDoubleCmdCDetector>?
    private var pressTimes: [Date] = []
    private let timeWindow: TimeInterval = 0.5
    private let handler: () -> Void
    private var permissionTimer: Timer?
    private var permissionPollCount = 0
    private let maxPermissionPolls = 150  // 5 minutes at 2s interval

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    func start() -> Bool {
        guard checkAccessibilityPermission() else {
            _ = requestAccessibilityPermission()
            showAccessibilityAlert()
            return false
        }
        _ = startEventTap()

        return true
    }

    private func eventCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent> {
        // Handle tap disabled (happens when user locks screen, etc.)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap = eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        // Check if it's C key (keycode 8)
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keycode == 8 else {
            return Unmanaged.passUnretained(event)
        }

        // Check if ONLY Command is pressed (no Shift, Option, Control)
        let flags = event.flags
        let hasCommand = flags.contains(.maskCommand)
        let hasShift = flags.contains(.maskShift)
        let hasOption = flags.contains(.maskAlternate)
        let hasControl = flags.contains(.maskControl)

        guard hasCommand && !hasShift && !hasOption && !hasControl else {
            return Unmanaged.passUnretained(event)
        }

        detectDoublePress()

        // IMPORTANT: Return the event unmodified so Cmd+C still works normally
        return Unmanaged.passUnretained(event)
    }

    private func detectDoublePress() {
        let now = Date()
        pressTimes = pressTimes.filter { now.timeIntervalSince($0) < timeWindow }
        pressTimes.append(now)
        if pressTimes.count >= 2 {
            pressTimes.removeAll()
            DispatchQueue.main.async {
                self.handler()
            }
        }
    }

    func stop() {
        permissionTimer?.invalidate()
        permissionTimer = nil

        if let runLoopSource = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)  // guarantees no further callbacks before self is freed
            self.eventTap = nil
        }
        retainedSelf?.release()
        retainedSelf = nil
    }

    deinit {
        stop()
    }

    private func requestAccessibilityPermission() -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options)
    }

    private func checkAccessibilityPermission() -> Bool {
        return AXIsProcessTrusted()
    }

    private func startEventTap() -> Bool {
        let eventMask = (1 << CGEventType.keyDown.rawValue)

        // Retain self so the C callback holds a valid pointer for its lifetime.
        // Balanced by release in stop() via CFMachPortInvalidate + manual release.
        let retained = Unmanaged.passRetained(self)

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { proxy, type, event, refcon in
                guard let refcon = refcon else {
                    return Unmanaged.passUnretained(event)
                }
                let detector = Unmanaged<GlobalDoubleCmdCDetector>.fromOpaque(refcon).takeUnretainedValue()
                return detector.eventCallback(proxy: proxy, type: type, event: event)
            },
            userInfo: retained.toOpaque()
        ) else {
            logger.error("Failed to create event tap")
            retained.release()
            return false
        }

        self.eventTap = eventTap
        self.retainedSelf = retained
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)

        logger.info("Global double Cmd+C detector started")
        return true
    }

    private func startPermissionPolling() {
        permissionTimer?.invalidate()
        permissionPollCount = 0
        logger.info("Starting permission polling...")
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            self.permissionPollCount += 1
            self.logger.info("Checking accessibility permission (poll \(self.permissionPollCount)/\(self.maxPermissionPolls))...")

            if self.checkAccessibilityPermission() {
                timer.invalidate()
                self.permissionTimer = nil
                self.logger.info("Permission granted!")
                _ = self.startEventTap()
            } else if self.permissionPollCount >= self.maxPermissionPolls {
                timer.invalidate()
                self.permissionTimer = nil
                self.logger.warning("Permission polling timed out after \(self.maxPermissionPolls) attempts")
            }
        }
    }

    private func showAccessibilityAlert() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString(
                "alert.accessibility.title",
                value: "Accessibility Access Required",
                comment: "Accessibility permission alert title"
            )
            alert.informativeText = NSLocalizedString(
                "alert.accessibility.message",
                value: "Verba needs Accessibility permission to detect the double Cmd+C shortcut while other apps are active.\n\nClick OK to open Privacy & Security settings. Enable Verba in the Accessibility list (click + to add it if not listed).",
                comment: "Accessibility permission alert message"
            )
            alert.alertStyle = .informational
            alert.addButton(withTitle: NSLocalizedString("alert.accessibility.button.ok", value: "Open Settings", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("alert.accessibility.button.later", value: "Later", comment: ""))

            if alert.runModal() == .alertFirstButtonReturn {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            self.startPermissionPolling()
        }
    }

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "verba-masos", category: "GlobalDoubleCmdCDetector")
}
