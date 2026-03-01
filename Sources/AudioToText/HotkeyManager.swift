import CoreGraphics
import Foundation

final class HotkeyManager {
    let callback: () -> Void
    var tapPort: CFMachPort?

    init(callback: @escaping () -> Void) {
        self.callback = callback
    }

    func start() -> Bool {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hotkeyEventCallback,
            userInfo: refcon
        ) else {
            return false
        }

        tapPort = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }
}

private func hotkeyEventCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon = refcon else {
        return Unmanaged.passUnretained(event)
    }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let port = manager.tapPort {
            CGEvent.tapEnable(tap: port, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }

    guard type == .keyDown else {
        return Unmanaged.passUnretained(event)
    }

    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags

    let hasCtrl = flags.contains(.maskControl)
    let hasOption = flags.contains(.maskAlternate)
    let noCmd = !flags.contains(.maskCommand)
    let noShift = !flags.contains(.maskShift)

    // Ctrl+Option+K: keycode 40
    if keyCode == 40 && hasCtrl && hasOption && noCmd && noShift {
        DispatchQueue.main.async {
            manager.callback()
        }
        return nil // swallow the event
    }

    return Unmanaged.passUnretained(event)
}
