import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let hotkeys = HotkeyTap()
    private var selector: RegionSelector?
    private var editors: [EditorController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Snapmark")
        statusItem.menu = buildMenu()

        guard Permissions.ensureHotkeyAccess() else {
            Permissions.alert("Snapmark needs Accessibility and Input Monitoring. Grant them to this app or its launching terminal in System Settings > Privacy & Security, then relaunch.")
            NSApp.terminate(nil)
            return
        }
        hotkeys.onHotkey = { [weak self] key in self?.handle(key) }
        guard hotkeys.start() else {
            Permissions.alert("Could not start the hotkey tap. Grant Input Monitoring, then relaunch.")
            NSApp.terminate(nil)
            return
        }
    }

    private var folderItem: NSMenuItem!
    private var loginItem: NSMenuItem!

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        func add(_ title: String, _ key: String, _ action: Selector) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = key.isEmpty ? [] : [.command, .shift]
            item.target = self
            menu.addItem(item)
        }
        add("Capture Region", "4", #selector(menuQuickRegion))
        add("Capture Region and Edit", "5", #selector(menuEditRegion))
        add("Capture Full Screen", "3", #selector(menuQuickFull))
        menu.addItem(.separator())
        folderItem = NSMenuItem(title: "", action: #selector(openFolder), keyEquivalent: "")
        folderItem.target = self
        menu.addItem(folderItem)
        add("Choose Save Folder…", "", #selector(chooseFolder))
        menu.addItem(.separator())
        loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Snapmark", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        folderItem.title = "Open \(Settings.saveFolder.lastPathComponent)"
        loginItem.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    @objc private func menuQuickRegion() { handle(.quickRegion) }
    @objc private func menuEditRegion() { handle(.editRegion) }
    @objc private func menuQuickFull() { handle(.quickFull) }
    @objc private func openFolder() { NSWorkspace.shared.open(Settings.saveFolder) }

    @objc private func chooseFolder() { Settings.chooseFolder() }

    @objc private func toggleLaunchAtLogin() {
        SettingsController.shared.setLaunchAtLogin(!LaunchAtLogin.isEnabled)
    }

    @objc private func openSettings() { SettingsController.shared.show() }

    private func handle(_ key: HotkeyTap.Key) {
        switch key {
        case .quickFull:
            let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main!
            capture(rect: screen.frame, edit: false)
        case .quickRegion, .editRegion:
            guard selector == nil else { return }
            let edit = key == .editRegion
            selector = RegionSelector { [weak self] rect in
                self?.selector = nil
                if let rect { self?.capture(rect: rect, edit: edit) }
            }
            selector?.begin()
        }
    }

    private func capture(rect: CGRect, edit: Bool) {
        // Let the overlay windows finish disappearing before grabbing pixels.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            Task { @MainActor in
                do {
                    let result = try await Capture.image(appKitRect: rect)
                    if edit {
                        let editor = EditorController(capture: result)
                        editor.onClose = { [weak self] e in self?.editors.removeAll { $0 === e } }
                        self.editors.append(editor)
                        editor.show()
                    } else {
                        if Settings.copyToClipboard { Output.copyToClipboard(result.image) }
                        if Settings.saveToFile { try Output.save(result.image) }
                        Output.playSound()
                    }
                } catch {
                    Permissions.alert("Capture failed: \(error.localizedDescription)\n\nCheck Screen Recording permission.")
                }
            }
        }
    }
}
