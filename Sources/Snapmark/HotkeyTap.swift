import AppKit
import CoreGraphics

private var tapHandler: ((HotkeyTap.Key) -> Void)?
private var tapPort: CFMachPort?

/// Swallows Cmd-Shift-3/4/5 so the system screenshot tool never sees them.
final class HotkeyTap {
    enum Key { case quickFull, quickRegion, editRegion }

    var onHotkey: ((Key) -> Void)? {
        get { tapHandler }
        set { tapHandler = newValue }
    }

    func start() -> Bool {
        let callback: CGEventTapCallBack = { _, type, event, _ in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let port = tapPort { CGEvent.tapEnable(tap: port, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            guard type == .keyDown else { return Unmanaged.passUnretained(event) }
            let f = event.flags
            guard f.contains(.maskCommand), f.contains(.maskShift), !f.contains(.maskAlternate) else {
                return Unmanaged.passUnretained(event)
            }
            let key: Key?
            switch event.getIntegerValueField(.keyboardEventKeycode) {
            case 20: key = .quickFull
            case 21: key = .quickRegion
            case 23: key = .editRegion
            default: key = nil
            }
            guard let key, Settings.hotkeyEnabled(key) else { return Unmanaged.passUnretained(event) }
            DispatchQueue.main.async { tapHandler?(key) }
            return nil
        }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: callback, userInfo: nil
        ) else { return false }
        tapPort = port
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }
}
