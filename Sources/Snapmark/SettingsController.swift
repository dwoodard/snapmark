import AppKit

final class SettingsController: NSObject {
    static let shared = SettingsController()
    var onChange: (() -> Void)?

    private var window: NSWindow?

    /// "0.1.0 (a1b2c3d)": the release version and the commit it was built from.
    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "dev"
        guard let commit = info?["SnapmarkBuildCommit"] as? String, commit != "unknown" else { return version }
        return "\(version) (\(commit))"
    }
    private var actions: [ActionTarget] = []
    private let loginCheckbox = NSButton(checkboxWithTitle: "Launch Snapmark at login", target: nil, action: nil)
    private let folderLabel = NSTextField(labelWithString: "")
    private let editorAppLabel = NSTextField(labelWithString: "")

    private final class ActionTarget: NSObject {
        let fn: (NSControl) -> Void
        init(_ fn: @escaping (NSControl) -> Void) { self.fn = fn }
        @objc func fire(_ sender: NSControl) { fn(sender) }
    }

    func show() {
        if window == nil { build() }
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func refresh() {
        loginCheckbox.state = LaunchAtLogin.isEnabled ? .on : .off
        folderLabel.stringValue = Settings.saveFolder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    // MARK: Layout

    private func build() {
        let grids: [(String, NSGridView)] = [
            ("General", general()),
            ("Screenshots", screenshots()),
            ("Video", video()),
            ("Editor", editor()),
            ("Shortcuts", shortcuts()),
        ]
        let tabs = NSTabView()
        grids.forEach { tabs.addTabViewItem(tab($0.0, $0.1)) }

        // Size the window to the tallest tab so no row is ever cut off.
        let tallest = grids.map { $0.1.fittingSize.height }.max() ?? 240
        let widest = grids.map { $0.1.fittingSize.width }.max() ?? 440
        let size = NSSize(width: max(widest + 90, 540), height: tallest + 120)

        let w = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Snapmark Settings"
        w.isReleasedWhenClosed = false
        let content = NSView()
        tabs.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(tabs)
        NSLayoutConstraint.activate([
            tabs.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            tabs.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10),
            tabs.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            tabs.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
        ])
        w.contentView = content
        w.setContentSize(size)
        w.center()
        window = w
    }

    private func tab(_ title: String, _ grid: NSGridView) -> NSTabViewItem {
        let item = NSTabViewItem()
        item.label = title
        let v = NSView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: v.topAnchor, constant: 18),
            grid.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 18),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: v.trailingAnchor, constant: -18),
        ])
        item.view = v
        return item
    }

    private func grid(_ rows: [(String, NSView)]) -> NSGridView {
        let g = NSGridView(views: rows.map { [NSTextField(labelWithString: $0.0), $0.1] })
        g.rowSpacing = 12
        g.columnSpacing = 14
        g.column(at: 0).xPlacement = .trailing
        g.rowAlignment = .firstBaseline
        return g
    }

    // MARK: Tabs

    private func general() -> NSGridView {
        loginCheckbox.target = self
        loginCheckbox.action = #selector(toggleLogin)
        folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.widthAnchor.constraint(equalToConstant: 220).isActive = true
        let choose = NSButton(title: "Choose…", target: self, action: #selector(chooseFolder))
        let folder = NSStackView(views: [folderLabel, choose])
        folder.spacing = 8
        return grid([
            ("Startup", loginCheckbox),
            ("Save folder", folder),
            ("Recent captures", slider(0...30, { Double(Settings.historyLimit) }, { Settings.historyLimit = Int($0) }, "%.0f kept")),
            ("Feedback", check("Play a sound after capture", { Settings.playSound }, { Settings.playSound = $0 })),
            ("Version", NSTextField(labelWithString: SettingsController.versionString)),
        ])
    }

    private func screenshots() -> NSGridView {
        let prefix = NSTextField(string: Settings.filenamePrefix)
        prefix.widthAnchor.constraint(equalToConstant: 160).isActive = true
        prefix.placeholderString = "Screenshot"
        let prefixAction = ActionTarget { Settings.filenamePrefix = ($0 as! NSTextField).stringValue.isEmpty ? "Screenshot" : ($0 as! NSTextField).stringValue }
        actions.append(prefixAction)
        prefix.target = prefixAction
        prefix.action = #selector(ActionTarget.fire(_:))

        let format = popup(ImageFormat.allCases.map(\.title), selected: ImageFormat.allCases.firstIndex(of: Settings.imageFormat) ?? 0) {
            Settings.imageFormat = ImageFormat.allCases[$0]
        }
        return grid([
            ("Quick capture", check("Copy to clipboard", { Settings.copyToClipboard }, { Settings.copyToClipboard = $0 })),
            ("", check("Save to the save folder", { Settings.saveToFile }, { Settings.saveToFile = $0 })),
            ("Region ratio", popup(AspectRatios.all.map(\.title), selected: Settings.aspectIndex) { Settings.aspectIndex = $0 }),
            ("Format", format),
            ("File name", prefix),
            ("Pointer", check("Include the mouse cursor", { Settings.showCursor }, { Settings.showCursor = $0 })),
        ])
    }

    private func video() -> NSGridView {
        grid([
            ("Audio", check("Computer sound", { Settings.recordSystemAudio }, { Settings.recordSystemAudio = $0 })),
            ("", check("Microphone", { Settings.recordMicrophone }, { Settings.recordMicrophone = $0 })),
            ("Quality", popup(VideoQuality.allCases.map(\.title), selected: Settings.videoQuality.rawValue) { Settings.videoQuality = VideoQuality(rawValue: $0) ?? .high }),
            ("Frame rate", popup(["30 fps", "60 fps"], selected: Settings.videoFPS == 60 ? 1 : 0) { Settings.videoFPS = $0 == 1 ? 60 : 30 }),
            ("After recording", check("Open the video to review it", { Settings.openViewerAfterRecording }, { Settings.openViewerAfterRecording = $0 })),
        ])
    }

    private func editor() -> NSGridView {
        let tool = popup(Tool.allCases.map { $0.label }, selected: Settings.defaultTool) { Settings.defaultTool = $0 }
        editorAppLabel.stringValue = Settings.externalEditorName
        let editorApp = NSStackView(views: [editorAppLabel, NSButton(title: "Choose…", target: self, action: #selector(chooseEditorApp))])
        editorApp.spacing = 8
        return grid([
            ("Open in", editorApp),
            ("Default tool", tool),
            ("Line width", slider(1...10, { Settings.lineWidth }, { Settings.lineWidth = $0 }, "%.0f pt")),
            ("Text size", slider(10...48, { Settings.textSize }, { Settings.textSize = $0 }, "%.0f pt")),
            ("Blur strength", slider(2...30, { Settings.blurStrength }, { Settings.blurStrength = $0 }, "%.0f")),
            ("When copying", check("Close the editor", { Settings.editorCloseAfterCopy }, { Settings.editorCloseAfterCopy = $0 })),
            ("", check("Also save to the save folder", { Settings.editorSaveOnCopy }, { Settings.editorSaveOnCopy = $0 })),
        ])
    }

    private func shortcuts() -> NSGridView {
        func row(_ keys: String, _ title: String, _ k: HotkeyTap.Key) -> (String, NSView) {
            (keys, check(title, { Settings.hotkeyEnabled(k) }, { Settings.setHotkey(k, enabled: $0) }))
        }
        let note = NSTextField(wrappingLabelWithString: "A turned-off shortcut goes back to macOS.\nHold Space while dragging to move the selection.\nWhile recording, any capture shortcut or the red menu bar icon stops it.")
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        return grid([
            row("⌘⇧4", "Capture region (copy + save)", .quickRegion),
            row("⌘⇧5", "Capture region: edit or record video", .editRegion),
            row("⌘⇧3", "Capture full screen", .quickFull),
            ("", note),
        ])
    }

    // MARK: Controls

    private func check(_ title: String, _ get: @escaping () -> Bool, _ set: @escaping (Bool) -> Void) -> NSButton {
        let b = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        b.state = get() ? .on : .off
        bind(b) { set(($0 as! NSButton).state == .on) }
        return b
    }

    private func popup(_ items: [String], selected: Int, _ onChange: @escaping (Int) -> Void) -> NSPopUpButton {
        let p = NSPopUpButton(frame: .zero, pullsDown: false)
        p.addItems(withTitles: items)
        p.selectItem(at: selected)
        bind(p) { onChange(($0 as! NSPopUpButton).indexOfSelectedItem) }
        return p
    }

    private func slider(_ range: ClosedRange<Double>, _ get: @escaping () -> Double, _ set: @escaping (Double) -> Void, _ format: String) -> NSView {
        let value = NSTextField(labelWithString: String(format: format, get()))
        value.widthAnchor.constraint(equalToConstant: 48).isActive = true
        let s = NSSlider(value: get(), minValue: range.lowerBound, maxValue: range.upperBound, target: nil, action: nil)
        s.widthAnchor.constraint(equalToConstant: 180).isActive = true
        bind(s) {
            let v = ($0 as! NSSlider).doubleValue.rounded()
            set(v)
            value.stringValue = String(format: format, v)
        }
        let stack = NSStackView(views: [s, value])
        stack.spacing = 8
        return stack
    }

    private func bind(_ control: NSControl, _ fn: @escaping (NSControl) -> Void) {
        let t = ActionTarget(fn)
        actions.append(t)
        control.target = t
        control.action = #selector(ActionTarget.fire(_:))
    }

    // MARK: Actions

    @objc private func toggleLogin() {
        setLaunchAtLogin(loginCheckbox.state == .on)
        refresh()
    }

    @objc private func chooseEditorApp() {
        Settings.chooseExternalEditor()
        editorAppLabel.stringValue = Settings.externalEditorName
    }

    @objc private func chooseFolder() {
        Settings.chooseFolder()
        refresh()
        onChange?()
    }

    /// Shared by the settings window and the menu item.
    func setLaunchAtLogin(_ on: Bool) {
        do { try LaunchAtLogin.set(on) } catch {
            Permissions.alert("Could not change launch at login: \(error.localizedDescription)\n\nThis works when Snapmark runs as an installed app, not from `swift run`.")
        }
        onChange?()
    }
}
