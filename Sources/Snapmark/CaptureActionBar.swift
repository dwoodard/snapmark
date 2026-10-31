import AppKit

/// Small floating bar shown next to a selected region: edit a screenshot or record video.
final class CaptureActionBar {
    private var panel: NSPanel?
    private var outline: NSWindow?
    private var onEdit: (() -> Void)?
    private var onRecord: (() -> Void)?

    private final class BarPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    func show(near rect: CGRect, onEdit: @escaping () -> Void, onRecord: @escaping () -> Void) {
        dismiss()   // never leave a previous bar or outline behind
        self.onEdit = onEdit
        self.onRecord = onRecord

        // Thin outline so the selection stays visible while choosing.
        // Drawn just outside the selection so it can never land inside the captured area.
        let o = NSWindow(contentRect: rect.insetBy(dx: -2, dy: -2), styleMask: .borderless, backing: .buffered, defer: false)
        o.backgroundColor = .clear
        o.isOpaque = false
        o.hasShadow = false
        o.ignoresMouseEvents = true
        o.level = .statusBar
        o.contentView = NSView()
        o.contentView?.wantsLayer = true
        o.contentView?.layer?.borderWidth = 1
        o.contentView?.layer?.borderColor = NSColor.white.withAlphaComponent(0.6).cgColor
        o.orderFront(nil)
        outline = o

        let edit = button("Edit Screenshot", "pencil.tip.crop.circle", #selector(editTapped), key: "\r")
        let record = button("Record Video", "record.circle", #selector(recordTapped), key: "r")
        record.contentTintColor = .systemRed
        let cancel = button("", "xmark", #selector(cancelTapped), key: "\u{1b}")
        // Quick audio switches for recording. They remember their last state.
        let system = toggle("speaker.wave.2", "Computer sound", on: Settings.recordSystemAudio, #selector(systemToggled(_:)))
        let mic = toggle("mic", "Microphone", on: Settings.recordMicrophone, #selector(micToggled(_:)))

        let stack = NSStackView(views: [edit, record, system, mic, cancel])
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        let size = stack.fittingSize

        let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        blur.material = .hudWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 10
        blur.layer?.masksToBounds = true
        stack.frame = blur.bounds
        blur.addSubview(stack)

        let screen = NSScreen.screens.first { $0.frame.intersects(rect) } ?? NSScreen.main!
        var origin = CGPoint(x: rect.midX - size.width / 2, y: rect.minY - size.height - 10)
        if origin.y < screen.visibleFrame.minY { origin.y = rect.minY + 10 }   // no room below: sit inside the selection
        origin.x = min(max(origin.x, screen.visibleFrame.minX + 8), screen.visibleFrame.maxX - size.width - 8)

        let p = BarPanel(contentRect: NSRect(origin: origin, size: size), styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .statusBar
        p.contentView = blur
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        panel = p
    }

    func dismiss() {
        panel?.orderOut(nil)
        outline?.orderOut(nil)
        panel = nil
        outline = nil
    }

    private func button(_ title: String, _ symbol: String, _ action: Selector, key: String) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        b.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        b.bezelStyle = .rounded
        b.keyEquivalent = key
        return b
    }

    private func toggle(_ symbol: String, _ tip: String, on: Bool, _ action: Selector) -> NSButton {
        let b = NSButton(title: "", target: self, action: action)
        b.setButtonType(.pushOnPushOff)
        b.bezelStyle = .rounded
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        b.imagePosition = .imageOnly
        b.state = on ? .on : .off
        b.toolTip = tip + " when recording"
        return b
    }

    @objc private func systemToggled(_ sender: NSButton) { Settings.recordSystemAudio = sender.state == .on }
    @objc private func micToggled(_ sender: NSButton) { Settings.recordMicrophone = sender.state == .on }

    @objc private func editTapped() { let f = onEdit; dismiss(); f?() }
    @objc private func recordTapped() { let f = onRecord; dismiss(); f?() }
    @objc private func cancelTapped() { dismiss() }
}
