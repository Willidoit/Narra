import Foundation
import AppKit
import Carbon.HIToolbox
import IOKit.hid

@MainActor
final class KeybindingManager {

    static let shared = KeybindingManager()

    var onPushToTalkStart: (() -> Void)?
    var onPushToTalkStop: (() -> Void)?
    var onPushToToggle: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var fnDown: Bool = false
    private var toggleArmed: Bool = false

    var hasInputMonitoringAccess: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    private init() {}

    func start() {
        guard eventTap == nil, hasInputMonitoringAccess else { return }
        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: Self.tapCallback,
            userInfo: refcon
        ) else { return }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.eventTap = tap
        self.runLoopSource = source
    }

    private static let tapCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let manager = Unmanaged<KeybindingManager>.fromOpaque(refcon).takeUnretainedValue()
        DispatchQueue.main.async {
            manager.handle(type: type, event: event)
        }
        return Unmanaged.passUnretained(event)
    }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .flagsChanged:
            let isFn = event.flags.contains(.maskSecondaryFn)
            if isFn && !fnDown {
                fnDown = true
                toggleArmed = false
                onPushToTalkStart?()
            } else if !isFn && fnDown {
                fnDown = false
                if !toggleArmed {
                    onPushToTalkStop?()
                }
                toggleArmed = false
            }
        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if fnDown && keyCode == kVK_Space {
                toggleArmed = true
                onPushToToggle?()
            }
        default:
            break
        }
    }
}
