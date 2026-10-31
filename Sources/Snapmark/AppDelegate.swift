import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let hotkeys = HotkeyTap()
    private var selector: RegionSelector?
    private var editors: [EditorController] = []
    private var viewers: [VideoViewerController] = []
    private let actionBar = CaptureActionBar()
    private let recorder = Recorder()
    private var mainMenu: NSMenu!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        actionBar.onDismiss = { [weak self] in self?.refreshMenuBarIcon() }
        refreshMenuBarIcon()
        mainMenu = buildMenu()
        statusItem.menu = mainMenu
        recorder.onUnexpectedStop = { [weak self] in self?.stopRecording() }
        if Settings.checkForUpdates { Task { _ = try? await UpdateChecker.check() } }   // once per launch, quiet on failure

        hotkeys.onHotkey = { [weak self] key in self?.handle(key) }
        if !startHotkeys() {
            // Stay in the menu bar and keep trying until the user grants permission.
            statusItem.button?.appearsDisabled = true
            _ = Permissions.ensureHotkeyAccess()
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
                guard let self, self.startHotkeys() else { return }
                t.invalidate()
                self.permissionTimer = nil
                self.statusItem.button?.appearsDisabled = false
            }
        }
    }

    private func startHotkeys() -> Bool { AXIsProcessTrusted() && hotkeys.start() }

    private var permissionTimer: Timer?
    private var updateItem: NSMenuItem!
    private var updateSeparator: NSMenuItem!
    private var recentHeader: NSMenuItem!
    private var recentBarItem: NSMenuItem!
    private var videoHeader: NSMenuItem!
    private var videoBarItem: NSMenuItem!
    private var recentItem: NSMenuItem!
    private var folderItem: NSMenuItem!

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        updateItem = NSMenuItem(title: "", action: #selector(openSettings), keyEquivalent: "")
        updateItem.target = self
        updateItem.isHidden = true
        updateSeparator = .separator()
        updateSeparator.isHidden = true
        menu.addItem(updateItem)
        menu.addItem(updateSeparator)
        func add(_ title: String, _ key: String, _ action: Selector) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = key.isEmpty ? [] : [.command, .shift]
            item.target = self
            menu.addItem(item)
        }
        add("Capture Region", "4", #selector(menuQuickRegion))
        add("Capture Region: Edit or Record", "5", #selector(menuEditRegion))
        add("Capture Full Screen", "3", #selector(menuQuickFull))
        recentHeader = NSMenuItem.sectionHeader(title: "Recent Screenshots")
        recentBarItem = NSMenuItem()
        videoHeader = NSMenuItem.sectionHeader(title: "Recent Videos")
        videoBarItem = NSMenuItem()
        menu.addItem(.separator())
        menu.addItem(recentHeader)
        menu.addItem(recentBarItem)
        menu.addItem(videoHeader)
        menu.addItem(videoBarItem)
        recentItem = NSMenuItem(title: "All Recent Captures", action: nil, keyEquivalent: "")
        recentItem.submenu = NSMenu()
        menu.addItem(recentItem)
        menu.addItem(.separator())
        folderItem = NSMenuItem(title: "", action: #selector(openFolder), keyEquivalent: "")
        folderItem.target = self
        menu.addItem(folderItem)
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
        let update = UpdateChecker.available
        updateItem.isHidden = update == nil
        updateSeparator.isHidden = update == nil
        if let update { updateItem.title = "Update Available: Snapmark \(update)…" }
        rebuildRecentMenu()
    }

    @objc private func menuQuickRegion() { handle(.quickRegion) }
    @objc private func menuEditRegion() { handle(.editRegion) }
    @objc private func menuQuickFull() { handle(.quickFull) }
    @objc private func openFolder() { NSWorkspace.shared.open(Settings.saveFolder) }

    @objc private func openSettings() { SettingsController.shared.show() }

    private func handle(_ key: HotkeyTap.Key) {
        actionBar.dismiss()
        if recorder.isRecording { stopRecording(); return }
        switch key {
        case .quickFull:
            let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main!
            capture(rect: screen.frame, edit: false)
        case .quickRegion, .editRegion:
            guard selector == nil else { return }
            let edit = key == .editRegion
            selector = RegionSelector { [weak self] rect in
                guard let self else { return }
                self.selector = nil
                defer { self.refreshMenuBarIcon() }
                guard let rect else { return }
                if edit {
                    self.actionBar.show(near: rect,
                                        onEdit: { [weak self] in self?.capture(rect: rect, edit: true) },
                                        onRecord: { [weak self] in self?.startRecording(rect: rect) })
                } else {
                    self.capture(rect: rect, edit: false)
                }
            }
            selector?.begin()
            refreshMenuBarIcon()
        }
    }

    private var flashUntil = Date.distantPast

    /// One place decides the menu bar glyph from what is going on, so states never fight each other.
    private func refreshMenuBarIcon() {
        guard let button = statusItem?.button else { return }
        let state: MenuBarIcon.State
        if recorder.isRecording { state = .recording }
        else if flashUntil > Date() { state = .flash }
        else if selector != nil || actionBar.isShowing { state = .armed }
        else { state = .idle }
        MenuBarIcon.apply(state, to: button)
    }

    /// A quick shutter flash to confirm a capture was taken.
    private func flashCapture() {
        flashUntil = Date().addingTimeInterval(0.7)
        refreshMenuBarIcon()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in self?.refreshMenuBarIcon() }
    }

    // MARK: Recording

    private func startRecording(rect: CGRect) {
        // Let the selection outline and bar disappear before the first frame.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            Task { @MainActor in
                do {
                    try await self.recorder.start(appKitRect: rect, systemAudio: Settings.recordSystemAudio, microphone: Settings.recordMicrophone)
                    self.showRecordingState(true)
                } catch {
                    Permissions.alert("Recording failed: \(error.localizedDescription)\n\nCheck Screen Recording permission.")
                }
            }
        }
    }

    private func stopRecording() {
        guard recorder.isRecording else { return }
        Task { @MainActor in
            let url = await self.recorder.stop()
            self.showRecordingState(false)
            let size = url.flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? Int } ?? 0
            guard let url, size > 0 else {
                Permissions.alert("The recording did not produce a video file. Check Screen Recording permission and try again.")
                return
            }
            self.flashCapture()
            _ = await History.addVideo(url)
            if Settings.copyToClipboard {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([url as NSURL])
            }
            Output.playSound()
            if Settings.openViewerAfterRecording { self.openVideo(url) }
        }
    }

    @objc private func stopRecordingTapped() { stopRecording() }

    /// While recording, the menu bar icon is a red stop button. Clicking it stops.
    private func showRecordingState(_ on: Bool) {
        guard let button = statusItem.button else { return }
        if on {
            statusItem.menu = nil
            button.target = self
            button.action = #selector(stopRecordingTapped)
        } else {
            button.action = nil
            statusItem.menu = mainMenu
        }
        refreshMenuBarIcon()
    }

    private func openEditor(_ result: Capture.Result, historyID: String?, annotations: [Annotation] = []) {
        let editor = EditorController(capture: result, historyID: historyID, annotations: annotations)
        editor.onClose = { [weak self] e in self?.editors.removeAll { $0 === e } }
        editors.append(editor)
        editor.show()
    }

    @objc private func openRecentItem(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { openRecent(id: id) }
    }

    private func openRecent(id: String) {
        if let entry = History.entries().first(where: { $0.id == id }), entry.kind == .video {
            if let url = entry.videoURL, FileManager.default.fileExists(atPath: url.path) {
                openVideo(url)
            } else {
                History.remove(entry)   // the file was moved or deleted
            }
            return
        }
        if let open = editors.first(where: { $0.historyID == id }) { open.bringToFront(); return }
        guard let entry = History.entries().first(where: { $0.id == id }), let loaded = History.load(entry) else { return }
        openEditor(loaded.capture, historyID: id, annotations: loaded.annotations)
    }

    private func openVideo(_ url: URL) {
        if let open = viewers.first(where: { $0.url == url }) { open.bringToFront(); return }
        let viewer = VideoViewerController(url: url)
        viewer.onClose = { [weak self] v in self?.viewers.removeAll { $0 === v } }
        viewer.onSaved = { file, replaced in
            if replaced { History.removeVideoEntries(for: file) }   // refresh the thumbnail for the new cut
            Task { _ = await History.addVideo(file) }
        }
        viewer.onDeleted = { url in History.removeVideoEntries(for: url) }
        viewers.append(viewer)
        viewer.show()
    }

    @objc private func clearRecent() { History.clear() }

    private func menuItem(for e: HistoryEntry, formatter f: DateFormatter) -> NSMenuItem {
        let item = NSMenuItem(title: f.string(from: e.date), action: #selector(openRecentItem(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = e.id
        if let t = e.thumbnail {
            let h: CGFloat = 36
            t.size = NSSize(width: t.size.width * h / max(t.size.height, 1), height: h)
            item.image = t
        }
        return item
    }

    private func rebuildRecentMenu() {
        let sub = NSMenu()
        let all = History.entries()
        let entries = all.filter { $0.kind == .image }
        let videos = all.filter { $0.kind == .video }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true
        func addSection(_ title: String, _ list: [HistoryEntry]) {
            guard !list.isEmpty else { return }
            sub.addItem(NSMenuItem.sectionHeader(title: title))
            for e in list { sub.addItem(menuItem(for: e, formatter: f)) }
        }
        addSection("Screenshots", entries)
        addSection("Videos", videos)
        if all.isEmpty {
            let none = NSMenuItem(title: "No recent captures", action: nil, keyEquivalent: "")
            none.isEnabled = false
            sub.addItem(none)
        } else {
            sub.addItem(.separator())
            let clear = NSMenuItem(title: "Clear Recent", action: #selector(clearRecent), keyEquivalent: "")
            clear.target = self
            sub.addItem(clear)
        }
        recentItem.submenu = sub

        recentHeader.isHidden = entries.isEmpty
        recentBarItem.isHidden = entries.isEmpty
        recentBarItem.view = entries.isEmpty ? nil : RecentBarView(entries: entries) { [weak self] id in self?.openRecent(id: id) }

        videoHeader.isHidden = videos.isEmpty
        videoBarItem.isHidden = videos.isEmpty
        videoBarItem.view = videos.isEmpty ? nil : RecentBarView(entries: videos) { [weak self] id in self?.openRecent(id: id) }
    }

    private func capture(rect: CGRect, edit: Bool) {
        // Let the overlay windows finish disappearing before grabbing pixels.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            Task { @MainActor in
                do {
                    let result = try await Capture.image(appKitRect: rect)
                    let historyID = History.add(result)
                    self.flashCapture()
                    if edit {
                        self.openEditor(result, historyID: historyID)
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
