import AppKit

/// Dimmed full-screen overlay on every display. Drag to pick a rect, Esc to cancel.
final class RegionSelector {
    private var windows: [OverlayWindow] = []
    private let completion: (CGRect?) -> Void

    init(completion: @escaping (CGRect?) -> Void) { self.completion = completion }

    func begin() {
        NSApp.activate(ignoringOtherApps: true)
        for screen in NSScreen.screens {
            let w = OverlayWindow(screen: screen)
            w.selectionView.onFinish = { [weak self] rect in self?.finish(rect) }
            windows.append(w)
            w.makeKeyAndOrderFront(nil)
        }
        NSCursor.crosshair.push()
    }

    private func finish(_ rect: CGRect?) {
        NSCursor.pop()
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        completion(rect)
    }
}

private final class OverlayWindow: NSWindow {
    let selectionView: SelectionView

    init(screen: NSScreen) {
        selectionView = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = selectionView
        setFrame(screen.frame, display: true)
    }

    override var canBecomeKey: Bool { true }
}

private final class SelectionView: NSView {
    var onFinish: ((CGRect?) -> Void)?
    private var start: NSPoint?
    private var current: NSPoint?
    private var lastMouse: NSPoint?
    private var spaceHeld = false

    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    private var selection: NSRect? {
        guard let s = start, let c = current else { return nil }
        return NSRect(x: min(s.x, c.x), y: min(s.y, c.y), width: abs(s.x - c.x), height: abs(s.y - c.y))
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()
        guard let r = selection else { return }
        NSColor.clear.setFill()
        r.fill(using: .copy)
        NSColor.white.setStroke()
        let path = NSBezierPath(rect: r)
        path.lineWidth = 1
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        current = start
        lastMouse = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if spaceHeld, let last = lastMouse, let s = start, let c = current {
            // Space held: move the whole selection instead of resizing it.
            let dx = p.x - last.x, dy = p.y - last.y
            start = NSPoint(x: s.x + dx, y: s.y + dy)
            current = NSPoint(x: c.x + dx, y: c.y + dy)
        } else {
            current = p
        }
        lastMouse = p
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let r = selection, r.width > 3, r.height > 3, let window else {
            onFinish?(nil)
            return
        }
        // View rect -> global AppKit screen coordinates.
        onFinish?(window.convertToScreen(convert(r, to: nil)))
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onFinish?(nil)
        case 49: spaceHeld = true
        default: break
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 { spaceHeld = false }
    }
}
