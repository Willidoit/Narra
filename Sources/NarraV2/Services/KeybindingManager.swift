import AppKit
import IOKit.hid

// MARK: - KeybindingManager

/// Global NSEvent monitor for push-to-talk and push-to-toggle shortcuts.
/// Uses IOHIDRequestAccess/IOHIDCheckAccess for Input Monitoring permission.
/// Reads AppSettings.shared bindings on every event so changes take effect immediately.
final class KeybindingManager: @unchecked Sendable {
    static let shared = KeybindingManager()

    var onPushToTalkStart: (() -> Void)?
    var onPushToTalkStop:  (() -> Void)?
    var onPushToToggle:    (() -> Void)?

    private var monitors: [Any] = []
    private var previousFlags: NSEvent.ModifierFlags = []

    var hasInputMonitoringAccess: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    func start() {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        guard hasInputMonitoringAccess else { return }

        let flagMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        let downMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
        }
        let upMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
            self?.handleKeyUp(event)
        }
        monitors = [flagMonitor, downMonitor, upMonitor].compactMap { $0 }
    }

    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let ptt   = AppSettings.shared.pushToTalkBinding
        let pttog = AppSettings.shared.pushToToggleBinding

        let relevantBits: NSEvent.ModifierFlags = [.function, .command, .option, .control, .shift]
        let current  = event.modifierFlags.intersection(relevantBits)
        let previous = previousFlags
        previousFlags = current

        if ptt.keyChar == nil {
            let target = NSEvent.ModifierFlags(rawValue: ptt.modifierFlags)
            if !previous.contains(target) && current.contains(target) {
                onPushToTalkStart?()
            } else if previous.contains(target) && !current.contains(target) {
                onPushToTalkStop?()
            }
        }

        if pttog.keyChar == nil {
            let target = NSEvent.ModifierFlags(rawValue: pttog.modifierFlags)
            if !previous.contains(target) && current.contains(target) {
                onPushToToggle?()
            }
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        guard !event.isARepeat else { return }
        let ptt   = AppSettings.shared.pushToTalkBinding
        let pttog = AppSettings.shared.pushToToggleBinding
        if matches(event: event, binding: ptt)   { onPushToTalkStart?() }
        if matches(event: event, binding: pttog) { onPushToToggle?() }
    }

    private func handleKeyUp(_ event: NSEvent) {
        let ptt = AppSettings.shared.pushToTalkBinding
        if matches(event: event, binding: ptt) { onPushToTalkStop?() }
    }

    private func matches(event: NSEvent, binding: KeyBinding) -> Bool {
        guard let keyChar = binding.keyChar,
              let eventChar = event.charactersIgnoringModifiers?.lowercased() else {
            return false
        }
        let relevantBits: NSEvent.ModifierFlags = [.function, .command, .option, .control, .shift]
        let eventFlags   = event.modifierFlags.intersection(relevantBits)
        let bindingFlags = NSEvent.ModifierFlags(rawValue: binding.modifierFlags).intersection(relevantBits)
        return eventChar == keyChar && eventFlags == bindingFlags
    }
}
