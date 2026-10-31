import AppKit

/// Dimmed overlay on every display, like the macOS picker.
/// Hover highlights the window under the cursor (or the whole screen over empty desktop).
/// Click captures the highlight. Drag picks an area. Esc cancels.
final class RegionSelector {
    private var windows: [OverlayWindow] = []
    private let completion: (CGRect?) -> Void
    /// On-screen window frames in AppKit global coordinates, front to back.
    private var targets: [CGRect] = []

    enum HoverKind { case window, fullScreen, fullScreenButton }

    /// The "Full Screen" target at the top center of a display, in that display's own coordinates.
    static func fullScreenPill(in frame: CGRect) -> CGRect {
        CGRect(x: frame.midX - 52, y: frame.maxY - 70, width: 104, height: 26)
    }

    /// What a plain click would capture, in AppKit global coordinates.
    fileprivate(set) var hoverKind: HoverKind = .window
    fileprivate(set) var hover: CGRect?
    fileprivate(set) var activeScreenFrame: CGRect?

    init(completion: @escaping (CGRect?) -> Void) { self.completion = completion }

    func begin() {
        targets = RegionSelector.windowFrames()
        NSApp.activate(ignoringOtherApps: true)
        for screen in NSScreen.screens {
            let w = OverlayWindow(screen: screen, selector: self)
            w.selectionView.onFinish = { [weak self] rect in self?.finish(rect) }
            windows.append(w)
            w.makeKeyAndOrderFront(nil)
        }
        NSCursor.crosshair.push()
        updateHover(NSEvent.mouseLocation)
    }

    fileprivate func updateHover(_ p: NSPoint) {
        let screen = NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) }
        activeScreenFrame = screen?.frame
        if let screen, RegionSelector.fullScreenPill(in: screen.frame).contains(p) {
            hoverKind = .fullScreenButton
            hover = screen.frame
        } else if let window = targets.first(where: { $0.contains(p) }) {
            hoverKind = .window
            hover = window
        } else {
            hoverKind = .fullScreen   // empty desktop
            hover = screen?.frame
        }
        redraw()
    }

    /// Called when a drag starts, so the hover highlight gets out of the way.
    fileprivate func clearHover() {
        hover = nil
        redraw()
    }

    fileprivate func redraw() { windows.forEach { $0.selectionView.needsDisplay = true } }

    fileprivate func finishWithHover() { finish(hover) }

    private func finish(_ rect: CGRect?) {
        NSCursor.pop()
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        completion(rect)
    }

    private static func windowFrames() -> [CGRect] {
        let primaryHeight = NSScreen.screens[0].frame.height
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { w in
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowOwnerPID as String] as? Int) != Int(getpid()),
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.01,
                  let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: dict as CFDictionary),
                  r.width >= 40, r.height >= 40 else { return nil }
            return CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
        }
    }
}

private final class OverlayWindow: NSWindow {
    let selectionView: SelectionView

    init(screen: NSScreen, selector: RegionSelector) {
        selectionView = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size), selector: selector)
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = selectionView
        setFrame(screen.frame, display: true)
    }

    override var canBecomeKey: Bool { true }
}

private final class SelectionView: NSView {
    var onFinish: ((CGRect?) -> Void)?
    private unowned let selector: RegionSelector
    private var start: NSPoint?
    private var current: NSPoint?
    private var lastMouse: NSPoint?
    private var spaceHeld = false
    private var dragging = false

    init(frame: NSRect, selector: RegionSelector) {
        self.selector = selector
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    private var selection: NSRect? {
        guard dragging, let s = start, let c = current else { return nil }
        return NSRect(x: min(s.x, c.x), y: min(s.y, c.y), width: abs(s.x - c.x), height: abs(s.y - c.y))
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let win = window else { return }
        let isActive = selector.activeScreenFrame == win.frame
        // Displays without the cursor go a little darker.
        NSColor.black.withAlphaComponent(isActive || dragging ? 0.22 : 0.4).setFill()
        bounds.fill()

        if let r = selection {
            NSColor.clear.setFill()
            r.fill(using: .copy)
            NSColor.white.withAlphaComponent(0.8).setStroke()
            let path = NSBezierPath(rect: r.insetBy(dx: -0.5, dy: -0.5))
            path.lineWidth = 1
            path.stroke()
            drawSizeLabel(for: r)
        } else if let h = selector.hover {
            // Global AppKit rect -> this view's coordinates.
            let local = h.offsetBy(dx: -win.frame.minX, dy: -win.frame.minY).intersection(bounds)
            guard !local.isNull, local.width > 0, local.height > 0 else { return }
            let isScreen = selector.hoverKind != .window
            NSColor.clear.setFill()
            local.fill(using: .copy)
            NSColor.controlAccentColor.withAlphaComponent(isScreen ? 0.06 : 0.12).setFill()
            local.fill()
            // A window gets a thin outline. A whole screen gets only a soft edge and a small label.
            NSColor.controlAccentColor.withAlphaComponent(isScreen ? 0.5 : 0.9).setStroke()
            let path = NSBezierPath(rect: local.insetBy(dx: 1, dy: 1))
            path.lineWidth = 2
            path.stroke()
            if isScreen && isActive { drawCenterLabel("Full Screen", in: local) }
        }
        if !dragging {
            drawFullScreenPill(highlighted: isActive && selector.hoverKind == .fullScreenButton)
            if isActive { drawHint() }
        }
    }

    private func drawFullScreenPill(highlighted: Bool) {
        let r = RegionSelector.fullScreenPill(in: bounds)
        (highlighted ? NSColor.controlAccentColor : NSColor.black.withAlphaComponent(0.4)).setFill()
        NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(highlighted ? 1 : 0.8),
        ]
        let text = "Full Screen" as NSString
        let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: r.midX - size.width / 2, y: r.midY - size.height / 2), withAttributes: attrs)
    }

    /// One quiet line that says what a click does right now.
    private func drawHint() {
        let action: String
        switch selector.hoverKind {
        case .window: action = "Click: this window"
        case .fullScreen, .fullScreenButton: action = "Click: full screen"
        }
        let text = "\(action)   ·   Drag: select an area   ·   Esc: cancel" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.white.withAlphaComponent(0.85),
        ]
        let size = text.size(withAttributes: attrs)
        let box = NSRect(x: bounds.midX - size.width / 2 - 12, y: 48, width: size.width + 24, height: size.height + 10)
        NSColor.black.withAlphaComponent(0.45).setFill()
        NSBezierPath(roundedRect: box, xRadius: box.height / 2, yRadius: box.height / 2).fill()
        text.draw(at: NSPoint(x: box.minX + 12, y: box.minY + 5), withAttributes: attrs)
    }

    private func drawCenterLabel(_ string: String, in r: NSRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let text = string as NSString
        let size = text.size(withAttributes: attrs)
        let box = NSRect(x: r.midX - size.width / 2 - 14, y: r.midY - size.height / 2 - 6, width: size.width + 28, height: size.height + 12)
        NSColor.black.withAlphaComponent(0.45).setFill()
        NSBezierPath(roundedRect: box, xRadius: box.height / 2, yRadius: box.height / 2).fill()
        text.draw(at: NSPoint(x: box.minX + 14, y: box.minY + 6), withAttributes: attrs)
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
        let y = r.maxY + 4 + pill.height <= bounds.maxY ? r.maxY + 4 : r.maxY - pill.height - 8
        let box = NSRect(x: min(max(r.minX, bounds.minX + 4), bounds.maxX - pill.width - 4), y: y, width: pill.width, height: pill.height)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5).fill()
        (text as NSString).draw(at: NSPoint(x: box.minX + 6, y: box.minY + 3), withAttributes: attrs)
    }

    // MARK: Mouse

    override func mouseMoved(with event: NSEvent) {
        guard !dragging else { return }
        selector.updateHover(NSEvent.mouseLocation)
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        current = start
        lastMouse = start
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let s = start else { return }
        if !dragging {
            // Small movement is still a click.
            guard hypot(p.x - s.x, p.y - s.y) > 4 else { return }
            dragging = true
            selector.clearHover()
        }
        if spaceHeld, let last = lastMouse, let c = current {
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
        guard dragging else {
            // A click: capture whatever is highlighted (a window, or the whole screen).
            selector.finishWithHover()
            return
        }
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
