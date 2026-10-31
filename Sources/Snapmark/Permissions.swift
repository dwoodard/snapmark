import AppKit

enum Permissions {
    static func ensureHotkeyAccess() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    static func alert(_ text: String) {
        let a = NSAlert()
        a.messageText = "Snapmark"
        a.informativeText = text
        a.runModal()
    }
}
