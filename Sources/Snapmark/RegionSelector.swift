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
        drawSizeLabel(for: r)
    }

    private func drawSizeLabel(for r: NSRect) {
        let ratio = AspectRatios.label(w: r.width, h: r.height)
        let text = "\(Int(r.width.rounded())) × \(Int(r.height.rounded()))" + (ratio.isEmpty ? "" : "  ·  \(ratio)")
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let pill = NSSize(width: size.width + 12, height: size.height + 6)
        // Above the selection when there is room, otherwise inside its top edge.
        let y = r.maxY + 4 + pill.height <= bounds.maxY ? r.maxY + 4 : r.maxY - pill.height - 4
        let box = NSRect(x: min(max(r.minX, bounds.minX + 4), bounds.maxX - pill.width - 4), y: y, width: pill.width, height: pill.height)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5).fill()
        (text as NSString).draw(at: NSPoint(x: box.minX + 6, y: box.minY + 3), withAttributes: attrs)
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
            current = constrain(p)
        }
        lastMouse = p
        needsDisplay = true
    }

    /// Applies the Region ratio setting: fixed ratios always, Smart only when close to a common one.
    private func constrain(_ p: NSPoint) -> NSPoint {
        guard let s = start else { return p }
        let dx = p.x - s.x, dy = p.y - s.y
        let choice = AspectRatios.current
        let ratio = choice.ratio ?? (choice.smart ? AspectRatios.snapRatio(w: abs(dx), h: abs(dy)) : nil)
        guard let r = ratio else { return p }

        let sx: CGFloat = dx < 0 ? -1 : 1, sy: CGFloat = dy < 0 ? -1 : 1
        var w = max(abs(dx), abs(dy) * r)
        // Keep the rect on this screen.
        let maxW = sx > 0 ? bounds.maxX - s.x : s.x - bounds.minX
        let maxH = sy > 0 ? bounds.maxY - s.y : s.y - bounds.minY
        w = min(w, maxW, maxH * r)
        return NSPoint(x: s.x + sx * w, y: s.y + sy * (w / r))
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
